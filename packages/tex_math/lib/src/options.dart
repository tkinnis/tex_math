import 'dart:collection';

import 'package:meta/meta.dart';

import 'error.dart' show TexMathError;

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
    this.maxTokens = defaultMaxTokens,
    this.maxNestingDepth = defaultMaxNestingDepth,
    this.maxOutputItems = defaultMaxOutputItems,
    this.maxSvgLength = defaultMaxSvgLength,
  }) : assert(maxInputLength >= 0, 'maxInputLength must be non-negative'),
       assert(maxMacroDepth >= 0, 'maxMacroDepth must be non-negative'),
       assert(
         maxMacroExpansions >= 0,
         'maxMacroExpansions must be non-negative',
       ),
       assert(maxTokens >= 0, 'maxTokens must be non-negative'),
       assert(maxNestingDepth >= 0, 'maxNestingDepth must be non-negative'),
       assert(maxOutputItems >= 0, 'maxOutputItems must be non-negative'),
       assert(maxSvgLength >= 0, 'maxSvgLength must be non-negative');

  /// Default maximum input length in UTF-16 code units (`50000`).
  static const int defaultMaxInputLength = 50000;

  /// Default maximum nested macro expansion depth (`64`).
  static const int defaultMaxMacroDepth = 64;

  /// Default maximum total macro expansions per expression (`10000`).
  static const int defaultMaxMacroExpansions = 10000;

  /// Default maximum cumulative tokens processed or generated per parse
  /// (`100000`).
  static const int defaultMaxTokens = 100000;

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

  /// Maximum cumulative tokens buffered or synthesized during macro expansion.
  final int maxTokens;

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
    int? maxTokens,
    int? maxNestingDepth,
    int? maxOutputItems,
    int? maxSvgLength,
  }) {
    return TexMathBudgets(
      maxInputLength: maxInputLength ?? this.maxInputLength,
      maxMacroDepth: maxMacroDepth ?? this.maxMacroDepth,
      maxMacroExpansions: maxMacroExpansions ?? this.maxMacroExpansions,
      maxTokens: maxTokens ?? this.maxTokens,
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
          maxTokens == other.maxTokens &&
          maxNestingDepth == other.maxNestingDepth &&
          maxOutputItems == other.maxOutputItems &&
          maxSvgLength == other.maxSvgLength;

  @override
  int get hashCode => Object.hash(
    maxInputLength,
    maxMacroDepth,
    maxMacroExpansions,
    maxTokens,
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
      'maxTokens: $maxTokens, '
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
    List<String> packages = defaultPackages,
    List<String> requireAllowlist = defaultRequireAllowlist,
    Map<String, String> macros = const <String, String>{},
    this.budgets = const TexMathBudgets(),
    this.strictErrors = true,
    this.useOpticalScriptVariants = false,
    // ignore: prefer_initializing_formals
  }) : _packages = packages,
       // ignore: prefer_initializing_formals
       _requireAllowlist = requireAllowlist,
       // ignore: prefer_initializing_formals
       _macros = macros;

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

  final List<String> _packages;

  final List<String> _requireAllowlist;

  final Map<String, String> _macros;

  /// Ordered unmodifiable list of enabled TeX extension package names.
  List<String> get packages => identical(_packages, defaultPackages)
      ? defaultPackages
      : (_packages.isEmpty
            ? const <String>[]
            : UnmodifiableListView<String>(_packages));

  /// Unmodifiable package names permitted for synchronous `\require{pkg}`.
  List<String> get requireAllowlist =>
      identical(_requireAllowlist, defaultRequireAllowlist)
      ? defaultRequireAllowlist
      : (_requireAllowlist.isEmpty
            ? const <String>[]
            : UnmodifiableListView<String>(_requireAllowlist));

  /// Preconfigured unmodifiable macro definitions mapping control sequence
  /// names (without leading backslash) to TeX replacement bodies.
  Map<String, String> get macros => _macros.isEmpty
      ? const <String, String>{}
      : UnmodifiableMapView<String, String>(_macros);

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
      packages: packages == null
          ? _packages
          : (packages.isEmpty
                ? const <String>[]
                : List<String>.unmodifiable(packages)),
      requireAllowlist: requireAllowlist == null
          ? _requireAllowlist
          : (requireAllowlist.isEmpty
                ? const <String>[]
                : List<String>.unmodifiable(requireAllowlist)),
      macros: macros == null
          ? _macros
          : (macros.isEmpty
                ? const <String, String>{}
                : Map<String, String>.unmodifiable(macros)),
      budgets: budgets ?? this.budgets,
      strictErrors: strictErrors ?? this.strictErrors,
      useOpticalScriptVariants:
          useOpticalScriptVariants ?? this.useOpticalScriptVariants,
    );
  }

  static final int _defaultPackagesHash = Object.hashAll(defaultPackages);
  static final int _defaultAllowlistHash = Object.hashAll(
    defaultRequireAllowlist,
  );
  static final int _emptyMacrosHash = Object.hashAllUnordered(const <int>[]);
  static final Expando<int> _customHashCache = Expando<int>();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathOptions &&
          displayMode == other.displayMode &&
          _stringListEquals(_packages, other._packages) &&
          _stringListEquals(_requireAllowlist, other._requireAllowlist) &&
          _stringMapEquals(_macros, other._macros) &&
          budgets == other.budgets &&
          strictErrors == other.strictErrors &&
          useOpticalScriptVariants == other.useOpticalScriptVariants;

  @override
  int get hashCode {
    final bool hasCustom =
        !identical(_packages, defaultPackages) ||
        !identical(_requireAllowlist, defaultRequireAllowlist) ||
        _macros.isNotEmpty;
    if (hasCustom) {
      final int? cached = _customHashCache[this];
      if (cached != null) {
        return cached;
      }
    }
    final int computed = Object.hash(
      displayMode,
      identical(_packages, defaultPackages)
          ? _defaultPackagesHash
          : Object.hashAll(_packages),
      identical(_requireAllowlist, defaultRequireAllowlist)
          ? _defaultAllowlistHash
          : Object.hashAll(_requireAllowlist),
      _macros.isEmpty
          ? _emptyMacrosHash
          : Object.hashAllUnordered(
              _macros.entries.map(
                (MapEntry<String, String> entry) =>
                    Object.hash(entry.key, entry.value),
              ),
            ),
      budgets,
      strictErrors,
      useOpticalScriptVariants,
    );
    if (hasCustom) {
      _customHashCache[this] = computed;
    }
    return computed;
  }

  @override
  String toString() =>
      'TexMathOptions('
      'displayMode: $displayMode, '
      'packages: $_packages, '
      'requireAllowlist: $_requireAllowlist, '
      'macros: $_macros, '
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
  if (a.isEmpty) {
    return true;
  }
  for (final MapEntry<String, String> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
