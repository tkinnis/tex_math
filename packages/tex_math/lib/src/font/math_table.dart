import 'package:meta/meta.dart';

import '../error.dart';
import 'binary_reader.dart';
import 'variation.dart';

/// Four corner selectors for OpenType `MATH` staircase kerning queries.
enum MathKernCorner {
  /// Upper-right corner of the base or script glyph.
  topRight,

  /// Upper-left corner of the base or script glyph.
  topLeft,

  /// Lower-right corner of the base or script glyph.
  bottomRight,

  /// Lower-left corner of the base or script glyph.
  bottomLeft,
}

/// Design-unit value and optional device/variation offset from OpenType `MATH`.
@immutable
final class MathValueRecord {
  /// Creates a `MathValueRecord` with resolved [value] and raw [deviceOffset].
  const MathValueRecord({required this.value, this.deviceOffset = 0});

  /// Design-unit value (including any applied variation delta).
  final double value;

  /// Offset from the enclosing subtable to a `Device` or `VariationIndex`
  /// table (`0` if absent).
  final int deviceOffset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathValueRecord &&
          value == other.value &&
          deviceOffset == other.deviceOffset;

  @override
  int get hashCode => Object.hash(value, deviceOffset);

  @override
  String toString() =>
      'MathValueRecord(value: $value, deviceOffset: $deviceOffset)';
}

/// Complete OpenType `MATH` `MathConstants` subtable exposing all 56 constants.
@immutable
final class MathConstants {
  /// Creates a [MathConstants] instance from all 56 design constants.
  const MathConstants({
    required this.scriptPercentScaleDown,
    required this.scriptScriptPercentScaleDown,
    required this.delimitedSubFormulaMinHeight,
    required this.displayOperatorMinHeight,
    required this.mathLeadingRecord,
    required this.axisHeightRecord,
    required this.accentBaseHeightRecord,
    required this.flattenedAccentBaseHeightRecord,
    required this.subscriptShiftDownRecord,
    required this.subscriptTopMaxRecord,
    required this.subscriptBaselineDropMinRecord,
    required this.superscriptShiftUpRecord,
    required this.superscriptShiftUpCrampedRecord,
    required this.superscriptBottomMinRecord,
    required this.superscriptBaselineDropMaxRecord,
    required this.subSuperscriptGapMinRecord,
    required this.superscriptBottomMaxWithSubscriptRecord,
    required this.spaceAfterScriptRecord,
    required this.upperLimitGapMinRecord,
    required this.upperLimitBaselineRiseMinRecord,
    required this.lowerLimitGapMinRecord,
    required this.lowerLimitBaselineDropMinRecord,
    required this.stackTopShiftUpRecord,
    required this.stackTopDisplayStyleShiftUpRecord,
    required this.stackBottomShiftDownRecord,
    required this.stackBottomDisplayStyleShiftDownRecord,
    required this.stackGapMinRecord,
    required this.stackDisplayStyleGapMinRecord,
    required this.stretchStackTopShiftUpRecord,
    required this.stretchStackBottomShiftDownRecord,
    required this.stretchStackGapAboveMinRecord,
    required this.stretchStackGapBelowMinRecord,
    required this.fractionNumeratorShiftUpRecord,
    required this.fractionNumeratorDisplayStyleShiftUpRecord,
    required this.fractionDenominatorShiftDownRecord,
    required this.fractionDenominatorDisplayStyleShiftDownRecord,
    required this.fractionNumeratorGapMinRecord,
    required this.fractionNumDisplayStyleGapMinRecord,
    required this.fractionRuleThicknessRecord,
    required this.fractionDenominatorGapMinRecord,
    required this.fractionDenomDisplayStyleGapMinRecord,
    required this.skewedFractionHorizontalGapRecord,
    required this.skewedFractionVerticalGapRecord,
    required this.overbarVerticalGapRecord,
    required this.overbarRuleThicknessRecord,
    required this.overbarExtraAscenderRecord,
    required this.underbarVerticalGapRecord,
    required this.underbarRuleThicknessRecord,
    required this.underbarExtraDescenderRecord,
    required this.radicalVerticalGapRecord,
    required this.radicalDisplayStyleVerticalGapRecord,
    required this.radicalRuleThicknessRecord,
    required this.radicalExtraAscenderRecord,
    required this.radicalKernBeforeDegreeRecord,
    required this.radicalKernAfterDegreeRecord,
    required this.radicalDegreeBottomRaisePercent,
  });

  /// Percentage scale factor for first-level scripts (typically `70`).
  final int scriptPercentScaleDown;

  /// Percentage scale factor for nested script-scripts (typically `50`).
  final int scriptScriptPercentScaleDown;

  /// Minimum height of delimited subformula before choosing variants.
  final int delimitedSubFormulaMinHeight;

  /// Minimum height of display-style large operators.
  final int displayOperatorMinHeight;

  /// Full `MathValueRecord` for `mathLeading`.
  final MathValueRecord mathLeadingRecord;

  /// Full `MathValueRecord` for `axisHeight`.
  final MathValueRecord axisHeightRecord;

  /// Full `MathValueRecord` for `accentBaseHeight`.
  final MathValueRecord accentBaseHeightRecord;

  /// Full `MathValueRecord` for `flattenedAccentBaseHeight`.
  final MathValueRecord flattenedAccentBaseHeightRecord;

  /// Full `MathValueRecord` for `subscriptShiftDown`.
  final MathValueRecord subscriptShiftDownRecord;

  /// Full `MathValueRecord` for `subscriptTopMax`.
  final MathValueRecord subscriptTopMaxRecord;

  /// Full `MathValueRecord` for `subscriptBaselineDropMin`.
  final MathValueRecord subscriptBaselineDropMinRecord;

  /// Full `MathValueRecord` for `superscriptShiftUp`.
  final MathValueRecord superscriptShiftUpRecord;

  /// Full `MathValueRecord` for `superscriptShiftUpCramped`.
  final MathValueRecord superscriptShiftUpCrampedRecord;

  /// Full `MathValueRecord` for `superscriptBottomMin`.
  final MathValueRecord superscriptBottomMinRecord;

  /// Full `MathValueRecord` for `superscriptBaselineDropMax`.
  final MathValueRecord superscriptBaselineDropMaxRecord;

  /// Full `MathValueRecord` for `subSuperscriptGapMin`.
  final MathValueRecord subSuperscriptGapMinRecord;

  /// Full `MathValueRecord` for `superscriptBottomMaxWithSubscript`.
  final MathValueRecord superscriptBottomMaxWithSubscriptRecord;

  /// Full `MathValueRecord` for `spaceAfterScript`.
  final MathValueRecord spaceAfterScriptRecord;

  /// Full `MathValueRecord` for `upperLimitGapMin`.
  final MathValueRecord upperLimitGapMinRecord;

  /// Full `MathValueRecord` for `upperLimitBaselineRiseMin`.
  final MathValueRecord upperLimitBaselineRiseMinRecord;

  /// Full `MathValueRecord` for `lowerLimitGapMin`.
  final MathValueRecord lowerLimitGapMinRecord;

  /// Full `MathValueRecord` for `lowerLimitBaselineDropMin`.
  final MathValueRecord lowerLimitBaselineDropMinRecord;

  /// Full `MathValueRecord` for `stackTopShiftUp`.
  final MathValueRecord stackTopShiftUpRecord;

  /// Full `MathValueRecord` for `stackTopDisplayStyleShiftUp`.
  final MathValueRecord stackTopDisplayStyleShiftUpRecord;

  /// Full `MathValueRecord` for `stackBottomShiftDown`.
  final MathValueRecord stackBottomShiftDownRecord;

  /// Full `MathValueRecord` for `stackBottomDisplayStyleShiftDown`.
  final MathValueRecord stackBottomDisplayStyleShiftDownRecord;

  /// Full `MathValueRecord` for `stackGapMin`.
  final MathValueRecord stackGapMinRecord;

  /// Full `MathValueRecord` for `stackDisplayStyleGapMin`.
  final MathValueRecord stackDisplayStyleGapMinRecord;

  /// Full `MathValueRecord` for `stretchStackTopShiftUp`.
  final MathValueRecord stretchStackTopShiftUpRecord;

  /// Full `MathValueRecord` for `stretchStackBottomShiftDown`.
  final MathValueRecord stretchStackBottomShiftDownRecord;

  /// Full `MathValueRecord` for `stretchStackGapAboveMin`.
  final MathValueRecord stretchStackGapAboveMinRecord;

  /// Full `MathValueRecord` for `stretchStackGapBelowMin`.
  final MathValueRecord stretchStackGapBelowMinRecord;

  /// Full `MathValueRecord` for `fractionNumeratorShiftUp`.
  final MathValueRecord fractionNumeratorShiftUpRecord;

  /// Full `MathValueRecord` for `fractionNumeratorDisplayStyleShiftUp`.
  final MathValueRecord fractionNumeratorDisplayStyleShiftUpRecord;

  /// Full `MathValueRecord` for `fractionDenominatorShiftDown`.
  final MathValueRecord fractionDenominatorShiftDownRecord;

  /// Full `MathValueRecord` for `fractionDenominatorDisplayStyleShiftDown`.
  final MathValueRecord fractionDenominatorDisplayStyleShiftDownRecord;

  /// Full `MathValueRecord` for `fractionNumeratorGapMin`.
  final MathValueRecord fractionNumeratorGapMinRecord;

  /// Full `MathValueRecord` for `fractionNumDisplayStyleGapMin`.
  final MathValueRecord fractionNumDisplayStyleGapMinRecord;

  /// Full `MathValueRecord` for `fractionRuleThickness`.
  final MathValueRecord fractionRuleThicknessRecord;

  /// Full `MathValueRecord` for `fractionDenominatorGapMin`.
  final MathValueRecord fractionDenominatorGapMinRecord;

  /// Full `MathValueRecord` for `fractionDenomDisplayStyleGapMin`.
  final MathValueRecord fractionDenomDisplayStyleGapMinRecord;

  /// Full `MathValueRecord` for `skewedFractionHorizontalGap`.
  final MathValueRecord skewedFractionHorizontalGapRecord;

  /// Full `MathValueRecord` for `skewedFractionVerticalGap`.
  final MathValueRecord skewedFractionVerticalGapRecord;

  /// Full `MathValueRecord` for `overbarVerticalGap`.
  final MathValueRecord overbarVerticalGapRecord;

  /// Full `MathValueRecord` for `overbarRuleThickness`.
  final MathValueRecord overbarRuleThicknessRecord;

  /// Full `MathValueRecord` for `overbarExtraAscender`.
  final MathValueRecord overbarExtraAscenderRecord;

  /// Full `MathValueRecord` for `underbarVerticalGap`.
  final MathValueRecord underbarVerticalGapRecord;

  /// Full `MathValueRecord` for `underbarRuleThickness`.
  final MathValueRecord underbarRuleThicknessRecord;

  /// Full `MathValueRecord` for `underbarExtraDescender`.
  final MathValueRecord underbarExtraDescenderRecord;

  /// Full `MathValueRecord` for `radicalVerticalGap`.
  final MathValueRecord radicalVerticalGapRecord;

  /// Full `MathValueRecord` for `radicalDisplayStyleVerticalGap`.
  final MathValueRecord radicalDisplayStyleVerticalGapRecord;

  /// Full `MathValueRecord` for `radicalRuleThickness`.
  final MathValueRecord radicalRuleThicknessRecord;

  /// Full `MathValueRecord` for `radicalExtraAscender`.
  final MathValueRecord radicalExtraAscenderRecord;

  /// Full `MathValueRecord` for `radicalKernBeforeDegree`.
  final MathValueRecord radicalKernBeforeDegreeRecord;

  /// Full `MathValueRecord` for `radicalKernAfterDegree`.
  final MathValueRecord radicalKernAfterDegreeRecord;

  /// Percentage of radical height to raise the degree index baseline.
  final int radicalDegreeBottomRaisePercent;

  /// Default baseline-to-baseline spacing in multi-line displays.
  double get mathLeading => mathLeadingRecord.value;

  /// Height of the mathematical axis above baseline in font units.
  double get axisHeight => axisHeightRecord.value;

  /// Maximum base height using regular non-flattened accents.
  double get accentBaseHeight => accentBaseHeightRecord.value;

  /// Base height above which flattened accents are preferred.
  double get flattenedAccentBaseHeight => flattenedAccentBaseHeightRecord.value;

  /// Standard downward shift for subscripts.
  double get subscriptShiftDown => subscriptShiftDownRecord.value;

  /// Maximum height of subscript above the baseline.
  double get subscriptTopMax => subscriptTopMaxRecord.value;

  /// Minimum drop of subscript baseline below base box bottom.
  double get subscriptBaselineDropMin => subscriptBaselineDropMinRecord.value;

  /// Standard upward shift for superscripts in uncramped style.
  double get superscriptShiftUp => superscriptShiftUpRecord.value;

  /// Standard upward shift for superscripts in cramped style.
  double get superscriptShiftUpCramped => superscriptShiftUpCrampedRecord.value;

  /// Minimum height of superscript bottom above baseline.
  double get superscriptBottomMin => superscriptBottomMinRecord.value;

  /// Maximum drop of superscript baseline below base box top.
  double get superscriptBaselineDropMax =>
      superscriptBaselineDropMaxRecord.value;

  /// Minimum gap between subscript top and superscript bottom.
  double get subSuperscriptGapMin => subSuperscriptGapMinRecord.value;

  /// Maximum height of superscript bottom when paired with a subscript.
  double get superscriptBottomMaxWithSubscript =>
      superscriptBottomMaxWithSubscriptRecord.value;

  /// Extra horizontal space appended after scripts.
  double get spaceAfterScript => spaceAfterScriptRecord.value;

  /// Minimum clearance between operator top and upper limit.
  double get upperLimitGapMin => upperLimitGapMinRecord.value;

  /// Minimum distance from operator top to upper limit baseline.
  double get upperLimitBaselineRiseMin => upperLimitBaselineRiseMinRecord.value;

  /// Minimum clearance between operator bottom and lower limit.
  double get lowerLimitGapMin => lowerLimitGapMinRecord.value;

  /// Minimum distance from operator bottom to lower limit baseline.
  double get lowerLimitBaselineDropMin => lowerLimitBaselineDropMinRecord.value;

  /// Minimum upward shift for top element of non-display stacks.
  double get stackTopShiftUp => stackTopShiftUpRecord.value;

  /// Minimum upward shift for top element of display stacks.
  double get stackTopDisplayStyleShiftUp =>
      stackTopDisplayStyleShiftUpRecord.value;

  /// Minimum downward shift for bottom element of non-display stacks.
  double get stackBottomShiftDown => stackBottomShiftDownRecord.value;

  /// Minimum downward shift for bottom element of display stacks.
  double get stackBottomDisplayStyleShiftDown =>
      stackBottomDisplayStyleShiftDownRecord.value;

  /// Minimum gap between stacked elements in non-display styles.
  double get stackGapMin => stackGapMinRecord.value;

  /// Minimum gap between stacked elements in display styles.
  double get stackDisplayStyleGapMin => stackDisplayStyleGapMinRecord.value;

  /// Minimum upward shift for top element of stretchy stacks.
  double get stretchStackTopShiftUp => stretchStackTopShiftUpRecord.value;

  /// Minimum downward shift for bottom element of stretchy stacks.
  double get stretchStackBottomShiftDown =>
      stretchStackBottomShiftDownRecord.value;

  /// Minimum gap above stretched divider in stretchy stacks.
  double get stretchStackGapAboveMin => stretchStackGapAboveMinRecord.value;

  /// Minimum gap below stretched divider in stretchy stacks.
  double get stretchStackGapBelowMin => stretchStackGapBelowMinRecord.value;

  /// Minimum upward shift of fraction numerator in non-display style.
  double get fractionNumeratorShiftUp => fractionNumeratorShiftUpRecord.value;

  /// Minimum upward shift of fraction numerator in display style.
  double get fractionNumeratorDisplayStyleShiftUp =>
      fractionNumeratorDisplayStyleShiftUpRecord.value;

  /// Minimum downward shift of fraction denominator in non-display style.
  double get fractionDenominatorShiftDown =>
      fractionDenominatorShiftDownRecord.value;

  /// Minimum downward shift of fraction denominator in display style.
  double get fractionDenominatorDisplayStyleShiftDown =>
      fractionDenominatorDisplayStyleShiftDownRecord.value;

  /// Minimum gap between numerator bottom and fraction bar in non-display.
  double get fractionNumeratorGapMin => fractionNumeratorGapMinRecord.value;

  /// Minimum gap between numerator bottom and fraction bar in display style.
  double get fractionNumDisplayStyleGapMin =>
      fractionNumDisplayStyleGapMinRecord.value;

  /// Alias for [fractionNumDisplayStyleGapMin].
  double get fractionNumeratorDisplayStyleGapMin =>
      fractionNumDisplayStyleGapMinRecord.value;

  /// Default fraction rule thickness.
  double get fractionRuleThickness => fractionRuleThicknessRecord.value;

  /// Minimum gap between fraction bar and denominator top in non-display.
  double get fractionDenominatorGapMin => fractionDenominatorGapMinRecord.value;

  /// Minimum gap between fraction bar and denominator top in display style.
  double get fractionDenomDisplayStyleGapMin =>
      fractionDenomDisplayStyleGapMinRecord.value;

  /// Alias for [fractionDenomDisplayStyleGapMin].
  double get fractionDenominatorDisplayStyleGapMin =>
      fractionDenomDisplayStyleGapMinRecord.value;

  /// Horizontal gap between skewed fraction components.
  double get skewedFractionHorizontalGap =>
      skewedFractionHorizontalGapRecord.value;

  /// Vertical gap between skewed fraction components.
  double get skewedFractionVerticalGap => skewedFractionVerticalGapRecord.value;

  /// Vertical gap between base top and overbar.
  double get overbarVerticalGap => overbarVerticalGapRecord.value;

  /// Thickness of overbar rule.
  double get overbarRuleThickness => overbarRuleThicknessRecord.value;

  /// Extra vertical whitespace above overbar rule.
  double get overbarExtraAscender => overbarExtraAscenderRecord.value;

  /// Vertical gap between base bottom and underbar.
  double get underbarVerticalGap => underbarVerticalGapRecord.value;

  /// Thickness of underbar rule.
  double get underbarRuleThickness => underbarRuleThicknessRecord.value;

  /// Extra vertical whitespace below underbar rule.
  double get underbarExtraDescender => underbarExtraDescenderRecord.value;

  /// Vertical gap between radicand top and vinculum in non-display style.
  double get radicalVerticalGap => radicalVerticalGapRecord.value;

  /// Vertical gap between radicand top and vinculum in display style.
  double get radicalDisplayStyleVerticalGap =>
      radicalDisplayStyleVerticalGapRecord.value;

  /// Thickness of radical vinculum rule.
  double get radicalRuleThickness => radicalRuleThicknessRecord.value;

  /// Extra vertical whitespace above radical vinculum.
  double get radicalExtraAscender => radicalExtraAscenderRecord.value;

  /// Horizontal kern before radical degree index.
  double get radicalKernBeforeDegree => radicalKernBeforeDegreeRecord.value;

  /// Horizontal kern after radical degree index.
  double get radicalKernAfterDegree => radicalKernAfterDegreeRecord.value;

  /// Parses `MathConstants` starting at [offset] in [reader].
  factory MathConstants.parse(
    FontByteReader reader,
    int offset, {
    ItemVariationStore? gdefVarStore,
  }) {
    final FontByteReader sub = reader.slice(
      offset,
      reader.length - offset,
      'MATH.MathConstants',
    );
    sub.checkRange(0, 214, 'MATH.MathConstants');

    MathValueRecord rec(int index) {
      return _readMathValueRecord(
        sub,
        8 + index * 4,
        sub,
        gdefVarStore: gdefVarStore,
      );
    }

    return MathConstants(
      scriptPercentScaleDown: sub.readInt16(0, 'scriptPercentScaleDown'),
      scriptScriptPercentScaleDown: sub.readInt16(
        2,
        'scriptScriptPercentScaleDown',
      ),
      delimitedSubFormulaMinHeight: sub.readUint16(
        4,
        'delimitedSubFormulaMinHeight',
      ),
      displayOperatorMinHeight: sub.readUint16(6, 'displayOperatorMinHeight'),
      mathLeadingRecord: rec(0),
      axisHeightRecord: rec(1),
      accentBaseHeightRecord: rec(2),
      flattenedAccentBaseHeightRecord: rec(3),
      subscriptShiftDownRecord: rec(4),
      subscriptTopMaxRecord: rec(5),
      subscriptBaselineDropMinRecord: rec(6),
      superscriptShiftUpRecord: rec(7),
      superscriptShiftUpCrampedRecord: rec(8),
      superscriptBottomMinRecord: rec(9),
      superscriptBaselineDropMaxRecord: rec(10),
      subSuperscriptGapMinRecord: rec(11),
      superscriptBottomMaxWithSubscriptRecord: rec(12),
      spaceAfterScriptRecord: rec(13),
      upperLimitGapMinRecord: rec(14),
      upperLimitBaselineRiseMinRecord: rec(15),
      lowerLimitGapMinRecord: rec(16),
      lowerLimitBaselineDropMinRecord: rec(17),
      stackTopShiftUpRecord: rec(18),
      stackTopDisplayStyleShiftUpRecord: rec(19),
      stackBottomShiftDownRecord: rec(20),
      stackBottomDisplayStyleShiftDownRecord: rec(21),
      stackGapMinRecord: rec(22),
      stackDisplayStyleGapMinRecord: rec(23),
      stretchStackTopShiftUpRecord: rec(24),
      stretchStackBottomShiftDownRecord: rec(25),
      stretchStackGapAboveMinRecord: rec(26),
      stretchStackGapBelowMinRecord: rec(27),
      fractionNumeratorShiftUpRecord: rec(28),
      fractionNumeratorDisplayStyleShiftUpRecord: rec(29),
      fractionDenominatorShiftDownRecord: rec(30),
      fractionDenominatorDisplayStyleShiftDownRecord: rec(31),
      fractionNumeratorGapMinRecord: rec(32),
      fractionNumDisplayStyleGapMinRecord: rec(33),
      fractionRuleThicknessRecord: rec(34),
      fractionDenominatorGapMinRecord: rec(35),
      fractionDenomDisplayStyleGapMinRecord: rec(36),
      skewedFractionHorizontalGapRecord: rec(37),
      skewedFractionVerticalGapRecord: rec(38),
      overbarVerticalGapRecord: rec(39),
      overbarRuleThicknessRecord: rec(40),
      overbarExtraAscenderRecord: rec(41),
      underbarVerticalGapRecord: rec(42),
      underbarRuleThicknessRecord: rec(43),
      underbarExtraDescenderRecord: rec(44),
      radicalVerticalGapRecord: rec(45),
      radicalDisplayStyleVerticalGapRecord: rec(46),
      radicalRuleThicknessRecord: rec(47),
      radicalExtraAscenderRecord: rec(48),
      radicalKernBeforeDegreeRecord: rec(49),
      radicalKernAfterDegreeRecord: rec(50),
      radicalDegreeBottomRaisePercent: sub.readInt16(
        212,
        'radicalDegreeBottomRaisePercent',
      ),
    );
  }
}

/// Staircase kern table for one corner of a glyph.
final class _MathKernTable {
  const _MathKernTable(this.correctionHeights, this.kernValues);

  final List<double> correctionHeights;
  final List<double> kernValues;

  double evaluate(double correctionHeight) {
    int index = 0;
    while (index < correctionHeights.length &&
        correctionHeight >= correctionHeights[index]) {
      index++;
    }
    return kernValues[index];
  }
}

final class _MathKernEntry {
  const _MathKernEntry({
    this.topRight,
    this.topLeft,
    this.bottomRight,
    this.bottomLeft,
  });

  final _MathKernTable? topRight;
  final _MathKernTable? topLeft;
  final _MathKernTable? bottomRight;
  final _MathKernTable? bottomLeft;
}

/// OpenType `MATH` `MathGlyphInfo` subtable providing italics correction,
/// top accent attachment, extended shape flags, and 4-corner math kerns.
final class MathGlyphInfo {
  MathGlyphInfo._({
    required this._italicsCoverage,
    required this._italicsValues,
    required this._topAccentCoverage,
    required this._topAccentValues,
    required this._extendedShapeCoverage,
    required this._kernCoverage,
    required this._kernEntries,
  });

  /// Empty `MathGlyphInfo` when absent from a font.
  static final MathGlyphInfo empty = MathGlyphInfo._(
    italicsCoverage: CoverageTable.empty,
    italicsValues: const <double>[],
    topAccentCoverage: CoverageTable.empty,
    topAccentValues: const <double>[],
    extendedShapeCoverage: CoverageTable.empty,
    kernCoverage: CoverageTable.empty,
    kernEntries: const <_MathKernEntry>[],
  );

  final CoverageTable _italicsCoverage;
  final List<double> _italicsValues;
  final CoverageTable _topAccentCoverage;
  final List<double> _topAccentValues;
  final CoverageTable _extendedShapeCoverage;
  final CoverageTable _kernCoverage;
  final List<_MathKernEntry> _kernEntries;

  /// Returns italics correction for [glyphId] in font units, or `null` if
  /// unrecorded.
  double? italicsCorrection(int glyphId) {
    final int idx = _italicsCoverage.indexOf(glyphId);
    if (idx < 0 || idx >= _italicsValues.length) {
      return null;
    }
    return _italicsValues[idx];
  }

  /// Returns horizontal top-accent attachment coordinate for [glyphId] in font
  /// units, or `null` if unrecorded.
  double? topAccentAttachment(int glyphId) {
    final int idx = _topAccentCoverage.indexOf(glyphId);
    if (idx < 0 || idx >= _topAccentValues.length) {
      return null;
    }
    return _topAccentValues[idx];
  }

  /// Whether [glyphId] is flagged as an extended math shape.
  bool isExtendedShape(int glyphId) => _extendedShapeCoverage.contains(glyphId);

  /// Evaluates the cut-in math kern for [glyphId] at [corner] and
  /// [correctionHeight] in font design units.
  double mathKern(int glyphId, MathKernCorner corner, double correctionHeight) {
    final int idx = _kernCoverage.indexOf(glyphId);
    if (idx < 0 || idx >= _kernEntries.length) {
      return 0.0;
    }
    final _MathKernEntry entry = _kernEntries[idx];
    final _MathKernTable? table = switch (corner) {
      MathKernCorner.topRight => entry.topRight,
      MathKernCorner.topLeft => entry.topLeft,
      MathKernCorner.bottomRight => entry.bottomRight,
      MathKernCorner.bottomLeft => entry.bottomLeft,
    };
    return table == null ? 0.0 : table.evaluate(correctionHeight);
  }

  /// Parses `MathGlyphInfo` starting at [offset] in [reader].
  factory MathGlyphInfo.parse(
    FontByteReader reader,
    int offset, {
    ItemVariationStore? gdefVarStore,
  }) {
    final FontByteReader sub = reader.slice(
      offset,
      reader.length - offset,
      'MATH.MathGlyphInfo',
    );
    sub.checkRange(0, 8, 'MATH.MathGlyphInfo.header');
    final int italicsOff = sub.readUint16(0, 'mathItalicsCorrectionInfoOff');
    final int topAccentOff = sub.readUint16(2, 'mathTopAccentAttachmentOff');
    final int extShapeOff = sub.readUint16(4, 'extendedShapeCoverageOff');
    final int kernInfoOff = sub.readUint16(6, 'mathKernInfoOff');

    CoverageTable italicsCov = CoverageTable.empty;
    List<double> italicsVals = const <double>[];
    if (italicsOff != 0) {
      final FontByteReader it = sub.slice(
        italicsOff,
        sub.length - italicsOff,
        'MathItalicsCorrectionInfo',
      );
      final int covOff = it.readUint16(0, 'italicsCorrectionCoverageOffset');
      final int count = it.readUint16(2, 'italicsCorrectionCount');
      it.checkRange(4, count * 4, 'italicsCorrection');
      italicsCov = CoverageTable.parse(it, covOff, 'ItalicsCoverage');
      italicsVals = List<double>.generate(
        count,
        (int i) => _readMathValueRecord(
          it,
          4 + i * 4,
          it,
          gdefVarStore: gdefVarStore,
        ).value,
      );
    }

    CoverageTable topCov = CoverageTable.empty;
    List<double> topVals = const <double>[];
    if (topAccentOff != 0) {
      final FontByteReader ta = sub.slice(
        topAccentOff,
        sub.length - topAccentOff,
        'MathTopAccentAttachment',
      );
      final int covOff = ta.readUint16(0, 'topAccentCoverageOffset');
      final int count = ta.readUint16(2, 'topAccentAttachmentCount');
      ta.checkRange(4, count * 4, 'topAccentAttachment');
      topCov = CoverageTable.parse(ta, covOff, 'TopAccentCoverage');
      topVals = List<double>.generate(
        count,
        (int i) => _readMathValueRecord(
          ta,
          4 + i * 4,
          ta,
          gdefVarStore: gdefVarStore,
        ).value,
      );
    }

    final CoverageTable extCov = extShapeOff != 0
        ? CoverageTable.parse(sub, extShapeOff, 'ExtendedShapeCoverage')
        : CoverageTable.empty;

    CoverageTable kernCov = CoverageTable.empty;
    List<_MathKernEntry> kernEntries = const <_MathKernEntry>[];
    if (kernInfoOff != 0) {
      final FontByteReader ki = sub.slice(
        kernInfoOff,
        sub.length - kernInfoOff,
        'MathKernInfo',
      );
      final int covOff = ki.readUint16(0, 'mathKernCoverageOffset');
      final int count = ki.readUint16(2, 'mathKernCount');
      ki.checkRange(4, count * 8, 'mathKernInfoRecords');
      kernCov = CoverageTable.parse(ki, covOff, 'MathKernCoverage');
      final Map<int, _MathKernTable> parsedKerns = <int, _MathKernTable>{};

      _MathKernTable? loadKern(int kOff) {
        if (kOff == 0) {
          return null;
        }
        return parsedKerns.putIfAbsent(kOff, () {
          final FontByteReader kt = ki.slice(
            kOff,
            ki.length - kOff,
            'MathKern',
          );
          final int hCount = kt.readUint16(0, 'MathKern.heightCount');
          kt.checkRange(2, (hCount * 2 + 1) * 4, 'MathKern.records');
          final List<double> heights = List<double>.generate(
            hCount,
            (int j) => _readMathValueRecord(
              kt,
              2 + j * 4,
              kt,
              gdefVarStore: gdefVarStore,
            ).value,
          );
          final int kernBase = 2 + hCount * 4;
          final List<double> kerns = List<double>.generate(
            hCount + 1,
            (int j) => _readMathValueRecord(
              kt,
              kernBase + j * 4,
              kt,
              gdefVarStore: gdefVarStore,
            ).value,
          );
          return _MathKernTable(heights, kerns);
        });
      }

      kernEntries = List<_MathKernEntry>.generate(count, (int i) {
        final int pos = 4 + i * 8;
        return _MathKernEntry(
          topRight: loadKern(ki.readUint16(pos, 'topRightMathKernOffset')),
          topLeft: loadKern(ki.readUint16(pos + 2, 'topLeftMathKernOffset')),
          bottomRight: loadKern(
            ki.readUint16(pos + 4, 'bottomRightMathKernOffset'),
          ),
          bottomLeft: loadKern(
            ki.readUint16(pos + 6, 'bottomLeftMathKernOffset'),
          ),
        );
      });
    }

    return MathGlyphInfo._(
      italicsCoverage: italicsCov,
      italicsValues: italicsVals,
      topAccentCoverage: topCov,
      topAccentValues: topVals,
      extendedShapeCoverage: extCov,
      kernCoverage: kernCov,
      kernEntries: kernEntries,
    );
  }
}

/// Discrete size-step glyph record in `MathGlyphConstruction`.
@immutable
final class MathGlyphVariant {
  /// Creates a discrete size variant descriptor.
  const MathGlyphVariant({
    required this.variantGlyph,
    required this.advanceMeasurement,
  });

  /// Replacement glyph ID for this size step.
  final int variantGlyph;

  /// Alias for [variantGlyph].
  int get glyphId => variantGlyph;

  /// Advance height or width along the growth axis in font design units.
  final int advanceMeasurement;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathGlyphVariant &&
          variantGlyph == other.variantGlyph &&
          advanceMeasurement == other.advanceMeasurement;

  @override
  int get hashCode => Object.hash(variantGlyph, advanceMeasurement);

  @override
  String toString() =>
      'MathGlyphVariant(glyphId: $variantGlyph, advance: $advanceMeasurement)';
}

/// Single component piece in an OpenType `GlyphAssembly` construction.
@immutable
final class GlyphAssemblyPart {
  /// Creates an assembly part specification.
  const GlyphAssemblyPart({
    required this.glyphId,
    required this.startConnectorLength,
    required this.endConnectorLength,
    required this.fullAdvance,
    required this.isExtender,
  });

  /// Glyph ID for this segment.
  final int glyphId;

  /// Maximum overlap length at the start of this part in font units.
  final int startConnectorLength;

  /// Maximum overlap length at the end of this part in font units.
  final int endConnectorLength;

  /// Full advance length along the growth axis in font units.
  final int fullAdvance;

  /// Whether this part may be repeated to stretch arbitrarily.
  final bool isExtender;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphAssemblyPart &&
          glyphId == other.glyphId &&
          startConnectorLength == other.startConnectorLength &&
          endConnectorLength == other.endConnectorLength &&
          fullAdvance == other.fullAdvance &&
          isExtender == other.isExtender;

  @override
  int get hashCode => Object.hash(
    glyphId,
    startConnectorLength,
    endConnectorLength,
    fullAdvance,
    isExtender,
  );

  @override
  String toString() =>
      'GlyphAssemblyPart(glyphId: $glyphId, fullAdvance: $fullAdvance, '
      'isExtender: $isExtender)';
}

/// Extensible multi-part glyph recipe from OpenType `MATH` `GlyphAssembly`.
@immutable
final class GlyphAssembly {
  /// Creates a glyph assembly recipe.
  const GlyphAssembly({
    required this.italicsCorrectionRecord,
    required this.parts,
  });

  /// Italics correction record for the assembled glyph.
  final MathValueRecord italicsCorrectionRecord;

  /// Italics correction value in font design units.
  double get italicsCorrection => italicsCorrectionRecord.value;

  /// Ordered assembly segments from bottom/left to top/right.
  final List<GlyphAssemblyPart> parts;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphAssembly &&
          italicsCorrectionRecord == other.italicsCorrectionRecord &&
          _listEquals(parts, other.parts);

  @override
  int get hashCode =>
      Object.hash(italicsCorrectionRecord, Object.hashAll(parts));

  @override
  String toString() =>
      'GlyphAssembly(italicsCorrection: $italicsCorrection, '
      'parts: ${parts.length})';
}

/// Discrete size variants and optional extensible assembly for a single glyph.
@immutable
final class MathGlyphConstruction {
  /// Creates a construction record.
  const MathGlyphConstruction({required this.variants, this.assembly});

  /// Discrete size variant steps ordered from smallest to largest.
  final List<MathGlyphVariant> variants;

  /// Optional extensible part assembly when discrete steps are insufficient.
  final GlyphAssembly? assembly;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathGlyphConstruction &&
          assembly == other.assembly &&
          _listEquals(variants, other.variants);

  @override
  int get hashCode => Object.hash(assembly, Object.hashAll(variants));

  @override
  String toString() =>
      'MathGlyphConstruction(variants: ${variants.length}, '
      'hasAssembly: ${assembly != null})';
}

/// OpenType `MATH` `MathVariants` subtable providing stretchy vertical and
/// horizontal glyph constructions.
final class MathVariants {
  MathVariants._({
    required this.minConnectorOverlap,
    required this._vertCoverage,
    required this._vertConstructions,
    required this._horizCoverage,
    required this._horizConstructions,
  });

  /// Empty `MathVariants` table.
  static final MathVariants empty = MathVariants._(
    minConnectorOverlap: 0,
    vertCoverage: CoverageTable.empty,
    vertConstructions: const <MathGlyphConstruction>[],
    horizCoverage: CoverageTable.empty,
    horizConstructions: const <MathGlyphConstruction>[],
  );

  /// Minimum overlap required between consecutive assembly parts in font units.
  final int minConnectorOverlap;

  final CoverageTable _vertCoverage;
  final List<MathGlyphConstruction> _vertConstructions;
  final CoverageTable _horizCoverage;
  final List<MathGlyphConstruction> _horizConstructions;

  /// Returns vertical growth construction for [glyphId], or `null` if absent.
  MathGlyphConstruction? verticalConstruction(int glyphId) {
    final int idx = _vertCoverage.indexOf(glyphId);
    if (idx < 0 || idx >= _vertConstructions.length) {
      return null;
    }
    return _vertConstructions[idx];
  }

  /// Returns horizontal growth construction for [glyphId], or `null` if absent.
  MathGlyphConstruction? horizontalConstruction(int glyphId) {
    final int idx = _horizCoverage.indexOf(glyphId);
    if (idx < 0 || idx >= _horizConstructions.length) {
      return null;
    }
    return _horizConstructions[idx];
  }

  /// Parses `MathVariants` starting at [offset] in [reader].
  factory MathVariants.parse(
    FontByteReader reader,
    int offset, {
    ItemVariationStore? gdefVarStore,
  }) {
    final FontByteReader sub = reader.slice(
      offset,
      reader.length - offset,
      'MATH.MathVariants',
    );
    sub.checkRange(0, 10, 'MATH.MathVariants.header');
    final int minOverlap = sub.readUint16(0, 'minConnectorOverlap');
    final int vertCovOff = sub.readUint16(2, 'vertGlyphCoverageOffset');
    final int horizCovOff = sub.readUint16(4, 'horizGlyphCoverageOffset');
    final int vertCount = sub.readUint16(6, 'vertGlyphCount');
    final int horizCount = sub.readUint16(8, 'horizGlyphCount');
    sub.checkRange(10, (vertCount + horizCount) * 2, 'glyphConstructionOffs');

    final CoverageTable vertCov = vertCovOff != 0
        ? CoverageTable.parse(sub, vertCovOff, 'VertGlyphCoverage')
        : CoverageTable.empty;
    final CoverageTable horizCov = horizCovOff != 0
        ? CoverageTable.parse(sub, horizCovOff, 'HorizGlyphCoverage')
        : CoverageTable.empty;

    MathGlyphConstruction parseConstruction(int relOffset) {
      final FontByteReader c = sub.slice(
        relOffset,
        sub.length - relOffset,
        'MathGlyphConstruction',
      );
      c.checkRange(0, 4, 'MathGlyphConstruction.header');
      final int assemblyOff = c.readUint16(0, 'glyphAssemblyOffset');
      final int variantCount = c.readUint16(2, 'variantCount');
      c.checkRange(4, variantCount * 4, 'mathGlyphVariantRecords');

      final List<MathGlyphVariant> variants = List<MathGlyphVariant>.generate(
        variantCount,
        (int i) => MathGlyphVariant(
          variantGlyph: c.readUint16(4 + i * 4, 'variantGlyph'),
          advanceMeasurement: c.readUint16(6 + i * 4, 'advanceMeasurement'),
        ),
      );

      GlyphAssembly? assembly;
      if (assemblyOff != 0) {
        final FontByteReader a = c.slice(
          assemblyOff,
          c.length - assemblyOff,
          'GlyphAssembly',
        );
        a.checkRange(0, 6, 'GlyphAssembly.header');
        final MathValueRecord ital = _readMathValueRecord(
          a,
          0,
          a,
          gdefVarStore: gdefVarStore,
        );
        final int partCount = a.readUint16(4, 'GlyphAssembly.partCount');
        a.checkRange(6, partCount * 10, 'GlyphAssembly.partRecords');
        final List<GlyphAssemblyPart> parts = List<GlyphAssemblyPart>.generate(
          partCount,
          (int i) {
            final int p = 6 + i * 10;
            final int flags = a.readUint16(p + 8, 'partFlags');
            return GlyphAssemblyPart(
              glyphId: a.readUint16(p, 'glyphID'),
              startConnectorLength: a.readUint16(p + 2, 'startConnectorLength'),
              endConnectorLength: a.readUint16(p + 4, 'endConnectorLength'),
              fullAdvance: a.readUint16(p + 6, 'fullAdvance'),
              isExtender: (flags & 0x0001) != 0,
            );
          },
        );
        assembly = GlyphAssembly(
          italicsCorrectionRecord: ital,
          parts: List<GlyphAssemblyPart>.unmodifiable(parts),
        );
      }

      return MathGlyphConstruction(
        variants: List<MathGlyphVariant>.unmodifiable(variants),
        assembly: assembly,
      );
    }

    final List<MathGlyphConstruction> vertConstructions =
        List<MathGlyphConstruction>.generate(
          vertCount,
          (int i) => parseConstruction(
            sub.readUint16(10 + i * 2, 'vertGlyphConstructionOffsets'),
          ),
        );

    final int horizOffBase = 10 + vertCount * 2;
    final List<MathGlyphConstruction> horizConstructions =
        List<MathGlyphConstruction>.generate(
          horizCount,
          (int i) => parseConstruction(
            sub.readUint16(
              horizOffBase + i * 2,
              'horizGlyphConstructionOffsets',
            ),
          ),
        );

    return MathVariants._(
      minConnectorOverlap: minOverlap,
      vertCoverage: vertCov,
      vertConstructions: List<MathGlyphConstruction>.unmodifiable(
        vertConstructions,
      ),
      horizCoverage: horizCov,
      horizConstructions: List<MathGlyphConstruction>.unmodifiable(
        horizConstructions,
      ),
    );
  }
}

/// Complete parsed OpenType `MATH` table containing constants, glyph metadata,
/// and stretchy constructions.
final class MathTableData {
  /// Creates parsed `MATH` table data.
  const MathTableData({
    required this.constants,
    required this.glyphInfo,
    required this.variants,
  });

  /// All 56 mathematical typesetting design constants.
  final MathConstants constants;

  /// Per-glyph italics corrections, accent attachments, and cut-in kerns.
  final MathGlyphInfo glyphInfo;

  /// Vertical and horizontal size variants and extensible glyph assemblies.
  final MathVariants variants;

  /// Parses an OpenType `MATH` table from [reader].
  factory MathTableData.parse(
    FontByteReader reader, {
    ItemVariationStore? gdefVarStore,
  }) {
    if (reader.length < 10) {
      throw const TexMathFontError('Truncated MATH table (< 10 bytes).');
    }
    final int majorVersion = reader.readUint16(0, 'MATH.majorVersion');
    final int minorVersion = reader.readUint16(2, 'MATH.minorVersion');
    if (majorVersion != 1 || minorVersion != 0) {
      throw TexMathFontError(
        'Unsupported MATH table version $majorVersion.$minorVersion.',
      );
    }
    final int constOff = reader.readUint16(4, 'MATH.mathConstantsOffset');
    final int glyphInfoOff = reader.readUint16(6, 'MATH.mathGlyphInfoOffset');
    final int variantsOff = reader.readUint16(8, 'MATH.mathVariantsOffset');

    if (constOff == 0) {
      throw const TexMathFontError(
        'MATH table missing MathConstants subtable.',
      );
    }

    final MathConstants constants = MathConstants.parse(
      reader,
      constOff,
      gdefVarStore: gdefVarStore,
    );
    final MathGlyphInfo glyphInfo = glyphInfoOff != 0
        ? MathGlyphInfo.parse(reader, glyphInfoOff, gdefVarStore: gdefVarStore)
        : MathGlyphInfo.empty;
    final MathVariants variants = variantsOff != 0
        ? MathVariants.parse(reader, variantsOff, gdefVarStore: gdefVarStore)
        : MathVariants.empty;

    return MathTableData(
      constants: constants,
      glyphInfo: glyphInfo,
      variants: variants,
    );
  }
}

MathValueRecord _readMathValueRecord(
  FontByteReader reader,
  int offset,
  FontByteReader subtableBase, {
  ItemVariationStore? gdefVarStore,
}) {
  final int rawVal = reader.readInt16(offset, 'MathValueRecord.value');
  final int devOffset = reader.readUint16(
    offset + 2,
    'MathValueRecord.deviceOffset',
  );
  double value = rawVal.toDouble();
  if (devOffset != 0 &&
      gdefVarStore != null &&
      devOffset + 6 <= subtableBase.length) {
    final int deltaFormat = subtableBase.readUint16(
      devOffset + 4,
      'Device.deltaFormat',
    );
    if (deltaFormat == 0x8000) {
      final int outerIdx = subtableBase.readUint16(
        devOffset,
        'VariationIndex.deltaSetOuterIndex',
      );
      final int innerIdx = subtableBase.readUint16(
        devOffset + 2,
        'VariationIndex.deltaSetInnerIndex',
      );
      value += gdefVarStore.deltaFor(outerIdx, innerIdx);
    }
  }
  return MathValueRecord(value: value, deviceOffset: devOffset);
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
