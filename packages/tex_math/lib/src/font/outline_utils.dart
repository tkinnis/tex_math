import 'dart:math' as math;

import 'metrics.dart';
import 'outline.dart';

/// Computes the exact analytical bounding box of [commands] in font units.
///
/// Accounts for true quadratic and cubic Bezier curve extrema rather than
/// loose control-point convex hulls. Returns [FontBoundingBox.zero] when
/// [commands] contains no geometry points.
FontBoundingBox computeOutlineBoundingBox(List<PathCommand> commands) {
  if (commands.isEmpty) {
    return FontBoundingBox.zero;
  }

  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = -double.infinity;
  double maxY = -double.infinity;

  void includePoint(double x, double y) {
    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
  }

  double curX = 0.0;
  double curY = 0.0;
  double startX = 0.0;
  double startY = 0.0;

  for (final PathCommand cmd in commands) {
    switch (cmd) {
      case MoveTo(:final double x, :final double y):
        curX = x;
        curY = y;
        startX = x;
        startY = y;
        includePoint(x, y);
      case LineTo(:final double x, :final double y):
        includePoint(x, y);
        curX = x;
        curY = y;
      case QuadTo(
        :final double controlX,
        :final double controlY,
        :final double x,
        :final double y,
      ):
        includePoint(x, y);
        _includeQuadraticExtrema(curX, controlX, x, (double v) {
          if (v < minX) minX = v;
          if (v > maxX) maxX = v;
        });
        _includeQuadraticExtrema(curY, controlY, y, (double v) {
          if (v < minY) minY = v;
          if (v > maxY) maxY = v;
        });
        curX = x;
        curY = y;
      case CubicTo(
        :final double control1X,
        :final double control1Y,
        :final double control2X,
        :final double control2Y,
        :final double x,
        :final double y,
      ):
        includePoint(x, y);
        _includeCubicExtrema(curX, control1X, control2X, x, (double v) {
          if (v < minX) minX = v;
          if (v > maxX) maxX = v;
        });
        _includeCubicExtrema(curY, control1Y, control2Y, y, (double v) {
          if (v < minY) minY = v;
          if (v > maxY) maxY = v;
        });
        curX = x;
        curY = y;
      case ClosePath():
        curX = startX;
        curY = startY;
    }
  }

  if (!minX.isFinite || !minY.isFinite) {
    return FontBoundingBox.zero;
  }
  return FontBoundingBox(xMin: minX, yMin: minY, xMax: maxX, yMax: maxY);
}

void _includeQuadraticExtrema(
  double p0,
  double p1,
  double p2,
  void Function(double) include,
) {
  final double denom = p0 - 2.0 * p1 + p2;
  if (denom.abs() < 1e-12) {
    return;
  }
  final double t = (p0 - p1) / denom;
  if (t > 0.0 && t < 1.0) {
    final double u = 1.0 - t;
    include(u * u * p0 + 2.0 * u * t * p1 + t * t * p2);
  }
}

void _includeCubicExtrema(
  double p0,
  double p1,
  double p2,
  double p3,
  void Function(double) include,
) {
  final double a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
  final double b = 2.0 * (p0 - 2.0 * p1 + p2);
  final double c = p1 - p0;

  void evalAt(double t) {
    if (t > 0.0 && t < 1.0) {
      final double u = 1.0 - t;
      include(
        u * u * u * p0 +
            3.0 * u * u * t * p1 +
            3.0 * u * t * t * p2 +
            t * t * t * p3,
      );
    }
  }

  if (a.abs() < 1e-12) {
    if (b.abs() >= 1e-12) {
      evalAt(-c / b);
    }
    return;
  }

  final double discriminant = b * b - 4.0 * a * c;
  if (discriminant < 0.0) {
    return;
  }
  final double sqrtD = math.sqrt(discriminant);
  evalAt((-b - sqrtD) / (2.0 * a));
  evalAt((-b + sqrtD) / (2.0 * a));
}

/// Applies an affine 2D transform `[a, b, c, d, tx, ty]` to [commands].
List<PathCommand> transformPathCommands(
  List<PathCommand> commands,
  double a,
  double b,
  double c,
  double d,
  double tx,
  double ty,
) {
  double xformX(double x, double y) => a * x + c * y + tx;
  double xformY(double x, double y) => b * x + d * y + ty;

  if (commands.isEmpty) {
    return const <PathCommand>[];
  }
  if (commands.isEmpty) {
    return const <PathCommand>[];
  }
  return List<PathCommand>.unmodifiable(
    commands.map((PathCommand cmd) {
      return switch (cmd) {
        MoveTo(:final double x, :final double y) => MoveTo(
          xformX(x, y),
          xformY(x, y),
        ),
        LineTo(:final double x, :final double y) => LineTo(
          xformX(x, y),
          xformY(x, y),
        ),
        QuadTo(
          :final double controlX,
          :final double controlY,
          :final double x,
          :final double y,
        ) =>
          QuadTo(
            xformX(controlX, controlY),
            xformY(controlX, controlY),
            xformX(x, y),
            xformY(x, y),
          ),
        CubicTo(
          :final double control1X,
          :final double control1Y,
          :final double control2X,
          :final double control2Y,
          :final double x,
          :final double y,
        ) =>
          CubicTo(
            xformX(control1X, control1Y),
            xformY(control1X, control1Y),
            xformX(control2X, control2Y),
            xformY(control2X, control2Y),
            xformX(x, y),
            xformY(x, y),
          ),
        ClosePath() => const ClosePath(),
      };
    }),
  );
}

/// Alignment zone pairs and stem defaults extracted from a CFF Private DICT.
final class HintingContext {
  const HintingContext({
    this.blueValues = const <double>[],
    this.otherBlues = const <double>[],
    this.blueScale = 0.039625,
    this.blueShift = 7.0,
    this.blueFuzz = 1.0,
    this.stdHw,
    this.stdVw,
  });

  final List<double> blueValues;
  final List<double> otherBlues;
  final double blueScale;
  final double blueShift;
  final double blueFuzz;
  final double? stdHw;
  final double? stdVw;
}

/// Applies Type 2 horizontal/vertical stem hint grid-fitting at [ppem].
List<PathCommand> applyStemHinting({
  required List<PathCommand> commands,
  required List<StemHint> stems,
  required int unitsPerEm,
  required double ppem,
  HintingContext context = const HintingContext(),
}) {
  if (commands.isEmpty ||
      stems.isEmpty ||
      unitsPerEm <= 0 ||
      !ppem.isFinite ||
      ppem <= 0.0) {
    return commands;
  }

  final double scale = ppem / unitsPerEm;
  final List<StemHint> hStems = <StemHint>[];
  final List<StemHint> vStems = <StemHint>[];
  for (final StemHint stem in stems) {
    if (stem.orientation == StemOrientation.horizontal) {
      hStems.add(stem);
    } else {
      vStems.add(stem);
    }
  }

  final _AxisWarp yWarp = _buildAxisWarp(
    hStems,
    scale: scale,
    blueValues: context.blueValues,
    otherBlues: context.otherBlues,
    blueFuzz: context.blueFuzz,
    stdWidth: context.stdHw,
  );
  final _AxisWarp xWarp = _buildAxisWarp(
    vStems,
    scale: scale,
    blueValues: const <double>[],
    otherBlues: const <double>[],
    blueFuzz: 0.0,
    stdWidth: context.stdVw,
  );

  if (xWarp.isIdentity && yWarp.isIdentity) {
    return commands;
  }

  if (commands.isEmpty) {
    return const <PathCommand>[];
  }
  return List<PathCommand>.unmodifiable(
    commands.map((PathCommand cmd) {
      return switch (cmd) {
        MoveTo(:final double x, :final double y) => MoveTo(
          xWarp.map(x),
          yWarp.map(y),
        ),
        LineTo(:final double x, :final double y) => LineTo(
          xWarp.map(x),
          yWarp.map(y),
        ),
        QuadTo(
          :final double controlX,
          :final double controlY,
          :final double x,
          :final double y,
        ) =>
          QuadTo(
            xWarp.map(controlX),
            yWarp.map(controlY),
            xWarp.map(x),
            yWarp.map(y),
          ),
        CubicTo(
          :final double control1X,
          :final double control1Y,
          :final double control2X,
          :final double control2Y,
          :final double x,
          :final double y,
        ) =>
          CubicTo(
            xWarp.map(control1X),
            yWarp.map(control1Y),
            xWarp.map(control2X),
            yWarp.map(control2Y),
            xWarp.map(x),
            yWarp.map(y),
          ),
        ClosePath() => const ClosePath(),
      };
    }),
  );
}

final class _AnchorPair {
  const _AnchorPair(this.orig, this.snapped);

  final double orig;
  final double snapped;
}

final class _AxisWarp {
  const _AxisWarp(this.anchors);

  static const _AxisWarp identity = _AxisWarp(<_AnchorPair>[]);

  final List<_AnchorPair> anchors;

  bool get isIdentity => anchors.isEmpty;

  double map(double coord) {
    if (anchors.isEmpty) {
      return coord;
    }
    if (coord <= anchors.first.orig) {
      return coord + (anchors.first.snapped - anchors.first.orig);
    }
    if (coord >= anchors.last.orig) {
      return coord + (anchors.last.snapped - anchors.last.orig);
    }
    int low = 0;
    int high = anchors.length - 2;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final _AnchorPair a = anchors[mid];
      final _AnchorPair b = anchors[mid + 1];
      if (coord < a.orig) {
        high = mid - 1;
      } else if (coord > b.orig) {
        low = mid + 1;
      } else {
        final double span = b.orig - a.orig;
        if (span <= 1e-9) {
          return a.snapped;
        }
        final double t = (coord - a.orig) / span;
        return a.snapped + t * (b.snapped - a.snapped);
      }
    }
    return coord;
  }
}

_AxisWarp _buildAxisWarp(
  List<StemHint> stems, {
  required double scale,
  required List<double> blueValues,
  required List<double> otherBlues,
  required double blueFuzz,
  double? stdWidth,
}) {
  if (stems.isEmpty) {
    return _AxisWarp.identity;
  }

  final List<StemHint> sorted = List<StemHint>.from(stems)
    ..sort((StemHint a, StemHint b) => a.min.compareTo(b.min));

  final List<_AnchorPair> rawAnchors = <_AnchorPair>[];
  for (final StemHint stem in sorted) {
    final double w = (stem.max - stem.min).abs();
    if (w < 1e-6) {
      continue;
    }
    // Ghost stems have width 20 or 21 in Type 2; preserve edge snap without
    // enforcing a 1px minimum thickness.
    final bool isGhost = stem.width == -20.0 || stem.width == -21.0;
    final double snappedWidthPx = isGhost
        ? (w * scale).roundToDouble()
        : math.max(1.0, (w * scale).roundToDouble());
    final double snappedWidth = snappedWidthPx / scale;

    double? alignedTop = _snapBlueZone(
      stem.max,
      blueValues: blueValues,
      otherBlues: otherBlues,
      blueFuzz: blueFuzz,
      scale: scale,
      isBottom: false,
    );
    double? alignedBottom = _snapBlueZone(
      stem.min,
      blueValues: blueValues,
      otherBlues: otherBlues,
      blueFuzz: blueFuzz,
      scale: scale,
      isBottom: true,
    );

    if (alignedBottom == null && alignedTop == null) {
      alignedBottom = (stem.min * scale).roundToDouble() / scale;
      alignedTop = alignedBottom + snappedWidth;
    } else if (alignedBottom != null) {
      alignedTop = alignedBottom + snappedWidth;
    } else {
      alignedBottom = alignedTop! - snappedWidth;
    }

    rawAnchors
      ..add(_AnchorPair(stem.min, alignedBottom))
      ..add(_AnchorPair(stem.max, alignedTop));
  }

  if (rawAnchors.isEmpty) {
    return _AxisWarp.identity;
  }

  rawAnchors.sort((_AnchorPair a, _AnchorPair b) => a.orig.compareTo(b.orig));
  final List<_AnchorPair> deduped = <_AnchorPair>[];
  for (final _AnchorPair pair in rawAnchors) {
    if (deduped.isEmpty) {
      deduped.add(pair);
    } else if ((pair.orig - deduped.last.orig).abs() > 1e-6 &&
        pair.snapped >= deduped.last.snapped) {
      deduped.add(pair);
    }
  }
  return _AxisWarp(deduped);
}

double? _snapBlueZone(
  double coord, {
  required List<double> blueValues,
  required List<double> otherBlues,
  required double blueFuzz,
  required double scale,
  required bool isBottom,
}) {
  // In blueValues, index 0..1 is bottom baseline zone; subsequent pairs are top
  // zones. In otherBlues, all pairs are bottom zones.
  if (isBottom) {
    if (blueValues.length >= 2) {
      final double lo = math.min(blueValues[0], blueValues[1]) - blueFuzz;
      final double hi = math.max(blueValues[0], blueValues[1]) + blueFuzz;
      if (coord >= lo && coord <= hi) {
        return (blueValues[1] * scale).roundToDouble() / scale;
      }
    }
    for (int i = 0; i + 1 < otherBlues.length; i += 2) {
      final double lo = math.min(otherBlues[i], otherBlues[i + 1]) - blueFuzz;
      final double hi = math.max(otherBlues[i], otherBlues[i + 1]) + blueFuzz;
      if (coord >= lo && coord <= hi) {
        return (otherBlues[i + 1] * scale).roundToDouble() / scale;
      }
    }
    return null;
  }

  for (int i = 2; i + 1 < blueValues.length; i += 2) {
    final double lo = math.min(blueValues[i], blueValues[i + 1]) - blueFuzz;
    final double hi = math.max(blueValues[i], blueValues[i + 1]) + blueFuzz;
    if (coord >= lo && coord <= hi) {
      return (blueValues[i] * scale).roundToDouble() / scale;
    }
  }
  return null;
}
