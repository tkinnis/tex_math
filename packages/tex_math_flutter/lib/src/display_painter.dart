import 'package:flutter/rendering.dart';
import 'package:tex_math/tex_math.dart';

import 'theme.dart';

/// Paints a laid-out [DisplayList] onto a Flutter [Canvas] using theme colors
/// from [TexMathThemeData].
final class TexMathDisplayPainter extends CustomPainter {
  /// Creates a display list painter.
  const TexMathDisplayPainter({
    required this.displayList,
    required this.theme,
    required this.fontSize,
  });

  /// Laid-out display list to paint.
  final DisplayList displayList;

  /// Active theme providing semantic colors.
  final TexMathThemeData theme;

  /// Logical pixel size corresponding to `1.0` em.
  final double fontSize;

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
    final DisplayMetrics metrics = displayList.metrics;
    final double safeFontSize = fontSize.isFinite && fontSize > 0
        ? fontSize
        : theme.fontSize;
    final double unitsScale = safeFontSize / metrics.unitsPerEm;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (final DisplayItem item in displayList.items) {
      paint.color = theme.colorForRole(
        item.colorRole,
        customColorValue: item.customColor,
      );

      switch (item) {
        case RuleItem(
          :final double xEm,
          :final double yEm,
          :final double widthEm,
          :final double heightEm,
        ):
          final double left = xEm * safeFontSize;
          final double top =
              (metrics.baselineEm - (yEm + heightEm)) * safeFontSize;
          final double width = widthEm * safeFontSize;
          final double height = heightEm * safeFontSize;
          canvas.drawRect(Rect.fromLTWH(left, top, width, height), paint);

        case GlyphItem(
          :final int codePoint,
          :final double xEm,
          :final double yEm,
          :final double scaleX,
          :final double scaleY,
          :final GlyphOutline? outline,
        ):
          final double dx = xEm * safeFontSize;
          final double dy = (metrics.baselineEm - yEm) * safeFontSize;
          if (outline != null && !outline.isEmpty) {
            final Path path = buildPathFromCommands(outline.commands);
            canvas
              ..save()
              ..translate(dx, dy)
              ..scale(unitsScale * scaleX, -unitsScale * scaleY)
              ..drawPath(path, paint)
              ..restore();
          } else if (codePoint >= 0x20 && codePoint != 0x7F) {
            final TextPainter textPainter = TextPainter(
              text: TextSpan(
                text: String.fromCharCode(codePoint),
                style: TextStyle(
                  color: paint.color,
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
        fontSize != oldDelegate.fontSize;
  }
}
