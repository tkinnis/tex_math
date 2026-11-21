import '../ast.dart';
import '../font.dart';
import '../parser/symbol_map.dart';

/// Standard TeX thin math space (`3/18 em`).
const double thinMuSkipEm = 3.0 / 18.0;

/// Standard TeX medium math space (`4/18 em`).
const double medMuSkipEm = 4.0 / 18.0;

/// Standard TeX thick math space (`5/18 em`).
const double thickMuSkipEm = 5.0 / 18.0;

/// Standard TeX null delimiter space (`0.12 em`).
const double nullDelimiterSpaceEm = 0.12;

/// Returns whether [style] is a cramped math style.
bool isCrampedStyle(TexMathStyle style) {
  switch (style) {
    case TexMathStyle.crampedDisplay:
    case TexMathStyle.crampedText:
    case TexMathStyle.crampedScript:
    case TexMathStyle.crampedScriptScript:
      return true;
    case TexMathStyle.display:
    case TexMathStyle.text:
    case TexMathStyle.script:
    case TexMathStyle.scriptScript:
      return false;
  }
}

/// Returns whether [style] is a display math style (cramped or uncramped).
bool isDisplayStyle(TexMathStyle style) =>
    style == TexMathStyle.display || style == TexMathStyle.crampedDisplay;

/// Returns the Appendix G script nesting level (`0` = display/text,
/// `1` = script, `2` = scriptscript).
int scriptLevelForStyle(TexMathStyle style) {
  switch (style) {
    case TexMathStyle.display:
    case TexMathStyle.text:
    case TexMathStyle.crampedDisplay:
    case TexMathStyle.crampedText:
      return 0;
    case TexMathStyle.script:
    case TexMathStyle.crampedScript:
      return 1;
    case TexMathStyle.scriptScript:
    case TexMathStyle.crampedScriptScript:
      return 2;
  }
}

/// Returns the glyph scale factor for [style] derived from [constants].
double scaleForStyle(TexMathStyle style, MathConstants constants) {
  switch (scriptLevelForStyle(style)) {
    case 0:
      return 1.0;
    case 1:
      return constants.scriptPercentScaleDown > 0
          ? constants.scriptPercentScaleDown / 100.0
          : 0.70;
    default:
      return constants.scriptScriptPercentScaleDown > 0
          ? constants.scriptScriptPercentScaleDown / 100.0
          : 0.50;
  }
}

/// Returns the cramped counterpart of [style].
TexMathStyle toCrampedStyle(TexMathStyle style) {
  switch (style) {
    case TexMathStyle.display:
    case TexMathStyle.crampedDisplay:
      return TexMathStyle.crampedDisplay;
    case TexMathStyle.text:
    case TexMathStyle.crampedText:
      return TexMathStyle.crampedText;
    case TexMathStyle.script:
    case TexMathStyle.crampedScript:
      return TexMathStyle.crampedScript;
    case TexMathStyle.scriptScript:
    case TexMathStyle.crampedScriptScript:
      return TexMathStyle.crampedScriptScript;
  }
}

/// Returns the Appendix G superscript style for a base in [style].
TexMathStyle superscriptStyle(TexMathStyle style) {
  switch (style) {
    case TexMathStyle.display:
    case TexMathStyle.text:
      return TexMathStyle.script;
    case TexMathStyle.crampedDisplay:
    case TexMathStyle.crampedText:
      return TexMathStyle.crampedScript;
    case TexMathStyle.script:
    case TexMathStyle.scriptScript:
      return TexMathStyle.scriptScript;
    case TexMathStyle.crampedScript:
    case TexMathStyle.crampedScriptScript:
      return TexMathStyle.crampedScriptScript;
  }
}

/// Returns the Appendix G subscript style for a base in [style].
TexMathStyle subscriptStyle(TexMathStyle style) =>
    toCrampedStyle(superscriptStyle(style));

/// Returns the Appendix G fraction numerator style for [style].
TexMathStyle numeratorStyle(TexMathStyle style) {
  switch (style) {
    case TexMathStyle.display:
      return TexMathStyle.text;
    case TexMathStyle.crampedDisplay:
      return TexMathStyle.crampedText;
    case TexMathStyle.text:
      return TexMathStyle.script;
    case TexMathStyle.crampedText:
      return TexMathStyle.crampedScript;
    case TexMathStyle.script:
    case TexMathStyle.scriptScript:
      return TexMathStyle.scriptScript;
    case TexMathStyle.crampedScript:
    case TexMathStyle.crampedScriptScript:
      return TexMathStyle.crampedScriptScript;
  }
}

/// Returns the Appendix G fraction denominator style for [style].
TexMathStyle denominatorStyle(TexMathStyle style) =>
    toCrampedStyle(numeratorStyle(style));

/// TeX Appendix G 8x8 inter-atom spacing table indexed by
/// `[leftClass.index][rightClass.index]`.
///
/// Positive values (`1` = thin, `2` = medium, `3` = thick) apply only when both
/// adjacent atoms are at script level `0`. Negative `-1` encodes thin space in
/// all styles including scripts (`Ord <-> Op`, `Op <-> Op`, etc.).
const List<List<int>> _texAtomSpacingMatrix = <List<int>>[
  // Ord,  Op, Bin, Rel, Open, Close, Punct, Inner
  <int>[0, -1, 2, 3, 0, 0, 0, 1], // Ord
  <int>[-1, -1, 0, 3, 0, 0, 0, 1], // Op
  <int>[2, 2, 0, 0, 2, 0, 0, 2], // Bin
  <int>[3, 3, 0, 0, 3, 0, 0, 3], // Rel
  <int>[0, 0, 0, 0, 0, 0, 0, 0], // Open
  <int>[0, -1, 2, 3, 0, 0, 0, 1], // Close
  <int>[1, 1, 0, 1, 1, 1, 1, 1], // Punct
  <int>[1, -1, 2, 3, 1, 0, 1, 1], // Inner
];

/// Returns the TeX inter-atom space in ems between [left] and [right] at
/// [styleScale] and script levels [leftLevel] and [rightLevel].
double interAtomSpaceEm({
  required TexMathAtomClass left,
  required TexMathAtomClass right,
  required int leftLevel,
  required int rightLevel,
  required double styleScale,
}) {
  final int code = _texAtomSpacingMatrix[left.index][right.index];
  if (code == 0) {
    return 0.0;
  }
  if (code > 0 && (leftLevel > 0 || rightLevel > 0)) {
    return 0.0;
  }
  switch (code.abs()) {
    case 1:
      return thinMuSkipEm * styleScale;
    case 2:
      return medMuSkipEm * styleScale;
    case 3:
      return thickMuSkipEm * styleScale;
    default:
      return 0.0;
  }
}

/// Resolves whether a binary atom between [prevClass] and [nextClass] must
/// collapse to [TexMathAtomClass.ord] according to TeX Appendix G Rules 5 and 6.
TexMathAtomClass promoteAtomClass({
  required TexMathAtomClass atomClass,
  required TexMathAtomClass? prevClass,
  required TexMathAtomClass? nextClass,
}) {
  if (atomClass != TexMathAtomClass.bin) {
    return atomClass;
  }
  if (prevClass == null ||
      prevClass == TexMathAtomClass.bin ||
      prevClass == TexMathAtomClass.op ||
      prevClass == TexMathAtomClass.rel ||
      prevClass == TexMathAtomClass.open ||
      prevClass == TexMathAtomClass.punct) {
    return TexMathAtomClass.ord;
  }
  if (nextClass == null ||
      nextClass == TexMathAtomClass.rel ||
      nextClass == TexMathAtomClass.close ||
      nextClass == TexMathAtomClass.punct) {
    return TexMathAtomClass.ord;
  }
  return TexMathAtomClass.bin;
}

/// Resolves the Unicode scalar code point to look up in a [MathFont] for a
/// mathematical symbol with base scalar [baseCodePoint] and optional [variant].
///
/// Follows standard OpenType math Unicode scalar mapping:
/// - Default ASCII Latin letters map to Mathematical Italic (`\imath` ->
///   `U+1D6A4`, `\jmath` -> `U+1D6A5`, falling back to `U+0131`/`U+0237` when
///   unmapped in [font]).
/// - Lowercase Greek letters (`U+03B1`–`U+03C9`, variants, `\partial`) default
///   to Mathematical Italic Greek unless overridden by [variant].
/// - Uppercase Greek letters stay upright unless [variant] is explicitly given.
/// - Digits stay upright unless overridden by [variant].
int resolveMathGlyphCodePoint({
  required int baseCodePoint,
  required MathFont font,
  TexMathFontVariant? variant,
  bool isTextMode = false,
}) {
  if (isTextMode) {
    if (variant == null ||
        variant == TexMathFontVariant.normal ||
        variant == TexMathFontVariant.italic) {
      return baseCodePoint;
    }
    final int mapped = mathUnicodeCodePoint(baseCodePoint, variant);
    if (mapped != baseCodePoint && font.glyphIdForCodePoint(mapped) != 0) {
      return mapped;
    }
    return baseCodePoint;
  }

  if (baseCodePoint == 0x002D &&
      (variant == null || variant == TexMathFontVariant.normal) &&
      font.glyphIdForCodePoint(0x2212) != 0) {
    return 0x2212;
  }

  final TexMathFontVariant? effectiveVariant =
      variant ?? _defaultMathVariant(baseCodePoint);

  if (baseCodePoint == 0x0131 &&
      (effectiveVariant == null ||
          effectiveVariant == TexMathFontVariant.italic)) {
    if (font.glyphIdForCodePoint(0x1D6A4) != 0) {
      return 0x1D6A4;
    }
    return 0x0131;
  }
  if (baseCodePoint == 0x0237 &&
      (effectiveVariant == null ||
          effectiveVariant == TexMathFontVariant.italic)) {
    if (font.glyphIdForCodePoint(0x1D6A5) != 0) {
      return 0x1D6A5;
    }
    return 0x0237;
  }

  if (effectiveVariant == null) {
    return baseCodePoint;
  }

  final int mapped = mathUnicodeCodePoint(baseCodePoint, effectiveVariant);
  if (mapped != baseCodePoint && font.glyphIdForCodePoint(mapped) != 0) {
    return mapped;
  }
  return baseCodePoint;
}

TexMathFontVariant? _defaultMathVariant(int cp) {
  if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) {
    return TexMathFontVariant.italic;
  }
  if ((cp >= 0x03B1 && cp <= 0x03C9) ||
      cp == 0x03D1 ||
      cp == 0x03D5 ||
      cp == 0x03D6 ||
      cp == 0x03F0 ||
      cp == 0x03F1 ||
      cp == 0x03F5 ||
      cp == 0x2202) {
    return TexMathFontVariant.italic;
  }
  return null;
}

/// Resolves the OpenType glyph ID for [baseGlyphId] at [scriptLevel], using
/// `GSUB` `ssty` alternates only when [useOpticalScriptVariants] is enabled.
int resolveScriptVariantGlyphId({
  required MathFont font,
  required int baseGlyphId,
  required int scriptLevel,
  required bool useOpticalScriptVariants,
}) {
  if (!useOpticalScriptVariants || scriptLevel <= 0 || baseGlyphId == 0) {
    return baseGlyphId;
  }
  final int clampedLevel = scriptLevel > 2 ? 2 : scriptLevel;
  final int? variant = font.scriptVariantGlyph(baseGlyphId, clampedLevel);
  return (variant != null && variant != 0) ? variant : baseGlyphId;
}

/// Named function operators (`NamedFn` in TeX/MathJax) that emit invisible
/// function-application (`U+2061`) semantics before following operands.
const Set<String> namedFunctionOperators = <String>{
  'arccos',
  'arcsin',
  'arctan',
  'arg',
  'cos',
  'cosh',
  'cot',
  'coth',
  'csc',
  'deg',
  'dim',
  'exp',
  'hom',
  'ker',
  'lg',
  'ln',
  'log',
  'sec',
  'sin',
  'sinh',
  'tan',
  'tanh',
};

/// Named limit operators (`NamedOp` in TeX/MathJax) that do not emit `U+2061`.
const Set<String> namedLimitOperators = <String>{
  'det',
  'gcd',
  'inf',
  'injlim',
  'lim',
  'liminf',
  'limsup',
  'max',
  'min',
  'Pr',
  'projlim',
  'sup',
};

/// Resolves a TeX or CSS color specification (such as `red`, `#2563EB`, or
/// `#f00`) into a 32-bit ARGB integer, or `null` when unrecognized.
int? resolveColorSpecArgb(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final int? direct = _parseHexArgb(raw);
  if (direct != null) {
    return direct;
  }
  final String resolved = resolveTexColor(raw.trim());
  return _parseHexArgb(resolved);
}

int? _parseHexArgb(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  String hex = raw.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length == 3) {
    final String r = hex[0];
    final String g = hex[1];
    final String b = hex[2];
    hex = '$r$r$g$g$b$b';
  }
  if (hex.length == 6) {
    final int? rgb = int.tryParse(hex, radix: 16);
    return rgb != null ? (0xFF000000 | rgb) : null;
  }
  if (hex.length == 8) {
    return int.tryParse(hex, radix: 16);
  }
  return null;
}
