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

    overall.record(eval.outcome);
    byTier.putIfAbsent(c.tier, _Counts.new).record(eval.outcome);

    final _PackageAggregate pkgAgg = byPackage.putIfAbsent(
      c.package,
      () => _PackageAggregate(package: c.package),
    );
    pkgAgg.tiers.add(c.tier);
    pkgAgg.counts.record(eval.outcome);

    final String featureKey = '${c.tier}\u0000${c.package}\u0000${c.feature}';
    final _FeatureAggregate featAgg = byFeature.putIfAbsent(
      featureKey,
      () => _FeatureAggregate(
        tier: c.tier,
        package: c.package,
        feature: c.feature,
      ),
    );
    featAgg.counts.record(eval.outcome);
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
      'OracleAccepted=$oracleAcceptedCount, '
      'OracleRefused=$oracleRefusedCount, '
      'Pass=${overall.pass}, '
      'Differs=${overall.differs}, '
      'Unsupported=${overall.unsupported}, '
      'RefusedMatch=${overall.refusedMatch}, '
      'Pass%=${overall.passPercentFormatted}',
    );
    for (final String tier in byTier.keys) {
      final _Counts c = byTier[tier]!;
      stdout.writeln(
        '  $tier: Pass=${c.pass}, Differs=${c.differs}, '
        'Unsupported=${c.unsupported}, RefusedMatch=${c.refusedMatch}, '
        'Total=${c.total}, Pass%=${c.passPercentFormatted}',
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
  final StringBuffer out = StringBuffer()
    ..writeln('# Corpus Coverage Matrix')
    ..writeln()
    ..writeln(
      'This report is generated by `tool/coverage_report.dart` against '
      '`corpus/expectations.json` (pinned MathJax `$mathjaxVersion` with '
      '`$fontName`, comparison tolerance `${toleranceEm.toStringAsFixed(2)}em`) '
      'and live `TexMathEngine` execution.',
    )
    ..writeln()
    ..writeln(
      'Phase 1 establishes the pure-Dart public API, safety budgets, AST, and '
      'display list contracts, so `TexMathEngine.render` raises '
      '`TexMathUnsupportedError` across expressions within input-length '
      'limits. Passing and refused-match counts advance as parser, macro '
      'expansion, and Appendix G OpenType `MATH` layout stages land in '
      'subsequent phases. `Pass %` measures `(Pass + Refused Match) / Total`.',
    )
    ..writeln()
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| Metric | Count |')
    ..writeln('| :--- | ---: |')
    ..writeln('| Total Corpus Cases | ${overall.total} |')
    ..writeln('| Oracle Accepted | $oracleAcceptedCount |')
    ..writeln('| Oracle Refused | $oracleRefusedCount |')
    ..writeln('| Pass | ${overall.pass} |')
    ..writeln('| Differs | ${overall.differs} |')
    ..writeln('| Unsupported | ${overall.unsupported} |')
    ..writeln('| Refused Match | ${overall.refusedMatch} |')
    ..writeln('| Pass % | ${overall.passPercentFormatted} |')
    ..writeln()
    ..writeln('## Coverage by Tier')
    ..writeln()
    ..writeln(
      '| Tier | Pass | Differs | Unsupported | Refused Match | Total | Pass % |',
    )
    ..writeln('| :--- | ---: | ---: | ---: | ---: | ---: | ---: |');

  final List<String> orderedTiers = byTier.keys.toList()
    ..sort((String a, String b) => _tierOrder(a).compareTo(_tierOrder(b)));
  for (final String tier in orderedTiers) {
    final _Counts c = byTier[tier]!;
    out.writeln(
      '| $tier | ${c.pass} | ${c.differs} | ${c.unsupported} '
      '| ${c.refusedMatch} | ${c.total} | ${c.passPercentFormatted} |',
    );
  }
  out.writeln(
    '| **Total** | **${overall.pass}** | **${overall.differs}** '
    '| **${overall.unsupported}** | **${overall.refusedMatch}** '
    '| **${overall.total}** | **${overall.passPercentFormatted}** |',
  );

  out
    ..writeln()
    ..writeln('## Coverage by Package')
    ..writeln()
    ..writeln(
      '| Package | Tiers | Pass | Differs | Unsupported | Refused Match | Total | Pass % |',
    )
    ..writeln('| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final _PackageAggregate pkg in packages) {
    final List<String> sortedTiers = pkg.tiers.toList()
      ..sort((String a, String b) => _tierOrder(a).compareTo(_tierOrder(b)));
    final _Counts c = pkg.counts;
    out.writeln(
      '| `${pkg.package}` | ${sortedTiers.join(', ')} | ${c.pass} '
      '| ${c.differs} | ${c.unsupported} | ${c.refusedMatch} '
      '| ${c.total} | ${c.passPercentFormatted} |',
    );
  }

  out
    ..writeln()
    ..writeln('## Coverage by Feature')
    ..writeln()
    ..writeln(
      '| Tier | Package | Feature | Pass | Differs | Unsupported | Refused Match | Total | Pass % |',
    )
    ..writeln(
      '| :--- | :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |',
    );

  for (final _FeatureAggregate feat in features) {
    final _Counts c = feat.counts;
    out.writeln(
      '| ${feat.tier} | `${feat.package}` | `${feat.feature}` '
      '| ${c.pass} | ${c.differs} | ${c.unsupported} | ${c.refusedMatch} '
      '| ${c.total} | ${c.passPercentFormatted} |',
    );
  }

  return out.toString();
}

int _tierOrder(String tier) {
  final int index = canonicalTiers.indexOf(tier);
  return index == -1 ? canonicalTiers.length : index;
}

double _round2(double value) => (value * 100.0).roundToDouble() / 100.0;

final class _Counts {
  int pass = 0;
  int differs = 0;
  int unsupported = 0;
  int refusedMatch = 0;

  int get total => pass + differs + unsupported + refusedMatch;

  double get passPercent =>
      total == 0 ? 0.0 : ((pass + refusedMatch) * 100.0) / total;

  String get passPercentFormatted => '${passPercent.toStringAsFixed(1)}%';

  void record(EngineOutcome outcome) {
    switch (outcome) {
      case EngineOutcome.pass:
        pass++;
      case EngineOutcome.differs:
        differs++;
      case EngineOutcome.unsupported:
      case EngineOutcome.budgetError:
        unsupported++;
      case EngineOutcome.refusedMatch:
        refusedMatch++;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
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
