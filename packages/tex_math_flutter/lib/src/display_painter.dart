import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:tex_math/tex_math.dart';

import 'theme.dart';

/// Cache mapping `(fontSignature, glyphId)` pairs (and standalone
/// [GlyphOutline] records when no font or signature is attached) to reusable
/// Flutter [Path] geometry, plus a bounded LRU cache of fallback [TextPainter]s.
///
/// Caching paths per `(fontSignature, glyphId)` allows theme color updates and
/// repeated expressions (including isolate-laid-out display lists) to repaint
/// directly on the GPU without rebuilding outlines or invoking
/// [TexMathEngine.render].
final class TexMathPathCache {
  /// Creates a glyph path cache retaining at most [maxEntries] path entries and
  /// [maxTextPainterEntries] fallback [TextPainter] entries.
  TexMathPathCache({
    this.maxEntries = defaultMaxEntries,
    int? maxTextPainterEntries,
  }) : assert(maxEntries >= 0, 'maxEntries must be non-negative'),
       assert(
         maxTextPainterEntries == null || maxTextPainterEntries >= 0,
         'maxTextPainterEntries must be non-negative',
       ),
       maxTextPainterEntries =
           maxTextPainterEntries ??
           (maxEntries == 0
               ? 0
               : math.min(maxEntries, _defaultMaxTextPainters));

  /// Default maximum number of cached glyph paths retained in memory.
  static const int defaultMaxEntries = 4096;

  static const int _defaultMaxTextPainters = 256;

  /// Sentinel stored for empty glyphs (such as spaces) so cache hits are
  /// tracked in a single map lookup without returning invalid paths.
  static final Path _emptyPathSentinel = Path();

  /// Process-wide shared cache reused across [TexMathDisplayPainter] and
  /// [TexMath] instances when no explicit cache is provided.
  static final TexMathPathCache shared = TexMathPathCache();

  /// Maximum number of cached path entries retained across font and outline
  /// keys.
  final int maxEntries;

  /// Maximum number of fallback [TextPainter] instances retained in memory.
  final int maxTextPainterEntries;

  final Map<Object, Path> _entries = <Object, Path>{};
  final Map<_FallbackTextKey, TextPainter> _textPainterCache =
      <_FallbackTextKey, TextPainter>{};

  final Paint _highlightPaint = Paint()..style = PaintingStyle.fill;
  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _strokePaint = Paint()..style = PaintingStyle.stroke;

  int _hitCount = 0;
  int _buildCount = 0;
  int _textPainterHitCount = 0;
  int _textPainterBuildCount = 0;
  int _textPainterDisposedCount = 0;

  /// Number of glyph path entries currently stored in this cache.
  int get length => _entries.length;

  /// Number of glyph path cache lookups satisfied without constructing a new
  /// [Path].
  int get hitCount => _hitCount;

  /// Number of [Path] instances constructed by this cache.
  int get buildCount => _buildCount;

  /// Number of fallback [TextPainter] entries currently stored in this cache.
  @visibleForTesting
  int get textPainterLength => _textPainterCache.length;

  /// Number of fallback [TextPainter] lookups satisfied from the LRU cache.
  @visibleForTesting
  int get textPainterHitCount => _textPainterHitCount;

  /// Number of fallback [TextPainter] instances constructed by this cache.
  @visibleForTesting
  int get textPainterBuildCount => _textPainterBuildCount;

  /// Number of fallback [TextPainter] instances disposed on eviction or [clear].
  @visibleForTesting
  int get textPainterDisposedCount => _textPainterDisposedCount;

  /// Returns a cached [Path] for `(font, glyphId)` or builds and caches one
  /// from [outline] or `font.outlineForGlyph(glyphId)`.
  ///
  /// Returns `null` when the glyph has no outline contours (such as spaces).
  Path? pathForGlyph(
    MathFont font,
    int glyphId, {
    GlyphOutline? outline,
    int? ppemBucket,
  }) {
    return resolvePath(
      glyphId: glyphId,
      font: font,
      outline: outline,
      ppemBucket: ppemBucket,
    );
  }

  /// Resolves a cached [Path] for [glyphId] using [font] or [fontSignature]
  /// when available, or [outline] directly for standalone display lists.
  Path? resolvePath({
    required int glyphId,
    MathFont? font,
    GlyphOutline? outline,
    int? fontSignature,
    int? ppemBucket,
  }) {
    final bool hasRealFont = font != null && font.numGlyphs > 0;
    final int? effectiveSignature = hasRealFont
        ? font.signature
        : fontSignature;

    if (effectiveSignature != null) {
      final _FontGlyphKey key = _FontGlyphKey(
        effectiveSignature,
        glyphId,
        ppemBucket,
      );
      if (maxEntries > 0) {
        final Path? cached = _entries.remove(key);
        if (cached != null) {
          _entries[key] = cached;
          _hitCount++;
          return identical(cached, _emptyPathSentinel) ? null : cached;
        }
      }
      final GlyphOutline? effectiveOutline =
          outline ?? (hasRealFont ? font.outlineForGlyph(glyphId) : null);
      if (effectiveOutline == null || effectiveOutline.isEmpty) {
        _insertEntry(key, _emptyPathSentinel);
        return null;
      }
      final Path built = TexMathDisplayPainter.buildPathFromCommands(
        effectiveOutline.commands,
      );
      _buildCount++;
      _insertEntry(key, built);
      return built;
    }

    if (outline == null || outline.isEmpty) {
      return null;
    }
    if (maxEntries > 0) {
      final Path? cached = _entries.remove(outline);
      if (cached != null) {
        _entries[outline] = cached;
        _hitCount++;
        return cached;
      }
    }
    final Path built = TexMathDisplayPainter.buildPathFromCommands(
      outline.commands,
    );
    _buildCount++;
    _insertEntry(outline, built);
    return built;
  }

  TextPainter _resolveFallbackTextPainter({
    required int codePoint,
    required Color color,
    required double fontSize,
    required double scaleY,
  }) {
    final int argb = color.toARGB32();
    final _FallbackTextKey key = _FallbackTextKey(
      codePoint,
      argb,
      fontSize,
      scaleY,
    );
    final TextPainter? cached = _textPainterCache.remove(key);
    if (cached != null) {
      _textPainterCache[key] = cached;
      _textPainterHitCount++;
      return cached;
    }

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(codePoint),
        style: TextStyle(color: color, fontSize: fontSize * scaleY),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _textPainterBuildCount++;

    while (_textPainterCache.length >= maxTextPainterEntries) {
      final _FallbackTextKey oldestKey = _textPainterCache.keys.first;
      final TextPainter? evicted = _textPainterCache.remove(oldestKey);
      if (evicted != null) {
        _disposeTextPainter(evicted);
      }
    }
    _textPainterCache[key] = painter;
    return painter;
  }

  void _disposeTextPainter(TextPainter painter) {
    painter.dispose();
    assert(painter.debugDisposed);
    _textPainterDisposedCount++;
  }

  /// Removes all cached [Path] and [TextPainter] entries (disposing any cached
  /// [TextPainter] resources) and resets cache counters.
  void clear() {
    _entries.clear();
    for (final TextPainter painter in _textPainterCache.values) {
      _disposeTextPainter(painter);
    }
    _textPainterCache.clear();
    _hitCount = 0;
    _buildCount = 0;
    _textPainterHitCount = 0;
    _textPainterBuildCount = 0;
  }

  void _insertEntry(Object key, Path path) {
    if (maxEntries == 0) {
      return;
    }
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = path;
  }
}

@immutable
final class _FontGlyphKey {
  const _FontGlyphKey(this.fontSignature, this.glyphId, [this.ppemBucket]);

  final int fontSignature;
  final int glyphId;
  final int? ppemBucket;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FontGlyphKey &&
          fontSignature == other.fontSignature &&
          glyphId == other.glyphId &&
          ppemBucket == other.ppemBucket;

  @override
  int get hashCode => Object.hash(fontSignature, glyphId, ppemBucket);
}

@immutable
final class _FallbackTextKey {
  const _FallbackTextKey(this.codePoint, this.argb, this.fontSize, this.scaleY);

  final int codePoint;
  final int argb;
  final double fontSize;
  final double scaleY;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FallbackTextKey &&
          codePoint == other.codePoint &&
          argb == other.argb &&
          fontSize == other.fontSize &&
          scaleY == other.scaleY;

  @override
  int get hashCode => Object.hash(codePoint, argb, fontSize, scaleY);
}

/// Paints a laid-out [DisplayList] onto a Flutter [Canvas] using theme colors
/// from [TexMathThemeData] and cached glyph [Path] geometry.
final class TexMathDisplayPainter extends CustomPainter {
  /// Creates a display list painter.
  const TexMathDisplayPainter({
    required this.displayList,
    required this.theme,
    required this.fontSize,
    this.font,
    this.pathCache,
    this.selectionRects = const <Rect>[],
    this.selectionColor,
  });

  /// Laid-out display list to paint.
  final DisplayList displayList;

  /// Active theme providing semantic colors.
  final TexMathThemeData theme;

  /// Logical pixel size corresponding to `1.0` em.
  final double fontSize;

  /// Optional active [MathFont] used for `(fontSignature, glyphId)` path
  /// caching and outline lookup.
  final MathFont? font;

  /// Optional glyph path cache overriding [TexMathPathCache.shared].
  final TexMathPathCache? pathCache;

  /// Optional local-space highlight rectangles drawn behind selected glyphs.
  final List<Rect> selectionRects;

  /// Optional highlight color for [selectionRects].
  final Color? selectionColor;

  /// Converts pure-Dart [PathCommand] contours into a Flutter [Path].
  static Path buildPathFromCommands(List<PathCommand> commands) {
    final Path path = Path();
    for (final PathCommand command in commands) {
      switch (command) {
        case MoveTo(:final double x, :final double y):
          path.moveTo(x, y);
        case LineTo(:final double x, :final double y):
          path.lineTo(x, y);
        case QuadTo(
          :final double controlX,
          :final double controlY,
          :final double x,
          :final double y,
        ):
          path.quadraticBezierTo(controlX, controlY, x, y);
        case CubicTo(
          :final double control1X,
          :final double control1Y,
          :final double control2X,
          :final double control2Y,
          :final double x,
          :final double y,
        ):
          path.cubicTo(control1X, control1Y, control2X, control2Y, x, y);
        case ClosePath():
          path.close();
      }
    }
    return path;
  }

  /// Paints [displayList] directly onto [canvas] without allocating a
  /// [TexMathDisplayPainter] wrapper.
  static void paintDisplayList(
    Canvas canvas, {
    required DisplayList displayList,
    required TexMathThemeData theme,
    required double fontSize,
    MathFont? font,
    TexMathPathCache? pathCache,
    List<Rect> selectionRects = const <Rect>[],
    Color? selectionColor,
  }) {
    final TexMathPathCache effectiveCache =
        pathCache ?? TexMathPathCache.shared;

    if (selectionRects.isNotEmpty) {
      final Paint highlightPaint = effectiveCache._highlightPaint
        ..color = selectionColor ?? theme.accent.withValues(alpha: 0.28);
      for (final Rect rect in selectionRects) {
        canvas.drawRect(rect, highlightPaint);
      }
    }

    final DisplayMetrics metrics = displayList.metrics;
    final double safeFontSize = resolveSafeTexMathFontSize(
      fontSize,
      theme: theme,
    );
    final double unitsScale = safeFontSize / metrics.unitsPerEm;
    final Paint fillPaint = effectiveCache._fillPaint;
    final Paint strokePaint = effectiveCache._strokePaint;
    final int? displayFontSignature = displayList.fontSignature;

    for (final DisplayItem item in displayList.items) {
      final Color resolvedColor = theme.colorForRole(
        item.colorRole,
        customColorValue: item.customColor,
      );

      switch (item) {
        case RuleItem(
          :final double xEm,
          :final double yEm,
          :final double widthEm,
          :final double heightEm,
          :final double? strokeWidthEm,
        ):
          final double left = xEm * safeFontSize;
          final double top =
              (metrics.baselineEm - (yEm + heightEm)) * safeFontSize;
          final double width = widthEm * safeFontSize;
          final double height = heightEm * safeFontSize;
          final Rect rect = Rect.fromLTWH(left, top, width, height);
          if (strokeWidthEm != null && strokeWidthEm > 0) {
            strokePaint
              ..color = resolvedColor
              ..strokeWidth = strokeWidthEm * safeFontSize;
            canvas.drawRect(rect, strokePaint);
          } else {
            fillPaint.color = resolvedColor;
            canvas.drawRect(rect, fillPaint);
          }

        case GlyphItem(
          :final int glyphId,
          :final int codePoint,
          :final double xEm,
          :final double yEm,
          :final double scaleX,
          :final double scaleY,
          :final GlyphOutline? outline,
        ):
          final double dx = xEm * safeFontSize;
          final double dy = (metrics.baselineEm - yEm) * safeFontSize;
          if (outline != null || font != null) {
            final Path? path = effectiveCache.resolvePath(
              glyphId: glyphId,
              font: font,
              outline: outline,
              fontSignature: displayFontSignature,
            );
            if (path != null) {
              fillPaint.color = resolvedColor;
              canvas
                ..save()
                ..translate(dx, dy)
                ..scale(unitsScale * scaleX, -unitsScale * scaleY)
                ..drawPath(path, fillPaint)
                ..restore();
            }
          } else if (_isPrintableFallbackCodePoint(codePoint)) {
            if (effectiveCache.maxTextPainterEntries == 0) {
              final TextPainter textPainter = TextPainter(
                text: TextSpan(
                  text: String.fromCharCode(codePoint),
                  style: TextStyle(
                    color: resolvedColor,
                    fontSize: safeFontSize * scaleY,
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout();
              effectiveCache._textPainterBuildCount++;
              try {
                textPainter.paint(
                  canvas,
                  Offset(
                    dx,
                    dy -
                        textPainter.computeDistanceToActualBaseline(
                          TextBaseline.alphabetic,
                        ),
                  ),
                );
              } finally {
                effectiveCache._disposeTextPainter(textPainter);
              }
            } else {
              final TextPainter textPainter = effectiveCache
                  ._resolveFallbackTextPainter(
                    codePoint: codePoint,
                    color: resolvedColor,
                    fontSize: safeFontSize,
                    scaleY: scaleY,
                  );
              textPainter.paint(
                canvas,
                Offset(
                  dx,
                  dy -
                      textPainter.computeDistanceToActualBaseline(
                        TextBaseline.alphabetic,
                      ),
                ),
              );
            }
          }

        case AnchorItem():
          // Anchors are non-inked structural coordinates.
          break;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    paintDisplayList(
      canvas,
      displayList: displayList,
      theme: theme,
      fontSize: fontSize,
      font: font,
      pathCache: pathCache,
      selectionRects: selectionRects,
      selectionColor: selectionColor,
    );
  }

  @override
  bool shouldRepaint(TexMathDisplayPainter oldDelegate) {
    return fontSize != oldDelegate.fontSize ||
        !identical(pathCache, oldDelegate.pathCache) ||
        selectionColor != oldDelegate.selectionColor ||
        theme != oldDelegate.theme ||
        (!identical(font, oldDelegate.font) && font != oldDelegate.font) ||
        (!identical(selectionRects, oldDelegate.selectionRects) &&
            !listEquals(selectionRects, oldDelegate.selectionRects)) ||
        (!identical(displayList, oldDelegate.displayList) &&
            displayList != oldDelegate.displayList);
  }

  static bool _isPrintableFallbackCodePoint(int codePoint) {
    if (codePoint < 0x20 || codePoint == 0x7F || codePoint > 0x10FFFF) {
      return false;
    }
    if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
      return false;
    }
    if (codePoint >= 0x2061 && codePoint <= 0x2064) {
      return false;
    }
    return true;
  }
}
