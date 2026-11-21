import 'package:meta/meta.dart';

import 'ast.dart';
import 'error.dart';
import 'export/mathml.dart';
import 'export/spoken_text.dart';
import 'font/outline.dart';
import 'format_utils.dart';
import 'options.dart';
import 'source_span.dart';

/// Semantic classification of a potential line-breaking opportunity in math.
enum MathBreakKind {
  /// No automatic line break opportunity attached to this box.
  none,

  /// Discretionary break opportunity immediately after a binary operator.
  afterBinary,

  /// Discretionary break opportunity immediately after a relation symbol.
  afterRelation,

  /// Explicit numeric break penalty attached to a box.
  penalty,

  /// Explicit forced line break (such as `\\` in multiline structures).
  explicit,
}

/// Line-breaking metadata attached to laid-out boxes for downstream wrapping.
@immutable
final class BreakPoint {
  /// Creates break-hint metadata describing whether and how a line break may
  /// occur at this box boundary.
  const BreakPoint({
    this.kind = MathBreakKind.none,
    this.penalty = 0,
    this.isExplicit = false,
    this.isGood = false,
  });

  /// Sentinel representing the absence of any break hint.
  static const BreakPoint none = BreakPoint();

  /// Category of this break hint.
  final MathBreakKind kind;

  /// TeX-style line-breaking penalty value (`0` for neutral).
  final int penalty;

  /// Whether this break point forces a mandatory line break.
  final bool isExplicit;

  /// Whether this break point represents a preferred break site.
  final bool isGood;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BreakPoint &&
          kind == other.kind &&
          penalty == other.penalty &&
          isExplicit == other.isExplicit &&
          isGood == other.isGood;

  @override
  int get hashCode => Object.hash(kind, penalty, isExplicit, isGood);

  @override
  String toString() =>
      'BreakPoint(kind: $kind, penalty: $penalty, '
      'isExplicit: $isExplicit, isGood: $isGood)';
}

/// Positioned line-break opportunity emitted at top-level split boundaries.
@immutable
final class DisplayBreakHint {
  /// Creates a break-point hint at [xEm] immediately following [afterItemIndex].
  const DisplayBreakHint({
    required this.xEm,
    required this.afterItemIndex,
    required this.breakPoint,
    this.span,
  });

  /// Horizontal break coordinate from the display-list origin in ems.
  final double xEm;

  /// Index in [DisplayList.items] of the last item preceding the break (`-1`
  /// when the break precedes item index `0`).
  final int afterItemIndex;

  /// TeX-style line-breaking metadata for this split boundary.
  final BreakPoint breakPoint;

  /// Optional source span associated with the break-inducing element.
  final SourceSpan? span;

  /// Semantic category of this break opportunity.
  MathBreakKind get kind => breakPoint.kind;

  /// TeX-style line-breaking penalty value.
  int get penalty => breakPoint.penalty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayBreakHint &&
          xEm == other.xEm &&
          afterItemIndex == other.afterItemIndex &&
          breakPoint == other.breakPoint &&
          span == other.span;

  @override
  int get hashCode => Object.hash(xEm, afterItemIndex, breakPoint, span);

  @override
  String toString() =>
      'DisplayBreakHint(xEm: $xEm, afterItemIndex: $afterItemIndex, '
      'breakPoint: $breakPoint)';
}

/// Positioned layout primitive emitted by the layout engine for rendering or
/// SVG export.
@immutable
sealed class DisplayItem {
  /// Base constructor for immutable display items.
  const DisplayItem({
    this.span,
    this.colorRole = TexMathColorRole.foreground,
    this.customColor,
  });

  /// Optional source span linking this item back to the TeX input.
  final SourceSpan? span;

  /// Semantic theme color role applied when painting this item.
  final TexMathColorRole colorRole;

  /// Optional ARGB 32-bit color used when [colorRole] is
  /// [TexMathColorRole.custom].
  final int? customColor;
}

/// Positioned glyph item addressed by OpenType glyph ID and Unicode scalar.
@immutable
final class GlyphItem extends DisplayItem {
  /// Creates a positioned glyph item.
  const GlyphItem({
    required this.glyphId,
    required this.codePoint,
    required this.xEm,
    required this.yEm,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.advanceEm = 0.5,
    this.outline,
    super.span,
    super.colorRole,
    super.customColor,
  });

  /// OpenType glyph ID within the target math font.
  final int glyphId;

  /// Unicode code point associated with this glyph (or `0` if unencoded).
  final int codePoint;

  /// Horizontal origin offset from the left edge of the expression in ems.
  final double xEm;

  /// Baseline-relative vertical offset in ems (positive upward).
  final double yEm;

  /// Horizontal scale factor applied to the glyph outline.
  final double scaleX;

  /// Vertical scale factor applied to the glyph outline.
  final double scaleY;

  /// Horizontal advance width occupied by this glyph in ems.
  final double advanceEm;

  /// Optional pre-resolved glyph outline in font design units.
  final GlyphOutline? outline;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphItem &&
          glyphId == other.glyphId &&
          codePoint == other.codePoint &&
          xEm == other.xEm &&
          yEm == other.yEm &&
          scaleX == other.scaleX &&
          scaleY == other.scaleY &&
          advanceEm == other.advanceEm &&
          outline == other.outline &&
          span == other.span &&
          colorRole == other.colorRole &&
          customColor == other.customColor;

  @override
  int get hashCode => Object.hash(
    glyphId,
    codePoint,
    xEm,
    yEm,
    scaleX,
    scaleY,
    advanceEm,
    outline,
    span,
    colorRole,
    customColor,
  );

  @override
  String toString() =>
      'GlyphItem(glyphId: $glyphId, codePoint: $codePoint, '
      'xEm: $xEm, yEm: $yEm)';
}

/// Positioned horizontal or vertical rule (e.g. fraction bar or radical
/// vinculum).
@immutable
final class RuleItem extends DisplayItem {
  /// Creates a rectangular rule item at `(` [xEm], [yEm] `)` with size
  /// [widthEm] by [heightEm] in ems.
  const RuleItem({
    required this.xEm,
    required this.yEm,
    required this.widthEm,
    required this.heightEm,
    this.strokeWidthEm,
    super.span,
    super.colorRole,
    super.customColor,
  });

  /// Left edge offset from the expression origin in ems.
  final double xEm;

  /// Bottom edge offset relative to the math baseline in ems (positive upward).
  final double yEm;

  /// Rule width in ems.
  final double widthEm;

  /// Rule thickness/height in ems.
  final double heightEm;

  /// Optional border stroke thickness in ems for unfilled rectangular frames.
  final double? strokeWidthEm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleItem &&
          xEm == other.xEm &&
          yEm == other.yEm &&
          widthEm == other.widthEm &&
          heightEm == other.heightEm &&
          strokeWidthEm == other.strokeWidthEm &&
          span == other.span &&
          colorRole == other.colorRole &&
          customColor == other.customColor;

  @override
  int get hashCode => Object.hash(
    xEm,
    yEm,
    widthEm,
    heightEm,
    strokeWidthEm,
    span,
    colorRole,
    customColor,
  );

  @override
  String toString() =>
      'RuleItem(xEm: $xEm, yEm: $yEm, widthEm: $widthEm, '
      'heightEm: $heightEm, strokeWidthEm: $strokeWidthEm)';
}

/// Non-inked anchor marker used for cross-references, labels, or diagnostics.
@immutable
final class AnchorItem extends DisplayItem {
  /// Creates an anchor marker with [id] at `(` [xEm], [yEm] `)`.
  const AnchorItem({
    required this.id,
    required this.xEm,
    required this.yEm,
    this.label,
    super.span,
    super.colorRole,
    super.customColor,
  });

  /// Unique anchor identifier within the display list.
  final String id;

  /// Horizontal anchor coordinate in ems.
  final double xEm;

  /// Baseline-relative vertical anchor coordinate in ems (positive upward).
  final double yEm;

  /// Optional human-readable label attached to this anchor.
  final String? label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorItem &&
          id == other.id &&
          xEm == other.xEm &&
          yEm == other.yEm &&
          label == other.label &&
          span == other.span &&
          colorRole == other.colorRole &&
          customColor == other.customColor;

  @override
  int get hashCode =>
      Object.hash(id, xEm, yEm, label, span, colorRole, customColor);

  @override
  String toString() =>
      'AnchorItem(id: $id, xEm: $xEm, yEm: $yEm, label: $label)';
}

/// Bounding box and baseline metrics for a laid-out [DisplayList].
@immutable
final class DisplayMetrics {
  /// Creates display metrics in both em units and integer font design units.
  const DisplayMetrics({
    required this.widthEm,
    required this.heightEm,
    required this.depthEm,
    double? baselineEm,
    this.unitsPerEm = 1000,
  }) : assert(unitsPerEm > 0, 'unitsPerEm must be positive'),
       baselineEm = baselineEm ?? heightEm;

  /// Total expression width in ems.
  final double widthEm;

  /// Ascent above the math baseline in ems.
  final double heightEm;

  /// Descent below the math baseline in ems.
  final double depthEm;

  /// Distance from the top of the bounding box to the math baseline in ems.
  final double baselineEm;

  /// Font design units per em applied when computing integer unit dimensions.
  final int unitsPerEm;

  /// Total bounding box height (`heightEm + depthEm`) in ems.
  double get totalHeightEm => heightEm + depthEm;

  /// Total expression width in integer font design units.
  int get widthUnits => (widthEm * unitsPerEm).round();

  /// Ascent above the baseline in integer font design units.
  int get heightUnits => (heightEm * unitsPerEm).round();

  /// Descent below the baseline in integer font design units.
  int get depthUnits => (depthEm * unitsPerEm).round();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayMetrics &&
          widthEm == other.widthEm &&
          heightEm == other.heightEm &&
          depthEm == other.depthEm &&
          baselineEm == other.baselineEm &&
          unitsPerEm == other.unitsPerEm;

  @override
  int get hashCode =>
      Object.hash(widthEm, heightEm, depthEm, baselineEm, unitsPerEm);

  @override
  String toString() =>
      'DisplayMetrics(widthEm: $widthEm, heightEm: $heightEm, '
      'depthEm: $depthEm, baselineEm: $baselineEm, unitsPerEm: $unitsPerEm)';
}

/// Flat layout output ready for Canvas painting or standalone SVG export.
@immutable
final class DisplayList {
  /// Creates a display list with [metrics], [items], optional [source], and
  /// optional [breakHints].
  const DisplayList({
    required this.metrics,
    required this.items,
    this.source,
    this.breakHints = const <DisplayBreakHint>[],
  });

  /// Overall bounding box and baseline metrics.
  final DisplayMetrics metrics;

  /// Ordered flat list of positioned display primitives.
  final List<DisplayItem> items;

  /// Optional original TeX source associated with this display list.
  final String? source;

  /// Ordered top-level line-breaking hints emitted during layout.
  final List<DisplayBreakHint> breakHints;

  /// Serializes this display list as a standalone XML SVG document.
  ///
  /// Handles [RuleItem], [AnchorItem], and [GlyphItem] cleanly with or without
  /// resolved [GlyphOutline] paths. Throws [TexMathBudgetError] when item count
  /// exceeds [maxOutputItems] or serialized output exceeds [maxSvgLength].
  String toSvg({
    double fontSize = 16.0,
    int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
    int maxSvgLength = TexMathBudgets.defaultMaxSvgLength,
    Map<TexMathColorRole, String>? colors,
    String? title,
  }) {
    if (items.length > maxOutputItems) {
      throw TexMathBudgetError(
        'DisplayList item count ${items.length} exceeds limit $maxOutputItems.',
        budgetName: 'maxOutputItems',
        limit: maxOutputItems,
        actual: items.length,
      );
    }

    final double safeFontSize = fontSize.isFinite && fontSize > 0
        ? fontSize
        : 16.0;
    final double widthPx = _nonNegativeFinite(metrics.widthEm * safeFontSize);
    final double heightPx = _nonNegativeFinite(
      metrics.totalHeightEm * safeFontSize,
    );
    final double viewBoxWidth = widthPx > 0 ? widthPx : 1.0;
    final double viewBoxHeight = heightPx > 0 ? heightPx : 1.0;

    final StringBuffer buffer = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" width="');
    writeFormattedNumber(buffer, widthPx);
    buffer.write('" height="');
    writeFormattedNumber(buffer, heightPx);
    buffer.write('" viewBox="0 0 ');
    writeFormattedNumber(buffer, viewBoxWidth);
    buffer.writeCharCode(0x20);
    writeFormattedNumber(buffer, viewBoxHeight);
    buffer.write('" role="img">');

    if (title != null && title.isNotEmpty) {
      buffer.write('<title>');
      writeEscapedXmlText(buffer, title);
      buffer.write('</title>');
    }

    final double unitsScale = safeFontSize / metrics.unitsPerEm;
    final String fgFill = _resolvedRoleAttr(
      TexMathColorRole.foreground,
      colors,
    );
    final String accentFill = _resolvedRoleAttr(
      TexMathColorRole.accent,
      colors,
    );
    final String errorFill = _resolvedRoleAttr(TexMathColorRole.error, colors);
    final String mutedFill = _resolvedRoleAttr(TexMathColorRole.muted, colors);
    final String customFallbackFill = _resolvedRoleAttr(
      TexMathColorRole.custom,
      colors,
    );

    void writeResolvedFill(TexMathColorRole role, int? customColor) {
      if (role == TexMathColorRole.custom) {
        if (customColor != null) {
          writeCssHexRgb(buffer, customColor);
        } else {
          buffer.write(customFallbackFill);
        }
        return;
      }
      buffer.write(switch (role) {
        TexMathColorRole.foreground => fgFill,
        TexMathColorRole.accent => accentFill,
        TexMathColorRole.error => errorFill,
        TexMathColorRole.muted => mutedFill,
        TexMathColorRole.custom => customFallbackFill,
      });
    }

    for (final DisplayItem item in items) {
      switch (item) {
        case RuleItem(
          :final double xEm,
          :final double yEm,
          :final double widthEm,
          :final double heightEm,
          :final double? strokeWidthEm,
          :final TexMathColorRole colorRole,
          :final int? customColor,
        ):
          final double rx = _finite(xEm * safeFontSize);
          final double ry = _finite(
            (metrics.baselineEm - (yEm + heightEm)) * safeFontSize,
          );
          final double rw = _nonNegativeFinite(widthEm * safeFontSize);
          final double rh = _nonNegativeFinite(heightEm * safeFontSize);
          buffer.write('<rect x="');
          writeFormattedNumber(buffer, rx);
          buffer.write('" y="');
          writeFormattedNumber(buffer, ry);
          buffer.write('" width="');
          writeFormattedNumber(buffer, rw);
          buffer.write('" height="');
          writeFormattedNumber(buffer, rh);
          if (strokeWidthEm != null && strokeWidthEm > 0) {
            final double sw = _nonNegativeFinite(strokeWidthEm * safeFontSize);
            buffer.write('" fill="none" stroke="');
            writeResolvedFill(colorRole, customColor);
            buffer.write('" stroke-width="');
            writeFormattedNumber(buffer, sw);
            buffer.write('"/>');
          } else {
            buffer.write('" fill="');
            writeResolvedFill(colorRole, customColor);
            buffer.write('"/>');
          }

        case AnchorItem(
          :final String id,
          :final double xEm,
          :final double yEm,
          :final String? label,
        ):
          final double ax = _finite(xEm * safeFontSize);
          final double ay = _finite((metrics.baselineEm - yEm) * safeFontSize);
          buffer.write('<g id="');
          writeEscapedXmlAttr(buffer, id);
          buffer.write('" data-anchor="true"');
          if (label != null) {
            buffer.write(' data-label="');
            writeEscapedXmlAttr(buffer, label);
            buffer.writeCharCode(0x22);
          }
          buffer.write(' transform="translate(');
          writeFormattedNumber(buffer, ax);
          buffer.write(', ');
          writeFormattedNumber(buffer, ay);
          buffer.write(')"/>');

        case GlyphItem(
          :final int glyphId,
          :final int codePoint,
          :final double xEm,
          :final double yEm,
          :final double scaleX,
          :final double scaleY,
          :final GlyphOutline? outline,
          :final TexMathColorRole colorRole,
          :final int? customColor,
        ):
          final double gx = _finite(xEm * safeFontSize);
          final double gy = _finite((metrics.baselineEm - yEm) * safeFontSize);

          if (outline != null && !outline.isEmpty) {
            final double sx = _finite(unitsScale * scaleX);
            final double sy = _finite(-unitsScale * scaleY);
            buffer.write('<path d="');
            writeGlyphOutlineSvgPathData(buffer, outline.commands);
            buffer.write('" fill="');
            writeResolvedFill(colorRole, customColor);
            buffer
              ..write('" data-glyph-id="')
              ..write(glyphId)
              ..write('" data-codepoint="');
            writeUpperHexCodePoint(buffer, codePoint);
            buffer.write('" transform="translate(');
            writeFormattedNumber(buffer, gx);
            buffer.write(', ');
            writeFormattedNumber(buffer, gy);
            buffer.write(') scale(');
            writeFormattedNumber(buffer, sx);
            buffer.write(', ');
            writeFormattedNumber(buffer, sy);
            buffer.write(')"/>');
          } else if (outline == null && _isPrintableUnicodeScalar(codePoint)) {
            final String ch = String.fromCharCode(codePoint);
            buffer.write('<text x="0" y="0" font-family="serif" font-size="');
            writeFormattedNumber(buffer, safeFontSize);
            buffer.write('" fill="');
            writeResolvedFill(colorRole, customColor);
            buffer
              ..write('" data-glyph-id="')
              ..write(glyphId)
              ..write('" data-codepoint="');
            writeUpperHexCodePoint(buffer, codePoint);
            buffer.write('" transform="translate(');
            writeFormattedNumber(buffer, gx);
            buffer.write(', ');
            writeFormattedNumber(buffer, gy);
            buffer.write(') scale(');
            writeFormattedNumber(buffer, scaleX);
            buffer.write(', ');
            writeFormattedNumber(buffer, scaleY);
            buffer.write(')">');
            writeEscapedXmlText(buffer, ch);
            buffer.write('</text>');
          } else {
            buffer.write('<g fill="');
            writeResolvedFill(colorRole, customColor);
            buffer
              ..write('" data-glyph-id="')
              ..write(glyphId)
              ..write('" data-codepoint="');
            writeUpperHexCodePoint(buffer, codePoint);
            buffer.write('" transform="translate(');
            writeFormattedNumber(buffer, gx);
            buffer.write(', ');
            writeFormattedNumber(buffer, gy);
            buffer.write(')"/>');
          }
      }
    }

    buffer.write('</svg>');
    final String svg = buffer.toString();
    if (svg.length > maxSvgLength) {
      throw TexMathBudgetError(
        'Generated SVG length ${svg.length} exceeds limit $maxSvgLength.',
        budgetName: 'maxSvgLength',
        limit: maxSvgLength,
        actual: svg.length,
      );
    }
    return svg;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplayList &&
          metrics == other.metrics &&
          source == other.source &&
          _itemListEquals(items, other.items) &&
          _listEquals(breakHints, other.breakHints);

  @override
  int get hashCode => Object.hash(
    metrics,
    source,
    Object.hashAll(items),
    Object.hashAll(breakHints),
  );

  @override
  String toString() => 'DisplayList(metrics: $metrics, items: ${items.length})';
}

/// Combined syntax tree and laid-out display result returned by rendering.
@immutable
final class RenderResult {
  /// Creates a render result from [displayList] and [syntaxTree].
  const RenderResult({
    required this.displayList,
    required this.syntaxTree,
    this.source = '',
  });

  /// Flat display list ready for Canvas or SVG rendering.
  final DisplayList displayList;

  /// Parsed syntax tree preserving source spans.
  final MathNode syntaxTree;

  /// Original TeX source string.
  final String source;

  /// Serializes [displayList] into a standalone SVG XML document.
  String toSvg({
    double fontSize = 16.0,
    int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
    int maxSvgLength = TexMathBudgets.defaultMaxSvgLength,
    Map<TexMathColorRole, String>? colors,
    String? title,
  }) {
    return displayList.toSvg(
      fontSize: fontSize,
      maxOutputItems: maxOutputItems,
      maxSvgLength: maxSvgLength,
      colors: colors,
      title: title,
    );
  }

  /// Emits Presentation MathML from [syntaxTree].
  String toMathMl() => mathNodeToMathMl(syntaxTree);

  /// Emits plain spoken text for screen readers from [syntaxTree].
  String toSpokenText() => mathNodeToSpokenText(syntaxTree);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderResult &&
          displayList == other.displayList &&
          syntaxTree == other.syntaxTree &&
          source == other.source;

  @override
  int get hashCode => Object.hash(displayList, syntaxTree, source);

  @override
  String toString() =>
      'RenderResult(displayList: $displayList, syntaxTree: $syntaxTree)';
}

bool _itemListEquals(List<DisplayItem> a, List<DisplayItem> b) {
  return _listEquals(a, b);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

String _resolvedRoleAttr(
  TexMathColorRole role,
  Map<TexMathColorRole, String>? overrides,
) {
  final String? override = overrides?[role];
  if (override != null && override.isNotEmpty) {
    return escapeXmlAttr(override);
  }
  switch (role) {
    case TexMathColorRole.foreground:
    case TexMathColorRole.custom:
      return '#111827';
    case TexMathColorRole.accent:
      return '#2563EB';
    case TexMathColorRole.error:
      return '#DC2626';
    case TexMathColorRole.muted:
      return '#6B7280';
  }
}

bool _isPrintableUnicodeScalar(int codePoint) {
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

double _finite(double value) => value.isFinite ? value : 0.0;

double _nonNegativeFinite(double value) =>
    value.isFinite && value > 0 ? value : 0.0;
