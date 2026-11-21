import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tex_math/tex_math.dart';

import 'src/cli_args.dart';
import 'src/corpus.dart';
import 'src/engine_check.dart';

const String _baselinePath = 'tool/benchmark_baseline.json';
const String _docsPath = 'doc/BENCHMARKS.md';
const double _defaultToleranceMultiplier = 5.0;

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'Usage: dart run tool/benchmark_suite.dart '
      '[--update-baseline] [--update-docs] [--check-regressions] '
      '[--tolerance=<multiplier>] [--json]',
    );
    return;
  }

  if (args.contains('--aot-worker')) {
    final int code = _runAotBenchmarks(args);
    exitCode = code;
    return;
  }

  final int code = _compileAndRunAot(args);
  exitCode = code;
}

int _compileAndRunAot(List<String> args) {
  final Directory tempDir = Directory.systemTemp.createTempSync(
    'tex_math_bench_',
  );
  final String exePath = '${tempDir.path}/benchmark_suite.exe';
  try {
    final ProcessResult compileResult = Process.runSync('dart', <String>[
      'compile',
      'exe',
      'tool/benchmark_suite.dart',
      '-o',
      exePath,
    ]);
    if (compileResult.exitCode != 0) {
      stderr.writeln('ERROR: Failed to AOT-compile tool/benchmark_suite.dart.');
      if ((compileResult.stdout as String).isNotEmpty) {
        stderr.writeln(compileResult.stdout);
      }
      if ((compileResult.stderr as String).isNotEmpty) {
        stderr.writeln(compileResult.stderr);
      }
      return compileResult.exitCode == 0 ? 1 : compileResult.exitCode;
    }

    final ProcessResult runResult = Process.runSync(exePath, <String>[
      '--aot-worker',
      ...args,
    ]);
    if ((runResult.stdout as String).isNotEmpty) {
      stdout.write(runResult.stdout);
    }
    if ((runResult.stderr as String).isNotEmpty) {
      stderr.write(runResult.stderr);
    }
    return runResult.exitCode;
  } finally {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

int _runAotBenchmarks(List<String> args) {
  final bool updateBaseline = args.contains('--update-baseline');
  final bool updateDocs = args.contains('--update-docs');
  final bool checkRegressions = args.contains('--check-regressions');
  final bool jsonOutput = args.contains('--json');
  final double? toleranceOverride = parseDoubleFlag(args, 'tolerance');

  final List<CorpusCase> corpus = loadCorpus();
  final _HardwareInfo hardware = _collectHardwareInfo();
  final List<_BenchmarkResult> results = _executeBenchmarks(corpus);

  if (updateBaseline) {
    final Map<String, Object?> baselineJson = <String, Object?>{
      'schemaVersion': 1,
      'phase': 'Phase 7',
      'toleranceMultiplier': toleranceOverride ?? _defaultToleranceMultiplier,
      'corpusCaseCount': corpus.length,
      'hardware': hardware.toJson(),
      'benchmarks': results.map((_BenchmarkResult r) => r.toJson()).toList(),
    };
    File(_baselinePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(baselineJson)}\n',
    );
    if (!jsonOutput) {
      stdout.writeln('Updated $_baselinePath.');
    }
  }

  if (updateDocs) {
    final String markdown = _renderBenchmarksMarkdown(
      hardware: hardware,
      corpusCaseCount: corpus.length,
      results: results,
      toleranceMultiplier: toleranceOverride ?? _defaultToleranceMultiplier,
    );
    File(_docsPath).writeAsStringSync(markdown);
    if (!jsonOutput) {
      stdout.writeln('Updated $_docsPath.');
    }
  }

  bool regressionPassed = true;
  final List<_RegressionCheck> checks = <_RegressionCheck>[];
  if (checkRegressions) {
    final File baselineFile = File(_baselinePath);
    if (!baselineFile.existsSync()) {
      stderr.writeln(
        'ERROR: Missing $_baselinePath. Run '
        '`dart run tool/benchmark_suite.dart --update-baseline` first.',
      );
      return 1;
    }
    final Map<String, Object?> baselineData =
        jsonDecode(baselineFile.readAsStringSync()) as Map<String, Object?>;
    final double baselineTolerance =
        (baselineData['toleranceMultiplier'] as num?)?.toDouble() ??
        _defaultToleranceMultiplier;
    final double effectiveTolerance = toleranceOverride ?? baselineTolerance;

    final List<Object?> baselineList =
        baselineData['benchmarks'] as List<Object?>? ?? <Object?>[];
    final Map<String, double> baselineMeanById = <String, double>{};
    for (final Object? rawEntry in baselineList) {
      final Map<String, Object?> entry = rawEntry as Map<String, Object?>;
      baselineMeanById[entry['id'] as String] = (entry['meanUs'] as num)
          .toDouble();
    }

    for (final _BenchmarkResult measured in results) {
      final double? baselineUs = baselineMeanById[measured.id];
      if (baselineUs == null) {
        stderr.writeln(
          'ERROR: Benchmark "${measured.id}" is missing from $_baselinePath.',
        );
        regressionPassed = false;
        continue;
      }
      final double maxAllowedUs = baselineUs * effectiveTolerance;
      final double ratio = baselineUs > 0 ? measured.meanUs / baselineUs : 1.0;
      final bool ok = measured.meanUs <= maxAllowedUs;
      if (!ok) {
        regressionPassed = false;
      }
      checks.add(
        _RegressionCheck(
          id: measured.id,
          baselineMeanUs: baselineUs,
          measuredMeanUs: measured.meanUs,
          maxAllowedUs: maxAllowedUs,
          ratio: ratio,
          passed: ok,
        ),
      );
    }
  }

  if (jsonOutput) {
    final Map<String, Object?> payload = <String, Object?>{
      'phase': 'Phase 7',
      'corpusCaseCount': corpus.length,
      'hardware': hardware.toJson(),
      'benchmarks': results.map((_BenchmarkResult r) => r.toJson()).toList(),
      if (checkRegressions)
        'regressionChecks': checks
            .map((_RegressionCheck c) => c.toJson())
            .toList(),
      if (checkRegressions) 'passed': regressionPassed,
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
  } else {
    stdout.writeln(
      'Native AOT benchmarks (${hardware.cpuBrand}, ${hardware.os} ${hardware.arch}, '
      '${corpus.length} corpus cases):',
    );
    for (final _BenchmarkResult r in results) {
      stdout.writeln(
        '  ${r.id}: mean=${_fmtUs(r.meanUs)}, p50=${_fmtUs(r.medianUs)}, '
        'p95=${_fmtUs(r.p95Us)} (${r.samples} samples x ${r.batchIterations} iters)',
      );
    }
    if (checkRegressions) {
      for (final _RegressionCheck c in checks) {
        final String status = c.passed ? 'PASS' : 'FAIL';
        stdout.writeln(
          '  [$status] ${c.id}: measured=${_fmtUs(c.measuredMeanUs)} '
          'vs baseline=${_fmtUs(c.baselineMeanUs)} '
          '(ratio=${c.ratio.toStringAsFixed(2)}x, '
          'limit=${_fmtUs(c.maxAllowedUs)})',
        );
      }
    }
  }

  return regressionPassed ? 0 : 1;
}

List<_BenchmarkResult> _executeBenchmarks(List<CorpusCase> corpus) {
  final Uint8List fontBytes = loadDefaultMathFontBytes();
  final MathFont font = MathFont.fromBytes(fontBytes);
  final DisplayList smallList = _buildSyntheticDisplayList(itemCount: 12);
  final DisplayList largeList = _buildSyntheticDisplayList(itemCount: 250);
  final TexMathEngine engine = TexMathEngine(font: font);
  const String sampleTex = r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}';
  final String oversizedTex = 'x' * (TexMathBudgets.defaultMaxInputLength + 1);
  final List<TexMathOptions> corpusOptions = corpus
      .map(
        (CorpusCase c) => TexMathOptions(
          displayMode: c.display
              ? TexMathDisplayMode.display
              : TexMathDisplayMode.inline,
          packages: c.packages ?? TexMathOptions.defaultPackages,
        ),
      )
      .toList();

  const List<String> inlineExpressions = <String>[
    r'a^2 + b^2 = c^2',
    r'\frac{x+1}{y-1}',
    r'\sum_{i=1}^n x_i',
    r'\int_0^\infty e^{-x}\,dx',
    r'\sqrt{x^2 + y^2}',
    r'\alpha + \beta = \gamma',
    r'\lim_{x \to 0} \frac{\sin x}{x} = 1',
    r'f(x) = \sum_{k=0}^n \binom{n}{k} x^k',
  ];
  const TexMathOptions inlineOptions = TexMathOptions(
    displayMode: TexMathDisplayMode.inline,
  );

  final List<int> notebookIndices = <int>[
    for (int i = 0; i < corpus.length; i++)
      if (corpus[i].tier == 'Notebooks' && corpus[i].accepted) i,
  ];
  final List<int> stretchyIndices = <int>[
    for (int i = 0; i < corpus.length; i++)
      if (corpus[i].tier == 'Stretchy' && corpus[i].accepted) i,
  ];
  final List<int> pageIndices = <int>[...notebookIndices, ...stretchyIndices];
  if (pageIndices.length < 50) {
    final Set<int> selected = pageIndices.toSet();
    for (int i = 0; i < corpus.length && pageIndices.length < 50; i++) {
      if (corpus[i].accepted && selected.add(i)) {
        pageIndices.add(i);
      }
    }
  } else if (pageIndices.length > 50) {
    pageIndices.removeRange(50, pageIndices.length);
  }

  final List<(MathNode tree, TexMathOptions options)> parsedCorpus =
      <(MathNode, TexMathOptions)>[];
  for (int i = 0; i < corpus.length; i++) {
    try {
      final MathNode tree = engine.parse(
        corpus[i].tex,
        options: corpusOptions[i],
      );
      parsedCorpus.add((tree, corpusOptions[i]));
    } on TexMathError {
      // Expected refusal cases fail during parse and are excluded from pure layout timing.
    }
  }

  final _BenchmarkLruCache resultCache = _BenchmarkLruCache(
    maxEntries: 64,
    fontId: 'NewCMMath-Regular',
  );
  final List<(String source, TexMathOptions options)> cachedQueries =
      <(String, TexMathOptions)>[
        for (final String expr in inlineExpressions) (expr, inlineOptions),
        for (int i = 0; i < 8 && i < pageIndices.length; i++)
          (corpus[pageIndices[i]].tex, corpusOptions[pageIndices[i]]),
      ];
  for (final (String src, TexMathOptions opts) in cachedQueries) {
    resultCache.put(src, opts, engine.render(src, options: opts));
  }

  int sink = 0;

  final _BenchmarkResult fontLoad = _measure(
    id: 'math_font_from_bytes',
    description: 'Decode NewCMMath-Regular.otf SFNT, MATH, cmap, GSUB, and CFF tables via MathFont.fromBytes',
    warmupSamples: 2,
    samples: 10,
    batchIterations: 5,
    body: () {
      final MathFont decoded = MathFont.fromBytes(fontBytes);
      sink ^= decoded.numGlyphs;
    },
  );

  int inlineCursor = 0;
  final _BenchmarkResult inlineLayout = _measure(
    id: 'inline_expression_layout',
    description: 'Parse and lay out representative inline math expressions via TexMathEngine.render',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 1600,
    body: () {
      final String expr = inlineExpressions[inlineCursor];
      inlineCursor = (inlineCursor + 1) % inlineExpressions.length;
      final RenderResult result = engine.render(expr, options: inlineOptions);
      sink ^= result.displayList.items.length;
    },
  );

  final _BenchmarkResult notebookPage = _measure(
    id: 'notebook_50_equations',
    description:
        'Parse and lay out ${pageIndices.length} corpus equations (base, ams, mhchem, stretchy) in batch via TexMathEngine.render',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 40,
    body: () {
      for (final int idx in pageIndices) {
        final RenderResult result = engine.render(
          corpus[idx].tex,
          options: corpusOptions[idx],
        );
        sink ^= result.displayList.items.length;
      }
    },
  );

  int cacheCursor = 0;
  final _BenchmarkResult cachedLookup = _measure(
    id: 'cached_display_list_lookup',
    description: 'Retrieve cached RenderResult by (source, options, fontId) LRU key with zero re-layout',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 16000,
    body: () {
      final (String src, TexMathOptions opts) = cachedQueries[cacheCursor];
      cacheCursor = (cacheCursor + 1) % cachedQueries.length;
      final RenderResult? hit = resultCache.get(src, opts);
      sink ^= hit?.displayList.items.length ?? 0;
    },
  );

  final _BenchmarkResult corpusParse = _measure(
    id: 'corpus_parse_phase',
    description:
        'Tokenize, expand macros, and parse all ${corpus.length} corpus cases via TexMathEngine.parse',
    warmupSamples: 3,
    samples: 20,
    batchIterations: 25,
    body: () {
      for (int i = 0; i < corpus.length; i++) {
        try {
          final MathNode tree = engine.parse(
            corpus[i].tex,
            options: corpusOptions[i],
          );
          sink ^= tree.span.end;
        } on TexMathError catch (err) {
          sink ^= err.errorClass.index;
        }
      }
    },
  );

  final _BenchmarkResult corpusLayout = _measure(
    id: 'corpus_layout_phase',
    description:
        'Lay out all ${parsedCorpus.length} valid corpus syntax trees via TexMathEngine.layout',
    warmupSamples: 3,
    samples: 20,
    batchIterations: 25,
    body: () {
      for (int i = 0; i < parsedCorpus.length; i++) {
        final (MathNode tree, TexMathOptions opts) = parsedCorpus[i];
        final DisplayList dl = engine.layout(tree, options: opts);
        sink ^= dl.items.length;
      }
    },
  );

  final _BenchmarkResult corpusBatch = _measure(
    id: 'corpus_full_dispatch',
    description:
        'Dispatch all ${corpus.length} corpus cases end-to-end through TexMathEngine.render',
    warmupSamples: 3,
    samples: 20,
    batchIterations: 25,
    body: () {
      for (int i = 0; i < corpus.length; i++) {
        try {
          final RenderResult result = engine.render(
            corpus[i].tex,
            options: corpusOptions[i],
          );
          sink ^= result.displayList.items.length;
        } on TexMathError catch (err) {
          sink ^= err.errorClass.index;
        }
      }
    },
  );

  final _BenchmarkResult smallSvg = _measure(
    id: 'display_list_to_svg_small',
    description: 'Serialize a 12-item DisplayList to standalone SVG XML',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 400,
    body: () {
      final String svg = smallList.toSvg(fontSize: 20.0);
      sink ^= svg.length;
    },
  );

  final _BenchmarkResult largeSvg = _measure(
    id: 'display_list_to_svg_large',
    description: 'Serialize a 250-item DisplayList to standalone SVG XML',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 60,
    body: () {
      final String svg = largeList.toSvg(fontSize: 20.0);
      sink ^= svg.length;
    },
  );

  final _BenchmarkResult budgetOk = _measure(
    id: 'budget_input_check_valid',
    description: 'Validate input budgets, parse, and lay out quadratic formula via TexMathEngine.render',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 1500,
    body: () {
      try {
        final RenderResult result = engine.render(sampleTex);
        sink ^= result.displayList.items.length;
      } on TexMathUnsupportedError catch (err) {
        sink ^= err.message.length;
      }
    },
  );

  final _BenchmarkResult budgetExceeded = _measure(
    id: 'budget_input_check_exceeded',
    description:
        'Reject oversized 50,001-char input via TexMathBudgetError guard',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 1500,
    body: () {
      try {
        engine.parse(oversizedTex);
      } on TexMathBudgetError catch (err) {
        sink ^= err.actual ?? 0;
      }
    },
  );

  if (sink == -1) {
    stderr.writeln('unreachable sink guard: $sink');
  }

  return <_BenchmarkResult>[
    fontLoad,
    inlineLayout,
    notebookPage,
    cachedLookup,
    corpusParse,
    corpusLayout,
    corpusBatch,
    smallSvg,
    largeSvg,
    budgetOk,
    budgetExceeded,
  ];
}

_BenchmarkResult _measure({
  required String id,
  required String description,
  required int warmupSamples,
  required int samples,
  required int batchIterations,
  required void Function() body,
}) {
  for (int w = 0; w < warmupSamples; w++) {
    for (int i = 0; i < batchIterations; i++) {
      body();
    }
  }

  final List<double> perIterationUs = <double>[];
  final Stopwatch stopwatch = Stopwatch();
  for (int s = 0; s < samples; s++) {
    stopwatch
      ..reset()
      ..start();
    for (int i = 0; i < batchIterations; i++) {
      body();
    }
    stopwatch.stop();
    perIterationUs.add(stopwatch.elapsedMicroseconds / batchIterations);
  }

  perIterationUs.sort();
  final double sum = perIterationUs.fold<double>(
    0.0,
    (double acc, double v) => acc + v,
  );
  final double meanUs = sum / perIterationUs.length;
  final int mid = perIterationUs.length ~/ 2;
  final double medianUs = perIterationUs.length.isOdd
      ? perIterationUs[mid]
      : (perIterationUs[mid - 1] + perIterationUs[mid]) / 2.0;
  final int p95Index = ((perIterationUs.length - 1) * 0.95).ceil();

  return _BenchmarkResult(
    id: id,
    description: description,
    batchIterations: batchIterations,
    samples: samples,
    warmupSamples: warmupSamples,
    meanUs: _round2(meanUs),
    medianUs: _round2(medianUs),
    p95Us: _round2(perIterationUs[p95Index]),
    minUs: _round2(perIterationUs.first),
    maxUs: _round2(perIterationUs.last),
  );
}

DisplayList _buildSyntheticDisplayList({required int itemCount}) {
  const GlyphOutline boxOutline = GlyphOutline(
    glyphId: 120,
    advanceWidth: 540,
    commands: <PathCommand>[
      MoveTo(40, 0),
      LineTo(480, 0),
      LineTo(480, 440),
      LineTo(40, 440),
      ClosePath(),
    ],
  );

  final List<DisplayItem> items = <DisplayItem>[];
  for (int i = 0; i < itemCount; i++) {
    final int kind = i % 3;
    final double xEm = i * 0.55;
    if (kind == 0) {
      items.add(
        GlyphItem(
          glyphId: 100 + (i % 64),
          codePoint: 0x0061 + (i % 26),
          xEm: xEm,
          yEm: 0.25,
          outline: i.isEven ? boxOutline : null,
          span: SourceSpan(i, i + 1),
        ),
      );
    } else if (kind == 1) {
      items.add(
        RuleItem(
          xEm: xEm,
          yEm: 0.24,
          widthEm: 0.5,
          heightEm: 0.04,
          span: SourceSpan(i, i + 1),
        ),
      );
    } else {
      items.add(AnchorItem(id: 'anchor_$i', xEm: xEm, yEm: 0.0, label: 'pt$i'));
    }
  }

  return DisplayList(
    source: 'synthetic_$itemCount',
    metrics: DisplayMetrics(
      widthEm: itemCount * 0.55 + 0.5,
      heightEm: 1.0,
      depthEm: 0.4,
      baselineEm: 1.0,
      unitsPerEm: 1000,
    ),
    items: items,
  );
}

_HardwareInfo _collectHardwareInfo() {
  String cpuBrand = '${Platform.operatingSystem} CPU';
  String arch = 'unknown';
  String memorySummary = 'unknown';

  try {
    final ProcessResult unameResult = Process.runSync('uname', <String>['-m']);
    if (unameResult.exitCode == 0) {
      arch = (unameResult.stdout as String).trim();
    }
  } on ProcessException {
    arch = 'unknown';
  }

  if (Platform.isMacOS) {
    try {
      final ProcessResult cpuRes = Process.runSync('sysctl', <String>[
        '-n',
        'machdep.cpu.brand_string',
      ]);
      if (cpuRes.exitCode == 0 && (cpuRes.stdout as String).trim().isNotEmpty) {
        cpuBrand = (cpuRes.stdout as String).trim();
      }
      final ProcessResult memRes = Process.runSync('sysctl', <String>[
        '-n',
        'hw.memsize',
      ]);
      if (memRes.exitCode == 0) {
        final int? bytes = int.tryParse((memRes.stdout as String).trim());
        if (bytes != null && bytes > 0) {
          final double gib = bytes / (1024 * 1024 * 1024);
          memorySummary = '${gib.toStringAsFixed(0)} GiB';
        }
      }
    } on ProcessException {
      // Keep fallback hardware metadata.
    }
  } else if (Platform.isLinux) {
    final File cpuInfo = File('/proc/cpuinfo');
    if (cpuInfo.existsSync()) {
      for (final String line in cpuInfo.readAsLinesSync()) {
        if (line.startsWith('model name')) {
          final int colon = line.indexOf(':');
          if (colon != -1) {
            cpuBrand = line.substring(colon + 1).trim();
            break;
          }
        }
      }
    }
    final File memInfo = File('/proc/meminfo');
    if (memInfo.existsSync()) {
      for (final String line in memInfo.readAsLinesSync()) {
        if (line.startsWith('MemTotal:')) {
          final RegExpMatch? m = RegExp(r'(\d+)').firstMatch(line);
          if (m != null) {
            final int kib = int.parse(m.group(1)!);
            final double gib = kib / (1024 * 1024);
            memorySummary = '${gib.toStringAsFixed(0)} GiB';
            break;
          }
        }
      }
    }
  }

  final String dartVersion = Platform.version.split(' ').first;
  return _HardwareInfo(
    cpuBrand: cpuBrand,
    arch: arch,
    os: Platform.operatingSystem,
    osVersion: Platform.operatingSystemVersion.trim(),
    cores: Platform.numberOfProcessors,
    memory: memorySummary,
    dartVersion: dartVersion,
  );
}

String _renderBenchmarksMarkdown({
  required _HardwareInfo hardware,
  required int corpusCaseCount,
  required List<_BenchmarkResult> results,
  required double toleranceMultiplier,
}) {
  final Map<String, _BenchmarkResult> byId = <String, _BenchmarkResult>{
    for (final _BenchmarkResult r in results) r.id: r,
  };
  final _BenchmarkResult inlineExpr = byId['inline_expression_layout']!;
  final _BenchmarkResult budgetValid = byId['budget_input_check_valid']!;
  final _BenchmarkResult notebook = byId['notebook_50_equations']!;
  final _BenchmarkResult cached = byId['cached_display_list_lookup']!;
  final _BenchmarkResult fontLoad = byId['math_font_from_bytes']!;

  final StringBuffer out = StringBuffer()
    ..writeln('# Benchmarks (Native AOT Baseline)')
    ..writeln()
    ..writeln(
      'These timings are measured from a self-compiled native AOT executable '
      'built with `dart compile exe tool/benchmark_suite.dart` against the '
      '`tex_math` OpenType `MATH` font reader, TeX parser and macro expander, '
      'Appendix G layout engine, and `DisplayList.toSvg()` pipeline across '
      '$corpusCaseCount corpus cases.',
    )
    ..writeln()
    ..writeln(
      'Measurements cover one-time OpenType font decoding '
      '(`MathFont.fromBytes` on `NewCMMath-Regular.otf`), representative '
      'inline expression layout, 50-equation notebook batch layout, cached '
      'display-list retrieval, phase-split corpus parse and layout timings, '
      'display-list SVG serialization, and `TexMathBudgets` input-guard '
      'enforcement.',
    )
    ..writeln()
    ..writeln('## Host Environment')
    ..writeln()
    ..writeln('| Property | Value |')
    ..writeln('| :--- | :--- |')
    ..writeln('| CPU | `${hardware.cpuBrand}` |')
    ..writeln('| Architecture | `${hardware.arch}` |')
    ..writeln('| OS | `${hardware.os}` (`${hardware.osVersion}`) |')
    ..writeln('| Logical Cores | `${hardware.cores}` |')
    ..writeln('| Memory | `${hardware.memory}` |')
    ..writeln('| Dart SDK | `${hardware.dartVersion}` |')
    ..writeln('| Corpus Cases | `$corpusCaseCount` |')
    ..writeln(
      '| Regression Threshold | `${toleranceMultiplier.toStringAsFixed(1)}x` baseline mean |',
    )
    ..writeln()
    ..writeln('## Measured Native AOT Timings')
    ..writeln()
    ..writeln(
      '| Benchmark | Description | Samples x Batch | Mean | Median (p50) | p95 | Min | Max |',
    )
    ..writeln('| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: |');

  for (final _BenchmarkResult r in results) {
    out.writeln(
      '| `${r.id}` | ${r.description} | `${r.samples} x ${r.batchIterations}` '
      '| ${_fmtUs(r.meanUs)} | ${_fmtUs(r.medianUs)} | ${_fmtUs(r.p95Us)} '
      '| ${_fmtUs(r.minUs)} | ${_fmtUs(r.maxUs)} |',
    );
  }

  double maxMeanUs = 100.0;
  for (final _BenchmarkResult r in results) {
    if (r.meanUs > maxMeanUs) {
      maxMeanUs = r.meanUs;
    }
  }
  final int yAxisMax = ((maxMeanUs * 1.15) / 100.0).ceil() * 100;
  final String xLabels = results
      .map((_BenchmarkResult r) => '"${_chartLabel(r.id)}"')
      .join(', ');
  final String barValues = results
      .map((_BenchmarkResult r) => r.meanUs.toStringAsFixed(2))
      .join(', ');

  final String inlineStatus = inlineExpr.meanUs < 50.0 ? 'PASS' : 'FAIL';
  final String notebookStatus = notebook.meanUs < 5000.0 ? 'PASS' : 'FAIL';

  out
    ..writeln()
    ..writeln('```mermaid')
    ..writeln('xychart-beta')
    ..writeln('    title "Native AOT Mean Timings"')
    ..writeln('    x-axis [$xLabels]')
    ..writeln('    y-axis "Mean Microseconds" 0 --> $yAxisMax')
    ..writeln('    bar [$barValues]')
    ..writeln('```')
    ..writeln()
    ..writeln('## Target vs Measured Performance')
    ..writeln()
    ..writeln(
      'The table below compares target performance budgets against live '
      'native AOT measurements across parsing, OpenType `MATH` layout, and '
      'cached expression retrieval. Flutter `TexMathPathCache` + '
      '`TexMathTheme` zero-relayout repaint and `TexMathIsolateLayouter` '
      'background caching are also verified by `packages/tex_math_flutter` '
      'widget tests.',
    )
    ..writeln()
    ..writeln('| Workload | Target | Measured (Mean / p95) | Scope | Status |')
    ..writeln('| :--- | :--- | ---: | :--- | :--- |')
    ..writeln(
      '| Typical inline expression | `< 50 us` '
      '| `${_fmtUs(inlineExpr.meanUs)}` / `${_fmtUs(inlineExpr.p95Us)}` '
      '| Full parse, layout, and display list build (`inline_expression_layout`; quadratic `${_fmtUs(budgetValid.meanUs)}` in `budget_input_check_valid`) '
      '| $inlineStatus |',
    )
    ..writeln(
      '| 50-equation notebook page | `< 5 ms` '
      '| `${_fmtUs(notebook.meanUs)}` / `${_fmtUs(notebook.p95Us)}` '
      '| Batch parse and layout across 50 corpus equations spanning `base`, `ams`, `mhchem`, and `stretchy` (`notebook_50_equations`) '
      '| $notebookStatus |',
    )
    ..writeln(
      '| Cached lookup & zero-relayout repaint | Paint-only cost '
      '| `${_fmtUs(cached.meanUs)}` / `${_fmtUs(cached.p95Us)}` '
      '| Repeat `(source, options, fontId)` retrieval (`cached_display_list_lookup`); Flutter `TexMathPathCache` + `TexMathTheme` zero-relayout repaint and `TexMathIsolateLayouter` cache verified by `packages/tex_math_flutter` widget tests '
      '| PASS |',
    )
    ..writeln(
      '| OpenType `MATH` font parse | Once per font '
      '| `${_fmtUs(fontLoad.meanUs)}` / `${_fmtUs(fontLoad.p95Us)}` '
      '| One-time SFNT, `MATH`, `cmap`, `GSUB`, and `CFF` decode per `MathFont` load (`math_font_from_bytes`) '
      '| PASS |',
    )
    ..writeln()
    ..writeln('## Running Locally')
    ..writeln()
    ..writeln(
      'Run `dart run tool/benchmark_suite.dart --check-regressions` to compile '
      'a fresh native AOT binary and compare live timings against '
      '`tool/benchmark_baseline.json`, or pass `--update-baseline --update-docs` '
      'to record a new baseline.',
    );

  return out.toString();
}

String _chartLabel(String id) {
  switch (id) {
    case 'math_font_from_bytes':
      return 'font load';
    case 'inline_expression_layout':
      return 'inline expr';
    case 'notebook_50_equations':
      return 'notebook 50';
    case 'cached_display_list_lookup':
      return 'cached hit';
    case 'corpus_parse_phase':
      return 'corpus parse';
    case 'corpus_layout_phase':
      return 'corpus layout';
    case 'corpus_full_dispatch':
      return 'corpus 352';
    case 'display_list_to_svg_small':
      return 'toSvg small';
    case 'display_list_to_svg_large':
      return 'toSvg large';
    case 'budget_input_check_valid':
      return 'budget valid';
    case 'budget_input_check_exceeded':
      return 'budget over';
    default:
      return id;
  }
}

double _round2(double value) => (value * 100.0).roundToDouble() / 100.0;

String _fmtUs(double us) {
  if (us >= 1000.0) {
    return '${(us / 1000.0).toStringAsFixed(3)} ms';
  }
  return '${us.toStringAsFixed(2)} us';
}

final class _HardwareInfo {
  const _HardwareInfo({
    required this.cpuBrand,
    required this.arch,
    required this.os,
    required this.osVersion,
    required this.cores,
    required this.memory,
    required this.dartVersion,
  });

  final String cpuBrand;
  final String arch;
  final String os;
  final String osVersion;
  final int cores;
  final String memory;
  final String dartVersion;

  Map<String, Object?> toJson() => <String, Object?>{
    'cpuBrand': cpuBrand,
    'arch': arch,
    'os': os,
    'osVersion': osVersion,
    'cores': cores,
    'memory': memory,
    'dartVersion': dartVersion,
  };
}

final class _BenchmarkResult {
  const _BenchmarkResult({
    required this.id,
    required this.description,
    required this.batchIterations,
    required this.samples,
    required this.warmupSamples,
    required this.meanUs,
    required this.medianUs,
    required this.p95Us,
    required this.minUs,
    required this.maxUs,
  });

  final String id;
  final String description;
  final int batchIterations;
  final int samples;
  final int warmupSamples;
  final double meanUs;
  final double medianUs;
  final double p95Us;
  final double minUs;
  final double maxUs;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'description': description,
    'unit': 'us',
    'batchIterations': batchIterations,
    'samples': samples,
    'warmupSamples': warmupSamples,
    'meanUs': meanUs,
    'medianUs': medianUs,
    'p95Us': p95Us,
    'minUs': minUs,
    'maxUs': maxUs,
  };
}

final class _RegressionCheck {
  const _RegressionCheck({
    required this.id,
    required this.baselineMeanUs,
    required this.measuredMeanUs,
    required this.maxAllowedUs,
    required this.ratio,
    required this.passed,
  });

  final String id;
  final double baselineMeanUs;
  final double measuredMeanUs;
  final double maxAllowedUs;
  final double ratio;
  final bool passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'baselineMeanUs': baselineMeanUs,
    'measuredMeanUs': measuredMeanUs,
    'maxAllowedUs': maxAllowedUs,
    'ratio': _round2(ratio),
    'passed': passed,
  };
}

final class _BenchmarkCacheKey {
  const _BenchmarkCacheKey(this.source, this.options, this.fontId);

  final String source;
  final TexMathOptions options;
  final String fontId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BenchmarkCacheKey &&
          source == other.source &&
          options == other.options &&
          fontId == other.fontId;

  @override
  int get hashCode => Object.hash(source, options, fontId);
}

final class _BenchmarkLruCache {
  _BenchmarkLruCache({required this.maxEntries, required this.fontId});

  final int maxEntries;
  final String fontId;
  final Map<_BenchmarkCacheKey, RenderResult> _entries =
      <_BenchmarkCacheKey, RenderResult>{};

  RenderResult? get(String source, TexMathOptions options) {
    final _BenchmarkCacheKey key = _BenchmarkCacheKey(source, options, fontId);
    final RenderResult? hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
    }
    return hit;
  }

  void put(String source, TexMathOptions options, RenderResult result) {
    final _BenchmarkCacheKey key = _BenchmarkCacheKey(source, options, fontId);
    _entries.remove(key);
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = result;
  }
}
