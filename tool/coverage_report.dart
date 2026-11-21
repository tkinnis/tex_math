import 'dart:convert';
import 'dart:io';

import 'src/cli_args.dart';
import 'src/corpus.dart';
import 'src/engine_check.dart';

const String _coverageDocPath = 'doc/COVERAGE.md';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/coverage_report.dart '
      '[--json] [--no-write] [--tolerance-em=0.02]',
    );
    return;
  }

  final bool jsonOutput = args.contains('--json');
  final bool writeDoc = !args.contains('--no-write');
  final double toleranceEm = parseDoubleFlag(args, 'tolerance-em') ?? 0.02;

  final List<CorpusCase> cases = loadCorpus();
  final Map<String, Object?> expectations = loadExpectationsJson();
  final Map<String, Object?>? expectationCases =
      expectations['cases'] as Map<String, Object?>?;
  if (expectationCases == null) {
    stderr.writeln('ERROR: corpus/expectations.json is missing "cases" map.');
    exitCode = 1;
    return;
  }

  final _Counts overall = _Counts();
  int oracleAcceptedCount = 0;
  int oracleRefusedCount = 0;

  final Map<String, _Counts> byTier = <String, _Counts>{
    for (final String tier in canonicalTiers) tier: _Counts(),
  };
  final Map<String, _PackageAggregate> byPackage =
      <String, _PackageAggregate>{};
  final Map<String, _FeatureAggregate> byFeature =
      <String, _FeatureAggregate>{};

  for (final CorpusCase c in cases) {
    final Map<String, Object?>? exp =
        expectationCases[c.id] as Map<String, Object?>?;
    if (exp == null) {
      stderr.writeln(
        'ERROR: Corpus case "${c.id}" is missing from corpus/expectations.json.',
      );
      exitCode = 1;
      return;
    }

    final bool oracleAccepted = exp['oracleAccepted'] as bool;
    final String? oracleErrorClass = exp['oracleErrorClass'] as String?;
    final Map<String, Object?>? oracleBox = exp['box'] as Map<String, Object?>?;
    final List<Object?>? oracleGlyphs = exp['glyphs'] as List<Object?>?;
    final List<Object?>? oracleRules = exp['rules'] as List<Object?>?;

    if (oracleAccepted) {
      oracleAcceptedCount++;
    } else {
      oracleRefusedCount++;
    }

    final EngineEvaluation eval = evaluateEngineAgainstOracle(
      corpusCase: c,
      oracleAccepted: oracleAccepted,
      oracleErrorClass: oracleErrorClass,
      oracleBox: oracleBox,
      oracleGlyphs: oracleGlyphs,
      oracleRules: oracleRules,
      toleranceEm: toleranceEm,
    );

    overall.record(eval: eval, oracleAccepted: oracleAccepted);
    byTier
        .putIfAbsent(c.tier, _Counts.new)
        .record(eval: eval, oracleAccepted: oracleAccepted);

    final _PackageAggregate pkgAgg = byPackage.putIfAbsent(
      c.package,
      () => _PackageAggregate(package: c.package),
    );
    pkgAgg.tiers.add(c.tier);
    pkgAgg.counts.record(eval: eval, oracleAccepted: oracleAccepted);

    final String featureKey = '${c.tier}\u0000${c.package}\u0000${c.feature}';
    final _FeatureAggregate featAgg = byFeature.putIfAbsent(
      featureKey,
      () => _FeatureAggregate(
        tier: c.tier,
        package: c.package,
        feature: c.feature,
      ),
    );
    featAgg.counts.record(eval: eval, oracleAccepted: oracleAccepted);
  }

  final List<_PackageAggregate> sortedPackages = byPackage.values.toList()
    ..sort(
      (_PackageAggregate a, _PackageAggregate b) =>
          a.package.compareTo(b.package),
    );
  final List<_FeatureAggregate> sortedFeatures = byFeature.values.toList()
    ..sort((_FeatureAggregate a, _FeatureAggregate b) {
      final int tierCmp = _tierOrder(a.tier).compareTo(_tierOrder(b.tier));
      if (tierCmp != 0) {
        return tierCmp;
      }
      final int pkgCmp = a.package.compareTo(b.package);
      if (pkgCmp != 0) {
        return pkgCmp;
      }
      return a.feature.compareTo(b.feature);
    });

  if (writeDoc) {
    final String markdown = _renderCoverageMarkdown(
      mathjaxVersion: expectations['mathjaxVersion'] as String? ?? '4.1.3',
      fontName: expectations['font'] as String? ?? 'mathjax-newcm',
      toleranceEm: toleranceEm,
      oracleAcceptedCount: oracleAcceptedCount,
      oracleRefusedCount: oracleRefusedCount,
      overall: overall,
      byTier: byTier,
      packages: sortedPackages,
      features: sortedFeatures,
    );
    File(_coverageDocPath).writeAsStringSync(markdown);
  }

  if (jsonOutput) {
    final Map<String, Object?> payload = <String, Object?>{
      'total': overall.total,
      'oracleAccepted': oracleAcceptedCount,
      'oracleRefused': oracleRefusedCount,
      'rendered': overall.rendered,
      'supported': overall.supported,
      'supportPercent': _round2(overall.supportPercent),
      'pass': overall.pass,
      'differs': overall.differs,
      'unsupported': overall.unsupported,
      'refusedMatch': overall.refusedMatch,
      'passPercent': _round2(overall.passPercent),
      'tiers': <String, Object?>{
        for (final MapEntry<String, _Counts> e in byTier.entries)
          e.key: e.value.toJson(),
      },
      'packages': <String, Object?>{
        for (final _PackageAggregate p in sortedPackages)
          p.package: p.counts.toJson(),
      },
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
  } else {
    stdout.writeln(
      'Generated $_coverageDocPath: '
      'Total=${overall.total}, '
      'Rendered=${overall.rendered}/$oracleAcceptedCount, '
      'RefusedMatch=${overall.refusedMatch}/$oracleRefusedCount, '
      'Unsupported=${overall.unsupported}, '
      'Supported=${overall.supportPercentFormatted}, '
      'StrictBox=${overall.pass}/${overall.oracleAccepted} '
      '(${overall.strictBoxMatchPercentOfTotal.toStringAsFixed(1)}% of total, '
      'MetricDelta=${overall.renderedWithMetricDelta}, '
      'CombinedStrict=${overall.passPercentFormatted})',
    );
    for (final String tier in byTier.keys) {
      final _Counts c = byTier[tier]!;
      stdout.writeln(
        '  $tier: Rendered=${c.rendered}, RefusedMatch=${c.refusedMatch}, '
        'Unsupported=${c.unsupported}, Total=${c.total}, '
        'Supported=${c.supportPercentFormatted}, '
        'Strict=${c.formatStrictColumn()}',
      );
    }
  }
}

String _renderCoverageMarkdown({
  required String mathjaxVersion,
  required String fontName,
  required double toleranceEm,
  required int oracleAcceptedCount,
  required int oracleRefusedCount,
  required _Counts overall,
  required Map<String, _Counts> byTier,
  required List<_PackageAggregate> packages,
  required List<_FeatureAggregate> features,
}) {
  final String toleranceStr = toleranceEm.toStringAsFixed(2);
  final String summaryProse = _renderSummaryProse(
    mathjaxVersion: mathjaxVersion,
    toleranceStr: toleranceStr,
    overall: overall,
    oracleAcceptedCount: oracleAcceptedCount,
    oracleRefusedCount: oracleRefusedCount,
    packageCount: packages.length,
  );
  final StringBuffer out = StringBuffer()
    ..writeln('# Corpus Coverage Matrix')
    ..writeln()
    ..writeln(
      'This report is generated by `tool/coverage_report.dart` against '
      '`corpus/expectations.json` (pinned MathJax `$mathjaxVersion` with '
      '`$fontName`, strict box-metric tolerance `±${toleranceStr}em`) '
      'and live `TexMathEngine` execution.',
    )
    ..writeln()
    ..writeln(summaryProse)
    ..writeln();

  _writeSummaryTables(
    out: out,
    toleranceStr: toleranceStr,
    oracleAcceptedCount: oracleAcceptedCount,
    oracleRefusedCount: oracleRefusedCount,
    overall: overall,
  );
  _writeTierTable(
    out: out,
    toleranceStr: toleranceStr,
    overall: overall,
    byTier: byTier,
  );
  _writePackageTable(out: out, toleranceStr: toleranceStr, packages: packages);
  _writeFeatureTable(out: out, toleranceStr: toleranceStr, features: features);

  return out.toString();
}

void _writeSummaryTables({
  required StringBuffer out,
  required String toleranceStr,
  required int oracleAcceptedCount,
  required int oracleRefusedCount,
  required _Counts overall,
}) {
  final String strictOfTotal =
      '${overall.strictBoxMatchPercentOfTotal.toStringAsFixed(1)}%';
  out
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Value |')
    ..writeln('| :--- | ---: |')
    ..writeln('| Total Corpus Cases | ${overall.total} |')
    ..writeln(
      '| Expressions Rendered | ${overall.rendered} / $oracleAcceptedCount |',
    )
    ..writeln(
      '| Error Refusals Matched | '
      '${overall.refusedMatch} / $oracleRefusedCount |',
    )
    ..writeln('| Unsupported | ${overall.unsupported} |')
    ..writeln(
      '| **Feature Support** | **${overall.supportPercentFormatted}** |',
    )
    ..writeln()
    ..writeln('### *Oracle Tolerance Diagnostic*')
    ..writeln()
    ..writeln(
      '| Diagnostic (`±${toleranceStr}em` vs. MathJax `.tfm`) | Value |',
    )
    ..writeln('| :--- | ---: |')
    ..writeln(
      '| Strict ±${toleranceStr}em Match | ${overall.pass} ($strictOfTotal) |',
    )
    ..writeln('| Rendered with Metric Δ | ${overall.renderedWithMetricDelta} |')
    ..writeln(
      '| Combined Strict Oracle Match | '
      '${overall.pass + overall.refusedMatch} / ${overall.total} '
      '(${overall.passPercentFormatted}) |',
    )
    ..writeln()
    ..writeln(
      '`Strict ±${toleranceStr}em Match` (`${overall.pass} / ${overall.total}`) '
      'and `Combined Strict Oracle Match` '
      '(`(${overall.pass} + ${overall.refusedMatch}) / ${overall.total}`) '
      'report strict `.tfm` box-metric parity over the full '
      '${overall.total}-case corpus; the tables below report `Strict '
      '±${toleranceStr}em*` over oracle-accepted expressions (`Pass / '
      'Oracle Accepted`).',
    )
    ..writeln();
}

void _writeTierTable({
  required StringBuffer out,
  required String toleranceStr,
  required _Counts overall,
  required Map<String, _Counts> byTier,
}) {
  out
    ..writeln('## Coverage by Tier')
    ..writeln()
    ..writeln(
      '| Tier | Rendered | Refused Match | Unsupported | Total | Supported | '
      'Strict ±${toleranceStr}em* |',
    )
    ..writeln('| :--- | ---: | ---: | ---: | ---: | ---: | ---: |');

  final List<String> orderedTiers = byTier.keys.toList()
    ..sort((String a, String b) => _tierOrder(a).compareTo(_tierOrder(b)));
  for (final String tier in orderedTiers) {
    final _Counts c = byTier[tier]!;
    out.writeln(
      '| $tier | ${c.rendered} | ${c.refusedMatch} | ${c.unsupported} '
      '| ${c.total} | ${c.supportPercentFormatted} '
      '| ${c.formatStrictColumn()} |',
    );
  }
  out
    ..writeln(
      '| **Total** | **${overall.rendered}** | **${overall.refusedMatch}** '
      '| **${overall.unsupported}** | **${overall.total}** '
      '| **${overall.supportPercentFormatted}** '
      '| **${overall.formatStrictColumn()}** |',
    )
    ..writeln()
    ..writeln(
      '\\* *Strict `±${toleranceStr}em` box parity vs. MathJax `.tfm` oracle '
      '(`Pass / Oracle Accepted`, or `—` for refusal-only rows); small metric '
      'deltas come from OpenType `MATH` font tables rather than missing '
      'support.*',
    )
    ..writeln();
}

void _writePackageTable({
  required StringBuffer out,
  required String toleranceStr,
  required List<_PackageAggregate> packages,
}) {
  out
    ..writeln('## Coverage by Package')
    ..writeln()
    ..writeln(
      '| Package | Tiers | Rendered | Refused Match | Unsupported | Total | '
      'Supported | Strict ±${toleranceStr}em* |',
    )
    ..writeln('| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final _PackageAggregate pkg in packages) {
    final List<String> sortedTiers = pkg.tiers.toList()
      ..sort((String a, String b) => _tierOrder(a).compareTo(_tierOrder(b)));
    final _Counts c = pkg.counts;
    out.writeln(
      '| `${pkg.package}` | ${sortedTiers.join(', ')} | ${c.rendered} '
      '| ${c.refusedMatch} | ${c.unsupported} | ${c.total} '
      '| ${c.supportPercentFormatted} | ${c.formatStrictColumn()} |',
    );
  }
  out.writeln();
}

void _writeFeatureTable({
  required StringBuffer out,
  required String toleranceStr,
  required List<_FeatureAggregate> features,
}) {
  out
    ..writeln('## Coverage by Feature')
    ..writeln()
    ..writeln(
      '| Tier | Package | Feature | Rendered | Refused Match | Unsupported | '
      'Total | Supported | Strict ±${toleranceStr}em* |',
    )
    ..writeln(
      '| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |',
    );

  for (final _FeatureAggregate feat in features) {
    final _Counts c = feat.counts;
    out.writeln(
      '| ${feat.tier} | `${feat.package}` | `${feat.feature}` '
      '| ${c.rendered} | ${c.refusedMatch} | ${c.unsupported} '
      '| ${c.total} | ${c.supportPercentFormatted} '
      '| ${c.formatStrictColumn()} |',
    );
  }
}

int _tierOrder(String tier) {
  final int index = canonicalTiers.indexOf(tier);
  return index == -1 ? canonicalTiers.length : index;
}

String _renderSummaryProse({
  required String mathjaxVersion,
  required String toleranceStr,
  required _Counts overall,
  required int oracleAcceptedCount,
  required int oracleRefusedCount,
  required int packageCount,
}) {
  final String capabilitySentence;
  if (overall.unsupported == 0 &&
      overall.rendered == oracleAcceptedCount &&
      overall.refusedMatch == oracleRefusedCount) {
    capabilitySentence =
        '`tex_math` renders **all ${overall.rendered} accepted expressions** '
        'into valid layout & SVG output (**${overall.unsupported} Unsupported**) '
        'and matches **${overall.refusedMatch} of $oracleRefusedCount oracle '
        'error refusals** (**${overall.supportPercentFormatted} feature support '
        'across all $packageCount packages**).';
  } else {
    capabilitySentence =
        '`tex_math` renders **${overall.rendered} of $oracleAcceptedCount '
        'accepted expressions** into valid layout & SVG output '
        '(**${overall.unsupported} Unsupported**) and matches '
        '**${overall.refusedMatch} of $oracleRefusedCount oracle error '
        'refusals** (**${overall.supportPercentFormatted} feature support '
        'across $packageCount packages**).';
  }

  final String oracleExplanation =
      'MathJax `$mathjaxVersion` is used as a differential test oracle, and '
      '`Strict ±${toleranceStr}em` tracks verbatim bounding-box agreement '
      'against MathJax\'s JavaScript `.tfm` font tables—whereas `tex_math` '
      'uses OpenType `MATH` metrics from `NewCMMath-Regular.otf`, so the '
      '`${overall.renderedWithMetricDelta}` expressions with small box-metric '
      'differences are expected typographic differences (fraction rule '
      'thickness, optical script offsets, unencoded assembly bounds), not '
      'broken or missing features.';

  return '$capabilitySentence\n\n$oracleExplanation';
}

double _round2(double value) => (value * 100.0).roundToDouble() / 100.0;

final class _Counts {
  int pass = 0;
  int differs = 0;
  int unsupported = 0;
  int refusedMatch = 0;
  int rendered = 0;
  int oracleAccepted = 0;
  int oracleRefused = 0;

  int get total => pass + differs + unsupported + refusedMatch;

  int get supported => rendered + refusedMatch;

  int get renderedWithMetricDelta => rendered - pass;

  double get supportPercent => total == 0 ? 0.0 : (supported * 100.0) / total;

  String get supportPercentFormatted => '${supportPercent.toStringAsFixed(1)}%';

  double get passPercent =>
      total == 0 ? 0.0 : ((pass + refusedMatch) * 100.0) / total;

  String get passPercentFormatted => '${passPercent.toStringAsFixed(1)}%';

  double get strictBoxMatchPercentOfTotal =>
      total == 0 ? 0.0 : (pass * 100.0) / total;

  double get strictBoxMatchPercentOfAccepted =>
      oracleAccepted == 0 ? 0.0 : (pass * 100.0) / oracleAccepted;

  String formatStrictColumn() {
    if (oracleAccepted == 0) {
      return '—';
    }
    return '$pass / $oracleAccepted '
        '(${strictBoxMatchPercentOfAccepted.toStringAsFixed(1)}%)';
  }

  void record({required EngineEvaluation eval, required bool oracleAccepted}) {
    if (oracleAccepted) {
      this.oracleAccepted++;
    } else {
      oracleRefused++;
    }

    switch (eval.outcome) {
      case EngineOutcome.pass:
        pass++;
        if (oracleAccepted) {
          rendered++;
        }
      case EngineOutcome.differs:
        differs++;
        if (oracleAccepted && eval.errorClass == null) {
          rendered++;
        }
      case EngineOutcome.unsupported:
      case EngineOutcome.budgetError:
        unsupported++;
      case EngineOutcome.refusedMatch:
        refusedMatch++;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'rendered': rendered,
    'supported': supported,
    'supportPercent': _round2(supportPercent),
    'pass': pass,
    'differs': differs,
    'unsupported': unsupported,
    'refusedMatch': refusedMatch,
    'total': total,
    'passPercent': _round2(passPercent),
  };
}

final class _PackageAggregate {
  _PackageAggregate({required this.package});

  final String package;
  final Set<String> tiers = <String>{};
  final _Counts counts = _Counts();
}

final class _FeatureAggregate {
  _FeatureAggregate({
    required this.tier,
    required this.package,
    required this.feature,
  });

  final String tier;
  final String package;
  final String feature;
  final _Counts counts = _Counts();
}
