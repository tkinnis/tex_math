import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'src/cli_args.dart';
import 'src/corpus.dart';
import 'src/engine_check.dart';

const String _expectationsPath = 'corpus/expectations.json';
const String _oracleScriptPath = 'tool/oracle/render.mjs';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/verify_against_mathjax.dart '
      '[--update-expectations] [--tolerance-em=0.02]',
    );
    return;
  }

  final bool updateExpectations = args.contains('--update-expectations');
  final double toleranceEm = parseDoubleFlag(args, 'tolerance-em') ?? 0.02;

  final List<CorpusCase> cases = loadCorpus();
  final Map<String, Object?> oraclePayload = await _runOracle(cases);
  final String mathjaxVersion =
      oraclePayload['mathjaxVersion'] as String? ?? 'unknown';
  final String fontName = oraclePayload['font'] as String? ?? 'unknown';
  final List<Object?> rawResults =
      oraclePayload['results'] as List<Object?>? ?? <Object?>[];

  final Map<String, Map<String, Object?>> oracleById =
      <String, Map<String, Object?>>{};
  for (final Object? item in rawResults) {
    final Map<String, Object?> map = item as Map<String, Object?>;
    oracleById[map['id'] as String] = map;
  }

  if (updateExpectations) {
    final bool ok = _writeExpectations(
      cases: cases,
      oracleById: oracleById,
      mathjaxVersion: mathjaxVersion,
      fontName: fontName,
      toleranceEm: toleranceEm,
    );
    exitCode = ok ? 0 : 1;
    return;
  }

  final bool ok = _verifyAll(
    cases: cases,
    oracleById: oracleById,
    mathjaxVersion: mathjaxVersion,
    fontName: fontName,
    toleranceEm: toleranceEm,
  );
  exitCode = ok ? 0 : 1;
}

Future<Map<String, Object?>> _runOracle(List<CorpusCase> cases) async {
  final File scriptFile = File(_oracleScriptPath);
  if (!scriptFile.existsSync()) {
    throw StateError('Missing oracle script: $_oracleScriptPath');
  }

  final List<Map<String, Object?>> requestCases = cases
      .map(
        (CorpusCase c) => <String, Object?>{
          'id': c.id,
          'tex': c.tex,
          'display': c.display,
          if (c.packages != null) 'packages': c.packages,
        },
      )
      .toList();

  final bool needsTexHtml = cases.any(
    (CorpusCase c) => c.packages?.contains('texhtml') ?? false,
  );
  final Process process = await Process.start('node', <String>[
    _oracleScriptPath,
    if (needsTexHtml) '--allow-texhtml',
  ]);

  final Future<String> stdoutFuture = utf8.decodeStream(process.stdout);
  final Future<String> stderrFuture = utf8.decodeStream(process.stderr);

  process.stdin.write(jsonEncode(requestCases));
  await process.stdin.flush();
  await process.stdin.close();

  final List<Object> results = await Future.wait<Object>(<Future<Object>>[
    stdoutFuture,
    stderrFuture,
    process.exitCode,
  ]);
  final String stdoutText = results[0] as String;
  final String stderrText = results[1] as String;
  final int code = results[2] as int;

  if (code != 0) {
    throw StateError('Oracle exited with code $code: ${stderrText.trim()}');
  }
  return jsonDecode(stdoutText) as Map<String, Object?>;
}

bool _writeExpectations({
  required List<CorpusCase> cases,
  required Map<String, Map<String, Object?>> oracleById,
  required String mathjaxVersion,
  required String fontName,
  required double toleranceEm,
}) {
  final List<String> errors = <String>[];
  final Map<String, Object?> caseEntries = <String, Object?>{};
  int acceptedCount = 0;
  int refusedCount = 0;

  final List<CorpusCase> sortedCases = List<CorpusCase>.of(cases)
    ..sort((CorpusCase a, CorpusCase b) => a.id.compareTo(b.id));

  for (final CorpusCase c in sortedCases) {
    final Map<String, Object?>? oracle = oracleById[c.id];
    if (oracle == null) {
      errors.add('Oracle did not return a result for ${c.id}.');
      continue;
    }

    final bool oracleAccepted = oracle['accepted'] as bool;
    final String? oracleErrorClass = oracle['errorClass'] as String?;

    if (oracleAccepted != c.accepted) {
      errors.add(
        '${c.id}: .tex header accepted=${c.accepted} disagrees with live '
        'oracle accepted=$oracleAccepted '
        '(${oracle['errorMessage'] ?? 'no error'}).',
      );
      continue;
    }
    if (!oracleAccepted &&
        c.errorClass != null &&
        oracleErrorClass != c.errorClass) {
      errors.add(
        '${c.id}: .tex header error_class=${c.errorClass} disagrees with '
        'live oracle errorClass=$oracleErrorClass.',
      );
      continue;
    }

    if (oracleAccepted) {
      acceptedCount++;
    } else {
      refusedCount++;
    }

    final Map<String, Object?>? box = oracle['box'] as Map<String, Object?>?;
    final List<Object?> glyphs =
        oracle['glyphs'] as List<Object?>? ?? <Object?>[];
    final List<Object?> rules =
        oracle['rules'] as List<Object?>? ?? <Object?>[];

    final EngineEvaluation eval = evaluateEngineAgainstOracle(
      corpusCase: c,
      oracleAccepted: oracleAccepted,
      oracleErrorClass: oracleErrorClass,
      oracleBox: box,
      oracleGlyphs: glyphs,
      oracleRules: rules,
      toleranceEm: toleranceEm,
    );

    caseEntries[c.id] = <String, Object?>{
      'id': c.id,
      'path': c.relativePath,
      'tier': c.tier,
      'package': c.package,
      'feature': c.feature,
      'display': c.display,
      if (c.packages != null) 'packages': c.packages,
      'oracleAccepted': oracleAccepted,
      'oracleErrorClass': oracleErrorClass,
      'texMathStatus': eval.outcome.wireName,
      'box': box,
      'glyphs': glyphs,
      'rules': rules,
    };
  }

  if (errors.isNotEmpty) {
    for (final String err in errors) {
      stderr.writeln('ERROR: $err');
    }
    return false;
  }

  final Map<String, Object?> document = <String, Object?>{
    'schemaVersion': 1,
    'mathjaxVersion': mathjaxVersion,
    'font': fontName,
    'caseCount': sortedCases.length,
    'acceptedCount': acceptedCount,
    'refusedCount': refusedCount,
    'cases': caseEntries,
  };

  File(_expectationsPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(document)}\n',
  );
  stdout.writeln(
    'Wrote $_expectationsPath: ${sortedCases.length} cases '
    '($acceptedCount accepted, $refusedCount refused, '
    'MathJax $mathjaxVersion, font $fontName).',
  );
  return true;
}

bool _verifyAll({
  required List<CorpusCase> cases,
  required Map<String, Map<String, Object?>> oracleById,
  required String mathjaxVersion,
  required String fontName,
  required double toleranceEm,
}) {
  final Map<String, Object?> expectations = loadExpectationsJson(
    path: _expectationsPath,
  );
  final List<String> errors = <String>[];

  final String? expectedMjVersion = expectations['mathjaxVersion'] as String?;
  final String? expectedFont = expectations['font'] as String?;
  if (expectedMjVersion != mathjaxVersion) {
    errors.add(
      'MathJax version mismatch: expectations=$expectedMjVersion, '
      'live=$mathjaxVersion.',
    );
  }
  if (expectedFont != fontName) {
    errors.add(
      'Oracle font mismatch: expectations=$expectedFont, live=$fontName.',
    );
  }

  final Map<String, Object?>? expCases =
      expectations['cases'] as Map<String, Object?>?;
  if (expCases == null) {
    stderr.writeln('ERROR: $_expectationsPath is missing "cases" object.');
    return false;
  }

  final Set<String> corpusIds = cases.map((CorpusCase c) => c.id).toSet();
  final Set<String> expectationIds = expCases.keys.toSet();
  for (final String missing in corpusIds.difference(expectationIds)) {
    errors.add('Corpus case "$missing" missing from $_expectationsPath.');
  }
  for (final String stale in expectationIds.difference(corpusIds)) {
    errors.add(
      'Stale expectation "$stale" in $_expectationsPath has no .tex file.',
    );
  }

  final Map<EngineOutcome, int> outcomeCounts = <EngineOutcome, int>{
    for (final EngineOutcome o in EngineOutcome.values) o: 0,
  };

  for (final CorpusCase c in cases) {
    final Map<String, Object?>? oracle = oracleById[c.id];
    final Map<String, Object?>? exp = expCases[c.id] as Map<String, Object?>?;
    if (oracle == null) {
      errors.add('${c.id}: missing live oracle result.');
      continue;
    }
    if (exp == null) {
      continue;
    }

    final bool liveAccepted = oracle['accepted'] as bool;
    final String? liveErrorClass = oracle['errorClass'] as String?;
    final bool expAccepted = exp['oracleAccepted'] as bool;
    final String? expErrorClass = exp['oracleErrorClass'] as String?;

    if (liveAccepted != c.accepted || liveAccepted != expAccepted) {
      errors.add(
        '${c.id}: acceptance mismatch '
        '(header=${c.accepted}, expectations=$expAccepted, live=$liveAccepted).',
      );
      continue;
    }

    if (!liveAccepted) {
      if (liveErrorClass != expErrorClass) {
        errors.add(
          '${c.id}: errorClass drift '
          '(expectations=$expErrorClass, live=$liveErrorClass).',
        );
      }
      if (c.errorClass != null && liveErrorClass != c.errorClass) {
        errors.add(
          '${c.id}: header error_class=${c.errorClass} != live=$liveErrorClass.',
        );
      }
    } else {
      final String? oracleDiff = _compareOracleGeometry(
        id: c.id,
        live: oracle,
        expected: exp,
        toleranceEm: toleranceEm,
      );
      if (oracleDiff != null) {
        errors.add(oracleDiff);
      }
    }

    final EngineEvaluation eval = evaluateEngineAgainstOracle(
      corpusCase: c,
      oracleAccepted: expAccepted,
      oracleErrorClass: expErrorClass,
      oracleBox: exp['box'] as Map<String, Object?>?,
      oracleGlyphs: exp['glyphs'] as List<Object?>?,
      oracleRules: exp['rules'] as List<Object?>?,
      toleranceEm: toleranceEm,
    );
    outcomeCounts[eval.outcome] = (outcomeCounts[eval.outcome] ?? 0) + 1;

    final EngineOutcome? expectedStatus = EngineOutcome.fromWireName(
      exp['texMathStatus'] as String?,
    );
    if (expectedStatus == null) {
      errors.add(
        '${c.id}: invalid texMathStatus "${exp['texMathStatus']}" in $_expectationsPath.',
      );
      continue;
    }

    switch (expectedStatus) {
      case EngineOutcome.pass:
        if (eval.outcome != EngineOutcome.pass) {
          errors.add(
            '${c.id}: regression (expected pass, got ${eval.outcome.wireName}: '
            '${eval.detail ?? ''}).',
          );
        }
      case EngineOutcome.refusedMatch:
        if (eval.outcome != EngineOutcome.refusedMatch) {
          errors.add(
            '${c.id}: regression (expected refused_match, got '
            '${eval.outcome.wireName}: ${eval.detail ?? ''}).',
          );
        }
      case EngineOutcome.budgetError:
        if (eval.outcome != EngineOutcome.budgetError &&
            eval.outcome != EngineOutcome.refusedMatch) {
          errors.add(
            '${c.id}: regression (expected budget_error, got '
            '${eval.outcome.wireName}: ${eval.detail ?? ''}).',
          );
        }
      case EngineOutcome.unsupported:
        if (eval.outcome == EngineOutcome.differs) {
          errors.add('${c.id}: unexpected mismatch (${eval.detail ?? ''}).');
        }
      case EngineOutcome.differs:
        break;
    }
  }

  if (errors.isNotEmpty) {
    for (final String err in errors) {
      stderr.writeln('ERROR: $err');
    }
    stderr.writeln('Verification failed with ${errors.length} error(s).');
    return false;
  }

  stdout.writeln(
    'Verified ${cases.length} corpus cases against live MathJax '
    '$mathjaxVersion ($fontName) and $_expectationsPath '
    '(tolerance=${toleranceEm.toStringAsFixed(2)}em): '
    'pass=${outcomeCounts[EngineOutcome.pass]}, '
    'refused_match=${outcomeCounts[EngineOutcome.refusedMatch]}, '
    'unsupported=${outcomeCounts[EngineOutcome.unsupported]}, '
    'budget_error=${outcomeCounts[EngineOutcome.budgetError]}, '
    'differs=${outcomeCounts[EngineOutcome.differs]}.',
  );
  return true;
}

String? _compareOracleGeometry({
  required String id,
  required Map<String, Object?> live,
  required Map<String, Object?> expected,
  required double toleranceEm,
}) {
  final Map<String, Object?>? liveBox = live['box'] as Map<String, Object?>?;
  final Map<String, Object?>? expBox = expected['box'] as Map<String, Object?>?;
  if (liveBox == null || expBox == null) {
    return '$id: missing box metrics in oracle or expectations.';
  }
  for (final String key in <String>['width', 'height', 'depth']) {
    final double a = (liveBox[key] as num).toDouble();
    final double b = (expBox[key] as num).toDouble();
    if ((a - b).abs() > toleranceEm) {
      return '$id: oracle box.$key drift (expected=$b, live=$a).';
    }
  }

  final List<Object?> liveGlyphs =
      live['glyphs'] as List<Object?>? ?? <Object?>[];
  final List<Object?> expGlyphs =
      expected['glyphs'] as List<Object?>? ?? <Object?>[];
  if (liveGlyphs.length != expGlyphs.length) {
    return '$id: oracle glyph count drift '
        '(expected=${expGlyphs.length}, live=${liveGlyphs.length}).';
  }
  for (int i = 0; i < expGlyphs.length; i++) {
    final Map<String, Object?> lg = liveGlyphs[i] as Map<String, Object?>;
    final Map<String, Object?> eg = expGlyphs[i] as Map<String, Object?>;
    if (parseCodePoint(lg['codePoint']) != parseCodePoint(eg['codePoint'])) {
      return '$id: oracle glyph[$i] codePoint drift '
          '(expected=${eg['codePoint']}, live=${lg['codePoint']}).';
    }
    for (final String coord in <String>['x', 'y', 'scaleX', 'scaleY']) {
      final double a = (lg[coord] as num?)?.toDouble() ?? 1.0;
      final double b = (eg[coord] as num?)?.toDouble() ?? 1.0;
      if ((a - b).abs() > toleranceEm) {
        return '$id: oracle glyph[$i].$coord drift (expected=$b, live=$a).';
      }
    }
  }

  final List<Object?> liveRules =
      live['rules'] as List<Object?>? ?? <Object?>[];
  final List<Object?> expRules =
      expected['rules'] as List<Object?>? ?? <Object?>[];
  if (liveRules.length != expRules.length) {
    return '$id: oracle rule count drift '
        '(expected=${expRules.length}, live=${liveRules.length}).';
  }
  for (int i = 0; i < expRules.length; i++) {
    final Map<String, Object?> lr = liveRules[i] as Map<String, Object?>;
    final Map<String, Object?> er = expRules[i] as Map<String, Object?>;
    for (final String field in <String>['x', 'y', 'width', 'height']) {
      final double a = (lr[field] as num).toDouble();
      final double b = (er[field] as num).toDouble();
      if ((a - b).abs() > toleranceEm) {
        return '$id: oracle rule[$i].$field drift (expected=$b, live=$a).';
      }
    }
  }

  return null;
}
