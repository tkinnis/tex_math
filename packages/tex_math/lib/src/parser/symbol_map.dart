import 'package:meta/meta.dart';

import '../ast.dart';

/// Metadata describing a TeX math or text symbol command.
@immutable
final class TexSymbolSpec {
  /// Creates a symbol specification.
  const TexSymbolSpec(
    this.unicode, {
    this.atomClass = TexMathAtomClass.ord,
    this.fontVariant,
    this.hasLimits = false,
    this.isLarge = false,
    this.isStretchy = false,
    this.isOperator = false,
    this.isDelimiter = false,
    this.isAccent = false,
    this.isWideAccent = false,
    this.isUnderAccent = false,
  });

  /// Canonical Unicode character or string produced by this symbol.
  final String unicode;

  /// Default Appendix G atom classification.
  final TexMathAtomClass atomClass;

  /// Optional explicit math font variant (e.g. upright Greek).
  final TexMathFontVariant? fontVariant;

  /// Whether limits default to above/below in display style.
  final bool hasLimits;

  /// Whether this symbol is a large operator (`\sum`, `\int`, etc.).
  final bool isLarge;

  /// Whether this symbol stretches vertically or horizontally.
  final bool isStretchy;

  /// Whether this symbol emits an [OperatorNode] rather than a [SymbolNode].
  final bool isOperator;

  /// Whether this symbol can follow `\left`, `\right`, `\middle`, or `\big`.
  final bool isDelimiter;

  /// Whether this command is a combining/stacked accent.
  final bool isAccent;

  /// Whether this command is a wide stretching accent (`\widehat`).
  final bool isWideAccent;

  /// Whether this accent attaches underneath its base.
  final bool isUnderAccent;
}

/// Core TeX `base` package symbol definitions keyed by control sequence name
/// (without leading `\`).
const Map<String, TexSymbolSpec> baseSymbolMap = <String, TexSymbolSpec>{
  // Lowercase Greek (italic by default in math mode).
  'alpha': TexSymbolSpec('\u03B1', fontVariant: TexMathFontVariant.italic),
  'beta': TexSymbolSpec('\u03B2', fontVariant: TexMathFontVariant.italic),
  'gamma': TexSymbolSpec('\u03B3', fontVariant: TexMathFontVariant.italic),
  'delta': TexSymbolSpec('\u03B4', fontVariant: TexMathFontVariant.italic),
  'epsilon': TexSymbolSpec('\u03F5', fontVariant: TexMathFontVariant.italic),
  'zeta': TexSymbolSpec('\u03B6', fontVariant: TexMathFontVariant.italic),
  'eta': TexSymbolSpec('\u03B7', fontVariant: TexMathFontVariant.italic),
  'theta': TexSymbolSpec('\u03B8', fontVariant: TexMathFontVariant.italic),
  'iota': TexSymbolSpec('\u03B9', fontVariant: TexMathFontVariant.italic),
  'kappa': TexSymbolSpec('\u03BA', fontVariant: TexMathFontVariant.italic),
  'lambda': TexSymbolSpec('\u03BB', fontVariant: TexMathFontVariant.italic),
  'mu': TexSymbolSpec('\u03BC', fontVariant: TexMathFontVariant.italic),
  'nu': TexSymbolSpec('\u03BD', fontVariant: TexMathFontVariant.italic),
  'xi': TexSymbolSpec('\u03BE', fontVariant: TexMathFontVariant.italic),
  'omicron': TexSymbolSpec('\u03BF', fontVariant: TexMathFontVariant.italic),
  'pi': TexSymbolSpec('\u03C0', fontVariant: TexMathFontVariant.italic),
  'rho': TexSymbolSpec('\u03C1', fontVariant: TexMathFontVariant.italic),
  'sigma': TexSymbolSpec('\u03C3', fontVariant: TexMathFontVariant.italic),
  'tau': TexSymbolSpec('\u03C4', fontVariant: TexMathFontVariant.italic),
  'upsilon': TexSymbolSpec('\u03C5', fontVariant: TexMathFontVariant.italic),
  'phi': TexSymbolSpec('\u03D5', fontVariant: TexMathFontVariant.italic),
  'chi': TexSymbolSpec('\u03C7', fontVariant: TexMathFontVariant.italic),
  'psi': TexSymbolSpec('\u03C8', fontVariant: TexMathFontVariant.italic),
  'omega': TexSymbolSpec('\u03C9', fontVariant: TexMathFontVariant.italic),
  'varepsilon': TexSymbolSpec('\u03B5', fontVariant: TexMathFontVariant.italic),
  'vartheta': TexSymbolSpec('\u03D1', fontVariant: TexMathFontVariant.italic),
  'varpi': TexSymbolSpec('\u03D6', fontVariant: TexMathFontVariant.italic),
  'varrho': TexSymbolSpec('\u03F1', fontVariant: TexMathFontVariant.italic),
  'varsigma': TexSymbolSpec('\u03C2', fontVariant: TexMathFontVariant.italic),
  'varphi': TexSymbolSpec('\u03C6', fontVariant: TexMathFontVariant.italic),

  // Uppercase Greek (upright by default in TeX math mode).
  'Gamma': TexSymbolSpec('\u0393', fontVariant: TexMathFontVariant.normal),
  'Delta': TexSymbolSpec('\u0394', fontVariant: TexMathFontVariant.normal),
  'Theta': TexSymbolSpec('\u0398', fontVariant: TexMathFontVariant.normal),
  'Lambda': TexSymbolSpec('\u039B', fontVariant: TexMathFontVariant.normal),
  'Xi': TexSymbolSpec('\u039E', fontVariant: TexMathFontVariant.normal),
  'Pi': TexSymbolSpec('\u03A0', fontVariant: TexMathFontVariant.normal),
  'Sigma': TexSymbolSpec('\u03A3', fontVariant: TexMathFontVariant.normal),
  'Upsilon': TexSymbolSpec('\u03A5', fontVariant: TexMathFontVariant.normal),
  'Phi': TexSymbolSpec('\u03A6', fontVariant: TexMathFontVariant.normal),
  'Psi': TexSymbolSpec('\u03A8', fontVariant: TexMathFontVariant.normal),
  'Omega': TexSymbolSpec('\u03A9', fontVariant: TexMathFontVariant.normal),

  // Ordinary symbols (`mathchar0mi` / `mathchar7`).
  'AA': TexSymbolSpec('\u212B', fontVariant: TexMathFontVariant.normal),
  'S': TexSymbolSpec('\u00A7', fontVariant: TexMathFontVariant.normal),
  'P': TexSymbolSpec('\u00B6', fontVariant: TexMathFontVariant.normal),
  'aleph': TexSymbolSpec('\u2135', fontVariant: TexMathFontVariant.normal),
  'hbar': TexSymbolSpec('\u210F'),
  'imath': TexSymbolSpec('\u0131', fontVariant: TexMathFontVariant.italic),
  'jmath': TexSymbolSpec('\u0237', fontVariant: TexMathFontVariant.italic),
  'ell': TexSymbolSpec('\u2113'),
  'wp': TexSymbolSpec('\u2118', fontVariant: TexMathFontVariant.normal),
  'Re': TexSymbolSpec('\u211C', fontVariant: TexMathFontVariant.normal),
  'Im': TexSymbolSpec('\u2111', fontVariant: TexMathFontVariant.normal),
  'partial': TexSymbolSpec('\u2202', fontVariant: TexMathFontVariant.italic),
  'infty': TexSymbolSpec('\u221E', fontVariant: TexMathFontVariant.normal),
  'prime': TexSymbolSpec('\u2032'),
  'emptyset': TexSymbolSpec('\u2205', fontVariant: TexMathFontVariant.normal),
  'nabla': TexSymbolSpec('\u2207', fontVariant: TexMathFontVariant.normal),
  'top': TexSymbolSpec('\u22A4', fontVariant: TexMathFontVariant.normal),
  'bot': TexSymbolSpec('\u22A5', fontVariant: TexMathFontVariant.normal),
  'angle': TexSymbolSpec('\u2220', fontVariant: TexMathFontVariant.normal),
  'triangle': TexSymbolSpec('\u25B3', fontVariant: TexMathFontVariant.normal),
  'backslash': TexSymbolSpec(
    '\\',
    fontVariant: TexMathFontVariant.normal,
    isDelimiter: true,
    isStretchy: true,
  ),
  'forall': TexSymbolSpec('\u2200', fontVariant: TexMathFontVariant.normal),
  'exists': TexSymbolSpec('\u2203', fontVariant: TexMathFontVariant.normal),
  'neg': TexSymbolSpec('\u00AC', fontVariant: TexMathFontVariant.normal),
  'lnot': TexSymbolSpec('\u00AC', fontVariant: TexMathFontVariant.normal),
  'flat': TexSymbolSpec('\u266D', fontVariant: TexMathFontVariant.normal),
  'natural': TexSymbolSpec('\u266E', fontVariant: TexMathFontVariant.normal),
  'sharp': TexSymbolSpec('\u266F', fontVariant: TexMathFontVariant.normal),
  'clubsuit': TexSymbolSpec('\u2663', fontVariant: TexMathFontVariant.normal),
  'diamondsuit': TexSymbolSpec(
    '\u2662',
    fontVariant: TexMathFontVariant.normal,
  ),
  'heartsuit': TexSymbolSpec('\u2661', fontVariant: TexMathFontVariant.normal),
  'spadesuit': TexSymbolSpec('\u2660', fontVariant: TexMathFontVariant.normal),
  'surd': TexSymbolSpec('\u221A', isStretchy: true),
  '_': TexSymbolSpec('\u005F'),
  '#': TexSymbolSpec('\u0023'),
  r'$': TexSymbolSpec('\u0024'),
  '%': TexSymbolSpec('\u0025'),
  '&': TexSymbolSpec('\u0026'),
  'And': TexSymbolSpec('\u0026'),
  'notChar': TexSymbolSpec('\u29F8'),

  // Large operators.
  'coprod': TexSymbolSpec(
    '\u2210',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigvee': TexSymbolSpec(
    '\u22C1',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigwedge': TexSymbolSpec(
    '\u22C0',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'biguplus': TexSymbolSpec(
    '\u2A04',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigcap': TexSymbolSpec(
    '\u22C2',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigcup': TexSymbolSpec(
    '\u22C3',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'int': TexSymbolSpec(
    '\u222B',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'intop': TexSymbolSpec(
    '\u222B',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'iint': TexSymbolSpec(
    '\u222C',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'iiint': TexSymbolSpec(
    '\u222D',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'prod': TexSymbolSpec(
    '\u220F',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'sum': TexSymbolSpec(
    '\u2211',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigotimes': TexSymbolSpec(
    '\u2A02',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigoplus': TexSymbolSpec(
    '\u2A01',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'bigodot': TexSymbolSpec(
    '\u2A00',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'oint': TexSymbolSpec(
    '\u222E',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'ointop': TexSymbolSpec(
    '\u222E',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'oiint': TexSymbolSpec(
    '\u222F',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'oiiint': TexSymbolSpec(
    '\u2230',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'bigsqcup': TexSymbolSpec(
    '\u2A06',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
  'smallint': TexSymbolSpec(
    '\u222B',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),

  // Named functions and operators.
  'arcsin': TexSymbolSpec(
    'arcsin',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'arccos': TexSymbolSpec(
    'arccos',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'arctan': TexSymbolSpec(
    'arctan',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'arg': TexSymbolSpec('arg', atomClass: TexMathAtomClass.op, isOperator: true),
  'cos': TexSymbolSpec('cos', atomClass: TexMathAtomClass.op, isOperator: true),
  'cosh': TexSymbolSpec(
    'cosh',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'cot': TexSymbolSpec('cot', atomClass: TexMathAtomClass.op, isOperator: true),
  'coth': TexSymbolSpec(
    'coth',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'csc': TexSymbolSpec('csc', atomClass: TexMathAtomClass.op, isOperator: true),
  'deg': TexSymbolSpec('deg', atomClass: TexMathAtomClass.op, isOperator: true),
  'det': TexSymbolSpec(
    'det',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'dim': TexSymbolSpec('dim', atomClass: TexMathAtomClass.op, isOperator: true),
  'exp': TexSymbolSpec('exp', atomClass: TexMathAtomClass.op, isOperator: true),
  'gcd': TexSymbolSpec(
    'gcd',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'hom': TexSymbolSpec('hom', atomClass: TexMathAtomClass.op, isOperator: true),
  'inf': TexSymbolSpec(
    'inf',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'ker': TexSymbolSpec('ker', atomClass: TexMathAtomClass.op, isOperator: true),
  'lg': TexSymbolSpec('lg', atomClass: TexMathAtomClass.op, isOperator: true),
  'lim': TexSymbolSpec(
    'lim',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'liminf': TexSymbolSpec(
    'lim\u2006inf',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'limsup': TexSymbolSpec(
    'lim\u2006sup',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'ln': TexSymbolSpec('ln', atomClass: TexMathAtomClass.op, isOperator: true),
  'log': TexSymbolSpec('log', atomClass: TexMathAtomClass.op, isOperator: true),
  'max': TexSymbolSpec(
    'max',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'min': TexSymbolSpec(
    'min',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'Pr': TexSymbolSpec(
    'Pr',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'sec': TexSymbolSpec('sec', atomClass: TexMathAtomClass.op, isOperator: true),
  'sin': TexSymbolSpec('sin', atomClass: TexMathAtomClass.op, isOperator: true),
  'sinh': TexSymbolSpec(
    'sinh',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),
  'sup': TexSymbolSpec(
    'sup',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'tan': TexSymbolSpec('tan', atomClass: TexMathAtomClass.op, isOperator: true),
  'tanh': TexSymbolSpec(
    'tanh',
    atomClass: TexMathAtomClass.op,
    isOperator: true,
  ),

  // Binary operators.
  'bigtriangleup': TexSymbolSpec('\u25B3', atomClass: TexMathAtomClass.bin),
  'bigtriangledown': TexSymbolSpec('\u25BD', atomClass: TexMathAtomClass.bin),
  'wedge': TexSymbolSpec('\u2227', atomClass: TexMathAtomClass.bin),
  'land': TexSymbolSpec('\u2227', atomClass: TexMathAtomClass.bin),
  'vee': TexSymbolSpec('\u2228', atomClass: TexMathAtomClass.bin),
  'lor': TexSymbolSpec('\u2228', atomClass: TexMathAtomClass.bin),
  'cap': TexSymbolSpec('\u2229', atomClass: TexMathAtomClass.bin),
  'cup': TexSymbolSpec('\u222A', atomClass: TexMathAtomClass.bin),
  'ddagger': TexSymbolSpec('\u2021', atomClass: TexMathAtomClass.bin),
  'dagger': TexSymbolSpec('\u2020', atomClass: TexMathAtomClass.bin),
  'sqcap': TexSymbolSpec('\u2293', atomClass: TexMathAtomClass.bin),
  'sqcup': TexSymbolSpec('\u2294', atomClass: TexMathAtomClass.bin),
  'uplus': TexSymbolSpec('\u228E', atomClass: TexMathAtomClass.bin),
  'amalg': TexSymbolSpec('\u2A3F', atomClass: TexMathAtomClass.bin),
  'diamond': TexSymbolSpec('\u22C4', atomClass: TexMathAtomClass.bin),
  'bullet': TexSymbolSpec('\u2219', atomClass: TexMathAtomClass.bin),
  'wr': TexSymbolSpec('\u2240', atomClass: TexMathAtomClass.bin),
  'div': TexSymbolSpec('\u00F7', atomClass: TexMathAtomClass.bin),
  'odot': TexSymbolSpec('\u2299', atomClass: TexMathAtomClass.bin),
  'oslash': TexSymbolSpec('\u2298', atomClass: TexMathAtomClass.bin),
  'otimes': TexSymbolSpec('\u2297', atomClass: TexMathAtomClass.bin),
  'ominus': TexSymbolSpec('\u2296', atomClass: TexMathAtomClass.bin),
  'oplus': TexSymbolSpec('\u2295', atomClass: TexMathAtomClass.bin),
  'mp': TexSymbolSpec('\u2213', atomClass: TexMathAtomClass.bin),
  'pm': TexSymbolSpec('\u00B1', atomClass: TexMathAtomClass.bin),
  'circ': TexSymbolSpec('\u2218', atomClass: TexMathAtomClass.bin),
  'bigcirc': TexSymbolSpec('\u25EF', atomClass: TexMathAtomClass.bin),
  'setminus': TexSymbolSpec('\u2216', atomClass: TexMathAtomClass.bin),
  'cdot': TexSymbolSpec('\u22C5', atomClass: TexMathAtomClass.bin),
  'ast': TexSymbolSpec('\u2217', atomClass: TexMathAtomClass.bin),
  'times': TexSymbolSpec('\u00D7', atomClass: TexMathAtomClass.bin),
  'star': TexSymbolSpec('\u22C6', atomClass: TexMathAtomClass.bin),

  // Relations.
  'propto': TexSymbolSpec('\u221D', atomClass: TexMathAtomClass.rel),
  'sqsubseteq': TexSymbolSpec('\u2291', atomClass: TexMathAtomClass.rel),
  'sqsupseteq': TexSymbolSpec('\u2292', atomClass: TexMathAtomClass.rel),
  'parallel': TexSymbolSpec('\u2225', atomClass: TexMathAtomClass.rel),
  'mid': TexSymbolSpec('\u2223', atomClass: TexMathAtomClass.rel),
  'dashv': TexSymbolSpec('\u22A3', atomClass: TexMathAtomClass.rel),
  'vdash': TexSymbolSpec('\u22A2', atomClass: TexMathAtomClass.rel),
  'leq': TexSymbolSpec('\u2264', atomClass: TexMathAtomClass.rel),
  'le': TexSymbolSpec('\u2264', atomClass: TexMathAtomClass.rel),
  'geq': TexSymbolSpec('\u2265', atomClass: TexMathAtomClass.rel),
  'ge': TexSymbolSpec('\u2265', atomClass: TexMathAtomClass.rel),
  'lt': TexSymbolSpec('\u003C', atomClass: TexMathAtomClass.rel),
  'gt': TexSymbolSpec('\u003E', atomClass: TexMathAtomClass.rel),
  'succ': TexSymbolSpec('\u227B', atomClass: TexMathAtomClass.rel),
  'prec': TexSymbolSpec('\u227A', atomClass: TexMathAtomClass.rel),
  'approx': TexSymbolSpec('\u2248', atomClass: TexMathAtomClass.rel),
  'succeq': TexSymbolSpec('\u2AB0', atomClass: TexMathAtomClass.rel),
  'preceq': TexSymbolSpec('\u2AAF', atomClass: TexMathAtomClass.rel),
  'supset': TexSymbolSpec('\u2283', atomClass: TexMathAtomClass.rel),
  'subset': TexSymbolSpec('\u2282', atomClass: TexMathAtomClass.rel),
  'supseteq': TexSymbolSpec('\u2287', atomClass: TexMathAtomClass.rel),
  'subseteq': TexSymbolSpec('\u2286', atomClass: TexMathAtomClass.rel),
  'in': TexSymbolSpec('\u2208', atomClass: TexMathAtomClass.rel),
  'ni': TexSymbolSpec('\u220B', atomClass: TexMathAtomClass.rel),
  'notin': TexSymbolSpec('\u2209', atomClass: TexMathAtomClass.rel),
  'owns': TexSymbolSpec('\u220B', atomClass: TexMathAtomClass.rel),
  'gg': TexSymbolSpec('\u226B', atomClass: TexMathAtomClass.rel),
  'll': TexSymbolSpec('\u226A', atomClass: TexMathAtomClass.rel),
  'sim': TexSymbolSpec('\u223C', atomClass: TexMathAtomClass.rel),
  'simeq': TexSymbolSpec('\u2243', atomClass: TexMathAtomClass.rel),
  'perp': TexSymbolSpec('\u27C2', atomClass: TexMathAtomClass.rel),
  'equiv': TexSymbolSpec('\u2261', atomClass: TexMathAtomClass.rel),
  'asymp': TexSymbolSpec('\u224D', atomClass: TexMathAtomClass.rel),
  'smile': TexSymbolSpec('\u2323', atomClass: TexMathAtomClass.rel),
  'frown': TexSymbolSpec('\u2322', atomClass: TexMathAtomClass.rel),
  'ne': TexSymbolSpec('\u2260', atomClass: TexMathAtomClass.rel),
  'neq': TexSymbolSpec('\u2260', atomClass: TexMathAtomClass.rel),
  'cong': TexSymbolSpec('\u2245', atomClass: TexMathAtomClass.rel),
  'doteq': TexSymbolSpec('\u2250', atomClass: TexMathAtomClass.rel),
  'bowtie': TexSymbolSpec('\u22C8', atomClass: TexMathAtomClass.rel),
  'models': TexSymbolSpec('\u22A7', atomClass: TexMathAtomClass.rel),

  // Arrows.
  'Leftrightarrow': TexSymbolSpec('\u21D4', atomClass: TexMathAtomClass.rel),
  'Leftarrow': TexSymbolSpec('\u21D0', atomClass: TexMathAtomClass.rel),
  'Rightarrow': TexSymbolSpec('\u21D2', atomClass: TexMathAtomClass.rel),
  'leftrightarrow': TexSymbolSpec('\u2194', atomClass: TexMathAtomClass.rel),
  'leftarrow': TexSymbolSpec('\u2190', atomClass: TexMathAtomClass.rel),
  'gets': TexSymbolSpec('\u2190', atomClass: TexMathAtomClass.rel),
  'rightarrow': TexSymbolSpec('\u2192', atomClass: TexMathAtomClass.rel),
  'to': TexSymbolSpec('\u2192', atomClass: TexMathAtomClass.rel),
  'mapsto': TexSymbolSpec('\u21A6', atomClass: TexMathAtomClass.rel),
  'leftharpoonup': TexSymbolSpec('\u21BC', atomClass: TexMathAtomClass.rel),
  'leftharpoondown': TexSymbolSpec('\u21BD', atomClass: TexMathAtomClass.rel),
  'rightharpoonup': TexSymbolSpec('\u21C0', atomClass: TexMathAtomClass.rel),
  'rightharpoondown': TexSymbolSpec('\u21C1', atomClass: TexMathAtomClass.rel),
  'nearrow': TexSymbolSpec('\u2197', atomClass: TexMathAtomClass.rel),
  'searrow': TexSymbolSpec('\u2198', atomClass: TexMathAtomClass.rel),
  'nwarrow': TexSymbolSpec('\u2196', atomClass: TexMathAtomClass.rel),
  'swarrow': TexSymbolSpec('\u2199', atomClass: TexMathAtomClass.rel),
  'rightleftharpoons': TexSymbolSpec('\u21CC', atomClass: TexMathAtomClass.rel),
  'hookrightarrow': TexSymbolSpec('\u21AA', atomClass: TexMathAtomClass.rel),
  'hookleftarrow': TexSymbolSpec('\u21A9', atomClass: TexMathAtomClass.rel),
  'longleftarrow': TexSymbolSpec('\u27F5', atomClass: TexMathAtomClass.rel),
  'Longleftarrow': TexSymbolSpec('\u27F8', atomClass: TexMathAtomClass.rel),
  'longrightarrow': TexSymbolSpec('\u27F6', atomClass: TexMathAtomClass.rel),
  'Longrightarrow': TexSymbolSpec('\u27F9', atomClass: TexMathAtomClass.rel),
  'Longleftrightarrow': TexSymbolSpec(
    '\u27FA',
    atomClass: TexMathAtomClass.rel,
  ),
  'longleftrightarrow': TexSymbolSpec(
    '\u27F7',
    atomClass: TexMathAtomClass.rel,
  ),
  'longmapsto': TexSymbolSpec('\u27FC', atomClass: TexMathAtomClass.rel),
  'iff': TexSymbolSpec('\u27FA', atomClass: TexMathAtomClass.rel),

  // Dots and punctuation.
  'ldots': TexSymbolSpec('\u2026', atomClass: TexMathAtomClass.ord),
  'cdots': TexSymbolSpec('\u22EF', atomClass: TexMathAtomClass.ord),
  'vdots': TexSymbolSpec('\u22EE', atomClass: TexMathAtomClass.ord),
  'ddots': TexSymbolSpec('\u22F1', atomClass: TexMathAtomClass.ord),
  'iddots': TexSymbolSpec('\u22F0', atomClass: TexMathAtomClass.ord),
  'dotsc': TexSymbolSpec('\u2026', atomClass: TexMathAtomClass.ord),
  'dotsb': TexSymbolSpec('\u22EF', atomClass: TexMathAtomClass.ord),
  'dotsm': TexSymbolSpec('\u22EF', atomClass: TexMathAtomClass.ord),
  'dotsi': TexSymbolSpec('\u22EF', atomClass: TexMathAtomClass.ord),
  'dotso': TexSymbolSpec('\u2026', atomClass: TexMathAtomClass.ord),
  'dots': TexSymbolSpec('\u2026', atomClass: TexMathAtomClass.ord),
  'ldotp': TexSymbolSpec('\u002E', atomClass: TexMathAtomClass.punct),
  'cdotp': TexSymbolSpec('\u22C5', atomClass: TexMathAtomClass.punct),
  'colon': TexSymbolSpec('\u003A', atomClass: TexMathAtomClass.punct),

  // Delimiters usable directly as commands or after `\left`/`\right`.
  'langle': TexSymbolSpec(
    '\u27E8',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rangle': TexSymbolSpec(
    '\u27E9',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lbrace': TexSymbolSpec(
    '{',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rbrace': TexSymbolSpec(
    '}',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  '{': TexSymbolSpec(
    '{',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  '}': TexSymbolSpec(
    '}',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lbrack': TexSymbolSpec(
    '[',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rbrack': TexSymbolSpec(
    ']',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lfloor': TexSymbolSpec(
    '\u230A',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rfloor': TexSymbolSpec(
    '\u230B',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lceil': TexSymbolSpec(
    '\u2308',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rceil': TexSymbolSpec(
    '\u2309',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'vert': TexSymbolSpec(
    '|',
    atomClass: TexMathAtomClass.ord,
    isDelimiter: true,
    isStretchy: true,
  ),
  'Vert': TexSymbolSpec(
    '\u2016',
    atomClass: TexMathAtomClass.ord,
    isDelimiter: true,
    isStretchy: true,
  ),
  '|': TexSymbolSpec(
    '\u2016',
    atomClass: TexMathAtomClass.ord,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lvert': TexSymbolSpec(
    '|',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rvert': TexSymbolSpec(
    '|',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lVert': TexSymbolSpec(
    '\u2016',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rVert': TexSymbolSpec(
    '\u2016',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'uparrow': TexSymbolSpec(
    '\u2191',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'downarrow': TexSymbolSpec(
    '\u2193',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'updownarrow': TexSymbolSpec(
    '\u2195',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'Uparrow': TexSymbolSpec(
    '\u21D1',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'Downarrow': TexSymbolSpec(
    '\u21D3',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'Updownarrow': TexSymbolSpec(
    '\u21D5',
    atomClass: TexMathAtomClass.rel,
    isDelimiter: true,
    isStretchy: true,
  ),
  'lmoustache': TexSymbolSpec('\u23B0', isDelimiter: true, isStretchy: true),
  'rmoustache': TexSymbolSpec('\u23B1', isDelimiter: true, isStretchy: true),
  'lgroup': TexSymbolSpec('\u27EE', isDelimiter: true, isStretchy: true),
  'rgroup': TexSymbolSpec('\u27EF', isDelimiter: true, isStretchy: true),
  'arrowvert': TexSymbolSpec('\u23D0', isDelimiter: true, isStretchy: true),
  'Arrowvert': TexSymbolSpec('\u2016', isDelimiter: true, isStretchy: true),
  'bracevert': TexSymbolSpec('\u23AA', isDelimiter: true, isStretchy: true),
};

/// `ams` package symbol extensions.
const Map<String, TexSymbolSpec> amsSymbolMap = <String, TexSymbolSpec>{
  'iiiint': TexSymbolSpec(
    '\u2A0C',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'idotsint': TexSymbolSpec(
    '\u222B\u22EF\u222B',
    atomClass: TexMathAtomClass.op,
    isLarge: true,
    isOperator: true,
  ),
  'injlim': TexSymbolSpec(
    'inj\u2006lim',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'projlim': TexSymbolSpec(
    'proj\u2006lim',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isOperator: true,
  ),
  'implies': TexSymbolSpec('\u27F9', atomClass: TexMathAtomClass.rel),
  'impliedby': TexSymbolSpec('\u27F8', atomClass: TexMathAtomClass.rel),
  'digamma': TexSymbolSpec('\u03DD'),
  'varkappa': TexSymbolSpec('\u03F0'),
  'beth': TexSymbolSpec('\u2136', fontVariant: TexMathFontVariant.normal),
  'gimel': TexSymbolSpec('\u2137', fontVariant: TexMathFontVariant.normal),
  'daleth': TexSymbolSpec('\u2138', fontVariant: TexMathFontVariant.normal),
  'backprime': TexSymbolSpec('\u2035'),
  'hslash': TexSymbolSpec('\u210F'),
  'varnothing': TexSymbolSpec('\u2205'),
  'blacktriangle': TexSymbolSpec('\u25B4'),
  'triangledown': TexSymbolSpec('\u25BD'),
  'blacktriangledown': TexSymbolSpec('\u25BE'),
  'square': TexSymbolSpec('\u25A1'),
  'Box': TexSymbolSpec('\u25A1'),
  'blacksquare': TexSymbolSpec('\u25A0'),
  'lozenge': TexSymbolSpec('\u25CA'),
  'Diamond': TexSymbolSpec('\u25CA'),
  'blacklozenge': TexSymbolSpec('\u29EB'),
  'circledS': TexSymbolSpec('\u24C8'),
  'bigstar': TexSymbolSpec('\u2605'),
  'sphericalangle': TexSymbolSpec('\u2222'),
  'measuredangle': TexSymbolSpec('\u2221'),
  'nexists': TexSymbolSpec('\u2204'),
  'complement': TexSymbolSpec('\u2201'),
  'mho': TexSymbolSpec('\u2127'),
  'eth': TexSymbolSpec('\u00F0'),
  'Finv': TexSymbolSpec('\u2132'),
  'diagup': TexSymbolSpec('\u2571'),
  'Game': TexSymbolSpec('\u2141'),
  'diagdown': TexSymbolSpec('\u2572'),
  'Bbbk': TexSymbolSpec('\u006B', fontVariant: TexMathFontVariant.doubleStruck),
  'yen': TexSymbolSpec('\u00A5'),
  'circledR': TexSymbolSpec('\u00AE'),
  'checkmark': TexSymbolSpec('\u2713'),
  'maltese': TexSymbolSpec('\u2720'),

  // Binary operators.
  'dotplus': TexSymbolSpec('\u2214', atomClass: TexMathAtomClass.bin),
  'ltimes': TexSymbolSpec('\u22C9', atomClass: TexMathAtomClass.bin),
  'smallsetminus': TexSymbolSpec('\u2216', atomClass: TexMathAtomClass.bin),
  'rtimes': TexSymbolSpec('\u22CA', atomClass: TexMathAtomClass.bin),
  'Cap': TexSymbolSpec('\u22D2', atomClass: TexMathAtomClass.bin),
  'doublecap': TexSymbolSpec('\u22D2', atomClass: TexMathAtomClass.bin),
  'leftthreetimes': TexSymbolSpec('\u22CB', atomClass: TexMathAtomClass.bin),
  'Cup': TexSymbolSpec('\u22D3', atomClass: TexMathAtomClass.bin),
  'doublecup': TexSymbolSpec('\u22D3', atomClass: TexMathAtomClass.bin),
  'rightthreetimes': TexSymbolSpec('\u22CC', atomClass: TexMathAtomClass.bin),
  'barwedge': TexSymbolSpec('\u22BC', atomClass: TexMathAtomClass.bin),
  'curlywedge': TexSymbolSpec('\u22CF', atomClass: TexMathAtomClass.bin),
  'veebar': TexSymbolSpec('\u22BB', atomClass: TexMathAtomClass.bin),
  'curlyvee': TexSymbolSpec('\u22CE', atomClass: TexMathAtomClass.bin),
  'doublebarwedge': TexSymbolSpec('\u2A5E', atomClass: TexMathAtomClass.bin),
  'boxminus': TexSymbolSpec('\u229F', atomClass: TexMathAtomClass.bin),
  'circleddash': TexSymbolSpec('\u229D', atomClass: TexMathAtomClass.bin),
  'boxtimes': TexSymbolSpec('\u22A0', atomClass: TexMathAtomClass.bin),
  'circledast': TexSymbolSpec('\u229B', atomClass: TexMathAtomClass.bin),
  'boxdot': TexSymbolSpec('\u22A1', atomClass: TexMathAtomClass.bin),
  'circledcirc': TexSymbolSpec('\u229A', atomClass: TexMathAtomClass.bin),
  'boxplus': TexSymbolSpec('\u229E', atomClass: TexMathAtomClass.bin),
  'centerdot': TexSymbolSpec('\u22C5', atomClass: TexMathAtomClass.bin),
  'divideontimes': TexSymbolSpec('\u22C7', atomClass: TexMathAtomClass.bin),
  'intercal': TexSymbolSpec('\u22BA', atomClass: TexMathAtomClass.bin),

  // Relations.
  'leqq': TexSymbolSpec('\u2266', atomClass: TexMathAtomClass.rel),
  'geqq': TexSymbolSpec('\u2267', atomClass: TexMathAtomClass.rel),
  'leqslant': TexSymbolSpec('\u2A7D', atomClass: TexMathAtomClass.rel),
  'geqslant': TexSymbolSpec('\u2A7E', atomClass: TexMathAtomClass.rel),
  'eqslantless': TexSymbolSpec('\u2A95', atomClass: TexMathAtomClass.rel),
  'eqslantgtr': TexSymbolSpec('\u2A96', atomClass: TexMathAtomClass.rel),
  'lesssim': TexSymbolSpec('\u2272', atomClass: TexMathAtomClass.rel),
  'gtrsim': TexSymbolSpec('\u2273', atomClass: TexMathAtomClass.rel),
  'lessapprox': TexSymbolSpec('\u2A85', atomClass: TexMathAtomClass.rel),
  'gtrapprox': TexSymbolSpec('\u2A86', atomClass: TexMathAtomClass.rel),
  'approxeq': TexSymbolSpec('\u224A', atomClass: TexMathAtomClass.rel),
  'lessdot': TexSymbolSpec('\u22D6', atomClass: TexMathAtomClass.rel),
  'gtrdot': TexSymbolSpec('\u22D7', atomClass: TexMathAtomClass.rel),
  'lll': TexSymbolSpec('\u22D8', atomClass: TexMathAtomClass.rel),
  'llless': TexSymbolSpec('\u22D8', atomClass: TexMathAtomClass.rel),
  'ggg': TexSymbolSpec('\u22D9', atomClass: TexMathAtomClass.rel),
  'gggtr': TexSymbolSpec('\u22D9', atomClass: TexMathAtomClass.rel),
  'lessgtr': TexSymbolSpec('\u2276', atomClass: TexMathAtomClass.rel),
  'gtrless': TexSymbolSpec('\u2277', atomClass: TexMathAtomClass.rel),
  'lesseqgtr': TexSymbolSpec('\u22DA', atomClass: TexMathAtomClass.rel),
  'gtreqless': TexSymbolSpec('\u22DB', atomClass: TexMathAtomClass.rel),
  'lesseqqgtr': TexSymbolSpec('\u2A8B', atomClass: TexMathAtomClass.rel),
  'gtreqqless': TexSymbolSpec('\u2A8C', atomClass: TexMathAtomClass.rel),
  'doteqdot': TexSymbolSpec('\u2251', atomClass: TexMathAtomClass.rel),
  'Doteq': TexSymbolSpec('\u2251', atomClass: TexMathAtomClass.rel),
  'eqcirc': TexSymbolSpec('\u2256', atomClass: TexMathAtomClass.rel),
  'risingdotseq': TexSymbolSpec('\u2253', atomClass: TexMathAtomClass.rel),
  'circeq': TexSymbolSpec('\u2257', atomClass: TexMathAtomClass.rel),
  'fallingdotseq': TexSymbolSpec('\u2252', atomClass: TexMathAtomClass.rel),
  'triangleq': TexSymbolSpec('\u225C', atomClass: TexMathAtomClass.rel),
  'backsim': TexSymbolSpec('\u223D', atomClass: TexMathAtomClass.rel),
  'thicksim': TexSymbolSpec('\u223C', atomClass: TexMathAtomClass.rel),
  'backsimeq': TexSymbolSpec('\u22CD', atomClass: TexMathAtomClass.rel),
  'thickapprox': TexSymbolSpec('\u2248', atomClass: TexMathAtomClass.rel),
  'subseteqq': TexSymbolSpec('\u2AC5', atomClass: TexMathAtomClass.rel),
  'supseteqq': TexSymbolSpec('\u2AC6', atomClass: TexMathAtomClass.rel),
  'Subset': TexSymbolSpec('\u22D0', atomClass: TexMathAtomClass.rel),
  'Supset': TexSymbolSpec('\u22D1', atomClass: TexMathAtomClass.rel),
  'sqsubset': TexSymbolSpec('\u228F', atomClass: TexMathAtomClass.rel),
  'sqsupset': TexSymbolSpec('\u2290', atomClass: TexMathAtomClass.rel),
  'preccurlyeq': TexSymbolSpec('\u227C', atomClass: TexMathAtomClass.rel),
  'succcurlyeq': TexSymbolSpec('\u227D', atomClass: TexMathAtomClass.rel),
  'curlyeqprec': TexSymbolSpec('\u22DE', atomClass: TexMathAtomClass.rel),
  'curlyeqsucc': TexSymbolSpec('\u22DF', atomClass: TexMathAtomClass.rel),
  'precsim': TexSymbolSpec('\u227E', atomClass: TexMathAtomClass.rel),
  'succsim': TexSymbolSpec('\u227F', atomClass: TexMathAtomClass.rel),
  'precapprox': TexSymbolSpec('\u2AB7', atomClass: TexMathAtomClass.rel),
  'succapprox': TexSymbolSpec('\u2AB8', atomClass: TexMathAtomClass.rel),
  'vartriangleleft': TexSymbolSpec('\u22B2', atomClass: TexMathAtomClass.rel),
  'lhd': TexSymbolSpec('\u22B2', atomClass: TexMathAtomClass.bin),
  'vartriangleright': TexSymbolSpec('\u22B3', atomClass: TexMathAtomClass.rel),
  'rhd': TexSymbolSpec('\u22B3', atomClass: TexMathAtomClass.bin),
  'trianglelefteq': TexSymbolSpec('\u22B4', atomClass: TexMathAtomClass.rel),
  'unlhd': TexSymbolSpec('\u22B4', atomClass: TexMathAtomClass.bin),
  'trianglerighteq': TexSymbolSpec('\u22B5', atomClass: TexMathAtomClass.rel),
  'unrhd': TexSymbolSpec('\u22B5', atomClass: TexMathAtomClass.bin),
  'vDash': TexSymbolSpec('\u22A8', atomClass: TexMathAtomClass.rel),
  'Vdash': TexSymbolSpec('\u22A9', atomClass: TexMathAtomClass.rel),
  'Vvdash': TexSymbolSpec('\u22AA', atomClass: TexMathAtomClass.rel),
  'smallsmile': TexSymbolSpec('\u2323', atomClass: TexMathAtomClass.rel),
  'shortmid': TexSymbolSpec('\u2223', atomClass: TexMathAtomClass.rel),
  'smallfrown': TexSymbolSpec('\u2322', atomClass: TexMathAtomClass.rel),
  'shortparallel': TexSymbolSpec('\u2225', atomClass: TexMathAtomClass.rel),
  'bumpeq': TexSymbolSpec('\u224F', atomClass: TexMathAtomClass.rel),
  'between': TexSymbolSpec('\u226C', atomClass: TexMathAtomClass.rel),
  'Bumpeq': TexSymbolSpec('\u224E', atomClass: TexMathAtomClass.rel),
  'pitchfork': TexSymbolSpec('\u22D4', atomClass: TexMathAtomClass.rel),
  'varpropto': TexSymbolSpec('\u221D', atomClass: TexMathAtomClass.rel),
  'backepsilon': TexSymbolSpec('\u220D', atomClass: TexMathAtomClass.rel),
  'blacktriangleleft': TexSymbolSpec('\u25C2', atomClass: TexMathAtomClass.rel),
  'blacktriangleright': TexSymbolSpec(
    '\u25B8',
    atomClass: TexMathAtomClass.rel,
  ),
  'therefore': TexSymbolSpec('\u2234', atomClass: TexMathAtomClass.rel),
  'because': TexSymbolSpec('\u2235', atomClass: TexMathAtomClass.rel),
  'eqsim': TexSymbolSpec('\u2242', atomClass: TexMathAtomClass.rel),
  'vartriangle': TexSymbolSpec('\u25B3', atomClass: TexMathAtomClass.rel),
  'Join': TexSymbolSpec('\u22C8', atomClass: TexMathAtomClass.rel),
  'nless': TexSymbolSpec('\u226E', atomClass: TexMathAtomClass.rel),
  'ngtr': TexSymbolSpec('\u226F', atomClass: TexMathAtomClass.rel),
  'nleq': TexSymbolSpec('\u2270', atomClass: TexMathAtomClass.rel),
  'ngeq': TexSymbolSpec('\u2271', atomClass: TexMathAtomClass.rel),
  'nleqslant': TexSymbolSpec('\u2A87', atomClass: TexMathAtomClass.rel),
  'ngeqslant': TexSymbolSpec('\u2A88', atomClass: TexMathAtomClass.rel),
  'nleqq': TexSymbolSpec('\u2270', atomClass: TexMathAtomClass.rel),
  'ngeqq': TexSymbolSpec('\u2271', atomClass: TexMathAtomClass.rel),
  'lneq': TexSymbolSpec('\u2A87', atomClass: TexMathAtomClass.rel),
  'gneq': TexSymbolSpec('\u2A88', atomClass: TexMathAtomClass.rel),
  'lneqq': TexSymbolSpec('\u2268', atomClass: TexMathAtomClass.rel),
  'gneqq': TexSymbolSpec('\u2269', atomClass: TexMathAtomClass.rel),
  'lvertneqq': TexSymbolSpec('\u2268', atomClass: TexMathAtomClass.rel),
  'gvertneqq': TexSymbolSpec('\u2269', atomClass: TexMathAtomClass.rel),
  'lnsim': TexSymbolSpec('\u22E6', atomClass: TexMathAtomClass.rel),
  'gnsim': TexSymbolSpec('\u22E7', atomClass: TexMathAtomClass.rel),
  'lnapprox': TexSymbolSpec('\u2A89', atomClass: TexMathAtomClass.rel),
  'gnapprox': TexSymbolSpec('\u2A8A', atomClass: TexMathAtomClass.rel),
  'nprec': TexSymbolSpec('\u2280', atomClass: TexMathAtomClass.rel),
  'nsucc': TexSymbolSpec('\u2281', atomClass: TexMathAtomClass.rel),
  'npreceq': TexSymbolSpec('\u22E0', atomClass: TexMathAtomClass.rel),
  'nsucceq': TexSymbolSpec('\u22E1', atomClass: TexMathAtomClass.rel),
  'precneqq': TexSymbolSpec('\u2AB5', atomClass: TexMathAtomClass.rel),
  'succneqq': TexSymbolSpec('\u2AB6', atomClass: TexMathAtomClass.rel),
  'precnsim': TexSymbolSpec('\u22E8', atomClass: TexMathAtomClass.rel),
  'succnsim': TexSymbolSpec('\u22E9', atomClass: TexMathAtomClass.rel),
  'precnapprox': TexSymbolSpec('\u2AB9', atomClass: TexMathAtomClass.rel),
  'succnapprox': TexSymbolSpec('\u2ABA', atomClass: TexMathAtomClass.rel),
  'nsim': TexSymbolSpec('\u2241', atomClass: TexMathAtomClass.rel),
  'ncong': TexSymbolSpec('\u2247', atomClass: TexMathAtomClass.rel),
  'nshortmid': TexSymbolSpec('\u2224', atomClass: TexMathAtomClass.rel),
  'nshortparallel': TexSymbolSpec('\u2226', atomClass: TexMathAtomClass.rel),
  'nmid': TexSymbolSpec('\u2224', atomClass: TexMathAtomClass.rel),
  'nparallel': TexSymbolSpec('\u2226', atomClass: TexMathAtomClass.rel),
  'nvdash': TexSymbolSpec('\u22AC', atomClass: TexMathAtomClass.rel),
  'nvDash': TexSymbolSpec('\u22AD', atomClass: TexMathAtomClass.rel),
  'nVdash': TexSymbolSpec('\u22AE', atomClass: TexMathAtomClass.rel),
  'nVDash': TexSymbolSpec('\u22AF', atomClass: TexMathAtomClass.rel),
  'ntriangleleft': TexSymbolSpec('\u22EA', atomClass: TexMathAtomClass.rel),
  'ntriangleright': TexSymbolSpec('\u22EB', atomClass: TexMathAtomClass.rel),
  'ntrianglelefteq': TexSymbolSpec('\u22EC', atomClass: TexMathAtomClass.rel),
  'ntrianglerighteq': TexSymbolSpec('\u22ED', atomClass: TexMathAtomClass.rel),
  'nsubseteq': TexSymbolSpec('\u2288', atomClass: TexMathAtomClass.rel),
  'nsupseteq': TexSymbolSpec('\u2289', atomClass: TexMathAtomClass.rel),
  'nsubseteqq': TexSymbolSpec('\u2288', atomClass: TexMathAtomClass.rel),
  'nsupseteqq': TexSymbolSpec('\u2289', atomClass: TexMathAtomClass.rel),
  'subsetneq': TexSymbolSpec('\u228A', atomClass: TexMathAtomClass.rel),
  'supsetneq': TexSymbolSpec('\u228B', atomClass: TexMathAtomClass.rel),
  'varsubsetneq': TexSymbolSpec('\u228A', atomClass: TexMathAtomClass.rel),
  'varsupsetneq': TexSymbolSpec('\u228B', atomClass: TexMathAtomClass.rel),
  'subsetneqq': TexSymbolSpec('\u2ACB', atomClass: TexMathAtomClass.rel),
  'supsetneqq': TexSymbolSpec('\u2ACC', atomClass: TexMathAtomClass.rel),
  'varsubsetneqq': TexSymbolSpec('\u2ACB', atomClass: TexMathAtomClass.rel),
  'varsupsetneqq': TexSymbolSpec('\u2ACC', atomClass: TexMathAtomClass.rel),

  // AMS arrows.
  'leftleftarrows': TexSymbolSpec('\u21C7', atomClass: TexMathAtomClass.rel),
  'rightrightarrows': TexSymbolSpec('\u21C9', atomClass: TexMathAtomClass.rel),
  'leftrightarrows': TexSymbolSpec('\u21C6', atomClass: TexMathAtomClass.rel),
  'rightleftarrows': TexSymbolSpec('\u21C4', atomClass: TexMathAtomClass.rel),
  'Lleftarrow': TexSymbolSpec('\u21DA', atomClass: TexMathAtomClass.rel),
  'Rrightarrow': TexSymbolSpec('\u21DB', atomClass: TexMathAtomClass.rel),
  'twoheadleftarrow': TexSymbolSpec('\u219E', atomClass: TexMathAtomClass.rel),
  'twoheadrightarrow': TexSymbolSpec('\u21A0', atomClass: TexMathAtomClass.rel),
  'leftarrowtail': TexSymbolSpec('\u21A2', atomClass: TexMathAtomClass.rel),
  'rightarrowtail': TexSymbolSpec('\u21A3', atomClass: TexMathAtomClass.rel),
  'looparrowleft': TexSymbolSpec('\u21AB', atomClass: TexMathAtomClass.rel),
  'looparrowright': TexSymbolSpec('\u21AC', atomClass: TexMathAtomClass.rel),
  'leftrightharpoons': TexSymbolSpec('\u21CB', atomClass: TexMathAtomClass.rel),
  'curvearrowleft': TexSymbolSpec('\u21B6', atomClass: TexMathAtomClass.rel),
  'curvearrowright': TexSymbolSpec('\u21B7', atomClass: TexMathAtomClass.rel),
  'circlearrowleft': TexSymbolSpec('\u21BA', atomClass: TexMathAtomClass.rel),
  'circlearrowright': TexSymbolSpec('\u21BB', atomClass: TexMathAtomClass.rel),
  'Lsh': TexSymbolSpec('\u21B0', atomClass: TexMathAtomClass.rel),
  'Rsh': TexSymbolSpec('\u21B1', atomClass: TexMathAtomClass.rel),
  'upuparrows': TexSymbolSpec('\u21C8', atomClass: TexMathAtomClass.rel),
  'downdownarrows': TexSymbolSpec('\u21CA', atomClass: TexMathAtomClass.rel),
  'upharpoonleft': TexSymbolSpec('\u21BF', atomClass: TexMathAtomClass.rel),
  'upharpoonright': TexSymbolSpec('\u21BE', atomClass: TexMathAtomClass.rel),
  'downharpoonleft': TexSymbolSpec('\u21C3', atomClass: TexMathAtomClass.rel),
  'restriction': TexSymbolSpec('\u21BE', atomClass: TexMathAtomClass.rel),
  'multimap': TexSymbolSpec('\u22B8', atomClass: TexMathAtomClass.rel),
  'downharpoonright': TexSymbolSpec('\u21C2', atomClass: TexMathAtomClass.rel),
  'leftrightsquigarrow': TexSymbolSpec(
    '\u21AD',
    atomClass: TexMathAtomClass.rel,
  ),
  'rightsquigarrow': TexSymbolSpec('\u21DD', atomClass: TexMathAtomClass.rel),
  'leadsto': TexSymbolSpec('\u21DD', atomClass: TexMathAtomClass.rel),
  'dashrightarrow': TexSymbolSpec('\u21E2', atomClass: TexMathAtomClass.rel),
  'dashleftarrow': TexSymbolSpec('\u21E0', atomClass: TexMathAtomClass.rel),
  'nleftarrow': TexSymbolSpec('\u219A', atomClass: TexMathAtomClass.rel),
  'nrightarrow': TexSymbolSpec('\u219B', atomClass: TexMathAtomClass.rel),
  'nLeftarrow': TexSymbolSpec('\u21CD', atomClass: TexMathAtomClass.rel),
  'nRightarrow': TexSymbolSpec('\u21CF', atomClass: TexMathAtomClass.rel),
  'nleftrightarrow': TexSymbolSpec('\u21AE', atomClass: TexMathAtomClass.rel),
  'nLeftrightarrow': TexSymbolSpec('\u21CE', atomClass: TexMathAtomClass.rel),

  // AMS corner delimiters.
  'ulcorner': TexSymbolSpec(
    '\u231C',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
  ),
  'urcorner': TexSymbolSpec(
    '\u231D',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
  ),
  'llcorner': TexSymbolSpec(
    '\u231E',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
  ),
  'lrcorner': TexSymbolSpec(
    '\u231F',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
  ),
};

/// `upgreek` upright Greek symbol map.
const Map<String, TexSymbolSpec> upgreekSymbolMap = <String, TexSymbolSpec>{
  'upalpha': TexSymbolSpec('\u03B1', fontVariant: TexMathFontVariant.normal),
  'upbeta': TexSymbolSpec('\u03B2', fontVariant: TexMathFontVariant.normal),
  'upgamma': TexSymbolSpec('\u03B3', fontVariant: TexMathFontVariant.normal),
  'updelta': TexSymbolSpec('\u03B4', fontVariant: TexMathFontVariant.normal),
  'upepsilon': TexSymbolSpec('\u03F5', fontVariant: TexMathFontVariant.normal),
  'upzeta': TexSymbolSpec('\u03B6', fontVariant: TexMathFontVariant.normal),
  'upeta': TexSymbolSpec('\u03B7', fontVariant: TexMathFontVariant.normal),
  'uptheta': TexSymbolSpec('\u03B8', fontVariant: TexMathFontVariant.normal),
  'upiota': TexSymbolSpec('\u03B9', fontVariant: TexMathFontVariant.normal),
  'upkappa': TexSymbolSpec('\u03BA', fontVariant: TexMathFontVariant.normal),
  'uplambda': TexSymbolSpec('\u03BB', fontVariant: TexMathFontVariant.normal),
  'upmu': TexSymbolSpec('\u03BC', fontVariant: TexMathFontVariant.normal),
  'upnu': TexSymbolSpec('\u03BD', fontVariant: TexMathFontVariant.normal),
  'upxi': TexSymbolSpec('\u03BE', fontVariant: TexMathFontVariant.normal),
  'upomicron': TexSymbolSpec('\u03BF', fontVariant: TexMathFontVariant.normal),
  'uppi': TexSymbolSpec('\u03C0', fontVariant: TexMathFontVariant.normal),
  'uprho': TexSymbolSpec('\u03C1', fontVariant: TexMathFontVariant.normal),
  'upsigma': TexSymbolSpec('\u03C3', fontVariant: TexMathFontVariant.normal),
  'uptau': TexSymbolSpec('\u03C4', fontVariant: TexMathFontVariant.normal),
  'upupsilon': TexSymbolSpec('\u03C5', fontVariant: TexMathFontVariant.normal),
  'upphi': TexSymbolSpec('\u03D5', fontVariant: TexMathFontVariant.normal),
  'upchi': TexSymbolSpec('\u03C7', fontVariant: TexMathFontVariant.normal),
  'uppsi': TexSymbolSpec('\u03C8', fontVariant: TexMathFontVariant.normal),
  'upomega': TexSymbolSpec('\u03C9', fontVariant: TexMathFontVariant.normal),
  'upvarepsilon': TexSymbolSpec(
    '\u03B5',
    fontVariant: TexMathFontVariant.normal,
  ),
  'upvartheta': TexSymbolSpec('\u03D1', fontVariant: TexMathFontVariant.normal),
  'upvarpi': TexSymbolSpec('\u03D6', fontVariant: TexMathFontVariant.normal),
  'upvarrho': TexSymbolSpec('\u03F1', fontVariant: TexMathFontVariant.normal),
  'upvarsigma': TexSymbolSpec('\u03C2', fontVariant: TexMathFontVariant.normal),
  'upvarphi': TexSymbolSpec('\u03C6', fontVariant: TexMathFontVariant.normal),
  'Upgamma': TexSymbolSpec('\u0393', fontVariant: TexMathFontVariant.normal),
  'Updelta': TexSymbolSpec('\u0394', fontVariant: TexMathFontVariant.normal),
  'Uptheta': TexSymbolSpec('\u0398', fontVariant: TexMathFontVariant.normal),
  'Uplambda': TexSymbolSpec('\u039B', fontVariant: TexMathFontVariant.normal),
  'Upxi': TexSymbolSpec('\u039E', fontVariant: TexMathFontVariant.normal),
  'Uppi': TexSymbolSpec('\u03A0', fontVariant: TexMathFontVariant.normal),
  'Upsigma': TexSymbolSpec('\u03A3', fontVariant: TexMathFontVariant.normal),
  'Upupsilon': TexSymbolSpec('\u03A5', fontVariant: TexMathFontVariant.normal),
  'Upphi': TexSymbolSpec('\u03A6', fontVariant: TexMathFontVariant.normal),
  'Uppsi': TexSymbolSpec('\u03A8', fontVariant: TexMathFontVariant.normal),
  'Upomega': TexSymbolSpec('\u03A9', fontVariant: TexMathFontVariant.normal),
};

/// `gensymb` package symbols.
const Map<String, TexSymbolSpec> gensymbSymbolMap = <String, TexSymbolSpec>{
  'ohm': TexSymbolSpec('\u2126', fontVariant: TexMathFontVariant.normal),
  'degree': TexSymbolSpec('\u00B0', fontVariant: TexMathFontVariant.normal),
  'celsius': TexSymbolSpec('\u2103', fontVariant: TexMathFontVariant.normal),
  'perthousand': TexSymbolSpec(
    '\u2030',
    fontVariant: TexMathFontVariant.normal,
  ),
  'micro': TexSymbolSpec('\u00B5', fontVariant: TexMathFontVariant.normal),
};

/// `textcomp` package text/math symbol mappings.
const Map<String, TexSymbolSpec> textcompSymbolMap = <String, TexSymbolSpec>{
  'textasciicircum': TexSymbolSpec('\u005E'),
  'textasciitilde': TexSymbolSpec('\u007E'),
  'textasteriskcentered': TexSymbolSpec('\u002A'),
  'textbackslash': TexSymbolSpec('\u005C'),
  'textbar': TexSymbolSpec('\u007C'),
  'textbraceleft': TexSymbolSpec('\u007B'),
  'textbraceright': TexSymbolSpec('\u007D'),
  'textbullet': TexSymbolSpec('\u2022'),
  'textdagger': TexSymbolSpec('\u2020'),
  'textdaggerdbl': TexSymbolSpec('\u2021'),
  'textellipsis': TexSymbolSpec('\u2026'),
  'textemdash': TexSymbolSpec('\u2014'),
  'textendash': TexSymbolSpec('\u2013'),
  'textexclamdown': TexSymbolSpec('\u00A1'),
  'textgreater': TexSymbolSpec('\u003E'),
  'textless': TexSymbolSpec('\u003C'),
  'textordfeminine': TexSymbolSpec('\u00AA'),
  'textordmasculine': TexSymbolSpec('\u00BA'),
  'textparagraph': TexSymbolSpec('\u00B6'),
  'textperiodcentered': TexSymbolSpec('\u00B7'),
  'textquestiondown': TexSymbolSpec('\u00BF'),
  'textquotedblleft': TexSymbolSpec('\u201C'),
  'textquotedblright': TexSymbolSpec('\u201D'),
  'textquoteleft': TexSymbolSpec('\u2018'),
  'textquoteright': TexSymbolSpec('\u2019'),
  'textsection': TexSymbolSpec('\u00A7'),
  'textunderscore': TexSymbolSpec('\u005F'),
  'textvisiblespace': TexSymbolSpec('\u2423'),
  'textacutedbl': TexSymbolSpec('\u02DD'),
  'textasciiacute': TexSymbolSpec('\u00B4'),
  'textasciibreve': TexSymbolSpec('\u02D8'),
  'textasciicaron': TexSymbolSpec('\u02C7'),
  'textasciidieresis': TexSymbolSpec('\u00A8'),
  'textasciimacron': TexSymbolSpec('\u00AF'),
  'textgravedbl': TexSymbolSpec('\u02F5'),
  'texttildelow': TexSymbolSpec('\u02F7'),
  'textbaht': TexSymbolSpec('\u0E3F'),
  'textcent': TexSymbolSpec('\u00A2'),
  'textcolonmonetary': TexSymbolSpec('\u20A1'),
  'textcurrency': TexSymbolSpec('\u00A4'),
  'textdollar': TexSymbolSpec('\u0024'),
  'textdong': TexSymbolSpec('\u20AB'),
  'texteuro': TexSymbolSpec('\u20AC'),
  'textflorin': TexSymbolSpec('\u0192'),
  'textguarani': TexSymbolSpec('\u20B2'),
  'textlira': TexSymbolSpec('\u20A4'),
  'textnaira': TexSymbolSpec('\u20A6'),
  'textpeso': TexSymbolSpec('\u20B1'),
  'textsterling': TexSymbolSpec('\u00A3'),
  'textwon': TexSymbolSpec('\u20A9'),
  'textyen': TexSymbolSpec('\u00A5'),
  'textcircledP': TexSymbolSpec('\u2117'),
  'textcompwordmark': TexSymbolSpec('\u200C'),
  'textcopyleft': TexSymbolSpec('\u{1F12F}'),
  'textcopyright': TexSymbolSpec('\u00A9'),
  'textregistered': TexSymbolSpec('\u00AE'),
  'textservicemark': TexSymbolSpec('\u2120'),
  'texttrademark': TexSymbolSpec('\u2122'),
  'textbardbl': TexSymbolSpec('\u2016'),
  'textbigcircle': TexSymbolSpec('\u25EF'),
  'textblank': TexSymbolSpec('\u2422'),
  'textbrokenbar': TexSymbolSpec('\u00A6'),
  'textdiscount': TexSymbolSpec('\u2052'),
  'textestimated': TexSymbolSpec('\u212E'),
  'textinterrobang': TexSymbolSpec('\u203D'),
  'textinterrobangdown': TexSymbolSpec('\u2E18'),
  'textmusicalnote': TexSymbolSpec('\u266A'),
  'textnumero': TexSymbolSpec('\u2116'),
  'textopenbullet': TexSymbolSpec('\u25E6'),
  'textpertenthousand': TexSymbolSpec('\u2031'),
  'textperthousand': TexSymbolSpec('\u2030'),
  'textrecipe': TexSymbolSpec('\u211E'),
  'textreferencemark': TexSymbolSpec('\u203B'),
  'textlangle': TexSymbolSpec('\u2329'),
  'textrangle': TexSymbolSpec('\u232A'),
  'textlbrackdbl': TexSymbolSpec('\u27E6'),
  'textrbrackdbl': TexSymbolSpec('\u27E7'),
  'textlquill': TexSymbolSpec('\u2045'),
  'textrquill': TexSymbolSpec('\u2046'),
  'textcelsius': TexSymbolSpec('\u2103'),
  'textdegree': TexSymbolSpec('\u00B0'),
  'textdiv': TexSymbolSpec('\u00F7'),
  'textdownarrow': TexSymbolSpec('\u2193'),
  'textfractionsolidus': TexSymbolSpec('\u2044'),
  'textleftarrow': TexSymbolSpec('\u2190'),
  'textlnot': TexSymbolSpec('\u00AC'),
  'textmho': TexSymbolSpec('\u2127'),
  'textminus': TexSymbolSpec('\u2212'),
  'textmu': TexSymbolSpec('\u00B5'),
  'textohm': TexSymbolSpec('\u2126'),
  'textonehalf': TexSymbolSpec('\u00BD'),
  'textonequarter': TexSymbolSpec('\u00BC'),
  'textonesuperior': TexSymbolSpec('\u00B9'),
  'textpm': TexSymbolSpec('\u00B1'),
  'textrightarrow': TexSymbolSpec('\u2192'),
  'textsurd': TexSymbolSpec('\u221A'),
  'textthreequarters': TexSymbolSpec('\u00BE'),
  'textthreesuperior': TexSymbolSpec('\u00B3'),
  'texttimes': TexSymbolSpec('\u00D7'),
  'texttwosuperior': TexSymbolSpec('\u00B2'),
  'textuparrow': TexSymbolSpec('\u2191'),
  'textborn': TexSymbolSpec('\u002A'),
  'textdied': TexSymbolSpec('\u2020'),
  'textdivorced': TexSymbolSpec('\u26AE'),
  'textmarried': TexSymbolSpec('\u26AD'),
};

/// `mathtools` relation/symbol mappings.
const Map<String, TexSymbolSpec> mathtoolsSymbolMap = <String, TexSymbolSpec>{
  'vcentcolon': TexSymbolSpec(':', atomClass: TexMathAtomClass.rel),
  'dblcolon': TexSymbolSpec('\u2237', atomClass: TexMathAtomClass.rel),
  'coloneqq': TexSymbolSpec('\u2254', atomClass: TexMathAtomClass.rel),
  'Coloneqq': TexSymbolSpec('::=', atomClass: TexMathAtomClass.rel),
  'coloneq': TexSymbolSpec('\u2254', atomClass: TexMathAtomClass.rel),
  'Coloneq': TexSymbolSpec('\u2A7A', atomClass: TexMathAtomClass.rel),
  'eqqcolon': TexSymbolSpec('\u2255', atomClass: TexMathAtomClass.rel),
  'Eqqcolon': TexSymbolSpec('=::', atomClass: TexMathAtomClass.rel),
  'eqcolon': TexSymbolSpec('\u2255', atomClass: TexMathAtomClass.rel),
  'Eqcolon': TexSymbolSpec('=::', atomClass: TexMathAtomClass.rel),
  'colonapprox': TexSymbolSpec(':\u2248', atomClass: TexMathAtomClass.rel),
  'Colonapprox': TexSymbolSpec('::\u2248', atomClass: TexMathAtomClass.rel),
  'colonsim': TexSymbolSpec(':\u223C', atomClass: TexMathAtomClass.rel),
  'Colonsim': TexSymbolSpec('::\u223C', atomClass: TexMathAtomClass.rel),
  'approxcolon': TexSymbolSpec('\u2248:', atomClass: TexMathAtomClass.rel),
  'Approxcolon': TexSymbolSpec('\u2248::', atomClass: TexMathAtomClass.rel),
  'simcolon': TexSymbolSpec('\u223C:', atomClass: TexMathAtomClass.rel),
  'Simcolon': TexSymbolSpec('\u223C::', atomClass: TexMathAtomClass.rel),
  'colondash': TexSymbolSpec(':-', atomClass: TexMathAtomClass.rel),
  'Colondash': TexSymbolSpec('::-', atomClass: TexMathAtomClass.rel),
  'dashcolon': TexSymbolSpec('\u2239', atomClass: TexMathAtomClass.rel),
  'Dashcolon': TexSymbolSpec('-::', atomClass: TexMathAtomClass.rel),
  'lparen': TexSymbolSpec(
    '(',
    atomClass: TexMathAtomClass.open,
    isDelimiter: true,
    isStretchy: true,
  ),
  'rparen': TexSymbolSpec(
    ')',
    atomClass: TexMathAtomClass.close,
    isDelimiter: true,
    isStretchy: true,
  ),
  'nuparrow': TexSymbolSpec('\u2191', atomClass: TexMathAtomClass.rel),
  'ndownarrow': TexSymbolSpec('\u2193', atomClass: TexMathAtomClass.rel),
  'bigtimes': TexSymbolSpec(
    '\u00D7',
    atomClass: TexMathAtomClass.op,
    hasLimits: true,
    isLarge: true,
    isOperator: true,
  ),
};

/// `bboldx` blackboard bold symbol mappings.
const Map<String, TexSymbolSpec> bboldxSymbolMap = <String, TexSymbolSpec>{
  'bbGamma': TexSymbolSpec(
    '\u0393',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbDelta': TexSymbolSpec(
    '\u2206',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbTheta': TexSymbolSpec(
    '\u0398',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbLambda': TexSymbolSpec(
    '\u039B',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbXi': TexSymbolSpec('\u039E', fontVariant: TexMathFontVariant.doubleStruck),
  'bbPi': TexSymbolSpec('\u03A0', fontVariant: TexMathFontVariant.doubleStruck),
  'bbSigma': TexSymbolSpec(
    '\u03A3',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbUpsilon': TexSymbolSpec(
    '\u03A5',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbPhi': TexSymbolSpec(
    '\u03A6',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbPsi': TexSymbolSpec(
    '\u03A8',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbOmega': TexSymbolSpec(
    '\u2126',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbalpha': TexSymbolSpec(
    '\u03B1',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbbeta': TexSymbolSpec(
    '\u03B2',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbgamma': TexSymbolSpec(
    '\u03B3',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbdelta': TexSymbolSpec(
    '\u03B4',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbepsilon': TexSymbolSpec(
    '\u03B5',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbzeta': TexSymbolSpec(
    '\u03B6',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbeta': TexSymbolSpec(
    '\u03B7',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbtheta': TexSymbolSpec(
    '\u03B8',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbiota': TexSymbolSpec(
    '\u03B9',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbkappa': TexSymbolSpec(
    '\u03BA',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bblambda': TexSymbolSpec(
    '\u03BB',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbmu': TexSymbolSpec('\u00B5', fontVariant: TexMathFontVariant.doubleStruck),
  'bbnu': TexSymbolSpec('\u03BD', fontVariant: TexMathFontVariant.doubleStruck),
  'bbxi': TexSymbolSpec('\u03BE', fontVariant: TexMathFontVariant.doubleStruck),
  'bbpi': TexSymbolSpec('\u03C0', fontVariant: TexMathFontVariant.doubleStruck),
  'bbrho': TexSymbolSpec(
    '\u03C1',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbsigma': TexSymbolSpec(
    '\u03C3',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbtau': TexSymbolSpec(
    '\u03C4',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbupsilon': TexSymbolSpec(
    '\u03C5',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbphi': TexSymbolSpec(
    '\u03C6',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbchi': TexSymbolSpec(
    '\u03C7',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbpsi': TexSymbolSpec(
    '\u03C8',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbomega': TexSymbolSpec(
    '\u03C9',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbdotlessi': TexSymbolSpec(
    '\u0131',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbdotlessj': TexSymbolSpec(
    '\u0237',
    fontVariant: TexMathFontVariant.doubleStruck,
  ),
  'bbLparen': TexSymbolSpec(
    '(',
    atomClass: TexMathAtomClass.open,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbRparen': TexSymbolSpec(
    ')',
    atomClass: TexMathAtomClass.close,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbLbrack': TexSymbolSpec(
    '[',
    atomClass: TexMathAtomClass.open,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbRbrack': TexSymbolSpec(
    ']',
    atomClass: TexMathAtomClass.close,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbLbrace': TexSymbolSpec(
    '{',
    atomClass: TexMathAtomClass.open,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbRbrace': TexSymbolSpec(
    '}',
    atomClass: TexMathAtomClass.close,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbLangle': TexSymbolSpec(
    '\u2329',
    atomClass: TexMathAtomClass.open,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bbRangle': TexSymbolSpec(
    '\u232A',
    atomClass: TexMathAtomClass.close,
    fontVariant: TexMathFontVariant.doubleStruck,
    isDelimiter: true,
  ),
  'bfbbGamma': TexSymbolSpec(
    '\u0393',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbDelta': TexSymbolSpec(
    '\u2206',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbTheta': TexSymbolSpec(
    '\u0398',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbLambda': TexSymbolSpec(
    '\u039B',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbXi': TexSymbolSpec(
    '\u039E',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbPi': TexSymbolSpec(
    '\u03A0',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbSigma': TexSymbolSpec(
    '\u03A3',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbUpsilon': TexSymbolSpec(
    '\u03A5',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbPhi': TexSymbolSpec(
    '\u03A6',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbPsi': TexSymbolSpec(
    '\u03A8',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbOmega': TexSymbolSpec(
    '\u2126',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbalpha': TexSymbolSpec(
    '\u03B1',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbbeta': TexSymbolSpec(
    '\u03B2',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbgamma': TexSymbolSpec(
    '\u03B3',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbdelta': TexSymbolSpec(
    '\u03B4',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbepsilon': TexSymbolSpec(
    '\u03B5',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbzeta': TexSymbolSpec(
    '\u03B6',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbeta': TexSymbolSpec(
    '\u03B7',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbtheta': TexSymbolSpec(
    '\u03B8',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbiota': TexSymbolSpec(
    '\u03B9',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbkappa': TexSymbolSpec(
    '\u03BA',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbblambda': TexSymbolSpec(
    '\u03BB',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbmu': TexSymbolSpec(
    '\u00B5',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbnu': TexSymbolSpec(
    '\u03BD',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbxi': TexSymbolSpec(
    '\u03BE',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbpi': TexSymbolSpec(
    '\u03C0',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbrho': TexSymbolSpec(
    '\u03C1',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbsigma': TexSymbolSpec(
    '\u03C3',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbtau': TexSymbolSpec(
    '\u03C4',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbupsilon': TexSymbolSpec(
    '\u03C5',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbphi': TexSymbolSpec(
    '\u03C6',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbchi': TexSymbolSpec(
    '\u03C7',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbpsi': TexSymbolSpec(
    '\u03C8',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbomega': TexSymbolSpec(
    '\u03C9',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbdotlessi': TexSymbolSpec(
    '\u0131',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
  'bfbbdotlessj': TexSymbolSpec(
    '\u0237',
    fontVariant: TexMathFontVariant.doubleStruckBold,
  ),
};

/// Mapping of negated base characters when preceded by `\not`.
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
  ',': 3.0 / 18.0,
  ':': 4.0 / 18.0,
  '>': 4.0 / 18.0,
  ';': 5.0 / 18.0,
  '!': -3.0 / 18.0,
  'enspace': 0.5,
  'quad': 1.0,
  'qquad': 2.0,
  'thinspace': 3.0 / 18.0,
  'negthinspace': -3.0 / 18.0,
  'medspace': 4.0 / 18.0,
  'negmedspace': -4.0 / 18.0,
  'thickspace': 5.0 / 18.0,
  'negthickspace': -5.0 / 18.0,
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

/// Math accent command configurations (`unicode`, `isWide`, `isUnder`).
const Map<String, ({String unicode, bool isWide, bool isUnder})>
mathAccentCommands = <String, ({String unicode, bool isWide, bool isUnder})>{
  'acute': (unicode: '\u00B4', isWide: false, isUnder: false),
  'grave': (unicode: '\u0060', isWide: false, isUnder: false),
  'ddot': (unicode: '\u00A8', isWide: false, isUnder: false),
  'dddot': (unicode: '\u20DB', isWide: false, isUnder: false),
  'ddddot': (unicode: '\u20DC', isWide: false, isUnder: false),
  'tilde': (unicode: '\u007E', isWide: false, isUnder: false),
  'bar': (unicode: '\u00AF', isWide: false, isUnder: false),
  'breve': (unicode: '\u02D8', isWide: false, isUnder: false),
  'check': (unicode: '\u02C7', isWide: false, isUnder: false),
  'hat': (unicode: '\u005E', isWide: false, isUnder: false),
  'vec': (unicode: '\u2192', isWide: false, isUnder: false),
  'dot': (unicode: '\u02D9', isWide: false, isUnder: false),
  'mathring': (unicode: '\u02DA', isWide: false, isUnder: false),
  'widetilde': (unicode: '\u007E', isWide: true, isUnder: false),
  'widehat': (unicode: '\u005E', isWide: true, isUnder: false),
  'overline': (unicode: '\u2015', isWide: true, isUnder: false),
  'underline': (unicode: '\u2015', isWide: true, isUnder: true),
  'overbrace': (unicode: '\u23DE', isWide: true, isUnder: false),
  'underbrace': (unicode: '\u23DF', isWide: true, isUnder: true),
  'overparen': (unicode: '\u23DC', isWide: true, isUnder: false),
  'underparen': (unicode: '\u23DD', isWide: true, isUnder: true),
  'overbracket': (unicode: '\u23B4', isWide: true, isUnder: false),
  'underbracket': (unicode: '\u23B5', isWide: true, isUnder: true),
  'overrightarrow': (unicode: '\u2192', isWide: true, isUnder: false),
  'underrightarrow': (unicode: '\u2192', isWide: true, isUnder: true),
  'overleftarrow': (unicode: '\u2190', isWide: true, isUnder: false),
  'underleftarrow': (unicode: '\u2190', isWide: true, isUnder: true),
  'overleftrightarrow': (unicode: '\u2194', isWide: true, isUnder: false),
  'underleftrightarrow': (unicode: '\u2194', isWide: true, isUnder: true),
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

/// Named colors normalized to hex `#RRGGBB` values.
const Map<String, String> standardTexColors = <String, String>{
  'black': '#000000',
  'blue': '#0000FF',
  'brown': '#A52A2A',
  'cyan': '#00FFFF',
  'darkgray': '#A9A9A9',
  'gray': '#808080',
  'green': '#008000',
  'lightblue': '#ADD8E6',
  'lightgray': '#D3D3D3',
  'lime': '#00FF00',
  'magenta': '#FF00FF',
  'olive': '#808000',
  'orange': '#FFA500',
  'pink': '#FFC0CB',
  'purple': '#800080',
  'red': '#FF0000',
  'teal': '#008080',
  'violet': '#EE82EE',
  'white': '#FFFFFF',
  'yellow': '#FFFF00',
  'lavender': '#E6E6FA',
  'crimson': '#DC143C',
  'navy': '#000080',
  'silver': '#C0C0C0',
  'maroon': '#800000',
  'aqua': '#00FFFF',
  'fuchsia': '#FF00FF',
};

/// Resolves a TeX color expression (`name`, `rgb`, `RGB`, `HTML`, `gray`) into
/// a CSS/hex color string.
String resolveTexColor(
  String colorSpec, {
  String model = '',
  Map<String, String> customColors = const <String, String>{},
}) {
  final String normalizedModel = model.trim().toLowerCase();
  final String spec = colorSpec.trim();

  if (normalizedModel == 'rgb') {
    final List<String> parts = spec.split(',');
    if (parts.length == 3) {
      final int r = _floatToChannel(parts[0]);
      final int g = _floatToChannel(parts[1]);
      final int b = _floatToChannel(parts[2]);
      return '#${_hexByte(r)}${_hexByte(g)}${_hexByte(b)}';
    }
  } else if (normalizedModel == 'html') {
    final String cleaned = spec.startsWith('#') ? spec.substring(1) : spec;
    return '#${cleaned.toUpperCase()}';
  } else if (normalizedModel == 'gray') {
    final int c = _floatToChannel(spec);
    return '#${_hexByte(c)}${_hexByte(c)}${_hexByte(c)}';
  } else if (model.trim() == 'RGB') {
    final List<String> parts = spec.split(',');
    if (parts.length == 3) {
      final int r = (int.tryParse(parts[0].trim()) ?? 0).clamp(0, 255);
      final int g = (int.tryParse(parts[1].trim()) ?? 0).clamp(0, 255);
      final int b = (int.tryParse(parts[2].trim()) ?? 0).clamp(0, 255);
      return '#${_hexByte(r)}${_hexByte(g)}${_hexByte(b)}';
    }
  }

  final String lower = spec.toLowerCase();
  final String? custom = customColors[lower] ?? customColors[spec];
  if (custom != null) {
    return custom;
  }
  final String? named = standardTexColors[lower];
  if (named != null) {
    return named;
  }
  if (spec.startsWith('#')) {
    return spec.toUpperCase();
  }
  return spec;
}

int _floatToChannel(String raw) {
  final double? value = double.tryParse(raw.trim());
  if (value == null) {
    return 0;
  }
  return (value * 255.0).round().clamp(0, 255);
}

String _hexByte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();

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
