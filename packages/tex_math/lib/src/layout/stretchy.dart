import 'dart:math' as math;

import '../ast.dart';
import '../font.dart';
import '../source_span.dart';
import 'box.dart';
import 'style_spacing.dart';

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
      ? GlyphOutline(glyphId: 0, commands: const <PathCommand>[])
      : font.outlineForGlyph(effectiveGlyphId);
  final double upem = font.unitsPerEm.toDouble();
  final double? rawIc = font.mathTable?.glyphInfo.italicsCorrection(
    effectiveGlyphId,
  );

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

/// Resolves the Unicode code point for a delimiter token string, or `null` for
/// the TeX null delimiter `.`.
int? delimiterCodePoint(String delimiter, {bool isStretchy = true}) {
  final String trimmed = delimiter.trim();
  if (trimmed.isEmpty || trimmed == '.') {
    return null;
  }
  switch (trimmed) {
    case '(':
      return 0x28;
    case ')':
      return 0x29;
    case '[':
    case r'\lbrack':
      return 0x5B;
    case ']':
    case r'\rbrack':
      return 0x5D;
    case '{':
    case r'\{':
    case r'\lbrace':
      return 0x7B;
    case '}':
    case r'\}':
    case r'\rbrace':
      return 0x7D;
    case '|':
    case r'\vert':
    case r'\lvert':
    case r'\rvert':
      return isStretchy ? 0x2223 : 0x7C;
    case '\u2223':
      return 0x2223;
    case '‖':
    case r'\|':
    case r'\Vert':
    case r'\lVert':
    case r'\rVert':
    case r'\Arrowvert':
      return isStretchy ? 0x2225 : 0x2016;
    case '\u2225':
      return 0x2225;
    case '/':
      return 0x2F;
    case r'\backslash':
    case '\\':
    case '\u2216':
      return 0x5C;
    case r'\langle':
    case '⟨':
    case '\u2329':
      return 0x27E8;
    case r'\rangle':
    case '⟩':
    case '\u232A':
      return 0x27E9;
    case r'\lfloor':
    case '\u230A':
      return 0x230A;
    case r'\rfloor':
    case '\u230B':
      return 0x230B;
    case r'\lceil':
    case '\u2308':
      return 0x2308;
    case r'\rceil':
    case '\u2309':
      return 0x2309;
    case r'\uparrow':
    case '\u2191':
      return 0x2191;
    case r'\downarrow':
    case '\u2193':
      return 0x2193;
    case r'\updownarrow':
    case '\u2195':
      return 0x2195;
    case r'\Uparrow':
    case '\u21D1':
      return 0x21D1;
    case r'\Downarrow':
    case '\u21D3':
      return 0x21D3;
    case r'\Updownarrow':
    case '\u21D5':
      return 0x21D5;
    case r'\lmoustache':
    case '\u23B0':
      return 0x23B0;
    case r'\rmoustache':
    case '\u23B1':
      return 0x23B1;
    case r'\lgroup':
    case '\u27EE':
      return 0x27EE;
    case r'\rgroup':
    case '\u27EF':
      return 0x27EF;
    case r'\arrowvert':
    case '\u23D0':
      return 0x23D0;
    case r'\bracevert':
      return 0x7C;
    default:
      if (trimmed.runes.length == 1) {
        return trimmed.runes.first;
      }
      return null;
  }
}

/// Builds a vertically stretched or fixed-size delimiter box centered on
/// `axisHeight` from OpenType `MATH` variants and `GlyphAssembly`.
MathBox buildVerticalDelimiterBox({
  required MathFont font,
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
  final double axisEm =
      ((font.mathTable?.constants.axisHeight ?? 250.0) / upem) * scale;

  final double desiredEm;
  if (fixedSizeEm != null) {
    // TeX \big/\Big/\bigg/\Bigg scale factors map via 1.2 / 0.85 to height.
    desiredEm = fixedSizeEm * (1.2 / 0.85) * scale;
  } else if (exactSize) {
    desiredEm = targetSpanEm;
  } else {
    // TeX Appendix G delimiterfactor (901) / delimitershortfall (0.5em).
    desiredEm = math.max(targetSpanEm * 0.901, targetSpanEm - 0.5 * scale);
  }

  final MathVariants? variants = font.mathTable?.variants;
  final MathGlyphConstruction? construction = variants?.verticalConstruction(
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
        minConnectorOverlap: variants?.minConnectorOverlap ?? 0,
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
  required double targetSpanEm,
  double scale = 1.0,
  SourceSpan? span,
}) {
  const int cp = 0x221A;
  final int baseGid = font.glyphIdForCodePoint(cp);
  final double upem = font.unitsPerEm.toDouble();
  final MathVariants? variants = font.mathTable?.variants;
  final MathGlyphConstruction? construction = variants?.verticalConstruction(
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
        minConnectorOverlap: variants?.minConnectorOverlap ?? 0,
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
  required int codePoint,
  required TexMathStyle style,
  double scale = 1.0,
  SourceSpan? span,
}) {
  final int baseGid = font.glyphIdForCodePoint(codePoint);
  final double upem = font.unitsPerEm.toDouble();
  final MathConstants? constants = font.mathTable?.constants;
  final double axisEm = ((constants?.axisHeight ?? 250.0) / upem) * scale;

  int selectedGid = baseGid;
  if (isDisplayStyle(style)) {
    final MathGlyphConstruction? construction = font.mathTable?.variants
        .verticalConstruction(baseGid);
    if (construction != null && construction.variants.isNotEmpty) {
      final double minDisplayUnits =
          (constants?.displayOperatorMinHeight ?? 1300).toDouble();
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
  required int codePoint,
  required double targetWidthEm,
  double scale = 1.0,
  TexMathAtomClass atomClass = TexMathAtomClass.ord,
  SourceSpan? span,
}) {
  final int baseGid = font.glyphIdForCodePoint(codePoint);
  final double upem = font.unitsPerEm.toDouble();
  final MathVariants? variants = font.mathTable?.variants;
  MathGlyphConstruction? construction = variants?.horizontalConstruction(
    baseGid,
  );
  int resolvedCodePoint = codePoint;
  if (construction == null ||
      (construction.variants.isEmpty && construction.assembly == null)) {
    final int? fallbackCp = _horizontalFallbackArrowCodePoint(codePoint);
    if (fallbackCp != null) {
      final int fallbackGid = font.glyphIdForCodePoint(fallbackCp);
      final MathGlyphConstruction? fallbackConstruction = variants
          ?.horizontalConstruction(fallbackGid);
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
        minConnectorOverlap: variants?.minConnectorOverlap ?? 0,
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
  if (chosen.isEmpty && hasExtender) {
    chosen = expand(1);
  }
  var (List<double> minOvs, List<double> maxOvs, double minLen, double maxLen) =
      measure(chosen);

  if (hasExtender) {
    for (int k = 1; k <= 512 && maxLen < safeTarget - 1e-6; k++) {
      final List<GlyphAssemblyPart> candidate = expand(k);
      final (
        List<double> cMinOvs,
        List<double> cMaxOvs,
        double cMinLen,
        double cMaxLen,
      ) = measure(
        candidate,
      );
      chosen = candidate;
      minOvs = cMinOvs;
      maxOvs = cMaxOvs;
      minLen = cMinLen;
      maxLen = cMaxLen;
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
double boxTopAccentAnchorEm(MathBox box, MathFont font) {
  final double upem = font.unitsPerEm.toDouble();
  switch (box) {
    case GlyphBox(:final int glyphId, :final double scaleX):
      final double? raw = font.mathTable?.glyphInfo.topAccentAttachment(
        glyphId,
      );
      return raw != null ? (raw / upem) * scaleX : box.widthEm / 2.0;
    case HBox(:final List<MathBox> children):
      final List<MathBox> visible = children
          .where((MathBox c) => c is! KernBox && c is! AnchorBox)
          .toList();
      if (visible.length == 1) {
        double offsetX = 0.0;
        for (final MathBox c in children) {
          if (identical(c, visible.first)) {
            return offsetX + boxTopAccentAnchorEm(c, font);
          }
          offsetX += c.widthEm;
        }
      }
      return box.widthEm / 2.0;
    case VBox(:final List<VBoxChild> placements):
      if (placements.isNotEmpty) {
        return placements.first.xEm +
            boxTopAccentAnchorEm(placements.first.box, font);
      }
      return box.widthEm / 2.0;
    case RuleBox():
    case KernBox():
    case AnchorBox():
      return box.widthEm / 2.0;
  }
}
