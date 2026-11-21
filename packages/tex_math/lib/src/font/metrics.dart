import 'package:meta/meta.dart';

/// Axis-aligned bounding box in font design units.
@immutable
final class FontBoundingBox {
  /// Creates a bounding box from design-unit extrema.
  const FontBoundingBox({
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
  });

  /// Empty bounding box at the origin.
  static const FontBoundingBox zero = FontBoundingBox(
    xMin: 0.0,
    yMin: 0.0,
    xMax: 0.0,
    yMax: 0.0,
  );

  /// Minimum horizontal coordinate in font design units.
  final double xMin;

  /// Minimum vertical coordinate in font design units (positive upward).
  final double yMin;

  /// Maximum horizontal coordinate in font design units.
  final double xMax;

  /// Maximum vertical coordinate in font design units (positive upward).
  final double yMax;

  /// Bounding box width (`xMax - xMin`).
  double get width => xMax - xMin;

  /// Bounding box height above baseline (`max(0, yMax)`).
  double get height => yMax > 0.0 ? yMax : 0.0;

  /// Bounding box depth below baseline (`max(0, -yMin)`).
  double get depth => yMin < 0.0 ? -yMin : 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontBoundingBox &&
          xMin == other.xMin &&
          yMin == other.yMin &&
          xMax == other.xMax &&
          yMax == other.yMax;

  @override
  int get hashCode => Object.hash(xMin, yMin, xMax, yMax);

  @override
  String toString() =>
      'FontBoundingBox(xMin: $xMin, yMin: $yMin, xMax: $xMax, yMax: $yMax)';
}

/// Complete per-glyph positioning, bounding box, and OpenType `MATH` metrics
/// in font design units.
@immutable
final class GlyphMetrics {
  /// Creates a glyph metrics record for [glyphId].
  const GlyphMetrics({
    required this.glyphId,
    required this.advanceWidth,
    required this.lsb,
    required this.xMin,
    required this.yMin,
    required this.xMax,
    required this.yMax,
    required this.height,
    required this.depth,
    this.italicsCorrection,
    this.topAccentAttachment,
  });

  /// Creates zeroed glyph metrics for an empty or missing [glyphId].
  const GlyphMetrics.empty(this.glyphId)
    : advanceWidth = 0.0,
      lsb = 0.0,
      xMin = 0.0,
      yMin = 0.0,
      xMax = 0.0,
      yMax = 0.0,
      height = 0.0,
      depth = 0.0,
      italicsCorrection = null,
      topAccentAttachment = null;

  /// OpenType glyph ID within the owning font.
  final int glyphId;

  /// Horizontal advance width in font design units.
  final double advanceWidth;

  /// Left side bearing in font design units.
  final double lsb;

  /// Left edge of the tight glyph outline bounding box.
  final double xMin;

  /// Bottom edge of the tight glyph outline bounding box.
  final double yMin;

  /// Right edge of the tight glyph outline bounding box.
  final double xMax;

  /// Top edge of the tight glyph outline bounding box.
  final double yMax;

  /// Ascent above the baseline (`max(0, yMax)`) in font design units.
  final double height;

  /// Descent below the baseline (`max(0, -yMin)`) in font design units.
  final double depth;

  /// Optional OpenType `MATH` italics correction in font design units.
  final double? italicsCorrection;

  /// Optional OpenType `MATH` top accent horizontal attachment coordinate.
  final double? topAccentAttachment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphMetrics &&
          glyphId == other.glyphId &&
          advanceWidth == other.advanceWidth &&
          lsb == other.lsb &&
          xMin == other.xMin &&
          yMin == other.yMin &&
          xMax == other.xMax &&
          yMax == other.yMax &&
          height == other.height &&
          depth == other.depth &&
          italicsCorrection == other.italicsCorrection &&
          topAccentAttachment == other.topAccentAttachment;

  @override
  int get hashCode => Object.hash(
    glyphId,
    advanceWidth,
    lsb,
    xMin,
    yMin,
    xMax,
    yMax,
    height,
    depth,
    italicsCorrection,
    topAccentAttachment,
  );

  @override
  String toString() =>
      'GlyphMetrics(glyphId: $glyphId, advanceWidth: $advanceWidth, '
      'height: $height, depth: $depth)';
}

/// Orientation of a Type 2 CharString stem hint.
enum StemOrientation {
  /// Horizontal stem controlling vertical coordinate grid alignment.
  horizontal,

  /// Vertical stem controlling horizontal coordinate grid alignment.
  vertical,
}

/// Horizontal or vertical stem hint captured from a `CFF` or `CFF2` charstring.
@immutable
final class StemHint {
  /// Creates a stem hint at [position] with stem thickness [width].
  const StemHint({
    required this.orientation,
    required this.position,
    required this.width,
  });

  /// Stem orientation (`horizontal` or `vertical`).
  final StemOrientation orientation;

  /// Starting coordinate of the stem in font design units.
  final double position;

  /// Stem thickness in font design units (may be negative for ghost stems).
  final double width;

  /// Lower coordinate bound of the stem (`min(position, position + width)`).
  double get min => width >= 0.0 ? position : position + width;

  /// Upper coordinate bound of the stem (`max(position, position + width)`).
  double get max => width >= 0.0 ? position + width : position;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StemHint &&
          orientation == other.orientation &&
          position == other.position &&
          width == other.width;

  @override
  int get hashCode => Object.hash(orientation, position, width);

  @override
  String toString() =>
      'StemHint(orientation: $orientation, position: $position, width: $width)';
}

/// Design-space variation axis declared in an OpenType `fvar` table.
@immutable
final class FontVariationAxis {
  /// Creates an axis descriptor from `fvar` values.
  const FontVariationAxis({
    required this.tag,
    required this.minValue,
    required this.defaultValue,
    required this.maxValue,
    this.flags = 0,
    this.axisNameId = 0,
  });

  /// Four-character OpenType axis tag (e.g. `'wght'`, `'opsz'`, `'MATH'`).
  final String tag;

  /// Minimum user-space coordinate along this axis.
  final double minValue;

  /// Default user-space coordinate along this axis.
  final double defaultValue;

  /// Maximum user-space coordinate along this axis.
  final double maxValue;

  /// Axis flags bitfield (`0x0001` indicates hidden axis).
  final int flags;

  /// `name` table ID for the human-readable axis label.
  final int axisNameId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontVariationAxis &&
          tag == other.tag &&
          minValue == other.minValue &&
          defaultValue == other.defaultValue &&
          maxValue == other.maxValue &&
          flags == other.flags &&
          axisNameId == other.axisNameId;

  @override
  int get hashCode =>
      Object.hash(tag, minValue, defaultValue, maxValue, flags, axisNameId);

  @override
  String toString() =>
      'FontVariationAxis(tag: $tag, min: $minValue, '
      'default: $defaultValue, max: $maxValue)';
}
