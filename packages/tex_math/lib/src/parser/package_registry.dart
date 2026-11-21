import 'package:meta/meta.dart';

import '../error.dart';
import '../options.dart';
import '../source_span.dart';

/// Coverage tier classification for a TeX extension package.
enum TexPackageTier {
  /// Core TeX, AMS, macro definition, text macros, and tag configuration.
  tier1,

  /// Standard JupyterLab TeX extensions.
  tier2,

  /// Extended MathJax TeX packages.
  tier3,
}

/// Compile-time descriptor of a single MathJax-compatible TeX package.
@immutable
final class TexPackageDescriptor {
  /// Creates an immutable package descriptor.
  const TexPackageDescriptor({
    required this.name,
    required this.tier,
    required this.description,
    this.dependencies = const <String>[],
    this.isDefaultJupyterLab = false,
    this.isRequireAllowedByDefault = true,
  });

  /// Canonical MathJax package identifier.
  final String name;

  /// Verification coverage tier for this package.
  final TexPackageTier tier;

  /// Concise description of the features provided by this package.
  final String description;

  /// Prerequisite package names activated alongside this package.
  final List<String> dependencies;

  /// Whether this package is part of the default JupyterLab configuration.
  final bool isDefaultJupyterLab;

  /// Whether `\require{name}` permits loading this package by default.
  final bool isRequireAllowedByDefault;
}

/// Compile-time immutable registry of all 42 MathJax `4.1.3` TeX packages.
abstract final class TexPackageRegistry {
  /// Ordered descriptors for all 42 supported TeX packages.
  static const List<TexPackageDescriptor> all = <TexPackageDescriptor>[
    // Tier 1 (6 packages)
    TexPackageDescriptor(
      name: 'base',
      tier: TexPackageTier.tier1,
      description: 'Core TeX math-mode primitives, symbols, and delimiters.',
      isDefaultJupyterLab: true,
      isRequireAllowedByDefault: false,
    ),
    TexPackageDescriptor(
      name: 'ams',
      tier: TexPackageTier.tier1,
      description: 'AMS math environments, operators, fractions, and symbols.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'newcommand',
      tier: TexPackageTier.tier1,
      description: 'User macro and environment definitions.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'textmacros',
      tier: TexPackageTier.tier1,
      description: 'Text-mode macros, accents, ligatures, and inline math.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'tagformat',
      tier: TexPackageTier.tier1,
      description: 'Equation tag formatting and reference hooks.',
      dependencies: <String>['ams'],
      isDefaultJupyterLab: true,
      isRequireAllowedByDefault: false,
    ),
    TexPackageDescriptor(
      name: 'configmacros',
      tier: TexPackageTier.tier1,
      description: 'Preconfigured macro loading from TexMathOptions.macros.',
      dependencies: <String>['newcommand'],
      isDefaultJupyterLab: true,
      isRequireAllowedByDefault: false,
    ),

    // Tier 2 (25 packages)
    TexPackageDescriptor(
      name: 'action',
      tier: TexPackageTier.tier2,
      description: 'Interactive toggle and tooltip annotations.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'amscd',
      tier: TexPackageTier.tier2,
      description: 'Commutative diagram CD environment.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'bbox',
      tier: TexPackageTier.tier2,
      description: 'Background, padding, and border bounding boxes.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'boldsymbol',
      tier: TexPackageTier.tier2,
      description: 'Bold mathematical symbols and poor-man bold.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'braket',
      tier: TexPackageTier.tier2,
      description: 'Dirac bra-ket and set builder notation.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'bussproofs',
      tier: TexPackageTier.tier2,
      description: 'Natural deduction and sequent calculus proof trees.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'cancel',
      tier: TexPackageTier.tier2,
      description: 'Diagonal and cross cancellation strokes.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'cases',
      tier: TexPackageTier.tier2,
      description: 'Numbered piecewise numcases and subnumcases environments.',
      dependencies: <String>['ams'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'centernot',
      tier: TexPackageTier.tier2,
      description: 'Horizontally centered negation slash over operators.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'color',
      tier: TexPackageTier.tier2,
      description: 'LaTeX color switches, textcolor, colorbox, and models.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'colortbl',
      tier: TexPackageTier.tier2,
      description: 'Cell, row, and column background colors inside arrays.',
      dependencies: <String>['base', 'color'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'empheq',
      tier: TexPackageTier.tier2,
      description: 'Emphasized equation blocks with custom delimiters.',
      dependencies: <String>['ams'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'enclose',
      tier: TexPackageTier.tier2,
      description: 'MathML-style menclose notations.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'extpfeil',
      tier: TexPackageTier.tier2,
      description: 'Extensible labeled arrows and \\Newextarrow.',
      dependencies: <String>['ams', 'newcommand'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'gensymb',
      tier: TexPackageTier.tier2,
      description: 'Generic degree, Celsius, ohm, micro, and perthousand.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'html',
      tier: TexPackageTier.tier2,
      description: 'HTML class, id, style, data attribute, and href wrappers.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'mathtools',
      tier: TexPackageTier.tier2,
      description: 'Extended AMS tools, paired delimiters, and prescripts.',
      dependencies: <String>['ams', 'newcommand'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'mhchem',
      tier: TexPackageTier.tier2,
      description: 'Chemical equations (\\ce) and physical units (\\pu).',
      dependencies: <String>['ams'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'noerrors',
      tier: TexPackageTier.tier2,
      description: 'Non-throwing error passthrough into ErrorNode.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'noundefined',
      tier: TexPackageTier.tier2,
      description: 'Renders undefined commands literally instead of throwing.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'require',
      tier: TexPackageTier.tier2,
      description: 'Synchronous \\require{pkg} activation against allowlist.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'textcomp',
      tier: TexPackageTier.tier2,
      description: 'Extended currency, legal, and scientific text symbols.',
      dependencies: <String>['base', 'textmacros'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'unicode',
      tier: TexPackageTier.tier2,
      description:
          'Direct Unicode character insertion (\\unicode, \\U, \\char).',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'upgreek',
      tier: TexPackageTier.tier2,
      description: 'Upright lowercase and uppercase Greek commands.',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),
    TexPackageDescriptor(
      name: 'verb',
      tier: TexPackageTier.tier2,
      description: 'Inline verbatim text runs (\\verb|...|).',
      dependencies: <String>['base'],
      isDefaultJupyterLab: true,
    ),

    // Tier 3 (11 packages)
    TexPackageDescriptor(
      name: 'autoload',
      tier: TexPackageTier.tier3,
      description: 'Automatic activation of extension packages on first use.',
      dependencies: <String>['require'],
      isRequireAllowedByDefault: false,
    ),
    TexPackageDescriptor(
      name: 'bbm',
      tier: TexPackageTier.tier3,
      description:
          'Blackboard bold variants (\\mathbbm, \\mathbbmss, \\mathbbmtt).',
      dependencies: <String>['base'],
    ),
    TexPackageDescriptor(
      name: 'bboldx',
      tier: TexPackageTier.tier3,
      description: 'Extended blackboard bold Greek and delimiters.',
      dependencies: <String>['base'],
    ),
    TexPackageDescriptor(
      name: 'begingroup',
      tier: TexPackageTier.tier3,
      description: 'Scoped macro groups and sandbox reset commands.',
      dependencies: <String>['newcommand'],
    ),
    TexPackageDescriptor(
      name: 'colorv2',
      tier: TexPackageTier.tier3,
      description: 'Two-argument grouped \\color{color}{expr} macro.',
      dependencies: <String>['base'],
    ),
    TexPackageDescriptor(
      name: 'dsfont',
      tier: TexPackageTier.tier3,
      description: 'Double-struck mathds alphabet with optional sans option.',
      dependencies: <String>['base'],
    ),
    TexPackageDescriptor(
      name: 'fontsizev3',
      tier: TexPackageTier.tier3,
      description: 'LaTeX font size scaling switches (\\tiny through \\Huge).',
      dependencies: <String>['base'],
    ),
    TexPackageDescriptor(
      name: 'physics',
      tier: TexPackageTier.tier3,
      description: 'Derivatives, bra-ket, matrices, norms, and operators.',
      dependencies: <String>['ams'],
    ),
    TexPackageDescriptor(
      name: 'setoptions',
      tier: TexPackageTier.tier3,
      description: 'Per-expression \\setOptions[pkg]{key=value} overrides.',
      dependencies: <String>['base'],
      isRequireAllowedByDefault: false,
    ),
    TexPackageDescriptor(
      name: 'texhtml',
      tier: TexPackageTier.tier3,
      description: 'Inline <tex-html>...</tex-html> markup inside expressions.',
      dependencies: <String>['base'],
      isRequireAllowedByDefault: false,
    ),
    TexPackageDescriptor(
      name: 'units',
      tier: TexPackageTier.tier3,
      description:
          'Physical unit formatting (\\units, \\unitfrac, \\nicefrac).',
      dependencies: <String>['base'],
    ),
  ];

  /// Map of canonical package names to descriptors.
  static final Map<String, TexPackageDescriptor> byName =
      Map<String, TexPackageDescriptor>.unmodifiable(
        <String, TexPackageDescriptor>{
          for (final TexPackageDescriptor desc in all) desc.name: desc,
        },
      );

  /// Ordered names of all 42 registered packages.
  static List<String> get allNames =>
      all.map((TexPackageDescriptor d) => d.name).toList(growable: false);

  /// Whether [name] is a registered package.
  static bool contains(String name) => byName.containsKey(name);

  /// Autoload mapping from macro name to owning Tier 2 package.
  static const Map<String, String> autoloadCommands = <String, String>{
    'toggle': 'action',
    'mathtip': 'action',
    'texttip': 'action',
    'bbox': 'bbox',
    'boldsymbol': 'boldsymbol',
    'pmb': 'boldsymbol',
    'bra': 'braket',
    'ket': 'braket',
    'braket': 'braket',
    'set': 'braket',
    'Bra': 'braket',
    'Ket': 'braket',
    'Braket': 'braket',
    'Set': 'braket',
    'ketbra': 'braket',
    'Ketbra': 'braket',
    'cancel': 'cancel',
    'bcancel': 'cancel',
    'xcancel': 'cancel',
    'cancelto': 'cancel',
    'color': 'color',
    'definecolor': 'color',
    'textcolor': 'color',
    'colorbox': 'color',
    'fcolorbox': 'color',
    'enclose': 'enclose',
    'xtwoheadrightarrow': 'extpfeil',
    'xtwoheadleftarrow': 'extpfeil',
    'xmapsto': 'extpfeil',
    'xlongequal': 'extpfeil',
    'xtofrom': 'extpfeil',
    'Newextarrow': 'extpfeil',
    'data': 'html',
    'href': 'html',
    'class': 'html',
    'style': 'html',
    'cssId': 'html',
    'ce': 'mhchem',
    'pu': 'mhchem',
    'newcommand': 'newcommand',
    'renewcommand': 'newcommand',
    'providecommand': 'newcommand',
    'newenvironment': 'newcommand',
    'renewenvironment': 'newcommand',
    'def': 'newcommand',
    'let': 'newcommand',
    'unicode': 'unicode',
    'U': 'unicode',
    'char': 'unicode',
    'verb': 'verb',
  };

  /// Autoload mapping from environment name to owning Tier 2 package.
  static const Map<String, String> autoloadEnvironments = <String, String>{
    'CD': 'amscd',
    'prooftree': 'bussproofs',
  };
}

/// Per-parse mutable state tracking enabled TeX packages and package options
/// without any global mutable state across renders.
final class TexActivePackages {
  /// Initializes active packages and scoped package options from [options].
  TexActivePackages(TexMathOptions options)
    : _allowlist = options.requireAllowlist.toSet(),
      _active = <String>{} {
    for (final String pkg in options.packages) {
      _activateWithDependencies(pkg);
    }
  }

  final Set<String> _allowlist;
  final Set<String> _active;

  /// Active `color` vs `colorv2` precedence: when `colorv2` is loaded, grouped
  /// two-argument `\color{c}{x}` overrides one-argument switch `\color{c}`.
  bool get usesColorV2 => _active.contains('colorv2');

  /// `dsfont` option: whether `\mathds` uses sans-serif style.
  bool dsfontSans = false;

  /// `units` option: whether `\units` inserts a non-breaking space.
  bool unitsLoose = false;

  /// `units` option: whether `\nicefrac` disables bevelled formatting.
  bool unitsUgly = false;

  /// `physics` option: whether `\dd` uses italic `d`.
  bool physicsItalicDiff = false;

  /// `physics` option: whether `\vnabla` adds an arrow accent.
  bool physicsArrowDel = false;

  /// `tex` option: whether grouped number patterns like `1,000` are enabled.
  bool texDigits = false;

  /// `bbm` option: whether `\mathversion{bold}` is active.
  bool bbmBold = false;

  /// Whether [packageName] is currently active for this parse.
  bool has(String packageName) => _active.contains(packageName);

  /// Synchronously activates [packageName] via `\require{...}` after checking
  /// registry membership and [TexMathOptions.requireAllowlist].
  void require(String packageName, {SourceSpan? span}) {
    final String name = packageName.trim();
    if (name.isEmpty || !RegExp(r'^[_a-zA-Z0-9]+$').hasMatch(name)) {
      throw TexMathSyntaxError(
        'Argument for \\require is not a valid package name: "$packageName".',
        errorClass: TexMathErrorClass.syntaxError,
        span: span,
      );
    }
    if (!TexPackageRegistry.contains(name)) {
      throw TexMathSyntaxError(
        'Unknown TeX extension "$name".',
        errorClass: TexMathErrorClass.syntaxError,
        span: span,
      );
    }
    if (!_allowlist.contains(name)) {
      throw TexMathSyntaxError(
        'Extension "$name" is not allowed to be loaded by \\require.',
        errorClass: TexMathErrorClass.syntaxError,
        span: span,
      );
    }
    _activateWithDependencies(name);
  }

  /// Attempts to autoload the owning package for command [name] when `autoload`
  /// is active. Returns `true` if a package was activated.
  bool tryAutoloadCommand(String name) {
    if (!has('autoload')) {
      return false;
    }
    final String? owner = TexPackageRegistry.autoloadCommands[name];
    if (owner == null || has(owner)) {
      return false;
    }
    if (!_allowlist.contains(owner)) {
      return false;
    }
    _activateWithDependencies(owner);
    return true;
  }

  /// Attempts to autoload the owning package for environment [name] when
  /// `autoload` is active. Returns `true` if a package was activated.
  bool tryAutoloadEnvironment(String name) {
    if (!has('autoload')) {
      return false;
    }
    final String? owner = TexPackageRegistry.autoloadEnvironments[name];
    if (owner == null || has(owner)) {
      return false;
    }
    if (!_allowlist.contains(owner)) {
      return false;
    }
    _activateWithDependencies(owner);
    return true;
  }

  /// Applies key-value configuration updates from `\setOptions[pkg]{opts}`.
  void setOptions(
    String packageName,
    Map<String, String> entries, {
    SourceSpan? span,
  }) {
    final String target = packageName.trim();
    if (target != 'tex' && !TexPackageRegistry.contains(target)) {
      throw TexMathSyntaxError(
        'Unknown package "$target" in \\setOptions.',
        errorClass: TexMathErrorClass.syntaxError,
        span: span,
      );
    }
    const Set<String> disallowedPackages = <String>{
      'setoptions',
      'autoload',
      'require',
      'configmacros',
      'tagformat',
    };
    if (disallowedPackages.contains(target)) {
      throw TexMathSyntaxError(
        'Options cannot be modified for package "$target".',
        errorClass: TexMathErrorClass.syntaxError,
        span: span,
      );
    }

    for (final MapEntry<String, String> entry in entries.entries) {
      final String key = entry.key.trim();
      final bool boolVal = entry.value.trim().toLowerCase() == 'true';
      if (target == 'dsfont' && key == 'sans') {
        dsfontSans = boolVal;
      } else if (target == 'units' && key == 'loose') {
        unitsLoose = boolVal;
      } else if (target == 'units' && key == 'ugly') {
        unitsUgly = boolVal;
      } else if (target == 'physics' && key == 'italicdiff') {
        physicsItalicDiff = boolVal;
      } else if (target == 'physics' && key == 'arrowdel') {
        physicsArrowDel = boolVal;
      } else if (target == 'tex' && key == 'digits') {
        texDigits = boolVal;
      } else if (target == 'bbm' && key == 'bold') {
        bbmBold = boolVal;
      }
    }
  }

  void _activateWithDependencies(String name) {
    if (_active.contains(name)) {
      return;
    }
    final TexPackageDescriptor? desc = TexPackageRegistry.byName[name];
    if (desc == null) {
      throw TexMathSyntaxError(
        'Unknown TeX package "$name".',
        errorClass: TexMathErrorClass.syntaxError,
      );
    }
    _active.add(name);
    for (final String dep in desc.dependencies) {
      _activateWithDependencies(dep);
    }
  }
}
