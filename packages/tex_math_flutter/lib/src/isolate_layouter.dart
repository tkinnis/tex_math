import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'async_zone.dart';
import 'font_bundle.dart';

/// Deterministic cache key identifying a `(source, options, fontId, fontSignature)`
/// render.
@immutable
final class TexMathLayoutCacheKey {
  /// Creates a layout cache key with precomputed [hashCode].
  TexMathLayoutCacheKey({
    required this.source,
    required this.options,
    required this.fontId,
    this.fontSignature,
  }) : _hashCode = Object.hash(source, options, fontId, fontSignature);

  /// TeX math source expression.
  final String source;

  /// Effective rendering and budget options.
  final TexMathOptions options;

  /// Identifier of the active math font.
  final String fontId;

  /// Optional [MathFont.signature] distinguishing explicit fonts from the
  /// layouter's default configured font.
  final int? fontSignature;

  final int _hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathLayoutCacheKey &&
          _hashCode == other._hashCode &&
          source == other.source &&
          options == other.options &&
          fontId == other.fontId &&
          fontSignature == other.fontSignature;

  @override
  int get hashCode => _hashCode;

  @override
  String toString() =>
      'TexMathLayoutCacheKey(fontId: $fontId, '
      'fontSignature: $fontSignature, sourceLength: ${source.length})';
}

/// Runs TeX parsing and layout in a persistent background [Isolate] backed by
/// an in-memory bounded LRU result cache.
///
/// When constructed with [fontBytes] (or via [TexMathIsolateLayouter.withBundledFont]),
/// the raw SFNT font payload is transferred once to the background worker
/// isolate and decoded once via [MathFont.fromBytes], avoiding repeated
/// isolate spawns and font parsing across equations. Explicit [MathFont]
/// instances passed per request are also cached by [MathFont.signature] inside
/// the worker isolate after their first use.
final class TexMathIsolateLayouter {
  /// Creates a background layouter keeping at most [maxCacheEntries] results.
  TexMathIsolateLayouter({
    this.maxCacheEntries = 256,
    this.fontId = 'NewCMMath-Regular',
    this.fontBytes,
    this.shutdownTimeout = const Duration(milliseconds: 500),
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

  /// Grace period before [dispose] kills an unresponsive worker isolate.
  final Duration shutdownTimeout;

  final Map<TexMathLayoutCacheKey, RenderResult> _cache =
      <TexMathLayoutCacheKey, RenderResult>{};
  final Map<TexMathLayoutCacheKey, Future<RenderResult>> _inFlight =
      <TexMathLayoutCacheKey, Future<RenderResult>>{};
  final Map<int, Completer<RenderResult>> _pending =
      <int, Completer<RenderResult>>{};

  _WorkerSession? _activeSession;
  Future<_WorkerSession>? _workerFuture;
  Future<void>? _disposeFuture;
  int _nextRequestId = 1;
  int _hitCount = 0;
  int _missCount = 0;
  bool _disposed = false;

  /// Whether font bytes were supplied for persistent worker decoding.
  bool get hasFontBytes => fontBytes != null;

  /// Whether the persistent background worker isolate is currently active.
  bool get isWorkerRunning =>
      !_disposed &&
      _activeSession != null &&
      _activeSession!.commandPort != null &&
      !_activeSession!.closed;

  /// Whether [dispose] has been called on this layouter.
  bool get isDisposed => _disposed;

  /// Number of entries currently stored in the LRU cache.
  int get cacheLength => _cache.length;

  /// Number of [renderInBackground] calls satisfied directly from the cache.
  int get hitCount => _hitCount;

  /// Number of [renderInBackground] calls dispatched past the cache.
  int get missCount => _missCount;

  /// Current worker isolate instance exposed for lifecycle testing.
  @visibleForTesting
  Isolate? get debugWorkerIsolate => _activeSession?.isolate;

  /// Number of explicit font signatures sent to the active worker isolate.
  @visibleForTesting
  int get debugWorkerFontCacheCount =>
      _activeSession?.cachedFontSignatures.length ?? 0;

  /// Looks up a cached [RenderResult] for [source], [options], and optional
  /// [font], promoting any hit to most-recently-used.
  RenderResult? getCached(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    MathFont? font,
  }) {
    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
      fontSignature: font?.signature,
    );
    final RenderResult? hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
    }
    return hit;
  }

  /// Stores [result] in the bounded LRU cache under
  /// `(source, options, fontId, font?.signature)`.
  void putCached(
    String source,
    RenderResult result, {
    TexMathOptions options = const TexMathOptions(),
    MathFont? font,
  }) {
    if (maxCacheEntries == 0) {
      return;
    }
    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
      fontSignature: font?.signature,
    );
    _putCachedByKey(key, result);
  }

  void _putCachedByKey(TexMathLayoutCacheKey key, RenderResult result) {
    if (maxCacheEntries == 0) {
      return;
    }
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
    await runInRealAsyncZone<Future<_WorkerSession>>(_ensureWorker);
  }

  /// Renders [source] inside the persistent background [Isolate] and caches
  /// successful results.
  ///
  /// Returns cached entries synchronously without touching the background
  /// isolate, deduplicates concurrent in-flight renders for identical keys
  /// (including custom fonts), and propagates [TexMathError] instances and
  /// worker stack traces across the isolate boundary.
  Future<RenderResult> renderInBackground(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    TexMathEngine engine = const TexMathEngine(),
    MathFont? font,
  }) async {
    _checkNotDisposed();
    final MathFont? effectiveFont = font ?? engine.font;
    final RenderResult? cached = getCached(
      source,
      options: options,
      font: effectiveFont,
    );
    if (cached != null) {
      _hitCount++;
      return cached;
    }

    return runInRealAsyncZone<Future<RenderResult>>(() {
      _checkNotDisposed();
      final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
        source: source,
        options: options,
        fontId: fontId,
        fontSignature: effectiveFont?.signature,
      );
      final Future<RenderResult>? existing = _inFlight[key];
      if (existing != null) {
        return existing;
      }

      _missCount++;
      late final Future<RenderResult> future;
      future =
          _dispatchRender(
            source: source,
            options: options,
            font: effectiveFont,
            cacheKey: key,
          ).whenComplete(() {
            if (identical(_inFlight[key], future)) {
              _inFlight.remove(key);
            }
          });
      _inFlight[key] = future;
      return future;
    });
  }

  /// Lays out [source] in the background [Isolate] and returns its
  /// [DisplayList].
  Future<DisplayList> layoutInBackground(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    TexMathEngine engine = const TexMathEngine(),
    MathFont? font,
  }) async {
    final RenderResult result = await renderInBackground(
      source,
      options: options,
      engine: engine,
      font: font,
    );
    return result.displayList;
  }

  /// Shuts down the persistent background worker isolate and closes all ports,
  /// killing the worker with [Isolate.immediate] if it does not exit within
  /// [shutdownTimeout].
  Future<void> dispose() {
    if (_disposed) {
      return _disposeFuture ?? Future<void>.value();
    }
    _disposed = true;
    final Future<void> future = runInRealAsyncZone<Future<void>>(
      _disposeInternal,
    );
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeInternal() async {
    _failPendingRequests(
      StateError('TexMathIsolateLayouter has been disposed.'),
    );
    _inFlight.clear();

    _WorkerSession? session = _activeSession;
    final Future<_WorkerSession>? workerFuture = _workerFuture;
    _activeSession = null;
    _workerFuture = null;

    if (workerFuture != null && session?.commandPort == null) {
      workerFuture.ignore();
      try {
        session = await workerFuture.timeout(shutdownTimeout);
      } catch (_) {
        // Ignore startup errors or timeouts during teardown.
      }
    }

    if (session != null) {
      final SendPort? commandPort = session.commandPort;
      final Isolate? isolate = session.isolate;
      final Completer<void> exited = session.exited;
      if (commandPort != null && !session.closed) {
        commandPort.send(const _WorkerShutdown());
      }

      if (isolate != null && !exited.isCompleted) {
        if (commandPort == null) {
          isolate.kill(priority: Isolate.immediate);
          if (!exited.isCompleted) {
            exited.complete();
          }
        } else {
          Timer? killTimer;
          try {
            killTimer = Timer(shutdownTimeout, () {
              isolate.kill(priority: Isolate.immediate);
              if (!exited.isCompleted) {
                exited.complete();
              }
            });
            await exited.future;
          } finally {
            killTimer?.cancel();
          }
        }
      }

      session.closeChannels();
    }
  }

  Future<RenderResult> _dispatchRender({
    required String source,
    required TexMathOptions options,
    required MathFont? font,
    required TexMathLayoutCacheKey cacheKey,
  }) async {
    final _WorkerSession session = await _ensureWorker();
    _checkNotDisposed();

    final SendPort? workerPort = session.commandPort;
    if (session.closed ||
        workerPort == null ||
        !identical(_activeSession, session)) {
      throw StateError(
        'TexMathIsolateLayouter worker isolate exited unexpectedly.',
      );
    }

    final int requestId = _nextRequestId++;
    final Completer<RenderResult> completer = Completer<RenderResult>();
    _pending[requestId] = completer;

    final int? fontSignature = font?.signature;
    MathFont? fontToCache;
    bool addedSignature = false;
    if (font != null &&
        fontSignature != null &&
        fontSignature != session.defaultFontSignature &&
        !session.cachedFontSignatures.contains(fontSignature)) {
      fontToCache = font;
      addedSignature = session.cachedFontSignatures.add(fontSignature);
    }

    try {
      workerPort.send(
        _WorkerRenderRequest(
          requestId: requestId,
          source: source,
          options: options,
          fontSignature: fontSignature,
          fontToCache: fontToCache,
          replyPort: session.responsePort.sendPort,
        ),
      );
    } catch (_) {
      _pending.remove(requestId);
      if (addedSignature && fontSignature != null) {
        session.cachedFontSignatures.remove(fontSignature);
      }
      rethrow;
    }

    final RenderResult result = await completer.future;
    if (!_disposed) {
      _putCachedByKey(cacheKey, result);
    }
    return result;
  }

  Future<_WorkerSession> _ensureWorker() {
    _checkNotDisposed();
    if (_workerFuture != null) {
      return _workerFuture!;
    }
    final Future<_WorkerSession> future = _startWorker();
    _workerFuture = future;
    return future;
  }

  Future<_WorkerSession> _startWorker() async {
    final _WorkerSession session = _WorkerSession();
    final ReceivePort startupPort = ReceivePort();
    final Completer<Object?> startupCompleter = Completer<Object?>();

    _activeSession = session;

    final StreamSubscription<Object?> startupSub = startupPort.listen((
      Object? message,
    ) {
      if (!startupCompleter.isCompleted) {
        startupCompleter.complete(message);
      }
    });

    session.listen(
      onResponse: _handleWorkerResponse,
      onError: (Object? message) {
        final (Object error, StackTrace? trace) = _decodeIsolateError(message);
        if (!startupCompleter.isCompleted) {
          startupCompleter.completeError(error, trace);
        }
        if (!_disposed && identical(_activeSession, session)) {
          _handleWorkerCrash(session, error, trace);
        }
      },
      onExit: (Object? _) {
        if (!session.exited.isCompleted) {
          session.exited.complete();
        }
        final StateError exitError = StateError(
          'TexMathIsolateLayouter worker isolate exited unexpectedly.',
        );
        if (!startupCompleter.isCompleted) {
          startupCompleter.completeError(exitError);
        }
        if (!_disposed && identical(_activeSession, session)) {
          _handleWorkerCrash(session, exitError, null);
        }
      },
    );

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
        onError: session.errorPort.sendPort,
        onExit: session.exitPort.sendPort,
        errorsAreFatal: true,
        debugName: 'tex_math_isolate_layouter',
      );
      session.isolate = isolate;

      if (_disposed || !identical(_activeSession, session)) {
        isolate.kill(priority: Isolate.immediate);
        session.closeChannels();
        throw StateError(
          'TexMathIsolateLayouter worker startup was cancelled.',
        );
      }

      final Object? startupReply = await startupCompleter.future;
      if (startupReply is _WorkerStartupError) {
        final StackTrace? trace = _parseStackTrace(startupReply.stackTrace);
        if (trace != null) {
          Error.throwWithStackTrace(startupReply.error, trace);
        }
        throw startupReply.error;
      }
      final _WorkerStartupSuccess ready =
          startupReply! as _WorkerStartupSuccess;
      if (_disposed || !identical(_activeSession, session)) {
        ready.commandPort.send(const _WorkerShutdown());
        isolate.kill(priority: Isolate.immediate);
        session.closeChannels();
        throw StateError('TexMathIsolateLayouter has been disposed.');
      }
      session.defaultFontSignature = ready.defaultFontSignature;
      session.commandPort = ready.commandPort;
      return session;
    } catch (_) {
      session.isolate?.kill(priority: Isolate.immediate);
      if (identical(_activeSession, session)) {
        _activeSession = null;
        _workerFuture = null;
      }
      session.closeChannels();
      rethrow;
    } finally {
      startupPort.close();
      unawaited(startupSub.cancel());
    }
  }

  void _handleWorkerCrash(
    _WorkerSession session,
    Object error,
    StackTrace? stackTrace,
  ) {
    if (_disposed || !identical(_activeSession, session)) {
      return;
    }
    _activeSession = null;
    _workerFuture = null;
    session.closeChannels();
    _failPendingRequests(error, stackTrace);
  }

  void _failPendingRequests(Object error, [StackTrace? stackTrace]) {
    if (_pending.isEmpty) {
      return;
    }
    final List<Completer<RenderResult>> pending = _pending.values.toList();
    _pending.clear();
    for (final Completer<RenderResult> completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
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
        final StackTrace? trace = _parseStackTrace(message.stackTrace);
        completer.completeError(message.error, trace);
      }
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TexMathIsolateLayouter has been disposed.');
    }
  }
}

final class _WorkerSession {
  final ReceivePort responsePort = ReceivePort();
  final ReceivePort errorPort = ReceivePort();
  final ReceivePort exitPort = ReceivePort();
  final Completer<void> exited = Completer<void>();
  final Set<int> cachedFontSignatures = <int>{};

  StreamSubscription<Object?>? _responseSub;
  StreamSubscription<Object?>? _errorSub;
  StreamSubscription<Object?>? _exitSub;
  Isolate? isolate;
  SendPort? commandPort;
  int? defaultFontSignature;
  bool closed = false;

  void listen({
    required void Function(Object? message) onResponse,
    required void Function(Object? message) onError,
    required void Function(Object? message) onExit,
  }) {
    _responseSub = responsePort.listen(onResponse);
    _errorSub = errorPort.listen(onError);
    _exitSub = exitPort.listen(onExit);
  }

  void closeChannels() {
    if (closed) {
      return;
    }
    closed = true;
    responsePort.close();
    errorPort.close();
    exitPort.close();

    if (_responseSub != null) {
      unawaited(_responseSub!.cancel());
      _responseSub = null;
    }
    if (_errorSub != null) {
      unawaited(_errorSub!.cancel());
      _errorSub = null;
    }
    if (_exitSub != null) {
      unawaited(_exitSub!.cancel());
      _exitSub = null;
    }
  }
}

(Object, StackTrace?) _decodeIsolateError(Object? message) {
  if (message is List<Object?> && message.isNotEmpty) {
    final String errorText = message[0]?.toString() ?? 'Worker isolate error';
    final StackTrace? trace = message.length > 1
        ? _parseStackTrace(message[1]?.toString())
        : null;
    return (StateError('Worker isolate crashed: $errorText'), trace);
  }
  return (StateError('Worker isolate crashed: $message'), null);
}

StackTrace? _parseStackTrace(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return StackTrace.fromString(raw);
}

@immutable
final class _WorkerInit {
  const _WorkerInit({required this.startupReplyPort, required this.fontBytes});

  final SendPort startupReplyPort;
  final TransferableTypedData? fontBytes;
}

@immutable
final class _WorkerStartupSuccess {
  const _WorkerStartupSuccess(this.commandPort, this.defaultFontSignature);

  final SendPort commandPort;
  final int? defaultFontSignature;
}

@immutable
final class _WorkerStartupError {
  const _WorkerStartupError(this.error, this.stackTrace);

  final Exception error;
  final String? stackTrace;
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
    required this.fontSignature,
    required this.fontToCache,
    required this.replyPort,
  });

  final int requestId;
  final String source;
  final TexMathOptions options;
  final int? fontSignature;
  final MathFont? fontToCache;
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
  const _WorkerRenderFailure(this.requestId, this.error, this.stackTrace);

  final int requestId;
  final Object error;
  final String? stackTrace;
}

Future<void> _workerMain(_WorkerInit init) async {
  MathFont? workerFont;
  final Map<int, MathFont> fontCache = <int, MathFont>{};
  if (init.fontBytes != null) {
    try {
      final Uint8List bytes = init.fontBytes!.materialize().asUint8List();
      workerFont = MathFont.fromBytes(bytes);
      fontCache[workerFont.signature] = workerFont;
    } catch (error, stackTrace) {
      final String stackString = stackTrace.toString();
      final Exception failure = error is Exception
          ? error
          : TexMathFontError('Worker font load failed: $error');
      try {
        init.startupReplyPort.send(_WorkerStartupError(failure, stackString));
      } catch (_) {
        init.startupReplyPort.send(
          _WorkerStartupError(
            TexMathFontError('Worker font load failed: $error'),
            stackString,
          ),
        );
      }
      return;
    }
  }

  final ReceivePort commandPort = ReceivePort();
  init.startupReplyPort.send(
    _WorkerStartupSuccess(commandPort.sendPort, workerFont?.signature),
  );

  await for (final Object? message in commandPort) {
    if (message is _WorkerShutdown) {
      commandPort.close();
      break;
    }
    if (message is _WorkerRenderRequest) {
      try {
        if (message.fontToCache != null) {
          final MathFont cachedFont = message.fontToCache!;
          fontCache[cachedFont.signature] = cachedFont;
        }
        final MathFont? effectiveFont;
        if (message.fontSignature != null) {
          effectiveFont =
              fontCache[message.fontSignature!] ??
              (throw TexMathFontError(
                'Missing cached worker MathFont for signature '
                '${message.fontSignature}.',
              ));
        } else {
          effectiveFont = workerFont;
        }
        final RenderResult result = const TexMathEngine().render(
          message.source,
          options: message.options,
          font: effectiveFont,
        );
        try {
          message.replyPort.send(
            _WorkerRenderSuccess(message.requestId, result),
          );
        } catch (sendError, sendStack) {
          message.replyPort.send(
            _WorkerRenderFailure(
              message.requestId,
              TexMathFontError('Worker reply serialization failed: $sendError'),
              sendStack.toString(),
            ),
          );
        }
      } catch (error, stackTrace) {
        final String stackString = stackTrace.toString();
        try {
          message.replyPort.send(
            _WorkerRenderFailure(message.requestId, error, stackString),
          );
        } catch (_) {
          message.replyPort.send(
            _WorkerRenderFailure(
              message.requestId,
              TexMathFontError('Worker render failed: $error'),
              stackString,
            ),
          );
        }
      }
    }
  }
}
