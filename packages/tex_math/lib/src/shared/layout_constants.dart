/// Centralized default constants and TeX layout ratios used when an expression
/// or sub-element specifies implicit dimensions rather than direct glyph kerns.
abstract final class LayoutDefaults {
  /// Default script scale factor (`0.70`) when `MathConstants` leaves
  /// `scriptPercentScaleDown` at zero.
  static const double scriptScaleRatio = 0.70;

  /// Default script-script scale factor (`0.50`) when `MathConstants` leaves
  /// `scriptScriptPercentScaleDown` at zero.
  static const double scriptScriptScaleRatio = 0.50;

  /// TeX `\big`/`\Big`/`\bigg`/`\Bigg` optical height factor (`1.2 / 0.85`).
  static const double bigDelimiterScaleRatio = 1.2 / 0.85;

  /// TeX Appendix G `\delimiterfactor` ratio (`901 / 1000`).
  static const double delimiterFactorRatio = 0.901;

  /// TeX Appendix G `\delimitershortfall` in ems (`0.5em`).
  static const double delimiterShortfallEm = 0.5;

  /// Fallback x-height ratio in ems when `OS/2.sxHeight` is zero or negative.
  static const double fallbackXHeightEm = 0.431;

  /// Fallback stroke rule thickness ratio in ems when `fractionRuleThickness`
  /// is non-positive.
  static const double fallbackRuleThicknessEm = 0.04;

  /// Fraction horizontal overhang past inner box edges.
  static const double fractionRuleOverhangEm = 0.12;

  /// Bevelled fraction diagonal slant clearance in ems.
  static const double bevelledFractionClearanceEm = 0.15;

  /// Radical left index upward fraction of radical box height.
  static const double radicalIndexRaiseRatio = 0.6;

  /// Matrix/array inter-column gap (`1.0em`).
  static const double arrayColumnGapEm = 1.0;

  /// Compact `smallmatrix` inter-column gap (`0.333em`).
  static const double smallMatrixColumnGapEm = 1.0 / 3.0;

  /// Minimum baseline spacing multiplier between matrix rows (`1.2em`).
  static const double matrixRowBaselineSpacingEm = 1.2;

  /// Compact `smallmatrix` baseline spacing (`0.95em`).
  static const double smallMatrixRowBaselineSpacingEm = 0.95;

  /// Matrix vertical padding added around top/bottom rows (`0.1em`).
  static const double matrixVerticalPaddingEm = 0.1;

  /// Double rule separation width multiplier relative to single rule thickness.
  static const double doubleRuleGapMultiplier = 3.0;

  /// Double rule total footprint width multiplier relative to single rule thickness.
  static const double doubleRuleTotalWidthMultiplier = 4.0;

  /// Minimum equation number tag separation in ems.
  static const double equationTagGapEm = 1.0;

  /// Cancellation diagonal slash overshoot (`0.1em`).
  static const double cancelOverhangEm = 0.1;

  /// Default `\enclose` padding in ems (`0.22em`).
  static const double enclosePaddingEm = 0.22;

  /// Default `\fbox` / `\boxed` padding in ems (`0.25em`).
  static const double fboxPaddingEm = 0.25;

  /// `\bbox` border rule width ratio when `border` specifies no thickness.
  static const double bboxDefaultBorderEm = 0.05;

  /// CD commutative diagram minimum horizontal/vertical arrow span (`2.0em`).
  static const double cdMinArrowLengthEm = 2.0;

  /// CD commutative diagram padding around label glyphs (`0.25em`).
  static const double cdLabelPaddingEm = 0.25;

  /// Prooftree inference rule horizontal padding (`0.2em`).
  static const double prooftreePaddingEm = 0.2;

  /// Prooftree minimum inference vertical gap (`0.15em`).
  static const double prooftreeVerticalGapEm = 0.15;
}
