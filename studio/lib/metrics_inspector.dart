import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'corpus_loader.dart';

/// Typed inspection outcome produced by [inspectTexExpression].
@immutable
sealed class StudioInspectionResult {
  /// Base constructor for studio inspection outcomes.
  const StudioInspectionResult();
}

/// Inspection state while `NewCMMath-Regular.otf` is still decoding.
@immutable
final class StudioInspectionPending extends StudioInspectionResult {
  /// Creates a pending inspection state with optional partial exports.
  const StudioInspectionPending({this.mathMl, this.spokenText});

  /// Presentation MathML parsed before layout when syntax is valid.
  final String? mathMl;

  /// Spoken text parsed before layout when syntax is valid.
  final String? spokenText;
}

/// Successful layout and export inspection snapshot for a TeX expression.
@immutable
final class StudioInspectionSuccess extends StudioInspectionResult {
  /// Creates a successful inspection snapshot.
  const StudioInspectionSuccess({
    required this.metrics,
    required this.glyphCount,
    required this.ruleCount,
    required this.anchorCount,
    required this.breakHintCount,
    required this.svgXml,
    required this.mathMl,
    required this.spokenText,
    this.oracleWidthEm,
    this.oracleHeightEm,
    this.oracleDepthEm,
  });

  /// Laid-out bounding box and baseline metrics in ems.
  final DisplayMetrics metrics;

  /// Number of emitted [GlyphItem] primitives.
  final int glyphCount;

  /// Number of emitted [RuleItem] primitives.
  final int ruleCount;

  /// Number of emitted [AnchorItem] primitives.
  final int anchorCount;

  /// Number of top-level [DisplayBreakHint] entries.
  final int breakHintCount;

  /// Generated standalone SVG XML string.
  final String svgXml;

  /// Generated Presentation MathML markup.
  final String mathMl;

  /// Generated plain spoken text string.
  final String spokenText;

  /// Expected MathJax oracle bounding width in ems, when matching a corpus case.
  final double? oracleWidthEm;

  /// Expected MathJax oracle bounding ascent in ems, when matching a corpus case.
  final double? oracleHeightEm;

  /// Expected MathJax oracle bounding descent in ems, when matching a corpus case.
  final double? oracleDepthEm;
}

/// Error snapshot when parsing, macro expansion, layout, or export throws a
/// [TexMathError].
@immutable
final class StudioInspectionFailure extends StudioInspectionResult {
  /// Creates an inspection failure state.
  const StudioInspectionFailure({
    required this.error,
    this.mathMl,
    this.spokenText,
  });

  /// Structured TeX math error thrown by the pure-Dart engine.
  final TexMathError error;

  /// Optional Presentation MathML if parsing succeeded before failure.
  final String? mathMl;

  /// Optional spoken text if parsing succeeded before failure.
  final String? spokenText;
}

/// Evaluates [source] synchronously through [TexMathEngine] to collect
/// [DisplayMetrics], primitive counts, SVG XML, Presentation MathML, and
/// spoken text.
StudioInspectionResult inspectTexExpression({
  required String source,
  required TexMathDisplayMode displayMode,
  MathFont? font,
  TexMathOptions options = const TexMathOptions(),
  StudioCorpusEntry? selectedEntry,
  double svgFontSize = 18.0,
  Map<TexMathColorRole, String>? svgColors,
}) {
  final TexMathOptions effectiveOptions = options.copyWith(
    displayMode: displayMode,
  );
  final TexMathEngine engine = TexMathEngine(
    defaultOptions: effectiveOptions,
    font: font,
  );

  if (font == null) {
    try {
      engine.parse(source, options: effectiveOptions);
      return StudioInspectionPending(
        mathMl: engine.toMathMl(source, options: effectiveOptions),
        spokenText: engine.toSpokenText(source, options: effectiveOptions),
      );
    } on TexMathError catch (error) {
      return StudioInspectionFailure(error: error);
    }
  }

  try {
    final RenderResult result = engine.render(
      source,
      options: effectiveOptions,
    );
    int glyphCount = 0;
    int ruleCount = 0;
    int anchorCount = 0;
    for (final DisplayItem item in result.displayList.items) {
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
      metrics: result.displayList.metrics,
      glyphCount: glyphCount,
      ruleCount: ruleCount,
      anchorCount: anchorCount,
      breakHintCount: result.displayList.breakHints.length,
      svgXml: result.toSvg(fontSize: svgFontSize, colors: svgColors),
      mathMl: result.toMathMl(),
      spokenText: result.toSpokenText(),
      oracleWidthEm: matchesCorpusEntry ? selectedEntry.oracleBoxWidthEm : null,
      oracleHeightEm: matchesCorpusEntry
          ? selectedEntry.oracleBoxHeightEm
          : null,
      oracleDepthEm: matchesCorpusEntry ? selectedEntry.oracleBoxDepthEm : null,
    );
  } on TexMathError catch (error) {
    String? mathMl;
    String? spokenText;
    try {
      mathMl = engine.toMathMl(source, options: effectiveOptions);
      spokenText = engine.toSpokenText(source, options: effectiveOptions);
    } on TexMathError {
      // Source failed during parsing; omit partial AST exports.
    }
    return StudioInspectionFailure(
      error: error,
      mathMl: mathMl,
      spokenText: spokenText,
    );
  }
}

/// Tabbed diagnostic inspector displaying live `DisplayMetrics`, primitive
/// counts, SVG XML, Presentation MathML, and spoken text.
final class StudioMetricsInspector extends StatelessWidget {
  /// Creates a metrics and export inspector widget.
  const StudioMetricsInspector({super.key, required this.inspection});

  /// Current inspection outcome for the active TeX source.
  final StudioInspectionResult inspection;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const TabBar(
              isScrollable: true,
              tabs: <Tab>[
                Tab(text: 'Metrics'),
                Tab(text: 'SVG'),
                Tab(text: 'MathML'),
                Tab(text: 'Spoken'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _buildMetricsTab(context),
                  _buildExportTab(
                    context,
                    label: 'SVG XML',
                    content: _svgContent(inspection),
                  ),
                  _buildExportTab(
                    context,
                    label: 'Presentation MathML',
                    content: _mathMlContent(inspection),
                  ),
                  _buildExportTab(
                    context,
                    label: 'Spoken Text',
                    content: _spokenContent(inspection),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsTab(BuildContext context) {
    switch (inspection) {
      case StudioInspectionPending():
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Text('Loading NewCMMath-Regular.otf metrics…'),
          ),
        );
      case StudioInspectionFailure(:final TexMathError error):
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
              const SizedBox(height: 4.0),
              SelectableText(
                error.message,
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

  Widget _buildExportTab(
    BuildContext context, {
    required String label,
    required String? content,
  }) {
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

  static String? _svgContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess(:final String svgXml):
        return svgXml;
      case StudioInspectionPending():
      case StudioInspectionFailure():
        return null;
    }
  }

  static String? _mathMlContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess(:final String mathMl):
        return mathMl;
      case StudioInspectionPending(:final String? mathMl):
      case StudioInspectionFailure(:final String? mathMl):
        return mathMl;
    }
  }

  static String? _spokenContent(StudioInspectionResult result) {
    switch (result) {
      case StudioInspectionSuccess(:final String spokenText):
        return spokenText;
      case StudioInspectionPending(:final String? spokenText):
      case StudioInspectionFailure(:final String? spokenText):
        return spokenText;
    }
  }

  static String _fmtDelta(double delta) {
    final String sign = delta >= 0 ? '+' : '';
    return '$sign${delta.toStringAsFixed(3)}';
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
