import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:tex_math/tex_math.dart';

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

/// Runs TeX parsing and layout in a background [Isolate] with an in-memory
/// bounded result cache.
final class TexMathIsolateLayouter {
  /// Creates a background layouter keeping at most [maxCacheEntries] results.
  TexMathIsolateLayouter({
    this.maxCacheEntries = 256,
    this.fontId = 'NewCMMath-Regular',
  }) : assert(maxCacheEntries >= 0, 'maxCacheEntries must be non-negative');

  /// Maximum number of cached [RenderResult] entries retained in memory.
  final int maxCacheEntries;

  /// Font identifier included in cache keys.
  final String fontId;

  final Map<TexMathLayoutCacheKey, RenderResult> _cache =
      <TexMathLayoutCacheKey, RenderResult>{};

  /// Number of entries currently stored in the cache.
  int get cacheLength => _cache.length;

  /// Looks up a cached [RenderResult] for [source] and [options].
  RenderResult? getCached(
    String source, {
    TexMathOptions options = const TexMathOptions(),
  }) {
    final TexMathLayoutCacheKey key = TexMathLayoutCacheKey(
      source: source,
      options: options,
      fontId: fontId,
    );
    return _cache[key];
  }

  /// Stores [result] in the bounded cache under `(source, options, fontId)`.
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
    if (_cache.length >= maxCacheEntries && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  /// Clears all cached layout results.
  void clearCache() {
    _cache.clear();
  }

  /// Renders [source] inside a background [Isolate] and caches successful
  /// results.
  ///
  /// Propagates [TexMathError] instances (including [TexMathBudgetError] and
  /// Phase 1 [TexMathUnsupportedError]) across the isolate boundary.
  Future<RenderResult> renderInBackground(
    String source, {
    TexMathOptions options = const TexMathOptions(),
    TexMathEngine engine = const TexMathEngine(),
  }) async {
    final RenderResult? cached = getCached(source, options: options);
    if (cached != null) {
      return cached;
    }
    final RenderResult result = await Isolate.run<RenderResult>(
      () => engine.render(source, options: options),
    );
    putCached(source, result, options: options);
    return result;
  }

  /// Lays out [source] in a background [Isolate] and returns its [DisplayList].
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
}
