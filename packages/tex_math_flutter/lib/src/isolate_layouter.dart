import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'font_bundle.dart';

/// Deterministic cache key identifying a `(source, options, fontId)` render.
@immutable
final class TexMathLayoutCacheKey {
  /// Creates a layout cache key.
  const TexMathLayoutCacheKey({
    required this.source,
    required this.options,
    required this.fontId,
  });

  /// TeX math source expression.
  final String source;

  /// Effective rendering and budget options.
  final TexMathOptions options;

  /// Identifier of the active math font.
  final String fontId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathLayoutCacheKey &&
          source == other.source &&
          options == other.options &&
          fontId == other.fontId;

  @override
  int get hashCode => Object.hash(source, options, fontId);

  @override
  String toString() =>
      'TexMathLayoutCacheKey(fontId: $fontId, sourceLength: ${source.length})';
}

/// Runs TeX parsing and layout in a persistent background [Isolate] backed by
/// an in-memory bounded LRU result cache.
///
/// When constructed with [fontBytes] (or via [TexMathIsolateLayouter.withBundledFont]),
/// the raw SFNT font payload is transferred once to the background worker
/// isolate and decoded once via [MathFont.fromBytes], avoiding repeated
/// isolate spawns and font parsing across equations.
final class TexMathIsolateLayouter {
  /// Creates a background layouter keeping at most [maxCacheEntries] results.
  TexMathIsolateLayouter({
    this.maxCacheEntries = 256,
    this.fontId = 'NewCMMath-Regular',
    this.fontBytes,
  }) : assert(maxCacheEntries >= 0, 'maxCacheEntries must be non-negative');

  /// Creates a background layouter preconfigured with the bundled
  /// `NewCMMath-Regular.otf` asset bytes from [TexMathFontBundle].
  static Future<TexMathIsolateLayouter> withBundledFont({
    int maxCacheEntries = 256,
    String fontId = 'NewCMMath-Regular',
    AssetBundle? bundle,
  }) async {
    final TexMathFontAsset asset = await TexMathFontBundle.load(bundle: bundle);
    return TexMathIsolateLayouter(
      maxCacheEntries: maxCacheEntries,
      fontId: fontId,
      fontBytes: asset.bytes,
    );
  }

  /// Maximum number of cached [RenderResult] entries retained in memory.
  final int maxCacheEntries;

  /// Font identifier included in cache keys.
  final String fontId;

  /// Optional raw SFNT font payload transferred once to the persistent worker
  /// isolate on startup.
  final Uint8List? fontBytes;
  final Map<TexMathLayoutCacheKey, RenderResult> _cache =
      <TexMathLayoutCacheKey, RenderResult>{};
  final Map<TexMathLayoutCacheKey, Future<RenderResult>> _inFlight =
      <TexMathLayoutCacheKey, Future<RenderResult>>{};
  final Map<int, Completer<RenderResult>> _pending =
      <int, Completer<RenderResult>>{};

  ReceivePort? _responsePort;
  StreamSubscription<Object?>? _responseSub;
  SendPort? _workerSendPort;
  Future<SendPort>? _workerFuture;
  Isolate? _workerIsolate;
  int _nextRequestId = 1;
  int _hitCount = 0;
  int _missCount = 0;
  bool _disposed = false;

  /// Whether font bytes were supplied for persistent worker decoding.
  bool get hasFontBytes => fontBytes != null;

  /// Whether the persistent background worker isolate is currently active.
  bool get isWorkerRunning => _workerSendPort != null && !_disposed;

  /// Whether [dispose] has been called on this layouter.
  bool get isDisposed => _disposed;

  /// Number of entries currently stored in the LRU cache.
  int get cacheLength => _cache.length;

  /// Number of [renderInBackground] calls satisfied directly from the cache.
  int get hitCount => _hitCount;

  /// Number of [renderInBackground] calls dispatched past the cache.
  int get missCount => _missCount;

  /// Looks up a cached [RenderResult] for [source] and [options], promoting
  /// any hit to most-recently-used.
  RenderResult? getCached(
    String source, {
    TexMathOptions options = const TexMathOptions(),
  }) {
    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
    );
    final RenderResult? hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
    }
    return hit;
  }

  /// Stores [result] in the bounded LRU cache under `(source, options, fontId)`.
  void putCached(
    String source,
    RenderResult result, {
    TexMathOptions options = const TexMathOptions(),
  }) {
    if (maxCacheEntries == 0) {
      return;
    }
    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
    );
    _cache.remove(key);
    if (_cache.length >= maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  /// Clears all cached layout results and hit/miss counters.
  void clearCache() {
    _cache.clear();
    _hitCount = 0;
    _missCount = 0;
  }

  /// Eagerly starts the persistent background worker isolate and decodes any
  /// supplied [fontBytes] off the UI thread.
  Future<void> warmUp() async {
    _checkNotDisposed();
    await _ensureWorker();
  }

  /// Renders [source] inside the persistent background [Isolate] and caches
  /// successful results.
  ///
  /// Returns cached entries synchronously via an already-completed future
  /// without touching the background isolate. Propagates [TexMathError]
  /// instances across the isolate boundary.
  Future<RenderResult> renderInBackground(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    TexMathEngine engine = const TexMathEngine(),
  }) async {
    _checkNotDisposed();
    final RenderResult? cached = getCached(source, options: options);
    if (cached != null) {
      _hitCount++;
      return cached;
    }

    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
    );
    final Future<RenderResult>? existing = _inFlight[key];
    if (existing != null && engine.font == null) {
      return existing;
    }

    _missCount++;
    final Future<RenderResult> future = _dispatchRender(
      source: source,
      options: options,
      engine: engine,
      cacheKey: key,
    );
    if (engine.font == null) {
      _inFlight[key] = future;
    }
    try {
      return await future;
    } finally {
      if (identical(_inFlight[key], future)) {
        final Future<RenderResult>? removed = _inFlight.remove(key);
        assert(removed != null);
      }
    }
  }

  /// Lays out [source] in the background [Isolate] and returns its
  /// [DisplayList].
  Future<DisplayList> layoutInBackground(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    TexMathEngine engine = const TexMathEngine(),
  }) async {
    final RenderResult result = await renderInBackground(
      source,
      options: options,
      engine: engine,
    );
    return result.displayList;
  }

  /// Shuts down the persistent background worker isolate and closes all ports.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    final List<Completer<RenderResult>> pending = _pending.values.toList();
    _pending.clear();
    _inFlight.clear();
    for (final Completer<RenderResult> completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('TexMathIsolateLayouter has been disposed.'),
        );
      }
    }

    final SendPort? sendPort = _workerSendPort;
    final Future<SendPort>? workerFuture = _workerFuture;
    _workerSendPort = null;
    _workerFuture = null;

    if (sendPort != null) {
      sendPort.send(const _WorkerShutdown());
    } else if (workerFuture != null) {
      try {
        final SendPort startedPort = await workerFuture;
        startedPort.send(const _WorkerShutdown());
      } catch (_) {
        // Ignore worker startup errors during teardown.
      }
    }

    await _responseSub?.cancel();
    _responseSub = null;
    _responsePort?.close();
    _responsePort = null;
    _workerIsolate = null;
  }

  Future<RenderResult> _dispatchRender({
    required String source,
    required TexMathOptions options,
    required TexMathEngine engine,
    required TexMathLayoutCacheKey cacheKey,
  }) async {
    final SendPort workerPort = await _ensureWorker();
    _checkNotDisposed();

    final int requestId = _nextRequestId++;
    final Completer<RenderResult> completer = Completer<RenderResult>();
    _pending[requestId] = completer;

    final TexMathEngine? customEngine = engine == const TexMathEngine()
        ? null
        : engine;
    workerPort.send(
      _WorkerRenderRequest(
        requestId: requestId,
        source: source,
        options: options,
        customEngine: customEngine,
        replyPort: _responsePort!.sendPort,
      ),
    );

    final RenderResult result = await completer.future;
    if (!_disposed) {
      putCached(cacheKey.source, result, options: cacheKey.options);
    }
    return result;
  }

  Future<SendPort> _ensureWorker() {
    _checkNotDisposed();
    if (_workerFuture != null) {
      return _workerFuture!;
    }
    final Future<SendPort> future = _startWorker();
    _workerFuture = future;
    return future;
  }

  Future<SendPort> _startWorker() async {
    final ReceivePort responsePort = ReceivePort();
    _responsePort = responsePort;
    _responseSub = responsePort.listen(_handleWorkerResponse);

    final ReceivePort startupPort = ReceivePort();
    try {
      final TransferableTypedData? transferableBytes = fontBytes == null
          ? null
          : TransferableTypedData.fromList(<Uint8List>[fontBytes!]);

      final Isolate isolate = await Isolate.spawn<_WorkerInit>(
        _workerMain,
        _WorkerInit(
          startupReplyPort: startupPort.sendPort,
          fontBytes: transferableBytes,
        ),
        debugName: 'tex_math_isolate_layouter',
      );
      _workerIsolate = isolate;

      final Object? startupReply = await startupPort.first;
      if (startupReply is _WorkerStartupError) {
        throw startupReply.error;
      }
      final SendPort sendPort = startupReply! as SendPort;
      if (_disposed) {
        sendPort.send(const _WorkerShutdown());
        throw StateError('TexMathIsolateLayouter has been disposed.');
      }
      _workerSendPort = sendPort;
      return sendPort;
    } catch (_) {
      _workerFuture = null;
      _workerSendPort = null;
      _workerIsolate?.kill(priority: Isolate.immediate);
      _workerIsolate = null;
      await _responseSub?.cancel();
      _responseSub = null;
      _responsePort?.close();
      _responsePort = null;
      rethrow;
    } finally {
      startupPort.close();
    }
  }

  void _handleWorkerResponse(Object? message) {
    if (message is _WorkerRenderSuccess) {
      final Completer<RenderResult>? completer = _pending.remove(
        message.requestId,
      );
      if (completer != null && !completer.isCompleted) {
        completer.complete(message.result);
      }
    } else if (message is _WorkerRenderFailure) {
      final Completer<RenderResult>? completer = _pending.remove(
        message.requestId,
      );
      if (completer != null && !completer.isCompleted) {
        completer.completeError(message.error);
      }
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TexMathIsolateLayouter has been disposed.');
    }
  }
}

@immutable
final class _WorkerInit {
  const _WorkerInit({required this.startupReplyPort, required this.fontBytes});

  final SendPort startupReplyPort;
  final TransferableTypedData? fontBytes;
}

@immutable
final class _WorkerStartupError {
  const _WorkerStartupError(this.error);

  final Exception error;
}

@immutable
final class _WorkerShutdown {
  const _WorkerShutdown();
}

@immutable
final class _WorkerRenderRequest {
  const _WorkerRenderRequest({
    required this.requestId,
    required this.source,
    required this.options,
    required this.customEngine,
    required this.replyPort,
  });

  final int requestId;
  final String source;
  final TexMathOptions options;
  final TexMathEngine? customEngine;
  final SendPort replyPort;
}

@immutable
final class _WorkerRenderSuccess {
  const _WorkerRenderSuccess(this.requestId, this.result);

  final int requestId;
  final RenderResult result;
}

@immutable
final class _WorkerRenderFailure {
  const _WorkerRenderFailure(this.requestId, this.error);

  final int requestId;
  final Object error;
}

Future<void> _workerMain(_WorkerInit init) async {
  MathFont? workerFont;
  if (init.fontBytes != null) {
    try {
      final Uint8List bytes = init.fontBytes!.materialize().asUint8List();
      workerFont = MathFont.fromBytes(bytes);
    } catch (error) {
      init.startupReplyPort.send(
        _WorkerStartupError(
          error is Exception
              ? error
              : TexMathFontError('Worker font load failed: $error'),
        ),
      );
      return;
    }
  }

  final ReceivePort commandPort = ReceivePort();
  init.startupReplyPort.send(commandPort.sendPort);

  await for (final Object? message in commandPort) {
    if (message is _WorkerShutdown) {
      commandPort.close();
      break;
    }
    if (message is _WorkerRenderRequest) {
      try {
        final TexMathEngine effectiveEngine =
            message.customEngine ?? const TexMathEngine();
        final MathFont? effectiveFont = effectiveEngine.font ?? workerFont;
        final RenderResult result = effectiveEngine.render(
          message.source,
          options: message.options,
          font: effectiveFont,
        );
        message.replyPort.send(_WorkerRenderSuccess(message.requestId, result));
      } catch (error) {
        message.replyPort.send(_WorkerRenderFailure(message.requestId, error));
      }
    }
  }
}
