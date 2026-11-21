import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'error.dart';

/// Vector path segment emitted from an OpenType `glyf` or `CFF`/`CFF2`
/// glyph outline.
@immutable
sealed class PathCommand {
  /// Base constructor for immutable path commands.
  const PathCommand();
}

/// Moves the current path pen to `(` [x], [y] `)` without drawing a stroke.
@immutable
final class MoveTo extends PathCommand {
  /// Creates a move-to command targeting `(` [x], [y] `)`.
  const MoveTo(this.x, this.y);

  /// Horizontal coordinate in font or em units.
  final double x;

  /// Vertical coordinate in font or em units.
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MoveTo && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'MoveTo($x, $y)';
}

/// Draws a straight line segment from the current point to `(` [x], [y] `)`.
@immutable
final class LineTo extends PathCommand {
  /// Creates a line-to command targeting `(` [x], [y] `)`.
  const LineTo(this.x, this.y);

  /// Horizontal target coordinate.
  final double x;

  /// Vertical target coordinate.
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is LineTo && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'LineTo($x, $y)';
}

/// Draws a quadratic Bezier curve using control point `(` [controlX],
/// [controlY] `)` to endpoint `(` [x], [y] `)`.
@immutable
final class QuadTo extends PathCommand {
  /// Creates a quadratic Bezier curve command.
  const QuadTo(this.controlX, this.controlY, this.x, this.y);

  /// Control point horizontal coordinate.
  final double controlX;

  /// Control point vertical coordinate.
  final double controlY;

  /// Endpoint horizontal coordinate.
  final double x;

  /// Endpoint vertical coordinate.
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuadTo &&
          controlX == other.controlX &&
          controlY == other.controlY &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(controlX, controlY, x, y);

  @override
  String toString() => 'QuadTo($controlX, $controlY, $x, $y)';
}

/// Draws a cubic Bezier curve using control points `(` [control1X],
/// [control1Y] `)` and `(` [control2X], [control2Y] `)` to `(` [x], [y] `)`.
@immutable
final class CubicTo extends PathCommand {
  /// Creates a cubic Bezier curve command.
  const CubicTo(
    this.control1X,
    this.control1Y,
    this.control2X,
    this.control2Y,
    this.x,
    this.y,
  );

  /// First control point horizontal coordinate.
  final double control1X;

  /// First control point vertical coordinate.
  final double control1Y;

  /// Second control point horizontal coordinate.
  final double control2X;

  /// Second control point vertical coordinate.
  final double control2Y;

  /// Endpoint horizontal coordinate.
  final double x;

  /// Endpoint vertical coordinate.
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CubicTo &&
          control1X == other.control1X &&
          control1Y == other.control1Y &&
          control2X == other.control2X &&
          control2Y == other.control2Y &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode =>
      Object.hash(control1X, control1Y, control2X, control2Y, x, y);

  @override
  String toString() =>
      'CubicTo($control1X, $control1Y, $control2X, $control2Y, $x, $y)';
}

/// Closes the active contour back to its starting point.
@immutable
final class ClosePath extends PathCommand {
  /// Creates a close-path command.
  const ClosePath();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ClosePath;

  @override
  int get hashCode => (ClosePath).hashCode;

  @override
  String toString() => 'ClosePath()';
}

/// Extracted outline and advance width for a single font glyph ID.
@immutable
final class GlyphOutline {
  /// Creates a glyph outline record for [glyphId].
  const GlyphOutline({
    required this.glyphId,
    required this.commands,
    this.advanceWidth = 0.0,
  });

  /// OpenType glyph index within the owning font.
  final int glyphId;

  /// Ordered vector path commands forming the glyph contours.
  final List<PathCommand> commands;

  /// Horizontal advance width in font design units.
  final double advanceWidth;

  /// Whether this glyph contains no contour commands (e.g. whitespace).
  bool get isEmpty => commands.isEmpty;

  /// Formats [commands] into an SVG `d` path attribute string.
  String toSvgPathData() {
    if (commands.isEmpty) {
      return '';
    }
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < commands.length; i++) {
      if (i > 0) {
        buffer.write(' ');
      }
      final PathCommand command = commands[i];
      switch (command) {
        case MoveTo(:final double x, :final double y):
          buffer
            ..write('M')
            ..write(_formatSvgNumber(x))
            ..write(' ')
            ..write(_formatSvgNumber(y));
        case LineTo(:final double x, :final double y):
          buffer
            ..write('L')
            ..write(_formatSvgNumber(x))
            ..write(' ')
            ..write(_formatSvgNumber(y));
        case QuadTo(
          :final double controlX,
          :final double controlY,
          :final double x,
          :final double y,
        ):
          buffer
            ..write('Q')
            ..write(_formatSvgNumber(controlX))
            ..write(' ')
            ..write(_formatSvgNumber(controlY))
            ..write(' ')
            ..write(_formatSvgNumber(x))
            ..write(' ')
            ..write(_formatSvgNumber(y));
        case CubicTo(
          :final double control1X,
          :final double control1Y,
          :final double control2X,
          :final double control2Y,
          :final double x,
          :final double y,
        ):
          buffer
            ..write('C')
            ..write(_formatSvgNumber(control1X))
            ..write(' ')
            ..write(_formatSvgNumber(control1Y))
            ..write(' ')
            ..write(_formatSvgNumber(control2X))
            ..write(' ')
            ..write(_formatSvgNumber(control2Y))
            ..write(' ')
            ..write(_formatSvgNumber(x))
            ..write(' ')
            ..write(_formatSvgNumber(y));
        case ClosePath():
          buffer.write('Z');
      }
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphOutline &&
          glyphId == other.glyphId &&
          advanceWidth == other.advanceWidth &&
          _commandListEquals(commands, other.commands);

  @override
  int get hashCode =>
      Object.hash(glyphId, advanceWidth, Object.hashAll(commands));

  @override
  String toString() =>
      'GlyphOutline(glyphId: $glyphId, commands: ${commands.length}, '
      'advanceWidth: $advanceWidth)';
}

/// Pure-Dart OpenType math font wrapper backed by in-memory SFNT bytes.
@immutable
final class MathFont {
  /// Creates a placeholder font descriptor for Phase 1 engine wiring and tests
  /// without font table decoding.
  const MathFont.stub({
    this.familyName = 'NewComputerModernMath',
    this.unitsPerEm = 1000,
  });

  /// Default maximum font payload accepted by [MathFont.fromBytes] (`16 MiB`).
  static const int defaultMaxFontBytes = 16 * 1024 * 1024;

  /// Parses an OpenType or TrueType font from an in-memory [bytes] buffer.
  ///
  /// Validates non-empty input, enforces [maxBytes], checks the SFNT header
  /// signature (`OTTO`, `0x00010000`, `true`, or `typ1`), and throws
  /// [TexMathUnsupportedError] in Phase 1 before full OpenType `MATH` table
  /// parsing is implemented.
  factory MathFont.fromBytes(
    Uint8List bytes, {
    int maxBytes = defaultMaxFontBytes,
  }) {
    if (bytes.isEmpty) {
      throw const TexMathFontError('Font byte buffer must not be empty.');
    }
    if (bytes.length > maxBytes) {
      throw TexMathBudgetError(
        'Font byte length ${bytes.length} exceeds limit $maxBytes.',
        budgetName: 'maxFontBytes',
        limit: maxBytes,
        actual: bytes.length,
      );
    }
    if (bytes.length < 12 || !_hasSupportedSfntTag(bytes)) {
      throw const TexMathFontError(
        'Invalid SFNT header; expected OTTO or TrueType magic bytes.',
      );
    }
    throw const TexMathUnsupportedError(
      'OpenType MATH table decoding is unimplemented in Phase 1.',
    );
  }

  /// Font family name.
  final String familyName;

  /// Design units per em square.
  final int unitsPerEm;

  /// Looks up the vector outline for [glyphId], returning `null` if missing.
  GlyphOutline? outlineForGlyph(int glyphId) => null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathFont &&
          familyName == other.familyName &&
          unitsPerEm == other.unitsPerEm;

  @override
  int get hashCode => Object.hash(familyName, unitsPerEm);

  @override
  String toString() =>
      'MathFont(familyName: $familyName, unitsPerEm: $unitsPerEm)';
}

bool _hasSupportedSfntTag(Uint8List bytes) {
  final int b0 = bytes[0];
  final int b1 = bytes[1];
  final int b2 = bytes[2];
  final int b3 = bytes[3];
  // 'OTTO' (CFF/CFF2 OpenType)
  if (b0 == 0x4F && b1 == 0x54 && b2 == 0x54 && b3 == 0x4F) {
    return true;
  }
  // 0x00010000 (TrueType)
  if (b0 == 0x00 && b1 == 0x01 && b2 == 0x00 && b3 == 0x00) {
    return true;
  }
  // 'true' (Apple TrueType)
  if (b0 == 0x74 && b1 == 0x72 && b2 == 0x75 && b3 == 0x65) {
    return true;
  }
  // 'typ1' (Type 1 SFNT)
  if (b0 == 0x74 && b1 == 0x79 && b2 == 0x70 && b3 == 0x31) {
    return true;
  }
  return false;
}

bool _commandListEquals(List<PathCommand> a, List<PathCommand> b) {
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

String _formatSvgNumber(double value) {
  if (!value.isFinite) {
    return '0';
  }
  final String fixed = value.toStringAsFixed(4);
  if (!fixed.contains('.')) {
    return fixed;
  }
  final String trimmed = fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return trimmed == '-0' ? '0' : trimmed;
}
