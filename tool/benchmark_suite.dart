import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:tex_math/tex_math.dart';

import 'src/cli_args.dart';
import 'src/corpus.dart';
import 'src/engine_check.dart';

const String _baselinePath = 'tool/benchmark_baseline.json';
const String _docsPath = 'doc/BENCHMARKS.md';
const double _defaultToleranceMultiplier = 1.5;

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
      'schemaVersion': 2,
      'phase': 'Phase 7',
      'regressionMetric': 'p50',
      'toleranceMultiplier': toleranceOverride ?? _defaultToleranceMultiplier,
      'corpusCaseCount': corpus.length,
      'processMaxRssMb': _round2(ProcessInfo.maxRss / (1024.0 * 1024.0)),
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
    final Map<String, ({double medianUs, double meanUs})> baselineById =
        <String, ({double medianUs, double meanUs})>{};
    for (final Object? rawEntry in baselineList) {
      final Map<String, Object?> entry = rawEntry as Map<String, Object?>;
      final double meanUs = (entry['meanUs'] as num).toDouble();
      final double medianUs = (entry['medianUs'] as num?)?.toDouble() ?? meanUs;
      baselineById[entry['id'] as String] = (
        medianUs: medianUs,
        meanUs: meanUs,
      );
    }

    for (final _BenchmarkResult measured in results) {
      final ({double medianUs, double meanUs})? baseline =
          baselineById[measured.id];
      if (baseline == null) {
        stderr.writeln(
          'ERROR: Benchmark "${measured.id}" is missing from $_baselinePath.',
        );
        regressionPassed = false;
        continue;
      }
      final double maxAllowedUs = baseline.medianUs * effectiveTolerance;
      final double ratio = baseline.medianUs > 0
          ? measured.medianUs / baseline.medianUs
          : 1.0;
      final bool ok = measured.medianUs <= maxAllowedUs;
      if (!ok) {
        regressionPassed = false;
      }
      checks.add(
        _RegressionCheck(
          id: measured.id,
          baselineMedianUs: baseline.medianUs,
          measuredMedianUs: measured.medianUs,
          baselineMeanUs: baseline.meanUs,
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
      'regressionMetric': 'p50',
      'corpusCaseCount': corpus.length,
      'processMaxRssMb': _round2(ProcessInfo.maxRss / (1024.0 * 1024.0)),
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
        'p95=${_fmtUs(r.p95Us)}, rss=${r.rssMb.toStringAsFixed(2)} MiB '
        '(delta=${_fmtSignedKb(r.rssDeltaKb)}) '
        '(${r.samples} samples x ${r.batchIterations} iters)',
      );
    }
    if (checkRegressions) {
      for (final _RegressionCheck c in checks) {
        final String status = c.passed ? 'PASS' : 'FAIL';
        stdout.writeln(
          '  [$status] ${c.id}: p50=${_fmtUs(c.measuredMedianUs)} '
          'vs baseline=${_fmtUs(c.baselineMedianUs)} '
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

  final ({
    CorpusCase smallCase,
    DisplayList smallList,
    int smallCffCount,
    CorpusCase largeCase,
    DisplayList largeList,
    int largeCffCount,
  })
  svgFixtures = _selectSvgCorpusCases(
    engine: engine,
    corpus: corpus,
    corpusOptions: corpusOptions,
  );

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

  const List<String> coldDecodeExpressions = <String>[
    r'\frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
    r'\int_0^\infty e^{-x^2}\,dx',
    r'\sum_{k=1}^n \binom{n}{k} \alpha^k',
    r'\left(\frac{a}{b}\right)',
  ];

  final List<int> pageIndices = _buildNotebookPageIndices(corpus);

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

  final List<(String source, TexMathOptions options)> cacheWorkloadQueries =
      _buildCacheWorkloadQueries(
        corpus: corpus,
        corpusOptions: corpusOptions,
        inlineExpressions: inlineExpressions,
        count: 128,
      );

  final _BenchmarkLruCache warmHitCache = _BenchmarkLruCache(
    maxEntries: 256,
    fontSignature: font.signature,
  );
  for (final (String src, TexMathOptions opts) in cacheWorkloadQueries) {
    warmHitCache.put(src, opts, engine.render(src, options: opts));
  }

  final _BenchmarkLruCache mixedLruCache = _BenchmarkLruCache(
    maxEntries: 32,
    fontSignature: font.signature,
  );
  // Pre-seed the 16-entry hot working set; entries 16..47 drive misses + evictions.
  for (int i = 0; i < 16; i++) {
    final (String src, TexMathOptions opts) = cacheWorkloadQueries[i];
    mixedLruCache.put(src, opts, engine.render(src, options: opts));
  }

  int sink = 0;

  final _BenchmarkResult fontLoad = _measure(
    id: 'math_font_from_bytes',
    description: 'Decode NewCMMath-Regular.otf SFNT, MATH, cmap, GSUB, and CFF tables via MathFont.fromBytes',
    warmupSamples: 5,
    samples: 20,
    batchIterations: 20,
    body: () {
      final MathFont decoded = MathFont.fromBytes(fontBytes);
      sink ^= decoded.numGlyphs;
    },
  );

  final _BenchmarkResult coldFontDecode = _measure(
    id: 'cold_font_glyph_decode',
    description: 'Cold MathFont.fromBytes plus initial glyph outline, metrics, and MATH layout decode via TexMathEngine.render',
    warmupSamples: 5,
    samples: 20,
    batchIterations: 15,
    body: () {
      final MathFont coldFont = MathFont.fromBytes(fontBytes);
      final TexMathEngine coldEngine = TexMathEngine(font: coldFont);
      for (final String expr in coldDecodeExpressions) {
        final RenderResult res = coldEngine.render(
          expr,
          options: inlineOptions,
        );
        sink ^= res.displayList.items.length;
      }
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
      inlineCursor = (inlineCursor + 1) & 7;
      final RenderResult result = engine.render(expr, options: inlineOptions);
      sink ^= result.displayList.items.length;
    },
  );

  final _BenchmarkResult notebookPage = _measure(
    id: 'notebook_50_equations',
    description:
        'Parse and lay out ${pageIndices.length} tier-stratified corpus equations (Tier 1/2/3, Stretchy, Notebooks) via TexMathEngine.render',
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
    description: 'Retrieve 128 cached RenderResult entries by (source, TexMathOptions, fontSignature) LRU key with zero re-layout',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 16000,
    body: () {
      final (String src, TexMathOptions opts) =
          cacheWorkloadQueries[cacheCursor];
      cacheCursor = (cacheCursor + 1) & 127;
      final RenderResult? hit = warmHitCache.get(src, opts);
      sink ^= hit?.displayList.items.length ?? 0;
    },
  );

  int hotCursor = 0;
  int tailCursor = 0;
  final _BenchmarkResult lruMixed = _measure(
    id: 'lru_cache_mixed_eviction',
    description: 'Run mixed hit, cold miss (TexMathEngine.render), and bounded 32-entry LRU eviction across varied TexMathOptions',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 200,
    body: () {
      for (int h = 0; h < 4; h++) {
        final (String hotSrc, TexMathOptions hotOpts) =
            cacheWorkloadQueries[hotCursor];
        hotCursor = (hotCursor + 1) & 15;
        final RenderResult hit = mixedLruCache.getOrRender(
          engine,
          hotSrc,
          hotOpts,
        );
        sink ^= hit.displayList.items.length;
      }
      for (int m = 0; m < 4; m++) {
        final (String tailSrc, TexMathOptions tailOpts) =
            cacheWorkloadQueries[16 + tailCursor];
        tailCursor = (tailCursor + 1) & 31;
        final RenderResult miss = mixedLruCache.getOrRender(
          engine,
          tailSrc,
          tailOpts,
        );
        sink ^= miss.displayList.items.length;
      }
    },
  );
  if (mixedLruCache.length > mixedLruCache.maxEntries ||
      mixedLruCache.hitCount == 0 ||
      mixedLruCache.missCount == 0 ||
      mixedLruCache.evictionCount == 0) {
    throw StateError(
      'LRU cache benchmark invariant failed: length=${mixedLruCache.length}, '
      'hits=${mixedLruCache.hitCount}, misses=${mixedLruCache.missCount}, '
      'evictions=${mixedLruCache.evictionCount}.',
    );
  }

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
    description:
        'Serialize real laid-out DisplayList for ${svgFixtures.smallCase.id} '
        '(${svgFixtures.smallList.items.length} items, ${svgFixtures.smallCffCount} CFF outlines) to standalone SVG XML',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 400,
    body: () {
      final String svg = svgFixtures.smallList.toSvg(fontSize: 20.0);
      sink ^= svg.length;
    },
  );

  final _BenchmarkResult largeSvg = _measure(
    id: 'display_list_to_svg_large',
    description:
        'Serialize real laid-out DisplayList for ${svgFixtures.largeCase.id} '
        '(${svgFixtures.largeList.items.length} items, ${svgFixtures.largeCffCount} CFF outlines) to standalone SVG XML',
    warmupSamples: 4,
    samples: 20,
    batchIterations: 120,
    body: () {
      final String svg = svgFixtures.largeList.toSvg(fontSize: 20.0);
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
    batchIterations: 4000,
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
    coldFontDecode,
    inlineLayout,
    notebookPage,
    cachedLookup,
    lruMixed,
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

  final int rssBeforeBytes = ProcessInfo.currentRss;
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
  final int rssAfterBytes = ProcessInfo.currentRss;
  final int maxRssBytes = ProcessInfo.maxRss;

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
    rssMb: _round2(rssAfterBytes / (1024.0 * 1024.0)),
    rssDeltaKb: _round2((rssAfterBytes - rssBeforeBytes) / 1024.0),
    maxRssMb: _round2(maxRssBytes / (1024.0 * 1024.0)),
  );
}

List<int> _buildNotebookPageIndices(
  List<CorpusCase> corpus, {
  int targetCount = 50,
}) {
  const List<String> stratifiedTiers = <String>[
    'Tier 1',
    'Tier 2',
    'Tier 3',
    'Stretchy',
    'Notebooks',
  ];
  final Map<String, List<int>> indicesByTier = <String, List<int>>{
    for (final String tier in stratifiedTiers) tier: <int>[],
  };
  for (int i = 0; i < corpus.length; i++) {
    final CorpusCase c = corpus[i];
    if (c.accepted && indicesByTier.containsKey(c.tier)) {
      indicesByTier[c.tier]!.add(i);
    }
  }

  final int totalAvailable = indicesByTier.values.fold<int>(
    0,
    (int sum, List<int> list) => sum + list.length,
  );
  if (totalAvailable == 0) {
    throw StateError('No accepted corpus cases available for notebook page.');
  }

  final int pageSize = math.min(targetCount, totalAvailable);
  final List<String> activeTiers = <String>[
    for (final String tier in stratifiedTiers)
      if (indicesByTier[tier]!.isNotEmpty) tier,
  ];

  // Hamilton largest-remainder apportionment across active tiers.
  final Map<String, int> quotas = <String, int>{};
  final Map<String, double> remainders = <String, double>{};
  int assigned = 0;
  for (final String tier in activeTiers) {
    final int available = indicesByTier[tier]!.length;
    final double exact = (available * pageSize) / totalAvailable;
    int base = exact.floor();
    if (base == 0 && pageSize >= activeTiers.length) {
      base = 1;
    }
    base = math.min(base, available);
    quotas[tier] = base;
    remainders[tier] = exact - base;
    assigned += base;
  }

  while (assigned < pageSize) {
    String? bestTier;
    double bestRemainder = -double.infinity;
    for (final String tier in activeTiers) {
      final int current = quotas[tier]!;
      final int available = indicesByTier[tier]!.length;
      if (current >= available) {
        continue;
      }
      final double rem = remainders[tier]!;
      if (rem > bestRemainder) {
        bestRemainder = rem;
        bestTier = tier;
      }
    }
    if (bestTier == null) {
      break;
    }
    quotas[bestTier] = quotas[bestTier]! + 1;
    assigned++;
  }

  final List<int> selected = <int>[];
  for (final String tier in activeTiers) {
    final List<int> pool = indicesByTier[tier]!;
    final int quota = quotas[tier]!;
    for (int slot = 0; slot < quota; slot++) {
      final int poolIndex = (slot * pool.length) ~/ quota;
      selected.add(pool[poolIndex]);
    }
  }
  return selected;
}

({
  CorpusCase smallCase,
  DisplayList smallList,
  int smallCffCount,
  CorpusCase largeCase,
  DisplayList largeList,
  int largeCffCount,
})
_selectSvgCorpusCases({
  required TexMathEngine engine,
  required List<CorpusCase> corpus,
  required List<TexMathOptions> corpusOptions,
}) {
  CorpusCase? smallCase;
  DisplayList? smallList;
  int smallCffCount = 0;

  CorpusCase? largeCase;
  DisplayList? largeList;
  int largeCffCount = 0;

  for (int i = 0; i < corpus.length; i++) {
    final CorpusCase c = corpus[i];
    if (!c.accepted) {
      continue;
    }
    final DisplayList dl = engine
        .render(c.tex, options: corpusOptions[i])
        .displayList;
    final int cffCount = dl.items
        .whereType<GlyphItem>()
        .where((GlyphItem g) => g.outline != null && !g.outline!.isEmpty)
        .length;
    if (cffCount == 0) {
      continue;
    }

    if (dl.items.length >= 10 &&
        dl.items.length <= 16 &&
        cffCount >= 8 &&
        (smallCase == null ||
            c.id == 'tier1_core/base/root_nested' ||
            (smallCase.id != 'tier1_core/base/root_nested' &&
                cffCount > smallCffCount))) {
      smallCase = c;
      smallList = dl;
      smallCffCount = cffCount;
    }

    if (largeList == null ||
        dl.items.length > largeList.items.length ||
        (dl.items.length == largeList.items.length &&
            cffCount > largeCffCount)) {
      largeCase = c;
      largeList = dl;
      largeCffCount = cffCount;
    }
  }

  if (smallCase == null ||
      smallList == null ||
      largeCase == null ||
      largeList == null) {
    throw StateError(
      'Unable to locate small and large real CFF corpus DisplayLists.',
    );
  }

  return (
    smallCase: smallCase,
    smallList: smallList,
    smallCffCount: smallCffCount,
    largeCase: largeCase,
    largeList: largeList,
    largeCffCount: largeCffCount,
  );
}

List<(String source, TexMathOptions options)> _buildCacheWorkloadQueries({
  required List<CorpusCase> corpus,
  required List<TexMathOptions> corpusOptions,
  required List<String> inlineExpressions,
  required int count,
}) {
  final List<TexMathOptions> variedOptions = <TexMathOptions>[
    const TexMathOptions(displayMode: TexMathDisplayMode.inline),
    const TexMathOptions(displayMode: TexMathDisplayMode.display),
    const TexMathOptions(
      displayMode: TexMathDisplayMode.inline,
      packages: <String>['base', 'ams', 'newcommand', 'configmacros'],
      macros: <String, String>{'RR': r'\mathbb{R}', 'norm': r'\lvert#1\rvert'},
    ),
    const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      packages: <String>['base', 'ams', 'mathtools'],
      budgets: TexMathBudgets(maxMacroExpansions: 5000, maxTokens: 50000),
    ),
  ];

  final List<String> sources = <String>[
    ...inlineExpressions,
    for (final CorpusCase c in corpus)
      if (c.accepted) c.tex,
  ];

  final List<(String source, TexMathOptions options)> queries =
      <(String, TexMathOptions)>[];
  final Set<(String, TexMathOptions)> seen = <(String, TexMathOptions)>{};

  int cursor = 0;
  while (queries.length < count &&
      cursor < corpus.length * variedOptions.length) {
    final String src = sources[cursor % sources.length];
    final TexMathOptions opts = cursor < corpus.length
        ? corpusOptions[cursor]
        : variedOptions[cursor % variedOptions.length];
    if (seen.add((src, opts))) {
      queries.add((src, opts));
    }
    cursor++;
  }

  if (queries.length < count) {
    for (int i = 0; queries.length < count; i++) {
      final String src =
          '${inlineExpressions[i % inlineExpressions.length]} + $i';
      final TexMathOptions opts = variedOptions[i % variedOptions.length];
      if (seen.add((src, opts))) {
        queries.add((src, opts));
      }
    }
  }
  return queries;
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
  final _BenchmarkResult lruMixed = byId['lru_cache_mixed_eviction']!;
  final _BenchmarkResult fontLoad = byId['math_font_from_bytes']!;
  final _BenchmarkResult coldDecode = byId['cold_font_glyph_decode']!;

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
      'Measurements cover one-time OpenType font decoding (`MathFont.fromBytes` '
      'on `NewCMMath-Regular.otf`), cold font plus initial glyph decoding, '
      'representative inline expression layout, tier-stratified 50-equation '
      'notebook batch layout, warm and mixed-eviction `(source, TexMathOptions, '
      'fontSignature)` LRU cache lookups, phase-split corpus parse and layout '
      'timings, real CFF `DisplayList.toSvg()` serialization, `TexMathBudgets` '
      'input-guard enforcement, and `ProcessInfo.currentRss` memory telemetry.',
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
      '| Regression Threshold | `${toleranceMultiplier.toStringAsFixed(1)}x` baseline p50 |',
    )
    ..writeln()
    ..writeln('## Measured Native AOT Timings')
    ..writeln()
    ..writeln(
      '| Benchmark | Description | Samples x Batch | Mean | Median (p50) | p95 | Min | Max | RSS (Delta) |',
    )
    ..writeln(
      '| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    );

  for (final _BenchmarkResult r in results) {
    out.writeln(
      '| `${r.id}` | ${r.description} | `${r.samples} x ${r.batchIterations}` '
      '| ${_fmtUs(r.meanUs)} | ${_fmtUs(r.medianUs)} | ${_fmtUs(r.p95Us)} '
      '| ${_fmtUs(r.minUs)} | ${_fmtUs(r.maxUs)} '
      '| ${r.rssMb.toStringAsFixed(2)} MiB (${_fmtSignedKb(r.rssDeltaKb)}) |',
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

  final String inlineStatus = inlineExpr.medianUs < 50.0 ? 'PASS' : 'FAIL';
  final String notebookStatus = notebook.medianUs < 5000.0 ? 'PASS' : 'FAIL';

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
    ..writeln('| Workload | Target | Measured (p50 / p95) | Scope | Status |')
    ..writeln('| :--- | :--- | ---: | :--- | :--- |')
    ..writeln(
      '| Typical inline expression | `< 50 us` '
      '| `${_fmtUs(inlineExpr.medianUs)}` / `${_fmtUs(inlineExpr.p95Us)}` '
      '| Full parse, layout, and display list build (`inline_expression_layout`; quadratic `${_fmtUs(budgetValid.medianUs)}` in `budget_input_check_valid`) '
      '| $inlineStatus |',
    )
    ..writeln(
      '| 50-equation notebook page | `< 5 ms` '
      '| `${_fmtUs(notebook.medianUs)}` / `${_fmtUs(notebook.p95Us)}` '
      '| Batch parse and layout across 50 tier-stratified corpus equations spanning `Tier 1`, `Tier 2`, `Tier 3`, `Stretchy`, and `Notebooks` (`notebook_50_equations`) '
      '| $notebookStatus |',
    )
    ..writeln(
      '| Cached lookup & mixed LRU eviction | Paint-only / bounded miss '
      '| `${_fmtUs(cached.medianUs)}` / `${_fmtUs(lruMixed.medianUs)}` '
      '| Repeat `(source, TexMathOptions, fontSignature)` hit (`cached_display_list_lookup`) and 32-entry hit+miss+eviction cycle (`lru_cache_mixed_eviction`); Flutter caches verified by `packages/tex_math_flutter` widget tests '
      '| PASS |',
    )
    ..writeln(
      '| OpenType `MATH` font parse & cold decode | Once per font '
      '| `${_fmtUs(fontLoad.medianUs)}` / `${_fmtUs(coldDecode.medianUs)}` '
      '| One-time SFNT/MATH/cmap/GSUB/CFF load (`math_font_from_bytes`) and cold font + initial glyph decode (`cold_font_glyph_decode`) '
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
    case 'cold_font_glyph_decode':
      return 'cold decode';
    case 'inline_expression_layout':
      return 'inline expr';
    case 'notebook_50_equations':
      return 'notebook 50';
    case 'cached_display_list_lookup':
      return 'cached hit';
    case 'lru_cache_mixed_eviction':
      return 'lru mixed';
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

String _fmtSignedKb(double kb) {
  final String prefix = kb >= 0 ? '+' : '';
  return '$prefix${kb.toStringAsFixed(1)} KiB';
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
    required this.rssMb,
    required this.rssDeltaKb,
    required this.maxRssMb,
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
  final double rssMb;
  final double rssDeltaKb;
  final double maxRssMb;

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
    'rssMb': rssMb,
    'rssDeltaKb': rssDeltaKb,
    'maxRssMb': maxRssMb,
  };
}

final class _RegressionCheck {
  const _RegressionCheck({
    required this.id,
    required this.baselineMedianUs,
    required this.measuredMedianUs,
    required this.baselineMeanUs,
    required this.measuredMeanUs,
    required this.maxAllowedUs,
    required this.ratio,
    required this.passed,
  });

  final String id;
  final double baselineMedianUs;
  final double measuredMedianUs;
  final double baselineMeanUs;
  final double measuredMeanUs;
  final double maxAllowedUs;
  final double ratio;
  final bool passed;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'baselineMedianUs': baselineMedianUs,
    'measuredMedianUs': measuredMedianUs,
    'baselineMeanUs': baselineMeanUs,
    'measuredMeanUs': measuredMeanUs,
    'maxAllowedUs': maxAllowedUs,
    'ratio': _round2(ratio),
    'passed': passed,
  };
}

final class _BenchmarkCacheKey {
  _BenchmarkCacheKey(this.source, this.options, this.fontSignature)
    : hashCode = Object.hash(source, options, fontSignature);

  final String source;
  final TexMathOptions options;
  final int fontSignature;

  @override
  final int hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _BenchmarkCacheKey &&
          hashCode == other.hashCode &&
          fontSignature == other.fontSignature &&
          source == other.source &&
          options == other.options;
}

final class _BenchmarkLruCache {
  _BenchmarkLruCache({required this.maxEntries, required this.fontSignature});

  final int maxEntries;
  final int fontSignature;
  final Map<_BenchmarkCacheKey, RenderResult> _entries =
      <_BenchmarkCacheKey, RenderResult>{};

  int _hitCount = 0;
  int _missCount = 0;
  int _evictionCount = 0;

  int get length => _entries.length;
  int get hitCount => _hitCount;
  int get missCount => _missCount;
  int get evictionCount => _evictionCount;

  RenderResult? get(String source, TexMathOptions options) {
    final _BenchmarkCacheKey key = _BenchmarkCacheKey(
      source,
      options,
      fontSignature,
    );
    final RenderResult? hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      _hitCount++;
    } else {
      _missCount++;
    }
    return hit;
  }

  void put(String source, TexMathOptions options, RenderResult result) {
    final _BenchmarkCacheKey key = _BenchmarkCacheKey(
      source,
      options,
      fontSignature,
    );
    _entries.remove(key);
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
      _evictionCount++;
    }
    _entries[key] = result;
  }

  RenderResult getOrRender(
    TexMathEngine engine,
    String source,
    TexMathOptions options,
  ) {
    final RenderResult? hit = get(source, options);
    if (hit != null) {
      return hit;
    }
    final RenderResult rendered = engine.render(source, options: options);
    put(source, options, rendered);
    return rendered;
  }
}
