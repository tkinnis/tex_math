import '../ast.dart';
import '../error.dart';
import 'layout_constants.dart';

/// Standard TeX thin math space (`3/18 em`).
const double thinMuSkipEm = 3.0 / 18.0;

/// Standard TeX medium math space (`4/18 em`).
const double medMuSkipEm = 4.0 / 18.0;

/// Standard TeX thick math space (`5/18 em`).
const double thickMuSkipEm = 5.0 / 18.0;

/// Standard TeX null delimiter space (`0.12 em`).
const double nullDelimiterSpaceEm = 0.12;

/// Canonical mapping of negated base characters when preceded by `\not`.
const Map<String, String> notRemap = <String, String>{
  '\u2190': '\u219A',
  '\u2192': '\u219B',
  '\u2194': '\u21AE',
  '\u21D0': '\u21CD',
  '\u21D2': '\u21CF',
  '\u21D4': '\u21CE',
  '\u2208': '\u2209',
  '\u220B': '\u220C',
  '\u2223': '\u2224',
  '\u2225': '\u2226',
  '\u223C': '\u2241',
  '\u007E': '\u2241',
  '\u2243': '\u2244',
  '\u2245': '\u2247',
  '\u2248': '\u2249',
  '\u224D': '\u226D',
  '\u003D': '\u2260',
  '\u2261': '\u2262',
  '\u003C': '\u226E',
  '\u003E': '\u226F',
  '\u2264': '\u2270',
  '\u2265': '\u2271',
  '\u2272': '\u2274',
  '\u2273': '\u2275',
  '\u2276': '\u2278',
  '\u2277': '\u2279',
  '\u227A': '\u2280',
  '\u227B': '\u2281',
  '\u2282': '\u2284',
  '\u2283': '\u2285',
  '\u2286': '\u2288',
  '\u2287': '\u2289',
  '\u22A2': '\u22AC',
  '\u22A8': '\u22AD',
  '\u22A9': '\u22AE',
  '\u22AB': '\u22AF',
  '\u227C': '\u22E0',
  '\u227D': '\u22E1',
  '\u2291': '\u22E2',
  '\u2292': '\u22E3',
  '\u22B2': '\u22EA',
  '\u22B3': '\u22EB',
  '\u22B4': '\u22EC',
  '\u22B5': '\u22ED',
  '\u2203': '\u2204',
};

/// Horizontal spacing commands mapped to em widths.
const Map<String, double> mathSpacingCommands = <String, double>{
  ',': thinMuSkipEm,
  ':': medMuSkipEm,
  '>': medMuSkipEm,
  ';': thickMuSkipEm,
  '!': -thinMuSkipEm,
  'enspace': 0.5,
  'quad': 1.0,
  'qquad': 2.0,
  'thinspace': thinMuSkipEm,
  'negthinspace': -thinMuSkipEm,
  'medspace': medMuSkipEm,
  'negmedspace': -medMuSkipEm,
  'thickspace': thickMuSkipEm,
  'negthickspace': -thickMuSkipEm,
  ' ': 0.25,
  'space': 0.25,
  'nobreakspace': 0.25,
  '\u00A0': 0.25,
};

/// Single-character literal delimiters accepted after `\left`, `\right`,
/// `\middle`, and `\big` variants.
const Map<String, String> literalDelimiterMap = <String, String>{
  '(': '(',
  ')': ')',
  '[': '[',
  ']': ']',
  '<': '\u27E8',
  '>': '\u27E9',
  '/': '/',
  '|': '|',
  '.': '',
};

/// Font size scale factors for `fontsizev3` / `base` sizing switches.
const Map<String, double> fontSizeCommands = <String, double>{
  'Tiny': 0.5,
  'tiny': 0.6,
  'scriptsize': 0.7,
  'SMALL': 0.7,
  'Small': 0.8,
  'footnotesize': 0.8,
  'small': 0.9,
  'normalsize': 1.0,
  'large': 1.095,
  'Large': 1.2,
  'LARGE': 1.44,
  'huge': 1.728,
  'Huge': 2.074,
  'HUGE': 2.49,
};

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

/// Normalizes delimiter control sequences (`\lvert`, `\Vert`, `\langle`, ...)
/// and `.` into canonical Unicode delimiter strings.
String normalizeDelimiterString(String raw) {
  switch (raw) {
    case r'\lvert':
    case r'\rvert':
    case r'\vert':
    case '|':
      return '|';
    case r'\lVert':
    case r'\rVert':
    case r'\Vert':
    case r'\|':
      return '\u2016';
    case r'\langle':
      return '\u27E8';
    case r'\rangle':
      return '\u27E9';
    case r'\lfloor':
      return '\u230A';
    case r'\rfloor':
      return '\u230B';
    case r'\lceil':
      return '\u2308';
    case r'\rceil':
      return '\u2309';
    case r'\{':
    case r'\lbrace':
      return '{';
    case r'\}':
    case r'\rbrace':
      return '}';
    case '.':
      return '';
    default:
      return raw;
  }
}

/// Resolves an `empheq` delimiter token (e.g. `\empheqlbrace`) to its
/// canonical delimiter string or `null` when empty.
String? resolveEmpheqDelimiter(String raw) {
  switch (raw) {
    case r'\empheqlbrace':
    case r'\empheqbiglbrace':
      return '{';
    case r'\empheqrbrace':
    case r'\empheqbigrbrace':
      return '}';
    case r'\empheqlbrack':
    case r'\empheqbiglbrack':
      return '[';
    case r'\empheqrbrack':
    case r'\empheqbigrbrack':
      return ']';
    case r'\empheqlangle':
    case r'\empheqbiglangle':
      return '\u27E8';
    case r'\empheqrangle':
    case r'\empheqbigrangle':
      return '\u27E9';
    case r'\empheqlparen':
    case r'\empheqbiglparen':
      return '(';
    case r'\empheqrparen':
    case r'\empheqbigrparen':
      return ')';
    case r'\empheqlvert':
    case r'\empheqrvert':
    case r'\empheqbiglvert':
    case r'\empheqbigrvert':
      return '|';
    case r'\empheqlVert':
    case r'\empheqrVert':
    case r'\empheqbiglVert':
    case r'\empheqbigrVert':
      return '\u2016';
    case r'\empheqlfloor':
    case r'\empheqbiglfloor':
      return '\u230A';
    case r'\empheqrfloor':
    case r'\empheqbigrfloor':
      return '\u230B';
    case r'\empheqlceil':
    case r'\empheqbiglceil':
      return '\u2308';
    case r'\empheqrceil':
    case r'\empheqbigrceil':
      return '\u2309';
    default:
      if (raw.isEmpty) {
        return null;
      }
      return normalizeDelimiterString(raw);
  }
}

/// Returns the TeX scale height in ems for `\big`/`\Big`/`\bigg`/`\Bigg`
/// command variants, or `null` when [cs] is not a sizing delimiter command.
double? sizeForBigCommand(String cs) {
  switch (cs) {
    case 'big':
    case 'bigl':
    case 'bigr':
    case 'bigm':
      return 0.85;
    case 'Big':
    case 'Bigl':
    case 'Bigr':
    case 'Bigm':
      return 1.15;
    case 'bigg':
    case 'biggl':
    case 'biggr':
    case 'biggm':
      return 1.45;
    case 'Bigg':
    case 'Biggl':
    case 'Biggr':
    case 'Biggm':
      return 1.75;
    default:
      return null;
  }
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
      return singleCodePointOrNull(trimmed);
  }
}

/// Maps a text-mode font style command (such as `\textbf`, `\textit`,
/// `\textbb`, or `\textbfbb`) to its MathML `mathvariant` attribute.
String? mathMlVariantForTextStyle(String? styleCommand) {
  switch (styleCommand) {
    case 'textbf':
      return 'bold';
    case 'textbfbb':
      return 'bold';
    case 'textbb':
      return 'double-struck';
    case 'textit':
    case 'emph':
      return 'italic';
    case 'textsf':
      return 'sans-serif';
    case 'texttt':
      return 'monospace';
    default:
      return null;
  }
}

/// Maps a text-mode style command to the matching [TexMathFontVariant],
/// preserving MathJax `textmacros`/`bboldx` compatibility.
TexMathFontVariant? textStyleFontVariant(String? cmd) {
  switch (cmd) {
    case 'textbf':
      return TexMathFontVariant.bold;
    case 'texttt':
      return TexMathFontVariant.monospace;
    case 'textsf':
      return TexMathFontVariant.sansSerif;
    case 'textit':
    case 'emph':
      return TexMathFontVariant.italic;
    case 'textbb':
      return TexMathFontVariant.doubleStruck;
    case 'textbfbb':
      return TexMathFontVariant.doubleStruckBold;
    default:
      return null;
  }
}

final RegExp _validTexDimensionPattern = RegExp(
  r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)\s*(?:pt|pc|in|bp|cm|mm|dd|cc|sp|em|ex|mu|px)$',
);

final RegExp _parseTexDimensionPattern = RegExp(
  r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))\s*(pt|pc|in|bp|cm|mm|dd|cc|sp|em|ex|mu|px)?$',
);

final RegExp _cssLengthPattern = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]*)$');

/// Returns whether [dim] is a syntactically valid TeX dimension literal.
bool isValidTexDimension(String dim) =>
    _validTexDimensionPattern.hasMatch(dim.trim());

/// Parses a TeX dimension string (such as `2em`, `4pt`, `1.5ex`, `18mu`) to
/// em units using [exFactor] for `ex`. Throws [TexMathSyntaxError] on non-finite
/// values.
double parseTexDimensionToEm(
  String dim, {
  double exFactor = LayoutDefaults.fallbackXHeightEm,
}) {
  final RegExpMatch? m = _parseTexDimensionPattern.firstMatch(dim.trim());
  if (m == null) {
    return 0.0;
  }
  final double val = double.tryParse(m.group(1)!) ?? 0.0;
  if (!val.isFinite) {
    throw TexMathSyntaxError(
      'TeX dimension "$dim" exceeds finite numeric bounds.',
      errorClass: TexMathErrorClass.syntaxError,
    );
  }
  final String unit = m.group(2) ?? 'em';
  final double result;
  switch (unit) {
    case 'em':
      result = val;
    case 'ex':
      result = val * exFactor;
    case 'mu':
      result = val / 18.0;
    case 'pt':
    case 'bp':
      result = val / 10.0;
    case 'px':
      result = val / 16.0;
    case 'pc':
      result = val * 1.2;
    case 'in':
      result = val * 7.227;
    case 'cm':
      result = val * 2.845;
    case 'mm':
      result = val * 0.2845;
    default:
      result = val;
  }
  if (!result.isFinite) {
    throw TexMathSyntaxError(
      'TeX dimension "$dim" overflows finite layout bounds.',
      errorClass: TexMathErrorClass.syntaxError,
    );
  }
  return result;
}

/// Parses a CSS length literal (used in `\bbox[...]` attributes) into ems,
/// scaled by [scale] and using [exFactor] for `ex`. Throws
/// [TexMathSyntaxError] when the parsed value or scaled result is non-finite.
double parseCssLengthToEm(
  String? raw,
  double scale, {
  double exFactor = LayoutDefaults.fallbackXHeightEm,
}) {
  if (raw == null || raw.isEmpty) {
    return 0.0;
  }
  final RegExpMatch? m = _cssLengthPattern.firstMatch(raw.trim());
  if (m == null) {
    return 0.0;
  }
  final double val = double.tryParse(m.group(1)!) ?? 0.0;
  if (!val.isFinite) {
    throw TexMathSyntaxError(
      'CSS length "$raw" exceeds finite numeric bounds.',
      errorClass: TexMathErrorClass.syntaxError,
    );
  }
  final String unit = (m.group(2) ?? '').toLowerCase();
  final double result;
  switch (unit) {
    case 'em':
      result = val * scale;
    case 'ex':
      result = val * exFactor * scale;
    case 'pt':
      result = (val / 10.0) * scale;
    case 'px':
    default:
      result = (val / 16.0) * scale;
  }
  if (!result.isFinite) {
    throw TexMathSyntaxError(
      'CSS length "$raw" overflows finite layout bounds.',
      errorClass: TexMathErrorClass.syntaxError,
    );
  }
  return result;
}

/// Decodes a string containing exactly one Unicode scalar code point without
/// allocating a `.runes.toList()` buffer, or returns `null` otherwise.
int? singleCodePointOrNull(String value) {
  final int len = value.length;
  if (len == 1) {
    return value.codeUnitAt(0);
  }
  if (len == 2) {
    final int u0 = value.codeUnitAt(0);
    if (u0 >= 0xD800 && u0 <= 0xDBFF) {
      final int u1 = value.codeUnitAt(1);
      if (u1 >= 0xDC00 && u1 <= 0xDFFF) {
        return 0x10000 + ((u0 - 0xD800) << 10) + (u1 - 0xDC00);
      }
    }
  }
  return null;
}

/// Returns the first Unicode scalar code point of [value], or [fallback] if
/// [value] is empty.
int firstCodePointOr(String value, int fallback) {
  if (value.isEmpty) {
    return fallback;
  }
  final int u0 = value.codeUnitAt(0);
  if (u0 >= 0xD800 && u0 <= 0xDBFF && value.length > 1) {
    final int u1 = value.codeUnitAt(1);
    if (u1 >= 0xDC00 && u1 <= 0xDFFF) {
      return 0x10000 + ((u0 - 0xD800) << 10) + (u1 - 0xDC00);
    }
  }
  return u0;
}

/// Returns the default TeX math font variant for [cp], or `null` when upright.
TexMathFontVariant? defaultMathVariantForCodePoint(int cp) {
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

/// Maps [baseVariant] (or the default math variant for [codePoint]) to its bold
/// counterpart inside `\boldsymbol{...}`.
TexMathFontVariant boldSymbolVariantFor(
  TexMathFontVariant? baseVariant,
  int? codePoint,
) {
  final TexMathFontVariant effective =
      baseVariant ??
      (codePoint != null ? defaultMathVariantForCodePoint(codePoint) : null) ??
      TexMathFontVariant.normal;
  switch (effective) {
    case TexMathFontVariant.normal:
      return TexMathFontVariant.bold;
    case TexMathFontVariant.italic:
      return TexMathFontVariant.boldItalic;
    case TexMathFontVariant.script:
      return TexMathFontVariant.boldScript;
    case TexMathFontVariant.fraktur:
      return TexMathFontVariant.boldFraktur;
    case TexMathFontVariant.sansSerif:
      return TexMathFontVariant.boldSansSerif;
    case TexMathFontVariant.sansSerifItalic:
      return TexMathFontVariant.sansSerifBoldItalic;
    case TexMathFontVariant.doubleStruck:
      return TexMathFontVariant.doubleStruckBold;
    case TexMathFontVariant.bold:
    case TexMathFontVariant.boldItalic:
    case TexMathFontVariant.boldScript:
    case TexMathFontVariant.boldFraktur:
    case TexMathFontVariant.boldSansSerif:
    case TexMathFontVariant.sansSerifBoldItalic:
    case TexMathFontVariant.monospace:
    case TexMathFontVariant.doubleStruckBold:
    case TexMathFontVariant.doubleStruckSans:
    case TexMathFontVariant.doubleStruckMonospace:
      return effective;
  }
}

/// Maps a base Unicode code point and [TexMathFontVariant] to the matching
/// Mathematical Alphanumeric Symbol code point when one exists.
int mathUnicodeCodePoint(int baseCodePoint, TexMathFontVariant? variant) {
  if (variant == null || variant == TexMathFontVariant.normal) {
    return baseCodePoint;
  }

  // ASCII uppercase A-Z.
  if (baseCodePoint >= 0x41 && baseCodePoint <= 0x5A) {
    final int offset = baseCodePoint - 0x41;
    switch (variant) {
      case TexMathFontVariant.normal:
        return baseCodePoint;
      case TexMathFontVariant.bold:
        return 0x1D400 + offset;
      case TexMathFontVariant.italic:
        return 0x1D434 + offset;
      case TexMathFontVariant.boldItalic:
        return 0x1D468 + offset;
      case TexMathFontVariant.script:
        return _scriptUpperExceptions[baseCodePoint] ?? (0x1D49C + offset);
      case TexMathFontVariant.boldScript:
        return 0x1D4D0 + offset;
      case TexMathFontVariant.fraktur:
        return _frakturUpperExceptions[baseCodePoint] ?? (0x1D504 + offset);
      case TexMathFontVariant.boldFraktur:
        return 0x1D56C + offset;
      case TexMathFontVariant.sansSerif:
        return 0x1D5A0 + offset;
      case TexMathFontVariant.boldSansSerif:
        return 0x1D5D4 + offset;
      case TexMathFontVariant.sansSerifItalic:
        return 0x1D608 + offset;
      case TexMathFontVariant.sansSerifBoldItalic:
        return 0x1D63C + offset;
      case TexMathFontVariant.monospace:
        return 0x1D670 + offset;
      case TexMathFontVariant.doubleStruck:
      case TexMathFontVariant.doubleStruckBold:
      case TexMathFontVariant.doubleStruckSans:
      case TexMathFontVariant.doubleStruckMonospace:
        return _doubleStruckUpperExceptions[baseCodePoint] ??
            (0x1D538 + offset);
    }
  }

  // ASCII lowercase a-z.
  if (baseCodePoint >= 0x61 && baseCodePoint <= 0x7A) {
    final int offset = baseCodePoint - 0x61;
    switch (variant) {
      case TexMathFontVariant.normal:
        return baseCodePoint;
      case TexMathFontVariant.bold:
        return 0x1D41A + offset;
      case TexMathFontVariant.italic:
        return baseCodePoint == 0x68 ? 0x210E : (0x1D44E + offset);
      case TexMathFontVariant.boldItalic:
        return 0x1D482 + offset;
      case TexMathFontVariant.script:
        return _scriptLowerExceptions[baseCodePoint] ?? (0x1D4B6 + offset);
      case TexMathFontVariant.boldScript:
        return 0x1D4EA + offset;
      case TexMathFontVariant.fraktur:
        return 0x1D51E + offset;
      case TexMathFontVariant.boldFraktur:
        return 0x1D586 + offset;
      case TexMathFontVariant.sansSerif:
        return 0x1D5BA + offset;
      case TexMathFontVariant.boldSansSerif:
        return 0x1D5EE + offset;
      case TexMathFontVariant.sansSerifItalic:
        return 0x1D622 + offset;
      case TexMathFontVariant.sansSerifBoldItalic:
        return 0x1D656 + offset;
      case TexMathFontVariant.monospace:
        return 0x1D68A + offset;
      case TexMathFontVariant.doubleStruck:
      case TexMathFontVariant.doubleStruckBold:
      case TexMathFontVariant.doubleStruckSans:
      case TexMathFontVariant.doubleStruckMonospace:
        return 0x1D552 + offset;
    }
  }

  // ASCII digits 0-9.
  if (baseCodePoint >= 0x30 && baseCodePoint <= 0x39) {
    final int offset = baseCodePoint - 0x30;
    switch (variant) {
      case TexMathFontVariant.bold:
        return 0x1D7CE + offset;
      case TexMathFontVariant.doubleStruck:
      case TexMathFontVariant.doubleStruckBold:
      case TexMathFontVariant.doubleStruckSans:
      case TexMathFontVariant.doubleStruckMonospace:
        return 0x1D7D8 + offset;
      case TexMathFontVariant.sansSerif:
        return 0x1D7E2 + offset;
      case TexMathFontVariant.boldSansSerif:
        return 0x1D7EC + offset;
      case TexMathFontVariant.monospace:
        return 0x1D7F6 + offset;
      default:
        return baseCodePoint;
    }
  }

  // Greek uppercase & lowercase math variants.
  if (baseCodePoint >= 0x0391 && baseCodePoint <= 0x03A9) {
    final int offset = baseCodePoint - 0x0391;
    switch (variant) {
      case TexMathFontVariant.bold:
        return 0x1D6A8 + offset;
      case TexMathFontVariant.italic:
        return 0x1D6E2 + offset;
      case TexMathFontVariant.boldItalic:
        return 0x1D71C + offset;
      case TexMathFontVariant.boldSansSerif:
        return 0x1D756 + offset;
      case TexMathFontVariant.sansSerifBoldItalic:
        return 0x1D790 + offset;
      default:
        return baseCodePoint;
    }
  }
  if (baseCodePoint >= 0x03B1 && baseCodePoint <= 0x03C9) {
    final int offset = baseCodePoint - 0x03B1;
    switch (variant) {
      case TexMathFontVariant.bold:
        return 0x1D6C2 + offset;
      case TexMathFontVariant.italic:
        return 0x1D6FC + offset;
      case TexMathFontVariant.boldItalic:
        return 0x1D736 + offset;
      case TexMathFontVariant.boldSansSerif:
        return 0x1D770 + offset;
      case TexMathFontVariant.sansSerifBoldItalic:
        return 0x1D7AA + offset;
      default:
        return baseCodePoint;
    }
  }

  final Map<TexMathFontVariant, int>? specialGreek =
      _greekVariantExceptions[baseCodePoint];
  if (specialGreek != null) {
    return specialGreek[variant] ?? baseCodePoint;
  }

  return baseCodePoint;
}

const Map<int, int> _scriptUpperExceptions = <int, int>{
  0x42: 0x212C,
  0x45: 0x2130,
  0x46: 0x2131,
  0x48: 0x210B,
  0x49: 0x2110,
  0x4C: 0x2112,
  0x4D: 0x2133,
  0x52: 0x211B,
};

const Map<int, int> _scriptLowerExceptions = <int, int>{
  0x65: 0x212F,
  0x67: 0x210A,
  0x6F: 0x2134,
};

const Map<int, int> _frakturUpperExceptions = <int, int>{
  0x43: 0x212D,
  0x48: 0x210C,
  0x49: 0x2111,
  0x52: 0x211C,
  0x5A: 0x2128,
};

const Map<int, int> _doubleStruckUpperExceptions = <int, int>{
  0x43: 0x2102,
  0x48: 0x210D,
  0x4E: 0x2115,
  0x50: 0x2119,
  0x51: 0x211A,
  0x52: 0x211D,
  0x5A: 0x2124,
};

const Map<int, Map<TexMathFontVariant, int>> _greekVariantExceptions =
    <int, Map<TexMathFontVariant, int>>{
      0x03F5: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6DC,
        TexMathFontVariant.italic: 0x1D716,
        TexMathFontVariant.boldItalic: 0x1D750,
      },
      0x03D1: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6DD,
        TexMathFontVariant.italic: 0x1D717,
        TexMathFontVariant.boldItalic: 0x1D751,
      },
      0x03F0: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6DE,
        TexMathFontVariant.italic: 0x1D718,
        TexMathFontVariant.boldItalic: 0x1D752,
      },
      0x03D5: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6DF,
        TexMathFontVariant.italic: 0x1D719,
        TexMathFontVariant.boldItalic: 0x1D753,
      },
      0x03F1: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6E0,
        TexMathFontVariant.italic: 0x1D71A,
        TexMathFontVariant.boldItalic: 0x1D754,
      },
      0x03D6: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6E1,
        TexMathFontVariant.italic: 0x1D71B,
        TexMathFontVariant.boldItalic: 0x1D755,
      },
      0x2202: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6DB,
        TexMathFontVariant.italic: 0x1D715,
        TexMathFontVariant.boldItalic: 0x1D74F,
      },
      0x2207: <TexMathFontVariant, int>{
        TexMathFontVariant.bold: 0x1D6C1,
        TexMathFontVariant.italic: 0x1D6FB,
        TexMathFontVariant.boldItalic: 0x1D735,
      },
    };
