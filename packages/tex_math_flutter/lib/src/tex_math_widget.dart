import 'package:flutter/material.dart';
import 'package:tex_math/tex_math.dart';

import 'display_painter.dart';
import 'error_widget.dart';
import 'theme.dart';

/// Builder callback invoked when [TexMath] catches a [TexMathError].
typedef TexMathErrorBuilder = Widget Function(
  BuildContext context,
  String source,
  TexMathError error,
);

/// Renders a TeX math expression or pre-computed [DisplayList] inside Flutter
/// with baseline alignment, text scaling, semantics, and selection support.
final class TexMath extends StatelessWidget {
  /// Creates a math widget rendering [source] with [displayMode].
  const TexMath(
    this.source, {
    super.key,
    this.displayMode = TexMathDisplayMode.display,
    this.options,
    this.engine = const TexMathEngine(),
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
  }) : displayList = null;

  /// Creates an inline math widget (`TexMathDisplayMode.inline`).
  const TexMath.inline(
    this.source, {
    super.key,
    this.options,
    this.engine = const TexMathEngine(),
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
  }) : displayMode = TexMathDisplayMode.inline,
       displayList = null;

  /// Creates a block display math widget (`TexMathDisplayMode.display`).
  const TexMath.display(
    this.source, {
    super.key,
    this.options,
    this.engine = const TexMathEngine(),
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
  }) : displayMode = TexMathDisplayMode.display,
       displayList = null;

  /// Creates a math widget directly from a pre-computed [DisplayList].
  const TexMath.displayList(
    DisplayList this.displayList, {
    super.key,
    this.source = '',
    this.displayMode = TexMathDisplayMode.display,
    this.options,
    this.engine = const TexMathEngine(),
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
  });

  /// TeX mathematical expression source string.
  final String source;

  /// Display mode (`inline` or `display`).
  final TexMathDisplayMode displayMode;

  /// Optional rendering and budget configuration passed to [engine].
  final TexMathOptions? options;

  /// Pure-Dart engine that parses and lays out [source].
  final TexMathEngine engine;

  /// Optional text style overriding ambient font size.
  final TextStyle? textStyle;

  /// Optional builder for custom error presentation when [engine] throws.
  final TexMathErrorBuilder? errorBuilder;

  /// Optional explicit accessibility label overriding [source].
  final String? semanticsLabel;

  /// Whether to wrap standalone output in a [SelectionArea] when no ancestor
  /// [SelectionContainer] exists.
  final bool selectable;

  /// Optional pre-laid-out [DisplayList] painted without invoking [engine].
  final DisplayList? displayList;

  @override
  Widget build(BuildContext context) {
    final TexMathThemeData theme = TexMathTheme.of(context);
    final TextStyle mergedStyle = DefaultTextStyle.of(context).style
        .merge(textStyle);
    final double baseSize = mergedStyle.fontSize ?? theme.fontSize;
    final double scaledFontSize = MediaQuery.textScalerOf(context)
        .scale(baseSize);

    final DisplayList? prebuilt = displayList;
    if (prebuilt != null) {
      return _buildDisplayListWidget(context, prebuilt, theme, scaledFontSize);
    }

    final TexMathOptions effectiveOptions = (options ?? engine.defaultOptions)
        .copyWith(displayMode: displayMode);

    try {
      final RenderResult result = engine.render(
        source,
        options: effectiveOptions,
      );
      return _buildDisplayListWidget(
        context,
        result.displayList,
        theme,
        scaledFontSize,
      );
    } on TexMathError catch (error) {
      if (errorBuilder != null) {
        return errorBuilder!(context, source, error);
      }
      return TexMathErrorWidget(
        source: source,
        error: error,
        displayMode: displayMode,
        selectable: selectable,
      );
    }
  }

  Widget _buildDisplayListWidget(
    BuildContext context,
    DisplayList list,
    TexMathThemeData theme,
    double fontSize,
  ) {
    final double width = (list.metrics.widthEm * fontSize).clamp(0.0, 1e6);
    final double height = (list.metrics.totalHeightEm * fontSize).clamp(
      0.0,
      1e6,
    );
    final double baseline = (list.metrics.baselineEm * fontSize).clamp(
      0.0,
      height,
    );

    final Widget painted = Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: CustomPaint(
        size: Size(width, height),
        painter: TexMathDisplayPainter(
          displayList: list,
          theme: theme,
          fontSize: fontSize,
        ),
      ),
    );

    final Widget maybeSelectable =
        selectable && SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: painted)
        : painted;

    final String label =
        semanticsLabel ??
        (source.isNotEmpty ? source : list.source ?? 'Math expression');

    return Semantics(label: label, readOnly: true, child: maybeSelectable);
  }
}

/// Baseline-aligned [WidgetSpan] helper for embedding inline TeX formulas inside
/// [Text.rich] or [RichText].
final class TexMathSpan extends WidgetSpan {
  /// Creates an inline math span aligned to the alphabetic text baseline.
  TexMathSpan(
    String source, {
    TexMathOptions? options,
    TexMathEngine engine = const TexMathEngine(),
    super.style,
    TexMathErrorBuilder? errorBuilder,
    String? semanticsLabel,
    bool selectable = false,
    super.alignment = PlaceholderAlignment.baseline,
    super.baseline = TextBaseline.alphabetic,
  }) : super(
         child: TexMath.inline(
           source,
           options: options,
           engine: engine,
           textStyle: style,
           errorBuilder: errorBuilder,
           semanticsLabel: semanticsLabel,
           selectable: selectable,
         ),
       );
}
