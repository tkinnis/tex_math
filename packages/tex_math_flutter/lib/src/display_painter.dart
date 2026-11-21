import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:tex_math/tex_math.dart';

import 'theme.dart';

/// Cache mapping `(MathFont, glyphId)` pairs (and standalone [GlyphOutline]
/// records when no [MathFont] is attached) to reusable Flutter [Path] geometry.
///
/// Caching paths per `(font, glyphId)` allows theme color updates and repeated
/// expressions to repaint directly on the GPU without rebuilding outlines or
/// invoking [TexMathEngine.render].
final class TexMathPathCache {
  /// Creates a glyph path cache retaining at most [maxEntries] entries.
  TexMathPathCache({this.maxEntries = defaultMaxEntries})
    : assert(maxEntries >= 0, 'maxEntries must be non-negative');

  /// Default maximum number of cached glyph paths retained in memory.
  static const int defaultMaxEntries = 4096;

  /// Process-wide shared cache reused across [TexMathDisplayPainter] and
  /// [TexMath] instances when no explicit cache is provided.
  static final TexMathPathCache shared = TexMathPathCache();

  /// Maximum number of cached entries retained across font and outline keys.
  final int maxEntries;

  final Map<_FontGlyphKey, Path?> _fontCache = <_FontGlyphKey, Path?>{};
  final Map<GlyphOutline, Path> _outlineCache = <GlyphOutline, Path>{};

  int _hitCount = 0;
  int _buildCount = 0;

  /// Number of entries currently stored in this cache.
  int get length => _fontCache.length + _outlineCache.length;

  /// Number of cache lookups satisfied without constructing a new [Path].
  int get hitCount => _hitCount;

  /// Number of [Path] instances constructed by this cache.
  int get buildCount => _buildCount;

  /// Returns a cached [Path] for `(font, glyphId)` or builds and caches one
  /// from [outline] or `font.outlineForGlyph(glyphId)`.
  ///
  /// Returns `null` when the glyph has no outline contours (such as spaces).
  Path? pathForGlyph(MathFont font, int glyphId, {GlyphOutline? outline}) {
    return resolvePath(glyphId: glyphId, font: font, outline: outline);
  }

  /// Resolves a cached [Path] for [glyphId] using [font] when a decoded font
  /// is available, or [outline] directly for standalone display lists.
  Path? resolvePath({
    required int glyphId,
    MathFont? font,
    GlyphOutline? outline,
  }) {
    if (font != null && font.numGlyphs > 0) {
      if (outline != null && outline.isEmpty) {
        return null;
      }
      final _FontGlyphKey key = _FontGlyphKey(font, glyphId);
      if (maxEntries > 0 && _fontCache.containsKey(key)) {
        final Path? cached = _fontCache.remove(key);
        _fontCache[key] = cached;
        _hitCount++;
        return cached;
      }
      final GlyphOutline? effectiveOutline =
          outline ?? font.outlineForGlyph(glyphId);
      if (effectiveOutline == null || effectiveOutline.isEmpty) {
        _insertFontEntry(key, null);
        return null;
      }
      final Path built = TexMathDisplayPainter.buildPathFromCommands(
        effectiveOutline.commands,
      );
      _buildCount++;
      _insertFontEntry(key, built);
      return built;
    }

    if (outline == null || outline.isEmpty) {
      return null;
    }
    if (maxEntries > 0 && _outlineCache.containsKey(outline)) {
      final Path cached = _outlineCache.remove(outline)!;
      _outlineCache[outline] = cached;
      _hitCount++;
      return cached;
    }
    final Path built = TexMathDisplayPainter.buildPathFromCommands(
      outline.commands,
    );
    _buildCount++;
    _insertOutlineEntry(outline, built);
    return built;
  }

  /// Removes all cached [Path] entries and resets cache counters.
  void clear() {
    _fontCache.clear();
    _outlineCache.clear();
    _hitCount = 0;
    _buildCount = 0;
  }

  void _insertFontEntry(_FontGlyphKey key, Path? path) {
    if (maxEntries == 0) {
      return;
    }
    _evictIfFull();
    _fontCache[key] = path;
  }

  void _insertOutlineEntry(GlyphOutline outline, Path path) {
    if (maxEntries == 0) {
      return;
    }
    _evictIfFull();
    _outlineCache[outline] = path;
  }

  void _evictIfFull() {
    while (length >= maxEntries) {
      if (_fontCache.isNotEmpty) {
        _fontCache.remove(_fontCache.keys.first);
      } else if (_outlineCache.isNotEmpty) {
        _outlineCache.remove(_outlineCache.keys.first);
      } else {
        break;
      }
    }
  }
}

@immutable
final class _FontGlyphKey {
  const _FontGlyphKey(this.font, this.glyphId);

  final MathFont font;
  final int glyphId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FontGlyphKey &&
          glyphId == other.glyphId &&
          (identical(font, other.font) || font == other.font);

  @override
  int get hashCode => Object.hash(font, glyphId);
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

  /// Optional active [MathFont] used for `(font, glyphId)` path caching and
  /// outline lookup.
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

  @override
  void paint(Canvas canvas, Size size) {
    if (selectionRects.isNotEmpty) {
      final Paint highlightPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = selectionColor ?? theme.accent.withValues(alpha: 0.28);
      for (final Rect rect in selectionRects) {
        canvas.drawRect(rect, highlightPaint);
      }
    }

    final DisplayMetrics metrics = displayList.metrics;
    final double safeFontSize = fontSize.isFinite && fontSize > 0
        ? fontSize
        : theme.fontSize;
    final double unitsScale = safeFontSize / metrics.unitsPerEm;
    final TexMathPathCache effectiveCache =
        pathCache ?? TexMathPathCache.shared;
    final Paint fillPaint = Paint()..style = PaintingStyle.fill;
    final Paint strokePaint = Paint()..style = PaintingStyle.stroke;

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

        case AnchorItem():
          // Anchors are non-inked structural coordinates.
          break;
      }
    }
  }

  @override
  bool shouldRepaint(TexMathDisplayPainter oldDelegate) {
    return displayList != oldDelegate.displayList ||
        theme != oldDelegate.theme ||
        fontSize != oldDelegate.fontSize ||
        font != oldDelegate.font ||
        !identical(pathCache, oldDelegate.pathCache) ||
        selectionColor != oldDelegate.selectionColor ||
        !listEquals(selectionRects, oldDelegate.selectionRects);
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
