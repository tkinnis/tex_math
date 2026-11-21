import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'corpus_loader.dart';
import 'metrics_inspector.dart';
import 'visual_diff_view.dart';
import 'webview_bridge.dart';

/// Entry point for the `tex_math` macOS three-way comparison studio.
void main() {
  runApp(const TexMathStudioApp());
}

/// Root application widget for the three-way TeX math comparison workbench.
final class TexMathStudioApp extends StatefulWidget {
  /// Creates the studio workbench application.
  const TexMathStudioApp({
    super.key,
    this.corpusCatalog,
    this.initialFont,
    this.fontLoader,
    this.webPaneControllerFactory,
    this.initialSource,
    this.initialCapturedPair,
    this.initialDarkTheme = false,
  });

  /// Optional preloaded corpus catalog overriding runtime disk discovery.
  final StudioCorpusCatalog? corpusCatalog;

  /// Optional pre-decoded [MathFont] overriding asset bundle decoding.
  final MathFont? initialFont;

  /// Optional async font loader overriding [TexMathFontBundle.loadMathFont].
  final Future<MathFont> Function()? fontLoader;

  /// Optional web pane controller factory for headless tests or custom bridges.
  final StudioWebPaneControllerFactory? webPaneControllerFactory;

  /// Optional initial TeX expression loaded into the source editor.
  final String? initialSource;

  /// Optional pre-captured RGBA pair used by tests or external harnesses.
  final StudioCapturedPair? initialCapturedPair;

  /// Initial light/dark theme mode.
  final bool initialDarkTheme;

  @override
  State<TexMathStudioApp> createState() => _TexMathStudioAppState();
}

final class _TexMathStudioAppState extends State<TexMathStudioApp> {
  late bool _isDarkTheme;

  @override
  void initState() {
    super.initState();
    _isDarkTheme = widget.initialDarkTheme;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme lightScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: Brightness.light,
    );
    final ColorScheme darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF14B8A6),
      brightness: Brightness.dark,
    );
    final ColorScheme activeScheme = _isDarkTheme ? darkScheme : lightScheme;

    return MaterialApp(
      title: 'tex_math Studio',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
      darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
      home: TexMathTheme(
        data: TexMathThemeData.fromColorScheme(activeScheme, fontSize: 22.0),
        child: StudioWorkbenchPage(
          isDarkTheme: _isDarkTheme,
          onToggleTheme: () {
            setState(() {
              _isDarkTheme = !_isDarkTheme;
            });
          },
          corpusCatalog: widget.corpusCatalog,
          initialFont: widget.initialFont,
          fontLoader: widget.fontLoader,
          webPaneControllerFactory: widget.webPaneControllerFactory,
          initialSource: widget.initialSource,
          initialCapturedPair: widget.initialCapturedPair,
        ),
      ),
    );
  }
}

/// Interactive workbench providing corpus browsing, live TeX editing, 3-way
/// rendering (`tex_math`, MathJax `4.1.3`, KaTeX `0.19.1`), pixel/curtain
/// visual diffing, and metrics/export inspection.
final class StudioWorkbenchPage extends StatefulWidget {
  /// Creates the studio workbench page.
  const StudioWorkbenchPage({
    super.key,
    this.isDarkTheme = false,
    this.onToggleTheme,
    this.corpusCatalog,
    this.initialFont,
    this.fontLoader,
    this.webPaneControllerFactory,
    this.initialSource,
    this.initialCapturedPair,
  });

  /// Whether the active application theme is dark.
  final bool isDarkTheme;

  /// Callback toggling light vs dark application themes.
  final VoidCallback? onToggleTheme;

  /// Optional preloaded corpus catalog overriding runtime disk discovery.
  final StudioCorpusCatalog? corpusCatalog;

  /// Optional pre-decoded [MathFont] overriding bundle loading.
  final MathFont? initialFont;

  /// Optional async font loader overriding [TexMathFontBundle.loadMathFont].
  final Future<MathFont> Function()? fontLoader;

  /// Optional factory overriding `WKWebView` comparison pane controllers.
  final StudioWebPaneControllerFactory? webPaneControllerFactory;

  /// Optional initial TeX source expression.
  final String? initialSource;

  /// Optional initial captured image pair for visual diff inspection.
  final StudioCapturedPair? initialCapturedPair;

  @override
  State<StudioWorkbenchPage> createState() => _StudioWorkbenchPageState();
}

final class _StudioWorkbenchPageState extends State<StudioWorkbenchPage> {
  static const List<String> _presets = <String>[
    r'\frac{a + b}{c - d}',
    r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
    r'\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}',
    r'\ce{CO2 + C -> 2CO}',
    r'\undefinedcmd',
  ];

  final GlobalKey _texMathBoundaryKey = GlobalKey();
  late final TextEditingController _sourceController;
  late final TextEditingController _searchController;

  late StudioCorpusCatalog _catalog;
  bool _isLoadingCorpus = false;
  int _filteredCorpusCount = 0;
  List<_SidebarRow> _corpusRows = const <_SidebarRow>[];

  StudioLocalAssetServer? _assetServer;
  late final StudioWebPaneController _mathJaxController;
  late final StudioWebPaneController _katexController;

  MathFont? _mathFont;
  String? _fontLoadError;
  TexMathDisplayMode _displayMode = TexMathDisplayMode.display;
  StudioComparisonMode _comparisonMode = StudioComparisonMode.sideBySide;
  StudioDiffTarget _diffTarget = StudioDiffTarget.mathJax;

  String _searchQuery = '';
  String? _selectedTier;
  StudioCorpusAcceptanceFilter _acceptanceFilter =
      StudioCorpusAcceptanceFilter.all;
  StudioCorpusGrouping _grouping = StudioCorpusGrouping.tier;
  StudioCorpusEntry? _selectedEntry;
  bool _showSidebar = true;

  StudioCapturedPair? _capturedPair;
  bool _isCapturing = false;

  bool _hasInitializedInspection = false;
  Map<TexMathColorRole, String>? _cachedSvgColors;
  late TexMathOptions _cachedOptions;
  late TexMathEngine _cachedEngine;
  late StudioInspectionResult _inspection;

  @override
  void initState() {
    super.initState();
    final String initialText = widget.initialSource ?? _presets.first;
    _sourceController = TextEditingController(text: initialText);
    _searchController = TextEditingController();
    _capturedPair = widget.initialCapturedPair;

    if (widget.corpusCatalog != null) {
      _catalog = widget.corpusCatalog!;
    } else {
      _catalog = StudioCorpusCatalog.embeddedFallback();
      _isLoadingCorpus = true;
      unawaited(_loadDiskCorpus());
    }
    _rebuildCorpusRows();

    _mathFont =
        widget.initialFont ??
        (widget.fontLoader == null ? TexMathFontBundle.cachedMathFont : null);
    if (_mathFont == null) {
      unawaited(_loadFont());
    }

    final StudioOracleAssets? oracleAssets =
        widget.webPaneControllerFactory == null &&
            WebViewPlatform.instance != null
        ? StudioOracleAssetLocator.locate()
        : null;
    if (oracleAssets != null) {
      _assetServer = StudioLocalAssetServer(oracleAssets);
    }

    final StudioWebPaneControllerFactory factory =
        widget.webPaneControllerFactory ?? _defaultPaneControllerFactory;
    _mathJaxController = factory(StudioEngineKind.mathJax, _assetServer);
    _katexController = factory(StudioEngineKind.katex, _assetServer);

    unawaited(_initializeWebPanes());
    if (kDebugMode) {
      unawaited(_maybeRunCaptureSpec());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Map<TexMathColorRole, String> nextColors = <TexMathColorRole, String>{
      TexMathColorRole.foreground: _colorToHex(scheme.onSurface),
      TexMathColorRole.accent: _colorToHex(scheme.primary),
      TexMathColorRole.error: _colorToHex(scheme.error),
      TexMathColorRole.muted: _colorToHex(scheme.onSurfaceVariant),
    };
    if (!_hasInitializedInspection) {
      _hasInitializedInspection = true;
      _cachedSvgColors = nextColors;
      _recomputeInspection();
      return;
    }
    if (!_colorMapEquals(_cachedSvgColors, nextColors)) {
      _cachedSvgColors = nextColors;
      final StudioInspectionResult current = _inspection;
      if (current is StudioInspectionSuccess) {
        _inspection = StudioInspectionSuccess(
          renderResult: current.renderResult,
          glyphCount: current.glyphCount,
          ruleCount: current.ruleCount,
          anchorCount: current.anchorCount,
          breakHintCount: current.breakHintCount,
          svgFontSize: current.svgFontSize,
          svgColors: nextColors,
          oracleWidthEm: current.oracleWidthEm,
          oracleHeightEm: current.oracleHeightEm,
          oracleDepthEm: current.oracleDepthEm,
        );
      } else {
        _recomputeInspection();
      }
    }
  }

  Future<void> _loadDiskCorpus() async {
    try {
      final StudioCorpusCatalog loaded = await StudioCorpusLoader.loadAsync();
      if (!mounted) {
        return;
      }
      setState(() {
        _catalog = loaded;
        _isLoadingCorpus = false;
        _rebuildCorpusRows();
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingCorpus = false;
      });
    }
  }

  void _rebuildCorpusRows() {
    final List<StudioCorpusEntry> filtered = _catalog.filter(
      query: _searchQuery,
      tier: _selectedTier,
      acceptance: _acceptanceFilter,
    );
    final Map<String, List<StudioCorpusEntry>> grouped = _catalog.groupEntries(
      filtered,
      _grouping,
    );
    final List<_SidebarRow> rows = <_SidebarRow>[];
    for (final MapEntry<String, List<StudioCorpusEntry>> group
        in grouped.entries) {
      rows.add(_SidebarGroupHeader('${group.key} (${group.value.length})'));
      for (final StudioCorpusEntry entry in group.value) {
        rows.add(_SidebarEntryRow(entry));
      }
    }
    _filteredCorpusCount = filtered.length;
    _corpusRows = rows;
  }

  void _recomputeInspection() {
    final String source = _sourceController.text;
    final TexMathOptions options = _effectiveOptions;
    _cachedOptions = options;
    _cachedEngine = TexMathEngine(defaultOptions: options, font: _mathFont);
    _inspection = inspectTexExpression(
      source: source,
      displayMode: _displayMode,
      font: _mathFont,
      options: options,
      selectedEntry: _selectedEntry,
      svgFontSize: 22.0,
      svgColors: _cachedSvgColors,
      fontLoadError: _fontLoadError,
    );
  }

  static bool _colorMapEquals(
    Map<TexMathColorRole, String>? a,
    Map<TexMathColorRole, String>? b,
  ) {
    if (identical(a, b)) {
      return true;
    }
    if (a == null || b == null || a.length != b.length) {
      return false;
    }
    for (final MapEntry<TexMathColorRole, String> entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  Future<void> _maybeRunCaptureSpec() async {
    if (!kDebugMode || widget.webPaneControllerFactory != null) {
      return;
    }
    final String? specPath =
        Platform.environment['TEX_MATH_STUDIO_CAPTURE_SPEC'];
    if (specPath == null || specPath.isEmpty) {
      return;
    }
    final File specFile = File(specPath);
    if (!specFile.existsSync()) {
      return;
    }

    final Object? decoded = jsonDecode(await specFile.readAsString());
    if (!mounted || decoded is! Map<String, Object?>) {
      return;
    }
    final Object? rawHandshake = decoded['handshakeDir'];
    final Object? rawSteps = decoded['steps'];
    if (rawHandshake is! String || rawSteps is! List<Object?>) {
      return;
    }
    final Directory handshakeDir = Directory(rawHandshake);
    if (!handshakeDir.existsSync()) {
      handshakeDir.createSync(recursive: true);
    }

    await _waitUntilCondition(
      () =>
          !_isLoadingCorpus &&
          _mathFont != null &&
          _mathJaxController.telemetry.value.isReady &&
          !_mathJaxController.telemetry.value.isRendering &&
          _katexController.telemetry.value.isReady &&
          !_katexController.telemetry.value.isRendering,
      timeout: const Duration(seconds: 20),
    );
    if (!mounted) {
      return;
    }

    for (int index = 0; index < rawSteps.length; index++) {
      if (!mounted) {
        return;
      }
      final Object? rawStep = rawSteps[index];
      if (rawStep is! Map<String, Object?>) {
        continue;
      }
      await _executeCaptureStep(
        index: index,
        step: rawStep,
        handshakeDir: handshakeDir,
      );
      if (!mounted) {
        return;
      }
    }

    if (decoded['exitOnComplete'] == true) {
      await _assetServer?.close();
      if (!mounted) {
        return;
      }
      exit(0);
    }
  }

  Future<void> _executeCaptureStep({
    required int index,
    required Map<String, Object?> step,
    required Directory handshakeDir,
  }) async {
    final Object? rawId = step['id'];
    final String id = rawId is String ? rawId : 'step_$index';
    final Object? rawCaseId = step['caseId'];
    final String? caseId = rawCaseId is String ? rawCaseId : null;
    final StudioCorpusEntry? entry = caseId == null
        ? null
        : _findCorpusEntry(caseId);
    final Object? rawTex = step['tex'];
    final String nextSource =
        entry?.tex ?? (rawTex is String ? rawTex : _sourceController.text);
    final Object? rawDisplay = step['display'];
    final bool? displayOverride = rawDisplay is bool ? rawDisplay : null;
    final TexMathDisplayMode nextDisplay = displayOverride != null
        ? (displayOverride
              ? TexMathDisplayMode.display
              : TexMathDisplayMode.inline)
        : (entry != null
              ? (entry.display
                    ? TexMathDisplayMode.display
                    : TexMathDisplayMode.inline)
              : _displayMode);
    final Object? rawDiffTarget = step['diffTarget'];
    final StudioDiffTarget nextTarget = rawDiffTarget == 'katex'
        ? StudioDiffTarget.katex
        : StudioDiffTarget.mathJax;
    final Object? rawMode = step['mode'];
    final StudioComparisonMode targetMode = switch (rawMode) {
      'pixelDiff' => StudioComparisonMode.pixelDiff,
      'curtainDiff' => StudioComparisonMode.curtainDiff,
      _ => StudioComparisonMode.sideBySide,
    };

    setState(() {
      if (_sourceController.text != nextSource) {
        _sourceController.text = nextSource;
      }
      _selectedEntry = entry;
      _displayMode = nextDisplay;
      _diffTarget = nextTarget;
      _comparisonMode = StudioComparisonMode.sideBySide;
      _capturedPair = null;
      _recomputeInspection();
    });

    await _dispatchWebRender();
    if (!mounted) {
      return;
    }
    await _waitUntilCondition(
      () =>
          !_mathJaxController.telemetry.value.isRendering &&
          !_katexController.telemetry.value.isRendering,
      timeout: const Duration(seconds: 15),
    );
    if (!mounted) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 550));
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    if (targetMode != StudioComparisonMode.sideBySide) {
      await _captureForDiff();
      if (!mounted) {
        return;
      }
      setState(() {
        _comparisonMode = targetMode;
      });
      await Future<void>.delayed(const Duration(milliseconds: 550));
      if (!mounted) {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
    }

    final StudioWebRenderTelemetry mj = _mathJaxController.telemetry.value;
    final StudioWebRenderTelemetry kx = _katexController.telemetry.value;
    final File readyFile = File('${handshakeDir.path}/ready_$index.json');
    await readyFile.writeAsString(
      jsonEncode(<String, Object?>{
        'index': index,
        'id': id,
        'caseId': caseId,
        'matchedEntry': entry != null,
        'mode': targetMode.name,
        'mathJaxStatus': mj.statusSummary,
        'mathJaxError': mj.errorMessage,
        'mathJaxWidthPx': mj.widthPx,
        'mathJaxHeightPx': mj.heightPx,
        'katexStatus': kx.statusSummary,
        'katexError': kx.errorMessage,
        'katexWidthPx': kx.widthPx,
        'katexHeightPx': kx.heightPx,
        'capturedWidth': _capturedPair?.texMathImage.width,
        'capturedHeight': _capturedPair?.texMathImage.height,
      }),
    );
    if (!mounted) {
      return;
    }

    final File ackFile = File('${handshakeDir.path}/ack_$index');
    await _waitUntilCondition(
      ackFile.existsSync,
      timeout: const Duration(seconds: 30),
    );
  }

  StudioCorpusEntry? _findCorpusEntry(String caseId) {
    for (final StudioCorpusEntry entry in _catalog.entries) {
      if (entry.id == caseId) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _waitUntilCondition(
    bool Function() predicate, {
    required Duration timeout,
  }) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    while (!predicate() && stopwatch.elapsed < timeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) {
        return;
      }
    }
  }

  StudioWebPaneController _defaultPaneControllerFactory(
    StudioEngineKind kind,
    StudioLocalAssetServer? server,
  ) {
    if (WebViewPlatform.instance != null) {
      return WkWebViewStudioPaneController(
        engineKind: kind,
        assetServer: server,
      );
    }
    return HeadlessOraclePaneController(
      engineKind: kind,
      assetsAvailable: server != null,
    );
  }

  Future<void> _loadFont() async {
    try {
      final Future<MathFont> Function() loader =
          widget.fontLoader ?? TexMathFontBundle.loadMathFont;
      final MathFont loaded = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _mathFont = loaded;
        _fontLoadError = null;
        _recomputeInspection();
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fontLoadError = error.toString();
        _recomputeInspection();
      });
    }
  }

  Future<void> _initializeWebPanes() async {
    await Future.wait<void>(<Future<void>>[
      _mathJaxController.initialize(),
      _katexController.initialize(),
    ]);
    if (!mounted) {
      return;
    }
    await _dispatchWebRender();
  }

  @override
  void didUpdateWidget(StudioWorkbenchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDarkTheme != widget.isDarkTheme) {
      _capturedPair = null;
      unawaited(_dispatchWebRender());
    }
    if (oldWidget.initialCapturedPair != widget.initialCapturedPair &&
        widget.initialCapturedPair != null) {
      _capturedPair = widget.initialCapturedPair;
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _searchController.dispose();
    unawaited(_mathJaxController.dispose());
    unawaited(_katexController.dispose());
    unawaited(_assetServer?.close() ?? Future<void>.value());
    super.dispose();
  }

  TexMathOptions get _effectiveOptions {
    final List<String>? entryPackages =
        _selectedEntry != null && _selectedEntry!.tex == _sourceController.text
        ? _selectedEntry!.packages
        : null;
    return TexMathOptions(
      displayMode: _displayMode,
      packages: entryPackages ?? TexMathOptions.defaultPackages,
    );
  }

  Future<void> _dispatchWebRender() async {
    final StudioWebRenderRequest request = StudioWebRenderRequest(
      source: _sourceController.text,
      displayMode: _displayMode,
      isDarkTheme: widget.isDarkTheme,
      fontSize: 22.0,
      packages: _effectiveOptions.packages,
    );
    await Future.wait<void>(<Future<void>>[
      _mathJaxController.render(request),
      _katexController.render(request),
    ]);
  }

  void _updateSource(
    String nextSource, {
    StudioCorpusEntry? entry,
    TexMathDisplayMode? displayMode,
  }) {
    setState(() {
      if (_sourceController.text != nextSource) {
        _sourceController.text = nextSource;
      }
      _selectedEntry = entry;
      if (displayMode != null) {
        _displayMode = displayMode;
      }
      _capturedPair = null;
      _recomputeInspection();
    });
    unawaited(_dispatchWebRender());
  }

  Future<void> _captureForDiff() async {
    if (_isCapturing) {
      return;
    }
    setState(() {
      _isCapturing = true;
    });
    try {
      final StudioCapturedImage? texMathImg = await captureRepaintBoundaryRgba(
        _texMathBoundaryKey,
      );
      if (!mounted) {
        return;
      }
      final StudioWebPaneController targetController =
          _diffTarget == StudioDiffTarget.mathJax
          ? _mathJaxController
          : _katexController;
      final StudioCapturedImage? targetImg = await targetController.captureRgba(
        targetWidth: texMathImg?.width ?? 480,
        targetHeight: texMathImg?.height ?? 220,
      );
      if (!mounted) {
        return;
      }
      if (texMathImg != null && targetImg != null) {
        setState(() {
          _capturedPair = StudioCapturedPair(
            texMathImage: texMathImg,
            targetImage: targetImg,
            target: _diffTarget,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String source = _sourceController.text;
    final StudioInspectionResult inspection = _inspection;

    final Widget texMathLeaf;
    switch (inspection) {
      case StudioInspectionSuccess(:final DisplayList displayList):
        texMathLeaf = TexMath.displayList(
          displayList,
          source: source,
          displayMode: _displayMode,
          options: _cachedOptions,
          engine: _cachedEngine,
          font: _mathFont,
          textStyle: const TextStyle(fontSize: 22.0),
        );
      case StudioInspectionFailure(:final TexMathError error):
        texMathLeaf = TexMathErrorWidget(
          source: source,
          error: error,
          displayMode: _displayMode,
        );
      case StudioInspectionPending(:final String? fontLoadError):
        if (fontLoadError != null) {
          final ColorScheme scheme = Theme.of(context).colorScheme;
          texMathLeaf = Container(
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.4),
              border: Border.all(color: scheme.error),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Text(
              'Unable to load bundled math font: $fontLoadError',
              style: TextStyle(color: scheme.error, fontSize: 12.0),
            ),
          );
        } else {
          texMathLeaf = const Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('Loading math font…', style: TextStyle(fontSize: 12.0)),
          );
        }
    }

    final Widget texMathPane = Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8.0),
        child: texMathLeaf,
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('tex_math Comparison Studio'),
        actions: <Widget>[
          IconButton(
            tooltip: _showSidebar
                ? 'Hide Corpus Sidebar'
                : 'Show Corpus Sidebar',
            icon: Icon(_showSidebar ? Icons.menu_open : Icons.menu),
            onPressed: () {
              setState(() {
                _showSidebar = !_showSidebar;
              });
            },
          ),
          IconButton(
            tooltip: 'Toggle Light/Dark Theme',
            icon: Icon(widget.isDarkTheme ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: SegmentedButton<TexMathDisplayMode>(
              segments: const <ButtonSegment<TexMathDisplayMode>>[
                ButtonSegment<TexMathDisplayMode>(
                  value: TexMathDisplayMode.display,
                  label: Text('Display'),
                ),
                ButtonSegment<TexMathDisplayMode>(
                  value: TexMathDisplayMode.inline,
                  label: Text('Inline'),
                ),
              ],
              selected: <TexMathDisplayMode>{_displayMode},
              onSelectionChanged: (Set<TexMathDisplayMode> next) {
                if (next.first == _displayMode) {
                  return;
                }
                setState(() {
                  _displayMode = next.first;
                  _capturedPair = null;
                  _recomputeInspection();
                });
                unawaited(_dispatchWebRender());
              },
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double sidebarWidth = constraints.maxWidth < 980
              ? 220.0
              : 290.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_showSidebar)
                SizedBox(
                  width: sidebarWidth,
                  child: _buildCorpusSidebar(context),
                ),
              if (_showSidebar) const VerticalDivider(width: 1.0),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildToolbarAndPresets(context),
                      const SizedBox(height: 8.0),
                      TextField(
                        controller: _sourceController,
                        minLines: 1,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'TeX Source',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        style: const TextStyle(fontFamily: 'monospace'),
                        onChanged: (String value) {
                          _updateSource(value);
                        },
                      ),
                      const SizedBox(height: 8.0),
                      Expanded(
                        flex: 3,
                        child: StudioComparisonView(
                          mode: _comparisonMode,
                          diffTarget: _diffTarget,
                          onDiffTargetChanged: (StudioDiffTarget next) {
                            if (next == _diffTarget) {
                              return;
                            }
                            setState(() {
                              _diffTarget = next;
                              _capturedPair = null;
                            });
                          },
                          texMathBoundaryKey: _texMathBoundaryKey,
                          texMathPane: texMathPane,
                          mathJaxController: _mathJaxController,
                          katexController: _katexController,
                          capturedPair: _capturedPair,
                          isCapturing: _isCapturing,
                          onCaptureRequested: () {
                            unawaited(_captureForDiff());
                          },
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Expanded(
                        flex: 2,
                        child: StudioMetricsInspector(inspection: inspection),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbarAndPresets(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          SegmentedButton<StudioComparisonMode>(
            segments: StudioComparisonMode.values
                .map(
                  (StudioComparisonMode mode) =>
                      ButtonSegment<StudioComparisonMode>(
                        value: mode,
                        label: Text(mode.label),
                      ),
                )
                .toList(),
            selected: <StudioComparisonMode>{_comparisonMode},
            onSelectionChanged: (Set<StudioComparisonMode> next) {
              final StudioComparisonMode mode = next.first;
              setState(() {
                _comparisonMode = mode;
              });
              if (mode != StudioComparisonMode.sideBySide &&
                  _capturedPair == null) {
                unawaited(_captureForDiff());
              }
            },
          ),
          const SizedBox(width: 12.0),
          for (final String preset in _presets) ...<Widget>[
            ActionChip(
              label: Text(preset, overflow: TextOverflow.ellipsis),
              onPressed: () => _updateSource(preset),
            ),
            const SizedBox(width: 6.0),
          ],
        ],
      ),
    );
  }

  Widget _buildCorpusSidebar(BuildContext context) {
    final List<_SidebarRow> rows = _corpusRows;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _catalog.isFromDisk
                      ? 'Corpus ($_filteredCorpusCount/${_catalog.length})'
                      : 'Presets ($_filteredCorpusCount)',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownButton<StudioCorpusGrouping>(
                value: _grouping,
                isDense: true,
                underline: const SizedBox.shrink(),
                onChanged: (StudioCorpusGrouping? next) {
                  if (next == null || next == _grouping) {
                    return;
                  }
                  setState(() {
                    _grouping = next;
                    _rebuildCorpusRows();
                  });
                },
                items: StudioCorpusGrouping.values
                    .map(
                      (StudioCorpusGrouping g) =>
                          DropdownMenuItem<StudioCorpusGrouping>(
                            value: g,
                            child: Text(
                              'By ${g.label}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                    )
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Filter corpus…',
              prefixIcon: const Icon(Icons.search, size: 18.0),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 16.0),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                          _rebuildCorpusRows();
                        });
                      },
                    ),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (String value) {
              setState(() {
                _searchQuery = value;
                _rebuildCorpusRows();
              });
            },
          ),
          const SizedBox(height: 6.0),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                DropdownButton<String?>(
                  value: _selectedTier,
                  isDense: true,
                  hint: const Text('All Tiers'),
                  onChanged: (String? tier) {
                    if (tier == _selectedTier) {
                      return;
                    }
                    setState(() {
                      _selectedTier = tier;
                      _rebuildCorpusRows();
                    });
                  },
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Tiers'),
                    ),
                    ..._catalog.availableTiers.map(
                      (String tier) => DropdownMenuItem<String?>(
                        value: tier,
                        child: Text(tier),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8.0),
                DropdownButton<StudioCorpusAcceptanceFilter>(
                  value: _acceptanceFilter,
                  isDense: true,
                  onChanged: (StudioCorpusAcceptanceFilter? filter) {
                    if (filter == null || filter == _acceptanceFilter) {
                      return;
                    }
                    setState(() {
                      _acceptanceFilter = filter;
                      _rebuildCorpusRows();
                    });
                  },
                  items: StudioCorpusAcceptanceFilter.values
                      .map(
                        (StudioCorpusAcceptanceFilter f) =>
                            DropdownMenuItem<StudioCorpusAcceptanceFilter>(
                              value: f,
                              child: Text(f.label),
                            ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 10.0),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No matching corpus entries'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (BuildContext context, int index) {
                      final _SidebarRow row = rows[index];
                      switch (row) {
                        case _SidebarGroupHeader(:final String title):
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: 8.0,
                              bottom: 4.0,
                              left: 4.0,
                            ),
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          );
                        case _SidebarEntryRow(:final StudioCorpusEntry entry):
                          final bool selected = _selectedEntry?.id == entry.id;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            selected: selected,
                            title: Text(
                              entry.shortName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${entry.package} · '
                              '${entry.display ? "display" : "inline"} · '
                              '${entry.expectationStatus ?? entry.acceptanceLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Icon(
                              entry.accepted
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 16.0,
                              color: entry.accepted
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                            onTap: () {
                              _updateSource(
                                entry.tex,
                                entry: entry,
                                displayMode: entry.display
                                    ? TexMathDisplayMode.display
                                    : TexMathDisplayMode.inline,
                              );
                            },
                          );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _colorToHex(Color color) {
    final int argb = color.toARGB32();
    final int rgb = argb & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

sealed class _SidebarRow {
  const _SidebarRow();
}

final class _SidebarGroupHeader extends _SidebarRow {
  const _SidebarGroupHeader(this.title);

  final String title;
}

final class _SidebarEntryRow extends _SidebarRow {
  const _SidebarEntryRow(this.entry);

  final StudioCorpusEntry entry;
}
