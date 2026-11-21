import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'corpus_loader.dart';

final class _LazyInspectionExports {
  String? svgXml;
  String? mathMl;
  String? spokenText;
}

/// Typed inspection outcome produced by [inspectTexExpression].
@immutable
sealed class StudioInspectionResult {
  /// Base constructor for studio inspection outcomes.
  const StudioInspectionResult();
}

/// Inspection state while `NewCMMath-Regular.otf` is still decoding or
/// failed to load.
@immutable
final class StudioInspectionPending extends StudioInspectionResult {
  /// Creates a pending inspection state with optional pre-parsed [syntaxTree]
  /// or [fontLoadError].
  StudioInspectionPending({
    this.syntaxTree,
    this.fontLoadError,
    String? mathMl,
    String? spokenText,
  }) : _explicitMathMl = mathMl,
       _explicitSpokenText = spokenText,
       _exports = _LazyInspectionExports();

  /// Parsed AST when syntax succeeded prior to font availability.
  final MathNode? syntaxTree;

  /// Error details when bundled font decoding failed.
  final String? fontLoadError;

  final String? _explicitMathMl;
  final String? _explicitSpokenText;
  final _LazyInspectionExports _exports;

  /// Presentation MathML computed lazily from [syntaxTree] when syntax is valid.
  String? get mathMl {
    if (_explicitMathMl != null) {
      return _explicitMathMl;
    }
    final MathNode? tree = syntaxTree;
    if (tree == null) {
      return null;
    }
    return _exports.mathMl ??= mathNodeToMathMl(tree);
  }

  /// Spoken text computed lazily from [syntaxTree] when syntax is valid.
  String? get spokenText {
    if (_explicitSpokenText != null) {
      return _explicitSpokenText;
    }
    final MathNode? tree = syntaxTree;
    if (tree == null) {
      return null;
    }
    return _exports.spokenText ??= mathNodeToSpokenText(tree);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioInspectionPending &&
          syntaxTree == other.syntaxTree &&
          fontLoadError == other.fontLoadError &&
          _explicitMathMl == other._explicitMathMl &&
          _explicitSpokenText == other._explicitSpokenText;

  @override
  int get hashCode => Object.hash(
    syntaxTree,
    fontLoadError,
    _explicitMathMl,
    _explicitSpokenText,
  );
}

/// Successful layout and export inspection snapshot for a TeX expression.
@immutable
final class StudioInspectionSuccess extends StudioInspectionResult {
  /// Creates a successful inspection snapshot backed by [renderResult].
  StudioInspectionSuccess({
    required this.renderResult,
    required this.glyphCount,
    required this.ruleCount,
    required this.anchorCount,
    required this.breakHintCount,
    this.svgFontSize = 18.0,
    Map<TexMathColorRole, String>? svgColors,
    this.oracleWidthEm,
    this.oracleHeightEm,
    this.oracleDepthEm,
  }) : svgColors = svgColors == null
           ? null
           : Map<TexMathColorRole, String>.unmodifiable(svgColors),
       _exports = _LazyInspectionExports();

  /// Combined syntax tree and laid-out display result shared with the preview.
  final RenderResult renderResult;

  /// Laid-out bounding box and baseline metrics in ems.
  DisplayMetrics get metrics => renderResult.displayList.metrics;

  /// Laid-out display list ready for `TexMath.displayList(...)`.
  DisplayList get displayList => renderResult.displayList;

  /// Parsed AST preserved for selection and accessibility.
  MathNode get syntaxTree => renderResult.syntaxTree;

  /// Number of emitted [GlyphItem] primitives.
  final int glyphCount;

  /// Number of emitted [RuleItem] primitives.
  final int ruleCount;

  /// Number of emitted [AnchorItem] primitives.
  final int anchorCount;

  /// Number of top-level [DisplayBreakHint] entries.
  final int breakHintCount;

  /// Font size in logical pixels used for standalone SVG export.
  final double svgFontSize;

  /// Optional theme color overrides for standalone SVG export.
  final Map<TexMathColorRole, String>? svgColors;

  /// Expected MathJax oracle bounding width in ems, when matching a corpus case.
  final double? oracleWidthEm;

  /// Expected MathJax oracle bounding ascent in ems, when matching a corpus case.
  final double? oracleHeightEm;

  /// Expected MathJax oracle bounding descent in ems, when matching a corpus case.
  final double? oracleDepthEm;

  final _LazyInspectionExports _exports;

  /// Generated standalone SVG XML string (computed lazily on first access).
  String get svgXml => _exports.svgXml ??= renderResult.toSvg(
    fontSize: svgFontSize,
    colors: svgColors,
  );

  /// Generated Presentation MathML markup (computed lazily on first access).
  String get mathMl => _exports.mathMl ??= renderResult.toMathMl();

  /// Generated plain spoken text string (computed lazily on first access).
  String get spokenText => _exports.spokenText ??= renderResult.toSpokenText();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioInspectionSuccess &&
          renderResult == other.renderResult &&
          glyphCount == other.glyphCount &&
          ruleCount == other.ruleCount &&
          anchorCount == other.anchorCount &&
          breakHintCount == other.breakHintCount &&
          svgFontSize == other.svgFontSize &&
          mapEquals(svgColors, other.svgColors) &&
          oracleWidthEm == other.oracleWidthEm &&
          oracleHeightEm == other.oracleHeightEm &&
          oracleDepthEm == other.oracleDepthEm;

  @override
  int get hashCode => Object.hash(
    renderResult,
    glyphCount,
    ruleCount,
    anchorCount,
    breakHintCount,
    svgFontSize,
    svgColors == null
        ? null
        : Object.hashAllUnordered(
            svgColors!.entries.map(
              (MapEntry<TexMathColorRole, String> e) =>
                  Object.hash(e.key, e.value),
            ),
          ),
    oracleWidthEm,
    oracleHeightEm,
    oracleDepthEm,
  );
}

/// Error snapshot when parsing, macro expansion, layout, or export throws a
/// [TexMathError].
@immutable
final class StudioInspectionFailure extends StudioInspectionResult {
  /// Creates an inspection failure state.
  StudioInspectionFailure({
    required this.error,
    this.source,
    this.syntaxTree,
    String? mathMl,
    String? spokenText,
  }) : _explicitMathMl = mathMl,
       _explicitSpokenText = spokenText,
       _exports = _LazyInspectionExports();

  /// Structured TeX math error thrown by the pure-Dart engine.
  final TexMathError error;

  /// Original TeX math input that triggered [error], when available.
  final String? source;

  /// Optional parsed AST if parsing succeeded before layout failure.
  final MathNode? syntaxTree;

  final String? _explicitMathMl;
  final String? _explicitSpokenText;
  final _LazyInspectionExports _exports;

  /// Optional Presentation MathML computed lazily when [syntaxTree] exists.
  String? get mathMl {
    if (_explicitMathMl != null) {
      return _explicitMathMl;
    }
    final MathNode? tree = syntaxTree;
    if (tree == null) {
      return null;
    }
    return _exports.mathMl ??= mathNodeToMathMl(tree);
  }

  /// Optional spoken text computed lazily when [syntaxTree] exists.
  String? get spokenText {
    if (_explicitSpokenText != null) {
      return _explicitSpokenText;
    }
    final MathNode? tree = syntaxTree;
    if (tree == null) {
      return null;
    }
    return _exports.spokenText ??= mathNodeToSpokenText(tree);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioInspectionFailure &&
          error == other.error &&
          source == other.source &&
          syntaxTree == other.syntaxTree &&
          _explicitMathMl == other._explicitMathMl &&
          _explicitSpokenText == other._explicitSpokenText;

  @override
  int get hashCode => Object.hash(
    error,
    source,
    syntaxTree,
    _explicitMathMl,
    _explicitSpokenText,
  );
}

/// Evaluates [source] synchronously through [TexMathEngine] once to collect
/// [DisplayMetrics], primitive counts, and a shared [RenderResult] whose
/// SVG XML, Presentation MathML, and spoken text exports are evaluated lazily.
StudioInspectionResult inspectTexExpression({
  required String source,
  required TexMathDisplayMode displayMode,
  MathFont? font,
  TexMathOptions options = const TexMathOptions(),
  StudioCorpusEntry? selectedEntry,
  double svgFontSize = 18.0,
  Map<TexMathColorRole, String>? svgColors,
  String? fontLoadError,
}) {
  final TexMathOptions effectiveOptions = options.copyWith(
    displayMode: displayMode,
  );
  final TexMathEngine engine = TexMathEngine(
    defaultOptions: effectiveOptions,
    font: font,
  );

  final MathNode tree;
  try {
    tree = engine.parse(source, options: effectiveOptions);
  } on TexMathError catch (error) {
    return StudioInspectionFailure(error: error, source: source);
  }

  if (font == null) {
    return StudioInspectionPending(
      syntaxTree: tree,
      fontLoadError: fontLoadError,
    );
  }

  try {
    final DisplayList displayList = engine.layout(
      tree,
      options: effectiveOptions,
      font: font,
    );
    final RenderResult result = RenderResult(
      displayList: displayList,
      syntaxTree: tree,
      source: source,
    );
    int glyphCount = 0;
    int ruleCount = 0;
    int anchorCount = 0;
    for (final DisplayItem item in displayList.items) {
      switch (item) {
        case GlyphItem():
          glyphCount++;
        case RuleItem():
          ruleCount++;
        case AnchorItem():
          anchorCount++;
      }
    }

    final bool matchesCorpusEntry =
        selectedEntry != null && selectedEntry.tex == source;

    return StudioInspectionSuccess(
      renderResult: result,
      glyphCount: glyphCount,
      ruleCount: ruleCount,
      anchorCount: anchorCount,
      breakHintCount: displayList.breakHints.length,
      svgFontSize: svgFontSize,
      svgColors: svgColors,
      oracleWidthEm: matchesCorpusEntry ? selectedEntry.oracleBoxWidthEm : null,
      oracleHeightEm: matchesCorpusEntry
          ? selectedEntry.oracleBoxHeightEm
          : null,
      oracleDepthEm: matchesCorpusEntry ? selectedEntry.oracleBoxDepthEm : null,
    );
  } on TexMathError catch (error) {
    return StudioInspectionFailure(
      error: error,
      source: source,
      syntaxTree: tree,
    );
  }
}

/// Tabbed diagnostic inspector displaying live `DisplayMetrics`, primitive
/// counts, and lazily evaluated SVG XML, Presentation MathML, and spoken text.
final class StudioMetricsInspector extends StatefulWidget {
  /// Creates a metrics and export inspector widget.
  const StudioMetricsInspector({super.key, required this.inspection});

  /// Current inspection outcome for the active TeX source.
  final StudioInspectionResult inspection;

  @override
  State<StudioMetricsInspector> createState() => _StudioMetricsInspectorState();
}

final class _StudioMetricsInspectorState extends State<StudioMetricsInspector>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  bool _isTabVisible(int tabIndex) {
    if (_tabController.index == tabIndex) {
      return true;
    }
    final double animValue =
        _tabController.animation?.value ?? _tabController.index.toDouble();
    return (animValue - tabIndex).abs() < 0.99;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const <Tab>[
              Tab(text: 'Metrics'),
              Tab(text: 'SVG'),
              Tab(text: 'MathML'),
              Tab(text: 'Spoken'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _buildMetricsTab(context),
                _LazyExportTab(
                  active: _isTabVisible(1),
                  label: 'SVG XML',
                  computeContent: () => _svgContent(widget.inspection),
                ),
                _LazyExportTab(
                  active: _isTabVisible(2),
                  label: 'Presentation MathML',
                  computeContent: () => _mathMlContent(widget.inspection),
                ),
                _LazyExportTab(
                  active: _isTabVisible(3),
                  label: 'Spoken Text',
                  computeContent: () => _spokenContent(widget.inspection),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsTab(BuildContext context) {
    final StudioInspectionResult inspection = widget.inspection;
    switch (inspection) {
      case StudioInspectionPending(:final String? fontLoadError):
        if (fontLoadError != null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Font Load Error',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4.0),
                SelectableText(
                  fontLoadError,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.0,
                  ),
                ),
              ],
            ),
          );
        }
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('Loading NewCMMath-Regular.otf metrics…'),
          ),
        );
      case StudioInspectionFailure(
        :final TexMathError error,
        :final String? source,
      ):
        final SourceSpan? span = error.span;
        final String diagnosticText = source != null && span != null
            ? error.formatWithSource(source)
            : error.formattedMessage;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Error Class: ${error.errorClass.name}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              if (span != null) ...<Widget>[
                const SizedBox(height: 2.0),
                Text(
                  'Position: ${error.position} (span ${span.start}..${span.end})',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.0,
                  ),
                ),
              ],
              const SizedBox(height: 4.0),
              SelectableText(
                diagnosticText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0),
              ),
            ],
          ),
        );
      case StudioInspectionSuccess(
        :final DisplayMetrics metrics,
        :final int glyphCount,
        :final int ruleCount,
        :final int anchorCount,
        :final int breakHintCount,
        :final double? oracleWidthEm,
        :final double? oracleHeightEm,
        :final double? oracleDepthEm,
      ):
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: <Widget>[
              _MetricBadge(
                label: 'widthEm',
                value: metrics.widthEm.toStringAsFixed(4),
              ),
              _MetricBadge(
                label: 'heightEm',
                value: metrics.heightEm.toStringAsFixed(4),
              ),
              _MetricBadge(
                label: 'depthEm',
                value: metrics.depthEm.toStringAsFixed(4),
              ),
              _MetricBadge(
                label: 'baselineEm',
                value: metrics.baselineEm.toStringAsFixed(4),
              ),
              _MetricBadge(label: 'GlyphItem', value: '$glyphCount'),
              _MetricBadge(label: 'RuleItem', value: '$ruleCount'),
              _MetricBadge(label: 'AnchorItem', value: '$anchorCount'),
              _MetricBadge(label: 'BreakHints', value: '$breakHintCount'),
              if (oracleWidthEm != null &&
                  oracleHeightEm != null &&
                  oracleDepthEm != null)
                _MetricBadge(
                  label: 'Oracle Δ(w,h,d)',
                  value:
                      '${_fmtDelta(metrics.widthEm - oracleWidthEm)}, '
                      '${_fmtDelta(metrics.heightEm - oracleHeightEm)}, '
                      '${_fmtDelta(metrics.depthEm - oracleDepthEm)}',
                ),
            ],
          ),
        );
    }
  }

  static String? _svgContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess():
        try {
          return result.svgXml;
        } on TexMathError catch (error) {
          return 'SVG export error (${error.errorClass.name}): ${error.message}';
        }
      case StudioInspectionPending():
      case StudioInspectionFailure():
        return null;
    }
  }

  static String? _mathMlContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess():
        return result.mathMl;
      case StudioInspectionPending():
        return result.mathMl;
      case StudioInspectionFailure():
        return result.mathMl;
    }
  }

  static String? _spokenContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess():
        return result.spokenText;
      case StudioInspectionPending():
        return result.spokenText;
      case StudioInspectionFailure():
        return result.spokenText;
    }
  }

  static String _fmtDelta(double delta) {
    final String sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(3)}';
  }
}

final class _LazyExportTab extends StatelessWidget {
  const _LazyExportTab({
    required this.active,
    required this.label,
    required this.computeContent,
  });

  final bool active;
  final String label;
  final String? Function() computeContent;

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const SizedBox.shrink();
    }
    final String? content = computeContent();
    if (content == null || content.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Text('No $label output for current expression.'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  unawaited(Clipboard.setData(ClipboardData(text: content)));
                },
                icon: const Icon(Icons.copy, size: 14.0),
                label: const Text('Copy'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MetricBadge extends StatelessWidget {
  const _MetricBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              fontSize: 12.0,
            ),
          ),
        ],
      ),
    );
  }
}
