import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

/// Canonical ordered tier labels displayed in the studio corpus browser.
const List<String> canonicalCorpusTiers = <String>[
  'Tier 1',
  'Tier 2',
  'Tier 3',
  'Stretchy',
  'Notebooks',
  'Errors',
];

/// Filtering constraint on MathJax oracle acceptance status.
enum StudioCorpusAcceptanceFilter {
  /// Include both oracle-accepted and oracle-refused corpus entries.
  all('All'),

  /// Include only expressions expected to be accepted cleanly.
  accepted('Accepted'),

  /// Include only expressions expected to throw a syntax/budget error.
  refused('Refused');

  const StudioCorpusAcceptanceFilter(this.label);

  /// Human-readable label shown in filter chips and dropdowns.
  final String label;
}

/// Grouping dimension applied to entries in the studio corpus sidebar.
enum StudioCorpusGrouping {
  /// Group entries by canonical verification tier.
  tier('Tier'),

  /// Group entries alphabetically by primary TeX extension package.
  package('Package'),

  /// Group entries by oracle acceptance (`Accepted` vs `Refused`).
  acceptance('Acceptance');

  const StudioCorpusGrouping(this.label);

  /// Human-readable label shown in grouping controls.
  final String label;
}

/// Single TeX corpus entry or embedded fallback preset loaded by the studio.
@immutable
final class StudioCorpusEntry {
  /// Creates an immutable studio corpus entry.
  const StudioCorpusEntry({
    required this.id,
    required this.relativePath,
    required this.tier,
    required this.package,
    required this.feature,
    required this.display,
    required this.accepted,
    required this.tex,
    this.errorClass,
    this.packages,
    this.expectationStatus,
    this.oracleBoxWidthEm,
    this.oracleBoxHeightEm,
    this.oracleBoxDepthEm,
    this.isEmbeddedFallback = false,
  });

  /// Unique corpus case identifier (for example `tier1_core/base/fraction_basic`).
  final String id;

  /// Forward-slash path relative to repository root.
  final String relativePath;

  /// Canonical tier name (`Tier 1`, `Tier 2`, `Tier 3`, `Stretchy`, `Notebooks`, `Errors`).
  final String tier;

  /// Primary TeX package under verification.
  final String package;

  /// Feature area within [package].
  final String feature;

  /// Whether the case uses display style (`true`) or inline style (`false`).
  final bool display;

  /// Whether the MathJax oracle accepts this expression without error.
  final bool accepted;

  /// Raw TeX math body without surrounding `$` or `$$` delimiters.
  final String tex;

  /// Expected canonical error class name when [accepted] is `false`.
  final String? errorClass;

  /// Explicit MathJax package list when non-default packages apply.
  final List<String>? packages;

  /// Recorded status in `corpus/expectations.json` (for example `pass`, `differs`, `refused_match`).
  final String? expectationStatus;

  /// MathJax oracle bounding box width in ems, when available.
  final double? oracleBoxWidthEm;

  /// MathJax oracle bounding box ascent in ems, when available.
  final double? oracleBoxHeightEm;

  /// MathJax oracle bounding box descent in ems, when available.
  final double? oracleBoxDepthEm;

  /// Whether this entry comes from embedded fallback presets rather than disk.
  final bool isEmbeddedFallback;

  /// Short readable display name derived from [id].
  String get shortName {
    final int slashIndex = id.lastIndexOf('/');
    return slashIndex >= 0 ? id.substring(slashIndex + 1) : id;
  }

  /// Acceptance label (`Accepted` or `Refused`).
  String get acceptanceLabel => accepted ? 'Accepted' : 'Refused';

  /// Returns `true` when [query] matches any metadata field or TeX source.
  bool matchesQuery(String query) {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return id.toLowerCase().contains(normalized) ||
        tier.toLowerCase().contains(normalized) ||
        package.toLowerCase().contains(normalized) ||
        feature.toLowerCase().contains(normalized) ||
        tex.toLowerCase().contains(normalized) ||
        (errorClass?.toLowerCase().contains(normalized) ?? false) ||
        (expectationStatus?.toLowerCase().contains(normalized) ?? false);
  }
}

/// Collection of loaded corpus cases with filtering and grouping helpers.
@immutable
final class StudioCorpusCatalog {
  /// Creates a catalog wrapping [entries].
  StudioCorpusCatalog({
    required List<StudioCorpusEntry> entries,
    required this.isFromDisk,
    this.corpusRootPath,
  }) : entries = List<StudioCorpusEntry>.unmodifiable(entries);

  /// Fallback presets displayed when the repository `corpus/` directory is
  /// unavailable at runtime.
  factory StudioCorpusCatalog.embeddedFallback() {
    return StudioCorpusCatalog(
      isFromDisk: false,
      entries: const <StudioCorpusEntry>[
        StudioCorpusEntry(
          id: 'tier1_core/base/fraction_basic',
          relativePath: 'corpus/tier1_core/base/fraction_basic.tex',
          tier: 'Tier 1',
          package: 'base',
          feature: 'fractions',
          display: true,
          accepted: true,
          tex: r'\frac{a + b}{c - d}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'tier1_core/base/gaussian_integral',
          relativePath: 'corpus/tier1_core/base/gaussian_integral.tex',
          tier: 'Tier 1',
          package: 'base',
          feature: 'integrals',
          display: true,
          accepted: true,
          tex: r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'tier1_core/ams/identity_matrix',
          relativePath: 'corpus/tier1_core/ams/identity_matrix.tex',
          tier: 'Tier 1',
          package: 'ams',
          feature: 'matrices',
          display: true,
          accepted: true,
          tex: r'\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'tier2_jupyter/mhchem/boudouard_reaction',
          relativePath: 'corpus/tier2_jupyter/mhchem/boudouard_reaction.tex',
          tier: 'Tier 2',
          package: 'mhchem',
          feature: 'chemistry',
          display: true,
          accepted: true,
          tex: r'\ce{CO2 + C -> 2CO}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'tier3_extended/physics/inner_product',
          relativePath: 'corpus/tier3_extended/physics/inner_product.tex',
          tier: 'Tier 3',
          package: 'physics',
          feature: 'braket',
          display: true,
          accepted: true,
          packages: <String>['base', 'physics'],
          tex: r'\braket{\psi}{\phi} = \dv{t}\mel{n}{\hat{H}}{m}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'stretchy/delimiters/nested_middle',
          relativePath: 'corpus/stretchy/delimiters/nested_middle.tex',
          tier: 'Stretchy',
          package: 'base',
          feature: 'stretchy_delimiters',
          display: true,
          accepted: true,
          tex: r'\left\{ \frac{x^2}{y^3} \,\middle|\, \sqrt{\sum_{k=1}^n a_k} \right\}',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'notebooks/quantum/schrodinger',
          relativePath: 'corpus/notebooks/quantum/schrodinger.tex',
          tier: 'Notebooks',
          package: 'ams',
          feature: 'notebook_equation',
          display: true,
          accepted: true,
          tex: r'i\hbar \frac{\partial \Psi}{\partial t} = -\frac{\hbar^2}{2m}\nabla^2\Psi + V\Psi',
          isEmbeddedFallback: true,
        ),
        StudioCorpusEntry(
          id: 'errors/undefined_command_sample',
          relativePath: 'corpus/errors/undefined_command_sample.tex',
          tier: 'Errors',
          package: 'base',
          feature: 'undefinedControlSequence',
          display: true,
          accepted: false,
          errorClass: 'undefinedControlSequence',
          tex: r'\undefinedcmd + x',
          isEmbeddedFallback: true,
        ),
      ],
    );
  }

  /// Immutable list of corpus entries in deterministic order.
  final List<StudioCorpusEntry> entries;

  /// Whether [entries] were loaded dynamically from `.tex` files on disk.
  final bool isFromDisk;

  /// Resolved path to the `corpus/` directory when [isFromDisk] is `true`.
  final String? corpusRootPath;

  /// Total number of entries in this catalog.
  int get length => entries.length;

  /// Available tiers present across [entries], ordered canonically.
  List<String> get availableTiers {
    final Set<String> present = entries
        .map((StudioCorpusEntry e) => e.tier)
        .toSet();
    final List<String> ordered = <String>[
      for (final String tier in canonicalCorpusTiers)
        if (present.contains(tier)) tier,
    ];
    for (final String tier in present) {
      if (!ordered.contains(tier)) {
        ordered.add(tier);
      }
    }
    return ordered;
  }

  /// Sorted list of distinct primary package names across [entries].
  List<String> get availablePackages {
    final List<String> packages =
        entries.map((StudioCorpusEntry e) => e.package).toSet().toList()
          ..sort();
    return packages;
  }

  /// Filters [entries] by search [query], optional [tier], optional [package],
  /// and [acceptance].
  List<StudioCorpusEntry> filter({
    String query = '',
    String? tier,
    String? package,
    StudioCorpusAcceptanceFilter acceptance = StudioCorpusAcceptanceFilter.all,
  }) {
    return entries.where((StudioCorpusEntry entry) {
      if (tier != null && tier.isNotEmpty && entry.tier != tier) {
        return false;
      }
      if (package != null && package.isNotEmpty && entry.package != package) {
        return false;
      }
      switch (acceptance) {
        case StudioCorpusAcceptanceFilter.all:
          break;
        case StudioCorpusAcceptanceFilter.accepted:
          if (!entry.accepted) {
            return false;
          }
        case StudioCorpusAcceptanceFilter.refused:
          if (entry.accepted) {
            return false;
          }
      }
      return entry.matchesQuery(query);
    }).toList();
  }

  /// Groups [items] according to [grouping] in deterministic key order.
  Map<String, List<StudioCorpusEntry>> groupEntries(
    List<StudioCorpusEntry> items,
    StudioCorpusGrouping grouping,
  ) {
    final Map<String, List<StudioCorpusEntry>> buckets =
        <String, List<StudioCorpusEntry>>{};
    for (final StudioCorpusEntry entry in items) {
      final String key;
      switch (grouping) {
        case StudioCorpusGrouping.tier:
          key = entry.tier;
        case StudioCorpusGrouping.package:
          key = entry.package;
        case StudioCorpusGrouping.acceptance:
          key = entry.acceptanceLabel;
      }
      buckets.putIfAbsent(key, () => <StudioCorpusEntry>[]).add(entry);
    }

    final List<String> sortedKeys;
    switch (grouping) {
      case StudioCorpusGrouping.tier:
        sortedKeys = <String>[
          for (final String tier in canonicalCorpusTiers)
            if (buckets.containsKey(tier)) tier,
          ...buckets.keys.where(
            (String k) => !canonicalCorpusTiers.contains(k),
          ),
        ];
      case StudioCorpusGrouping.package:
        sortedKeys = buckets.keys.toList()..sort();
      case StudioCorpusGrouping.acceptance:
        sortedKeys = <String>[
          if (buckets.containsKey('Accepted')) 'Accepted',
          if (buckets.containsKey('Refused')) 'Refused',
        ];
    }

    return <String, List<StudioCorpusEntry>>{
      for (final String key in sortedKeys) key: buckets[key]!,
    };
  }
}

/// Locates the `tex_math` repository root relative to the current working
/// directory or executable location without hardcoding any filesystem paths.
Directory? findRepositoryRoot({Directory? startDirectory}) {
  final List<Directory> candidates = <Directory>[
    (startDirectory ?? Directory.current).absolute,
  ];
  try {
    final Directory executableParent = File(Platform.resolvedExecutable)
        .parent
        .absolute;
    candidates.add(executableParent);
  } on Object {
    // Ignore executable resolution errors in constrained environments.
  }

  for (final Directory seed in candidates) {
    Directory current = seed;
    for (int depth = 0; depth < 12; depth++) {
      if (_looksLikeRepositoryRoot(current)) {
        return current;
      }
      final Directory parent = current.parent;
      if (parent.path == current.path) {
        break;
      }
      current = parent;
    }
  }
  return null;
}

bool _looksLikeRepositoryRoot(Directory dir) {
  if (!dir.existsSync()) {
    return false;
  }
  final bool hasCorpus =
      Directory('${dir.path}${Platform.pathSeparator}corpus').existsSync() &&
      File(
        '${dir.path}${Platform.pathSeparator}corpus'
        '${Platform.pathSeparator}README.md',
      ).existsSync();
  final bool hasToolOracle = Directory(
    '${dir.path}${Platform.pathSeparator}tool'
    '${Platform.pathSeparator}oracle',
  ).existsSync();
  return hasCorpus || hasToolOracle;
}

/// Loads all `.tex` corpus files and `corpus/expectations.json` dynamically
/// from disk, falling back to [StudioCorpusCatalog.embeddedFallback] outside
/// the repository tree.
final class StudioCorpusLoader {
  const StudioCorpusLoader._();

  /// Discovers and loads the studio corpus catalog relative to [startDirectory]
  /// (defaulting to [Directory.current]).
  static StudioCorpusCatalog load({
    Directory? startDirectory,
    bool includeExpectations = true,
  }) {
    final Directory? repoRoot = findRepositoryRoot(
      startDirectory: startDirectory,
    );
    if (repoRoot == null) {
      return StudioCorpusCatalog.embeddedFallback();
    }

    final Directory corpusDir = Directory(
      '${repoRoot.path}${Platform.pathSeparator}corpus',
    );
    if (!corpusDir.existsSync()) {
      return StudioCorpusCatalog.embeddedFallback();
    }

    final List<File> texFiles =
        corpusDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((File file) => file.path.endsWith('.tex'))
            .toList()
          ..sort((File a, File b) => a.path.compareTo(b.path));

    if (texFiles.isEmpty) {
      return StudioCorpusCatalog.embeddedFallback();
    }

    final Map<String, Map<String, Object?>> expectationsById =
        includeExpectations
        ? _loadExpectationsMap(corpusDir)
        : const <String, Map<String, Object?>>{};

    final List<StudioCorpusEntry> entries = <StudioCorpusEntry>[];
    final String corpusRootNorm = _normalizeSlashes(corpusDir.absolute.path);

    for (final File file in texFiles) {
      final String absNorm = _normalizeSlashes(file.absolute.path);
      final String relativeToCorpus = absNorm.startsWith('$corpusRootNorm/')
          ? absNorm.substring(corpusRootNorm.length + 1)
          : absNorm;
      final String relativePath = 'corpus/$relativeToCorpus';
      final StudioCorpusEntry? parsed = _parseCorpusFile(
        file,
        relativePath,
        expectationsById,
      );
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    if (entries.isEmpty) {
      return StudioCorpusCatalog.embeddedFallback();
    }

    entries.sort((StudioCorpusEntry a, StudioCorpusEntry b) {
      final int tierCmp = _tierOrder(a.tier).compareTo(_tierOrder(b.tier));
      if (tierCmp != 0) {
        return tierCmp;
      }
      return a.id.compareTo(b.id);
    });

    return StudioCorpusCatalog(
      entries: entries,
      isFromDisk: true,
      corpusRootPath: corpusDir.path,
    );
  }

  static int _tierOrder(String tier) {
    final int index = canonicalCorpusTiers.indexOf(tier);
    return index >= 0 ? index : canonicalCorpusTiers.length;
  }

  static Map<String, Map<String, Object?>> _loadExpectationsMap(
    Directory corpusDir,
  ) {
    final File expectationsFile = File(
      '${corpusDir.path}${Platform.pathSeparator}expectations.json',
    );
    if (!expectationsFile.existsSync()) {
      return const <String, Map<String, Object?>>{};
    }
    try {
      final Object? decoded = jsonDecode(expectationsFile.readAsStringSync());
      if (decoded is! Map<String, Object?>) {
        return const <String, Map<String, Object?>>{};
      }
      final Object? rawCases = decoded['cases'];
      if (rawCases is! Map<String, Object?>) {
        return const <String, Map<String, Object?>>{};
      }
      final Map<String, Map<String, Object?>> result =
          <String, Map<String, Object?>>{};
      for (final MapEntry<String, Object?> entry in rawCases.entries) {
        final Object? value = entry.value;
        if (value is Map<String, Object?>) {
          result[entry.key] = value;
        }
      }
      return result;
    } on Object {
      return const <String, Map<String, Object?>>{};
    }
  }

  static StudioCorpusEntry? _parseCorpusFile(
    File file,
    String relativePath,
    Map<String, Map<String, Object?>> expectationsById,
  ) {
    try {
      final List<String> lines = file.readAsLinesSync();
      final Map<String, String> headers = <String, String>{};
      final RegExp headerPattern = RegExp(r'^%\s*([a-zA-Z0-9_]+)\s*:\s*(.*)$');

      int bodyStart = 0;
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        final RegExpMatch? match = headerPattern.firstMatch(line);
        if (match != null) {
          headers[match.group(1)!.trim().toLowerCase()] = match
              .group(2)!
              .trim();
          bodyStart = i + 1;
          continue;
        }
        if (line.trim().isEmpty && headers.isNotEmpty) {
          bodyStart = i + 1;
          continue;
        }
        break;
      }

      final String tex = lines.sublist(bodyStart).join('\n').trim();
      if (tex.isEmpty) {
        return null;
      }

      final String id = headers['id']?.isNotEmpty == true
          ? headers['id']!
          : relativePath
                .replaceFirst('corpus/', '')
                .replaceFirst(RegExp(r'\.tex$'), '');
      final String rawTier = headers['tier'] ?? '';
      final String tier = _canonicalizeTier(rawTier, relativePath);
      final String package = headers['package']?.isNotEmpty == true
          ? headers['package']!
          : 'base';
      final String feature = headers['feature']?.isNotEmpty == true
          ? headers['feature']!
          : 'general';
      final String displayRaw = (headers['display'] ?? 'display').toLowerCase();
      final bool display = displayRaw == 'display' || displayRaw == 'true';
      final String acceptedRaw = (headers['accepted'] ?? 'true').toLowerCase();
      final bool accepted = acceptedRaw != 'false';
      final String? errorClass = headers['error_class'];
      final String? packagesRaw = headers['packages'];
      final List<String>? packages = packagesRaw == null || packagesRaw.isEmpty
          ? null
          : packagesRaw
                .split(',')
                .map((String item) => item.trim())
                .where((String item) => item.isNotEmpty)
                .toList();

      final Map<String, Object?>? expectation = expectationsById[id];
      final String? expectationStatus =
          expectation?['texMathStatus'] as String?;
      final Object? rawBox = expectation?['box'];
      double? boxW;
      double? boxH;
      double? boxD;
      if (rawBox is Map<String, Object?>) {
        boxW = _toDoubleOrNull(rawBox['width']);
        boxH = _toDoubleOrNull(rawBox['height']);
        boxD = _toDoubleOrNull(rawBox['depth']);
      }

      return StudioCorpusEntry(
        id: id,
        relativePath: relativePath,
        tier: tier,
        package: package,
        feature: feature,
        display: display,
        accepted: accepted,
        tex: tex,
        errorClass: errorClass,
        packages: packages,
        expectationStatus: expectationStatus,
        oracleBoxWidthEm: boxW,
        oracleBoxHeightEm: boxH,
        oracleBoxDepthEm: boxD,
      );
    } on Object {
      return null;
    }
  }

  static String _canonicalizeTier(String rawTier, String relativePath) {
    final String normalized = rawTier.trim().toLowerCase().replaceAll('_', ' ');
    switch (normalized) {
      case '1':
      case 'tier 1':
      case 'tier1':
      case 'tier1 core':
        return 'Tier 1';
      case '2':
      case 'tier 2':
      case 'tier2':
      case 'tier2 jupyter':
        return 'Tier 2';
      case '3':
      case 'tier 3':
      case 'tier3':
      case 'tier3 extended':
        return 'Tier 3';
      case 'stretchy':
        return 'Stretchy';
      case 'notebooks':
      case 'notebook':
        return 'Notebooks';
      case 'errors':
      case 'error':
        return 'Errors';
    }
    final String lowerPath = relativePath.toLowerCase();
    if (lowerPath.contains('tier1')) {
      return 'Tier 1';
    }
    if (lowerPath.contains('tier2')) {
      return 'Tier 2';
    }
    if (lowerPath.contains('tier3')) {
      return 'Tier 3';
    }
    if (lowerPath.contains('stretchy')) {
      return 'Stretchy';
    }
    if (lowerPath.contains('notebook')) {
      return 'Notebooks';
    }
    if (lowerPath.contains('error')) {
      return 'Errors';
    }
    return 'Tier 1';
  }

  static double? _toDoubleOrNull(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return null;
  }

  static String _normalizeSlashes(String path) => path.replaceAll('\\', '/');
}
