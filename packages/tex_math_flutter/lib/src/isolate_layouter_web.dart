import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'async_zone.dart';
import 'font_bundle.dart';
import 'isolate_layouter_cache_key.dart';

/// Runs TeX parsing and layout asynchronously on Web and Wasm targets where
/// `dart:isolate` is unavailable, backed by an in-memory bounded LRU cache.
///
/// Matches the native `TexMathIsolateLayouter` API so widgets and shared code
/// run identically across native, Web, and Wasm builds.
final class TexMathIsolateLayouter {
  /// Creates an asynchronous layouter keeping at most [maxCacheEntries]
  /// results.
  TexMathIsolateLayouter({
    this.maxCacheEntries = 256,
    this.fontId = 'NewCMMath-Regular',
    this.fontBytes,
    this.shutdownTimeout = const Duration(milliseconds: 500),
  }) : assert(maxCacheEntries >= 0, 'maxCacheEntries must be non-negative');

  /// Creates a layouter preconfigured with the bundled `NewCMMath-Regular.otf`
  /// asset bytes from [TexMathFontBundle].
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

  /// Optional raw SFNT font payload decoded once on [warmUp] or first render.
  final Uint8List? fontBytes;

  /// Retained for API parity with native worker shutdown configuration.
  final Duration shutdownTimeout;

  final Map<TexMathLayoutCacheKey, RenderResult> _cache =
      <TexMathLayoutCacheKey, RenderResult>{};
  final Map<TexMathLayoutCacheKey, Future<RenderResult>> _inFlight =
      <TexMathLayoutCacheKey, Future<RenderResult>>{};
  final Set<int> _cachedFontSignatures = <int>{};

  MathFont? _defaultFont;
  bool _started = false;
  bool _disposed = false;
  int _hitCount = 0;
  int _missCount = 0;

  /// Whether font bytes were supplied for persistent worker decoding.
  bool get hasFontBytes => fontBytes != null;

  /// Whether the layouter session is currently active.
  bool get isWorkerRunning => !_disposed && _started;

  /// Whether [dispose] has been called on this layouter.
  bool get isDisposed => _disposed;

  /// Number of entries currently stored in the LRU cache.
  int get cacheLength => _cache.length;

  /// Number of [renderInBackground] calls satisfied directly from the cache.
  int get hitCount => _hitCount;

  /// Number of [renderInBackground] calls dispatched past the cache.
  int get missCount => _missCount;

  /// Always `null` on Web/Wasm targets where `dart:isolate` is unavailable.
  @visibleForTesting
  Object? get debugWorkerIsolate => null;

  /// Number of distinct explicit font signatures seen by this layouter.
  @visibleForTesting
  int get debugWorkerFontCacheCount => _cachedFontSignatures.length;

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

  /// Decodes any supplied [fontBytes] and marks the layouter ready.
  Future<void> warmUp() async {
    _checkNotDisposed();
    await runInRealAsyncZone<Future<void>>(() async {
      await Future<void>.value();
      _ensureInitialized();
    });
  }

  /// Renders [source] asynchronously and caches successful results.
  ///
  /// Returns cached entries immediately, deduplicates concurrent in-flight
  /// renders for identical keys, and propagates [TexMathError] instances and
  /// stack traces.
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
          Future<RenderResult>(() {
            _checkNotDisposed();
            _ensureInitialized();
            final MathFont? resolvedFont = effectiveFont ?? _defaultFont;
            if (effectiveFont != null &&
                effectiveFont.signature != _defaultFont?.signature) {
              _cachedFontSignatures.add(effectiveFont.signature);
            }
            final RenderResult result = const TexMathEngine().render(
              source,
              options: options,
              font: resolvedFont,
            );
            if (!_disposed) {
              _putCachedByKey(key, result);
            }
            return result;
          }).whenComplete(() {
            if (identical(_inFlight[key], future)) {
              _inFlight.remove(key);
            }
          });
      _inFlight[key] = future;
      return future;
    });
  }

  /// Lays out [source] asynchronously and returns its [DisplayList].
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

  /// Marks the layouter as disposed and clears active state.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;
    _inFlight.clear();
  }

  void _ensureInitialized() {
    _checkNotDisposed();
    if (!_started) {
      if (fontBytes != null && _defaultFont == null) {
        _defaultFont = MathFont.fromBytes(fontBytes!);
      }
      _started = true;
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('TexMathIsolateLayouter has been disposed.');
    }
  }
}
