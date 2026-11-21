import 'dart:convert';
import 'dart:io';

/// Ordered canonical tier names used across coverage reports.
const List<String> canonicalTiers = <String>[
  'Tier 1',
  'Tier 2',
  'Tier 3',
  'Stretchy',
  'Notebooks',
  'Errors',
];

/// A parsed `.tex` corpus test case.
final class CorpusCase {
  /// Creates a parsed corpus test case.
  const CorpusCase({
    required this.id,
    required this.relativePath,
    required this.tier,
    required this.rawTier,
    required this.package,
    required this.feature,
    required this.display,
    required this.accepted,
    required this.tex,
    this.errorClass,
    this.packages,
  });

  /// Stable case identifier (e.g. `tier1_core/base/fraction_basic`).
  final String id;

  /// Forward-slash path relative to repository root.
  final String relativePath;

  /// Canonical tier name (`Tier 1`, `Tier 2`, `Tier 3`, `Stretchy`, `Notebooks`, `Errors`).
  final String tier;

  /// Raw `% tier:` header value from the `.tex` file.
  final String rawTier;

  /// Primary TeX package under test.
  final String package;

  /// Feature group within the package or category.
  final String feature;

  /// Whether the case renders in display mode (`true`) or inline mode (`false`).
  final bool display;

  /// Whether the MathJax oracle expects this expression to be accepted.
  final bool accepted;

  /// Expected error class name when [accepted] is `false`.
  final String? errorClass;

  /// Optional explicit MathJax package list when non-default packages apply.
  final List<String>? packages;

  /// TeX source expression body.
  final String tex;
}

/// Loads and validates all `.tex` corpus cases under [corpusDir].
List<CorpusCase> loadCorpus({String corpusDir = 'corpus'}) {
  final Directory root = Directory(corpusDir);
  if (!root.existsSync()) {
    throw StateError('Missing corpus directory: $corpusDir');
  }

  final List<File> texFiles =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.tex'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  if (texFiles.isEmpty) {
    throw StateError('No .tex corpus files found under $corpusDir');
  }

  final List<CorpusCase> cases = <CorpusCase>[];
  final Set<String> seenIds = <String>{};

  for (final File file in texFiles) {
    final String relativePath = _normalizePath(file.path);
    final CorpusCase parsed = _parseCorpusFile(file, relativePath);
    if (!seenIds.add(parsed.id)) {
      throw FormatException(
        'Duplicate corpus case id "${parsed.id}" in $relativePath',
      );
    }
    cases.add(parsed);
  }

  return cases;
}

CorpusCase _parseCorpusFile(File file, String relativePath) {
  final List<String> lines = file.readAsLinesSync();
  final Map<String, String> headers = <String, String>{};
  final RegExp headerPattern = RegExp(r'^%\s*([a-zA-Z0-9_]+)\s*:\s*(.*)$');

  int bodyStart = 0;
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final RegExpMatch? match = headerPattern.firstMatch(line);
    if (match != null) {
      headers[match.group(1)!.trim().toLowerCase()] = match.group(2)!.trim();
      bodyStart = i + 1;
      continue;
    }
    if (line.trim().isEmpty && headers.isNotEmpty) {
      bodyStart = i + 1;
      continue;
    }
    break;
  }

  String requireHeader(String key) {
    final String? value = headers[key];
    if (value == null || value.isEmpty) {
      throw FormatException('Missing "% $key:" metadata in $relativePath');
    }
    return value;
  }

  final String id = requireHeader('id');
  final String rawTier = requireHeader('tier');
  final String package = requireHeader('package');
  final String feature = requireHeader('feature');
  final String displayRaw = requireHeader('display').toLowerCase();
  final String acceptedRaw = requireHeader('accepted').toLowerCase();

  final bool display;
  if (displayRaw == 'display' || displayRaw == 'true') {
    display = true;
  } else if (displayRaw == 'inline' || displayRaw == 'false') {
    display = false;
  } else {
    throw FormatException(
      'Invalid "% display: $displayRaw" in $relativePath '
      '(expected display, inline, true, or false).',
    );
  }

  final bool accepted;
  if (acceptedRaw == 'true') {
    accepted = true;
  } else if (acceptedRaw == 'false') {
    accepted = false;
  } else {
    throw FormatException(
      'Invalid "% accepted: $acceptedRaw" in $relativePath '
      '(expected true or false).',
    );
  }

  final String? errorClass = headers['error_class'];
  final String? packagesRaw = headers['packages'];
  final List<String>? packages = packagesRaw == null || packagesRaw.isEmpty
      ? null
      : packagesRaw
            .split(',')
            .map((String item) => item.trim())
            .where((String item) => item.isNotEmpty)
            .toList();

  final String tex = lines.sublist(bodyStart).join('\n').trim();
  if (tex.isEmpty) {
    throw FormatException('Empty TeX body in $relativePath');
  }

  return CorpusCase(
    id: id,
    relativePath: relativePath,
    tier: canonicalizeTier(rawTier, relativePath),
    rawTier: rawTier,
    package: package,
    feature: feature,
    display: display,
    accepted: accepted,
    errorClass: errorClass,
    packages: packages,
    tex: tex,
  );
}

/// Maps raw tier metadata or file path prefixes to canonical coverage tier names.
String canonicalizeTier(String rawTier, String relativePath) {
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
  throw FormatException('Unknown tier "$rawTier" in $relativePath');
}

String _normalizePath(String path) {
  final String normalized = path.replaceAll('\\', '/');
  return normalized.startsWith('./') ? normalized.substring(2) : normalized;
}

/// Reads and decodes `corpus/expectations.json`.
Map<String, Object?> loadExpectationsJson({
  String path = 'corpus/expectations.json',
}) {
  final File file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Missing $path; run `dart run tool/verify_against_mathjax.dart '
      '--update-expectations` first.',
    );
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}
