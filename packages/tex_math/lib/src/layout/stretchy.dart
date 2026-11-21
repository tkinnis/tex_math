import 'dart:math' as math;

import '../ast.dart';
import '../break_point.dart';
import '../font.dart';
import '../shared/layout_constants.dart';
import '../shared/math_symbols.dart';
import '../source_span.dart';
import 'box.dart';
import 'style_spacing.dart';

export '../shared/math_symbols.dart' show delimiterCodePoint;

/// Builds a [GlyphBox] from a resolved [glyphId] and semantic [codePoint]
/// scaled by [scale] using [font] metrics and outline data.
GlyphBox buildGlyphBoxFromId({
  required MathFont font,
  required int glyphId,
  required int codePoint,
  double scale = 1.0,
  TexMathAtomClass atomClass = TexMathAtomClass.ord,
  int scriptLevel = 0,
  bool useOpticalScriptVariants = false,
  SourceSpan? span,
  BreakPoint breakPoint = BreakPoint.none,
}) {
  final int effectiveGlyphId = resolveScriptVariantGlyphId(
    font: font,
    baseGlyphId: glyphId,
    scriptLevel: scriptLevel,
    useOpticalScriptVariants: useOpticalScriptVariants,
  );

  final GlyphMetrics metrics = font.metricsForGlyph(effectiveGlyphId);
  final GlyphOutline? outline = effectiveGlyphId == 0
      ? const GlyphOutline(glyphId: 0, commands: <PathCommand>[])
      : font.outlineForGlyph(effectiveGlyphId);
  final double upem = font.unitsPerEm.toDouble();
  final double? rawIc = metrics.italicsCorrection;

  return GlyphBox(
    glyphId: effectiveGlyphId,
    codePoint: codePoint,
    widthEm: (metrics.advanceWidth / upem) * scale,
    heightEm: (metrics.height / upem) * scale,
    depthEm: (metrics.depth / upem) * scale,
    scaleX: scale,
    scaleY: scale,
    advanceEm: (metrics.advanceWidth / upem) * scale,
    italicsCorrectionEm: rawIc != null ? (rawIc / upem) * scale : 0.0,
    outline: outline,
    atomClass: atomClass,
    span: span,
    breakPoint: breakPoint,
  );
}

/// Builds a zero-width invisible function application (`U+2061`) [GlyphBox].
GlyphBox buildApplyFunctionBox({SourceSpan? span}) {
  return GlyphBox(
    glyphId: 0,
    codePoint: 0x2061,
    widthEm: 0.0,
    heightEm: 0.0,
    depthEm: 0.0,
    advanceEm: 0.0,
    outline: const GlyphOutline(glyphId: 0, commands: <PathCommand>[]),
    span: span,
  );
}

/// Builds a vertically stretched or fixed-size delimiter box centered on
/// `axisHeight` from OpenType `MATH` variants and `GlyphAssembly`.
MathBox buildVerticalDelimiterBox({
  required MathFont font,
  required MathTableData mathTable,
  required String? delimiter,
  required double targetSpanEm,
  required TexMathAtomClass atomClass,
  double scale = 1.0,
  double? fixedSizeEm,
  bool isNullDelimiterSpace = true,
  bool exactSize = false,
  SourceSpan? span,
}) {
  if (delimiter == null || delimiter.isEmpty) {
    return isNullDelimiterSpace
        ? KernBox(widthEm: nullDelimiterSpaceEm * scale, atomClass: atomClass)
        : KernBox(widthEm: 0.0, atomClass: atomClass);
  }
  final int? cp = delimiterCodePoint(delimiter, isStretchy: fixedSizeEm != 0.0);
  if (cp == null) {
    return isNullDelimiterSpace
        ? KernBox(widthEm: nullDelimiterSpaceEm * scale, atomClass: atomClass)
        : KernBox(widthEm: 0.0, atomClass: atomClass);
  }

  final int baseGid = _resolveDelimiterGlyphId(font, cp);
  final double upem = font.unitsPerEm.toDouble();
  final double axisEm = (mathTable.constants.axisHeight / upem) * scale;

  final double desiredEm;
  if (fixedSizeEm != null) {
    // TeX \big/\Big/\bigg/\Bigg scale factors map via 1.2 / 0.85 to height.
    desiredEm = fixedSizeEm * LayoutDefaults.bigDelimiterScaleRatio * scale;
  } else if (exactSize) {
    desiredEm = targetSpanEm;
  } else {
    // TeX Appendix G delimiterfactor (901) / delimitershortfall (0.5em).
    desiredEm = math.max(
      targetSpanEm * LayoutDefaults.delimiterFactorRatio,
      targetSpanEm - LayoutDefaults.delimiterShortfallEm * scale,
    );
  }

  final MathVariants variants = mathTable.variants;
  final MathGlyphConstruction? construction = variants.verticalConstruction(
    baseGid,
  );

  if (construction != null) {
    if (desiredEm <= 0.0 && construction.variants.isNotEmpty) {
      return buildGlyphBoxFromId(
        font: font,
        glyphId: baseGid,
        codePoint: cp,
        scale: scale,
        atomClass: atomClass,
        span: span,
      );
    }

    for (final MathGlyphVariant variant in construction.variants) {
      final double vSizeEm = (variant.advanceMeasurement / upem) * scale;
      if (vSizeEm >= desiredEm - 1e-6) {
        return buildGlyphBoxFromId(
          font: font,
          glyphId: variant.glyphId,
          codePoint: cp,
          scale: scale,
          atomClass: atomClass,
          span: span,
        );
      }
    }

    final GlyphAssembly? assembly = construction.assembly;
    if (assembly != null && assembly.parts.isNotEmpty) {
      return _assembleVerticalParts(
        font: font,
        assembly: assembly,
        minConnectorOverlap: variants.minConnectorOverlap,
        targetHeightEm: desiredEm,
        scale: scale,
        axisCenterEm: axisEm,
        atomClass: atomClass,
        span: span,
      );
    }

    if (construction.variants.isNotEmpty) {
      return buildGlyphBoxFromId(
        font: font,
        glyphId: construction.variants.last.glyphId,
        codePoint: cp,
        scale: scale,
        atomClass: atomClass,
        span: span,
      );
    }
  }

  return buildGlyphBoxFromId(
    font: font,
    glyphId: baseGid,
    codePoint: cp,
    scale: scale,
    atomClass: atomClass,
    span: span,
  );
}

/// Builds a vertical radical surd (`U+221A`) matching [targetSpanEm] without
/// shifting its vertical center to the math axis, returning the box with its
/// natural top/bottom metrics for Appendix G vinculum alignment.
MathBox buildVerticalSurdBox({
  required MathFont font,
  required MathTableData mathTable,
  required double targetSpanEm,
  double scale = 1.0,
  SourceSpan? span,
}) {
  const int cp = 0x221A;
  final int baseGid = font.glyphIdForCodePoint(cp);
  final double upem = font.unitsPerEm.toDouble();
  final MathVariants variants = mathTable.variants;
  final MathGlyphConstruction? construction = variants.verticalConstruction(
    baseGid,
  );

  if (construction != null) {
    for (final MathGlyphVariant variant in construction.variants) {
      final double vSizeEm = (variant.advanceMeasurement / upem) * scale;
      if (vSizeEm >= targetSpanEm - 1e-6) {
        return buildGlyphBoxFromId(
          font: font,
          glyphId: variant.glyphId,
          codePoint: cp,
          scale: scale,
          atomClass: TexMathAtomClass.ord,
          span: span,
        );
      }
    }

    final GlyphAssembly? assembly = construction.assembly;
    if (assembly != null && assembly.parts.isNotEmpty) {
      return _assembleVerticalParts(
        font: font,
        assembly: assembly,
        minConnectorOverlap: variants.minConnectorOverlap,
        targetHeightEm: targetSpanEm,
        scale: scale,
        axisCenterEm: null,
        atomClass: TexMathAtomClass.ord,
        span: span,
      );
    }

    if (construction.variants.isNotEmpty) {
      return buildGlyphBoxFromId(
        font: font,
        glyphId: construction.variants.last.glyphId,
        codePoint: cp,
        scale: scale,
        atomClass: TexMathAtomClass.ord,
        span: span,
      );
    }
  }

  return buildGlyphBoxFromId(
    font: font,
    glyphId: baseGid,
    codePoint: cp,
    scale: scale,
    atomClass: TexMathAtomClass.ord,
    span: span,
  );
}

/// Builds a display-style or inline-style large operator glyph centered on
/// `axisHeight` when selected via `displayOperatorMinHeight`.
MathBox buildLargeOperatorBox({
  required MathFont font,
  required MathTableData mathTable,
  required int codePoint,
  required TexMathStyle style,
  double scale = 1.0,
  SourceSpan? span,
}) {
  final int baseGid = font.glyphIdForCodePoint(codePoint);
  final double upem = font.unitsPerEm.toDouble();
  final MathConstants constants = mathTable.constants;
  final double axisEm = (constants.axisHeight / upem) * scale;

  int selectedGid = baseGid;
  if (isDisplayStyle(style)) {
    final MathGlyphConstruction? construction = mathTable.variants
        .verticalConstruction(baseGid);
    if (construction != null && construction.variants.isNotEmpty) {
      final double minDisplayUnits = constants.displayOperatorMinHeight
          .toDouble();
      int chosen = construction.variants.last.glyphId;
      for (final MathGlyphVariant variant in construction.variants) {
        if (variant.advanceMeasurement >= minDisplayUnits) {
          chosen = variant.glyphId;
          break;
        }
      }
      selectedGid = chosen;
    }
  }

  final GlyphBox box = buildGlyphBoxFromId(
    font: font,
    glyphId: selectedGid,
    codePoint: codePoint,
    scale: scale,
    atomClass: TexMathAtomClass.op,
    span: span,
  );

  // Center large operator on the math axis when font metrics do not already.
  final double currentMid = (box.heightEm - box.depthEm) / 2.0;
  final double delta = axisEm - currentMid;
  if (delta.abs() <= 1e-4) {
    return box;
  }
  return VBox.positioned(
    children: <VBoxChild>[VBoxChild(box: box, yEm: delta)],
    widthEm: box.widthEm,
    atomClass: TexMathAtomClass.op,
    italicsCorrectionEm: box.italicsCorrectionEm,
    span: span,
  );
}

/// Builds a horizontal stretchy glyph or `GlyphAssembly` (e.g. `\widehat`,
/// `\overbrace`, `\xrightarrow`) reaching at least [targetWidthEm].
MathBox buildHorizontalStretchyBox({
  required MathFont font,
  required MathTableData mathTable,
  required int codePoint,
  required double targetWidthEm,
  double scale = 1.0,
  TexMathAtomClass atomClass = TexMathAtomClass.ord,
  SourceSpan? span,
}) {
  final int baseGid = font.glyphIdForCodePoint(codePoint);
  final double upem = font.unitsPerEm.toDouble();
  final MathVariants variants = mathTable.variants;
  MathGlyphConstruction? construction = variants.horizontalConstruction(
    baseGid,
  );
  int resolvedCodePoint = codePoint;
  if (construction == null ||
      (construction.variants.isEmpty && construction.assembly == null)) {
    final int? fallbackCp = _horizontalFallbackArrowCodePoint(codePoint);
    if (fallbackCp != null) {
      final int fallbackGid = font.glyphIdForCodePoint(fallbackCp);
      final MathGlyphConstruction? fallbackConstruction = variants
          .horizontalConstruction(fallbackGid);
      if (fallbackConstruction != null &&
          (fallbackConstruction.variants.isNotEmpty ||
              fallbackConstruction.assembly != null)) {
        construction = fallbackConstruction;
        resolvedCodePoint = fallbackCp;
      }
    }
  }

  if (construction != null) {
    for (final MathGlyphVariant variant in construction.variants) {
      final double vWidthEm = (variant.advanceMeasurement / upem) * scale;
      if (vWidthEm >= targetWidthEm - 1e-6) {
        return buildGlyphBoxFromId(
          font: font,
          glyphId: variant.glyphId,
          codePoint: resolvedCodePoint,
          scale: scale,
          atomClass: atomClass,
          span: span,
        );
      }
    }

    final GlyphAssembly? assembly = construction.assembly;
    if (assembly != null && assembly.parts.isNotEmpty) {
      return _assembleHorizontalParts(
        font: font,
        assembly: assembly,
        minConnectorOverlap: variants.minConnectorOverlap,
        targetWidthEm: targetWidthEm,
        scale: scale,
        atomClass: atomClass,
        span: span,
      );
    }

    if (construction.variants.isNotEmpty) {
      return buildGlyphBoxFromId(
        font: font,
        glyphId: construction.variants.last.glyphId,
        codePoint: resolvedCodePoint,
        scale: scale,
        atomClass: atomClass,
        span: span,
      );
    }
  }

  return buildGlyphBoxFromId(
    font: font,
    glyphId: baseGid,
    codePoint: codePoint,
    scale: scale,
    atomClass: atomClass,
    span: span,
  );
}

int? _horizontalFallbackArrowCodePoint(int codePoint) {
  switch (codePoint) {
    case 0x27F5:
      return 0x2190;
    case 0x27F6:
      return 0x2192;
    case 0x27F7:
      return 0x2194;
    case 0x27F8:
      return 0x21D0;
    case 0x27F9:
      return 0x21D2;
    case 0x27FA:
      return 0x21D4;
    default:
      return null;
  }
}

int _resolveDelimiterGlyphId(MathFont font, int codePoint) {
  final int gid = font.glyphIdForCodePoint(codePoint);
  if (gid != 0) {
    return gid;
  }
  if (codePoint == 0x5C) {
    return font.glyphIdForCodePoint(0x2216);
  }
  if (codePoint == 0x2223 && gid == 0) {
    return font.glyphIdForCodePoint(0x7C);
  }
  if (codePoint == 0x2225) {
    return font.glyphIdForCodePoint(0x2016);
  }
  return gid;
}

class _AssemblyPlan {
  const _AssemblyPlan({
    required this.parts,
    required this.overlaps,
    required this.totalSpanUnits,
  });

  final List<GlyphAssemblyPart> parts;
  final List<double> overlaps;
  final double totalSpanUnits;
}

_AssemblyPlan _planAssembly({
  required GlyphAssembly assembly,
  required int minConnectorOverlap,
  required double targetDesignUnits,
}) {
  final List<GlyphAssemblyPart> rawParts = assembly.parts;
  final bool hasExtender = rawParts.any(
    (GlyphAssemblyPart part) => part.isExtender,
  );
  final double safeTarget = targetDesignUnits > 0.0 ? targetDesignUnits : 0.0;

  List<GlyphAssemblyPart> expand(int repeatCount) {
    final List<GlyphAssemblyPart> out = <GlyphAssemblyPart>[];
    for (final GlyphAssemblyPart part in rawParts) {
      if (part.isExtender) {
        for (int r = 0; r < repeatCount; r++) {
          out.add(part);
        }
      } else {
        out.add(part);
      }
    }
    return out;
  }

  (List<double>, List<double>, double, double) measure(
    List<GlyphAssemblyPart> expanded,
  ) {
    if (expanded.isEmpty) {
      return (const <double>[], const <double>[], 0.0, 0.0);
    }
    final List<double> minOverlaps = <double>[];
    final List<double> maxOverlaps = <double>[];
    double advanceSum = 0.0;
    for (int i = 0; i < expanded.length; i++) {
      advanceSum += expanded[i].fullAdvance;
      if (i + 1 < expanded.length) {
        final double maxOv = math
            .min(
              expanded[i].endConnectorLength,
              expanded[i + 1].startConnectorLength,
            )
            .toDouble();
        final double minOv = math.min(
          minConnectorOverlap.toDouble(),
          math.max(0.0, maxOv),
        );
        minOverlaps.add(minOv);
        maxOverlaps.add(math.max(0.0, maxOv));
      }
    }
    final double maxLen =
        advanceSum -
        minOverlaps.fold<double>(0.0, (double a, double b) => a + b);
    final double minLen =
        advanceSum -
        maxOverlaps.fold<double>(0.0, (double a, double b) => a + b);
    return (minOverlaps, maxOverlaps, minLen, maxLen);
  }

  List<GlyphAssemblyPart> chosen = expand(0);
  var (
    List<double> minOvs,
    List<double> maxOvs,
    double minLen,
    double maxLen,
  ) = chosen.isEmpty
      ? (const <double>[], const <double>[], 0.0, 0.0)
      : measure(chosen);

  if (hasExtender && (chosen.isEmpty || maxLen < safeTarget - 1e-6)) {
    // For any repeat count k >= 1, every extender contributes a fixed linear
    // increment (fullAdvance minus self-overlap) on top of the k = 1 measure.
    final (
      List<double> k1MinOvs,
      List<double> k1MaxOvs,
      double k1MinLen,
      double k1MaxLen,
    ) = measure(
      rawParts,
    );
    if (k1MaxLen >= safeTarget - 1e-6) {
      chosen = rawParts;
      minOvs = k1MinOvs;
      maxOvs = k1MaxOvs;
      minLen = k1MinLen;
      maxLen = k1MaxLen;
    } else {
      double step = 0.0;
      for (final GlyphAssemblyPart part in rawParts) {
        if (!part.isExtender) {
          continue;
        }
        final double maxOv = math
            .min(part.endConnectorLength, part.startConnectorLength)
            .toDouble();
        final double minOv = math.min(
          minConnectorOverlap.toDouble(),
          math.max(0.0, maxOv),
        );
        step += part.fullAdvance - minOv;
      }
      int repeatCount;
      if (step <= 1e-9) {
        repeatCount = 1;
      } else {
        repeatCount = 1 + ((safeTarget - 1e-6 - k1MaxLen) / step).ceil();
        if (repeatCount > 512) {
          repeatCount = 512;
        }
        while (repeatCount > 1 &&
            k1MaxLen + (repeatCount - 2) * step >= safeTarget - 1e-6) {
          repeatCount--;
        }
        if (repeatCount < 512 &&
            k1MaxLen + (repeatCount - 1) * step < safeTarget - 1e-6) {
          repeatCount++;
        }
      }
      if (repeatCount <= 1) {
        chosen = rawParts;
        minOvs = k1MinOvs;
        maxOvs = k1MaxOvs;
        minLen = k1MinLen;
        maxLen = k1MaxLen;
      } else {
        chosen = expand(repeatCount);
        (minOvs, maxOvs, minLen, maxLen) = measure(chosen);
      }
    }
  }

  final List<double> actualOverlaps = List<double>.from(minOvs);
  double actualSpan = maxLen;
  if (maxLen > safeTarget && minOvs.isNotEmpty) {
    final double remainingExcess = maxLen - math.max(safeTarget, minLen);
    double slackTotal = 0.0;
    for (int i = 0; i < minOvs.length; i++) {
      slackTotal += maxOvs[i] - minOvs[i];
    }
    if (slackTotal > 1e-6 && remainingExcess > 0.0) {
      final double ratio = math.min(1.0, remainingExcess / slackTotal);
      for (int i = 0; i < actualOverlaps.length; i++) {
        final double add = (maxOvs[i] - minOvs[i]) * ratio;
        actualOverlaps[i] += add;
        actualSpan -= add;
      }
    }
  }

  return _AssemblyPlan(
    parts: chosen,
    overlaps: actualOverlaps,
    totalSpanUnits: actualSpan,
  );
}

VBox _assembleVerticalParts({
  required MathFont font,
  required GlyphAssembly assembly,
  required int minConnectorOverlap,
  required double targetHeightEm,
  required double scale,
  required double? axisCenterEm,
  required TexMathAtomClass atomClass,
  SourceSpan? span,
}) {
  final double upem = font.unitsPerEm.toDouble();
  final double targetUnits = scale > 0.0
      ? (targetHeightEm / scale) * upem
      : 0.0;
  final _AssemblyPlan plan = _planAssembly(
    assembly: assembly,
    minConnectorOverlap: minConnectorOverlap,
    targetDesignUnits: targetUnits,
  );

  final double totalHeightEm = (plan.totalSpanUnits / upem) * scale;
  final double baseShiftY = axisCenterEm != null
      ? axisCenterEm - totalHeightEm / 2.0
      : 0.0;

  final List<VBoxChild> placements = <VBoxChild>[];
  double cursorUnits = 0.0;
  double maxWidthEm = 0.0;
  double topYEm = baseShiftY;
  double bottomYEm = -baseShiftY;

  for (int i = 0; i < plan.parts.length; i++) {
    final GlyphAssemblyPart part = plan.parts[i];
    final GlyphBox partBox = buildGlyphBoxFromId(
      font: font,
      glyphId: part.glyphId,
      codePoint: 0,
      scale: scale,
      span: span,
    );
    final GlyphMetrics gm = font.metricsForGlyph(part.glyphId);
    final double yEm = baseShiftY + (cursorUnits / upem) * scale;
    placements.add(VBoxChild(box: partBox, xEm: 0.0, yEm: yEm));
    if (partBox.widthEm > maxWidthEm) {
      maxWidthEm = partBox.widthEm;
    }
    final double partTop = yEm + (gm.yMax / upem) * scale;
    final double partBottom = -(yEm + (gm.yMin / upem) * scale);
    if (i == 0 || partTop > topYEm) {
      topYEm = partTop;
    }
    if (i == 0 || partBottom > bottomYEm) {
      bottomYEm = partBottom;
    }

    cursorUnits += part.fullAdvance;
    if (i < plan.overlaps.length) {
      cursorUnits -= plan.overlaps[i];
    }
  }

  return VBox.positioned(
    children: placements,
    widthEm: maxWidthEm,
    heightEm: math.max(0.0, topYEm),
    depthEm: math.max(0.0, bottomYEm),
    atomClass: atomClass,
    italicsCorrectionEm: (assembly.italicsCorrection / upem) * scale,
    span: span,
  );
}

VBox _assembleHorizontalParts({
  required MathFont font,
  required GlyphAssembly assembly,
  required int minConnectorOverlap,
  required double targetWidthEm,
  required double scale,
  required TexMathAtomClass atomClass,
  SourceSpan? span,
}) {
  final double upem = font.unitsPerEm.toDouble();
  final double targetUnits = scale > 0.0 ? (targetWidthEm / scale) * upem : 0.0;
  final _AssemblyPlan plan = _planAssembly(
    assembly: assembly,
    minConnectorOverlap: minConnectorOverlap,
    targetDesignUnits: targetUnits,
  );

  final List<VBoxChild> placements = <VBoxChild>[];
  double cursorUnits = 0.0;
  for (int i = 0; i < plan.parts.length; i++) {
    final GlyphAssemblyPart part = plan.parts[i];
    final GlyphBox partBox = buildGlyphBoxFromId(
      font: font,
      glyphId: part.glyphId,
      codePoint: 0,
      scale: scale,
      span: span,
    );
    final double xEm = (cursorUnits / upem) * scale;
    placements.add(VBoxChild(box: partBox, xEm: xEm, yEm: 0.0));
    cursorUnits += part.fullAdvance;
    if (i < plan.overlaps.length) {
      cursorUnits -= plan.overlaps[i];
    }
  }

  return VBox.positioned(
    children: placements,
    widthEm: (plan.totalSpanUnits / upem) * scale,
    atomClass: atomClass,
    italicsCorrectionEm: (assembly.italicsCorrection / upem) * scale,
    span: span,
  );
}

/// Computes the true ink vertical bounds `(yMinEm, yMaxEm)` of [box] in its
/// local baseline-relative coordinate frame without clamping to zero.
(double, double) boxVerticalInkBoundsEm(MathBox box, MathFont font) {
  final double upem = font.unitsPerEm.toDouble();
  switch (box) {
    case GlyphBox(:final int glyphId, :final double scaleY):
      if (glyphId == 0) {
        return (-box.depthEm, box.heightEm);
      }
      final GlyphMetrics m = font.metricsForGlyph(glyphId);
      return ((m.yMin / upem) * scaleY, (m.yMax / upem) * scaleY);
    case RuleBox():
      return (-box.depthEm, box.heightEm);
    case KernBox():
    case AnchorBox():
      return (0.0, 0.0);
    case HBox(:final List<MathBox> children):
      if (children.isEmpty) {
        return (0.0, 0.0);
      }
      double minY = double.infinity;
      double maxY = double.negativeInfinity;
      for (final MathBox child in children) {
        final (double cMin, double cMax) = boxVerticalInkBoundsEm(child, font);
        final double lo = cMin + child.shiftYEm;
        final double hi = cMax + child.shiftYEm;
        if (lo < minY) {
          minY = lo;
        }
        if (hi > maxY) {
          maxY = hi;
        }
      }
      return (
        minY.isFinite ? minY : -box.depthEm,
        maxY.isFinite ? maxY : box.heightEm,
      );
    case VBox(:final List<VBoxChild> placements):
      if (placements.isEmpty) {
        return (0.0, 0.0);
      }
      double minY = double.infinity;
      double maxY = double.negativeInfinity;
      for (final VBoxChild placement in placements) {
        final (double cMin, double cMax) = boxVerticalInkBoundsEm(
          placement.box,
          font,
        );
        final double y = placement.yEm + placement.box.shiftYEm;
        if (cMin + y < minY) {
          minY = cMin + y;
        }
        if (cMax + y > maxY) {
          maxY = cMax + y;
        }
      }
      return (
        minY.isFinite ? minY : -box.depthEm,
        maxY.isFinite ? maxY : box.heightEm,
      );
  }
}

/// Resolves the OpenType `MATH` horizontal top accent attachment X coordinate
/// for [box] in ems, falling back to `widthEm / 2.0`.
double boxTopAccentAnchorEm(
  MathBox box,
  MathFont font,
  MathTableData mathTable,
) {
  final double upem = font.unitsPerEm.toDouble();
  switch (box) {
    case GlyphBox(:final int glyphId, :final double scaleX):
      final double? raw = mathTable.glyphInfo.topAccentAttachment(glyphId);
      return raw != null ? (raw / upem) * scaleX : box.widthEm / 2.0;
    case HBox(:final List<MathBox> children):
      MathBox? singleVisible;
      double singleOffsetX = 0.0;
      double cursorX = 0.0;
      for (int i = 0; i < children.length; i++) {
        final MathBox child = children[i];
        if (child is! KernBox && child is! AnchorBox) {
          if (singleVisible != null) {
            return box.widthEm / 2.0;
          }
          singleVisible = child;
          singleOffsetX = cursorX;
        }
        cursorX += child.widthEm;
      }
      if (singleVisible != null) {
        return singleOffsetX +
            boxTopAccentAnchorEm(singleVisible, font, mathTable);
      }
      return box.widthEm / 2.0;
    case VBox(:final List<VBoxChild> placements):
      if (placements.isNotEmpty) {
        return placements.first.xEm +
            boxTopAccentAnchorEm(placements.first.box, font, mathTable);
      }
      return box.widthEm / 2.0;
    case RuleBox():
    case KernBox():
    case AnchorBox():
      return box.widthEm / 2.0;
  }
}
