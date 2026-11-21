import 'package:meta/meta.dart';

/// Mathematical typesetting mode controlling display style vs inline layout.
enum TexMathDisplayMode {
  /// Inline math mode (`$...$`), using compact text-style limits and fractions.
  inline,

  /// Display math mode (`$$...$$`), using full display-style operators and
  /// vertical limits.
  display,
}

/// Semantic color role assigned to layout items and theme overrides.
enum TexMathColorRole {
  /// Primary glyph and rule foreground color.
  foreground,

  /// Emphasized accent color for highlighted expressions or delimiters.
  accent,

  /// Diagnostic error foreground color.
  error,

  /// De-emphasized color for secondary annotations or tags.
  muted,

  /// Explicit caller-supplied or TeX `\color` custom color value.
  custom,
}

/// Resource and complexity limits enforced before and during TeX processing.
@immutable
final class TexMathBudgets {
  /// Creates a budget configuration with defensive defaults.
  const TexMathBudgets({
    this.maxInputLength = defaultMaxInputLength,
    this.maxMacroDepth = defaultMaxMacroDepth,
    this.maxMacroExpansions = defaultMaxMacroExpansions,
    this.maxNestingDepth = defaultMaxNestingDepth,
    this.maxOutputItems = defaultMaxOutputItems,
    this.maxSvgLength = defaultMaxSvgLength,
  }) : assert(maxInputLength >= 0, 'maxInputLength must be non-negative'),
       assert(maxMacroDepth >= 0, 'maxMacroDepth must be non-negative'),
       assert(
         maxMacroExpansions >= 0,
         'maxMacroExpansions must be non-negative',
       ),
       assert(maxNestingDepth >= 0, 'maxNestingDepth must be non-negative'),
       assert(maxOutputItems >= 0, 'maxOutputItems must be non-negative'),
       assert(maxSvgLength >= 0, 'maxSvgLength must be non-negative');

  /// Default maximum input length in UTF-16 code units (`50000`).
  static const int defaultMaxInputLength = 50000;

  /// Default maximum nested macro expansion depth (`64`).
  static const int defaultMaxMacroDepth = 64;

  /// Default maximum total macro expansions per expression (`10000`).
  static const int defaultMaxMacroExpansions = 10000;

  /// Default maximum AST or group nesting depth (`64`).
  static const int defaultMaxNestingDepth = 64;

  /// Default maximum display list items emitted per expression (`50000`).
  static const int defaultMaxOutputItems = 50000;

  /// Default maximum serialized SVG length in characters (`4000000`).
  static const int defaultMaxSvgLength = 4000000;

  /// Maximum TeX input length in UTF-16 code units.
  final int maxInputLength;

  /// Maximum nested macro invocation depth.
  final int maxMacroDepth;

  /// Maximum total macro expansions allowed for one expression.
  final int maxMacroExpansions;

  /// Maximum group or syntax-tree nesting depth.
  final int maxNestingDepth;

  /// Maximum number of items in a produced display list.
  final int maxOutputItems;

  /// Maximum character length of serialized SVG output.
  final int maxSvgLength;

  /// Returns a copy of this budget configuration with selected overrides.
  TexMathBudgets copyWith({
    int? maxInputLength,
    int? maxMacroDepth,
    int? maxMacroExpansions,
    int? maxNestingDepth,
    int? maxOutputItems,
    int? maxSvgLength,
  }) {
    return TexMathBudgets(
      maxInputLength: maxInputLength ?? this.maxInputLength,
      maxMacroDepth: maxMacroDepth ?? this.maxMacroDepth,
      maxMacroExpansions: maxMacroExpansions ?? this.maxMacroExpansions,
      maxNestingDepth: maxNestingDepth ?? this.maxNestingDepth,
      maxOutputItems: maxOutputItems ?? this.maxOutputItems,
      maxSvgLength: maxSvgLength ?? this.maxSvgLength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathBudgets &&
          maxInputLength == other.maxInputLength &&
          maxMacroDepth == other.maxMacroDepth &&
          maxMacroExpansions == other.maxMacroExpansions &&
          maxNestingDepth == other.maxNestingDepth &&
          maxOutputItems == other.maxOutputItems &&
          maxSvgLength == other.maxSvgLength;

  @override
  int get hashCode => Object.hash(
    maxInputLength,
    maxMacroDepth,
    maxMacroExpansions,
    maxNestingDepth,
    maxOutputItems,
    maxSvgLength,
  );

  @override
  String toString() =>
      'TexMathBudgets('
      'maxInputLength: $maxInputLength, '
      'maxMacroDepth: $maxMacroDepth, '
      'maxMacroExpansions: $maxMacroExpansions, '
      'maxNestingDepth: $maxNestingDepth, '
      'maxOutputItems: $maxOutputItems, '
      'maxSvgLength: $maxSvgLength)';
}

/// Configuration options controlling TeX parsing, macro expansion, and layout.
@immutable
final class TexMathOptions {
  /// Creates rendering and parsing options.
  const TexMathOptions({
    this.displayMode = TexMathDisplayMode.display,
    this.packages = defaultPackages,
    this.requireAllowlist = defaultRequireAllowlist,
    this.macros = const <String, String>{},
    this.budgets = const TexMathBudgets(),
    this.strictErrors = true,
    this.useOpticalScriptVariants = false,
  });

  /// Default active TeX package list matching JupyterLab defaults without
  /// `noerrors` or `noundefined`.
  static const List<String> defaultPackages = <String>[
    'base',
    'action',
    'ams',
    'amscd',
    'bbox',
    'boldsymbol',
    'braket',
    'bussproofs',
    'cancel',
    'cases',
    'centernot',
    'color',
    'colortbl',
    'empheq',
    'enclose',
    'extpfeil',
    'gensymb',
    'html',
    'mathtools',
    'mhchem',
    'newcommand',
    'upgreek',
    'unicode',
    'verb',
    'configmacros',
    'tagformat',
    'textcomp',
    'textmacros',
    'require',
  ];

  /// Default packages permitted by synchronous `\require{...}` loading.
  ///
  /// Matches MathJax's `require.allow` defaults by allowing built-in and
  /// preloaded extensions while disallowing `base`, `autoload`, `configmacros`,
  /// `tagformat`, `setoptions`, and `texhtml`.
  static const List<String> defaultRequireAllowlist = <String>[
    'action',
    'ams',
    'amscd',
    'bbm',
    'bboldx',
    'bbox',
    'begingroup',
    'boldsymbol',
    'braket',
    'bussproofs',
    'cancel',
    'cases',
    'centernot',
    'color',
    'colortbl',
    'colorv2',
    'dsfont',
    'empheq',
    'enclose',
    'extpfeil',
    'fontsizev3',
    'gensymb',
    'html',
    'mathtools',
    'mhchem',
    'newcommand',
    'noerrors',
    'noundefined',
    'physics',
    'require',
    'textcomp',
    'textmacros',
    'unicode',
    'units',
    'upgreek',
    'verb',
  ];

  /// Typesetting display mode (`inline` or `display`).
  final TexMathDisplayMode displayMode;

  /// Ordered list of enabled TeX extension package names.
  final List<String> packages;

  /// Package names permitted for synchronous loading via `\require{pkg}`.
  final List<String> requireAllowlist;

  /// Preconfigured macro definitions mapping control sequence names (without
  /// leading backslash) to TeX replacement bodies.
  final Map<String, String> macros;

  /// Safety limits enforced during parsing, expansion, layout, and export.
  final TexMathBudgets budgets;

  /// Whether TeX syntax and macro errors throw [TexMathError] instead of
  /// producing fallback error nodes.
  final bool strictErrors;

  /// Whether script layout substitutes OpenType `GSUB` `ssty` optical glyphs
  /// rather than relying solely on `MATH` scale-down factors.
  final bool useOpticalScriptVariants;

  /// Returns a copy of these options with the given fields replaced.
  TexMathOptions copyWith({
    TexMathDisplayMode? displayMode,
    List<String>? packages,
    List<String>? requireAllowlist,
    Map<String, String>? macros,
    TexMathBudgets? budgets,
    bool? strictErrors,
    bool? useOpticalScriptVariants,
  }) {
    return TexMathOptions(
      displayMode: displayMode ?? this.displayMode,
      packages: packages ?? this.packages,
      requireAllowlist: requireAllowlist ?? this.requireAllowlist,
      macros: macros ?? this.macros,
      budgets: budgets ?? this.budgets,
      strictErrors: strictErrors ?? this.strictErrors,
      useOpticalScriptVariants:
          useOpticalScriptVariants ?? this.useOpticalScriptVariants,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathOptions &&
          displayMode == other.displayMode &&
          _stringListEquals(packages, other.packages) &&
          _stringListEquals(requireAllowlist, other.requireAllowlist) &&
          _stringMapEquals(macros, other.macros) &&
          budgets == other.budgets &&
          strictErrors == other.strictErrors &&
          useOpticalScriptVariants == other.useOpticalScriptVariants;

  @override
  int get hashCode => Object.hash(
    displayMode,
    Object.hashAll(packages),
    Object.hashAll(requireAllowlist),
    Object.hashAllUnordered(
      macros.entries.map(
        (MapEntry<String, String> entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    budgets,
    strictErrors,
    useOpticalScriptVariants,
  );

  @override
  String toString() =>
      'TexMathOptions('
      'displayMode: $displayMode, '
      'packages: $packages, '
      'requireAllowlist: $requireAllowlist, '
      'macros: $macros, '
      'budgets: $budgets, '
      'strictErrors: $strictErrors, '
      'useOpticalScriptVariants: $useOpticalScriptVariants)';
}

bool _stringListEquals(List<String> a, List<String> b) {
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

bool _stringMapEquals(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
