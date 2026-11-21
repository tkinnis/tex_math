import 'package:meta/meta.dart';

import '../format_utils.dart';

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
    writeGlyphOutlineSvgPathData(buffer, commands);
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

/// Writes [commands] as SVG `d` attribute path data directly into [buffer].
void writeGlyphOutlineSvgPathData(
  StringBuffer buffer,
  List<PathCommand> commands,
) {
  for (int i = 0; i < commands.length; i++) {
    if (i > 0) {
      buffer.writeCharCode(0x20); // ' '
    }
    final PathCommand command = commands[i];
    switch (command) {
      case MoveTo(:final double x, :final double y):
        buffer.writeCharCode(0x4D); // 'M'
        writeFormattedNumber(buffer, x);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, y);
      case LineTo(:final double x, :final double y):
        buffer.writeCharCode(0x4C); // 'L'
        writeFormattedNumber(buffer, x);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, y);
      case QuadTo(
        :final double controlX,
        :final double controlY,
        :final double x,
        :final double y,
      ):
        buffer.writeCharCode(0x51); // 'Q'
        writeFormattedNumber(buffer, controlX);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, controlY);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, x);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, y);
      case CubicTo(
        :final double control1X,
        :final double control1Y,
        :final double control2X,
        :final double control2Y,
        :final double x,
        :final double y,
      ):
        buffer.writeCharCode(0x43); // 'C'
        writeFormattedNumber(buffer, control1X);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, control1Y);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, control2X);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, control2Y);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, x);
        buffer.writeCharCode(0x20);
        writeFormattedNumber(buffer, y);
      case ClosePath():
        buffer.writeCharCode(0x5A); // 'Z'
    }
  }
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
