import 'dart:async';

// Keeps ColorScheme/SelectionArea type compatibility with Flutter 3.32-3.47+ callers.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show SelectionArea, Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:tex_math/tex_math.dart';

import 'display_painter.dart';
import 'error_widget.dart';
import 'font_bundle.dart';
import 'isolate_layouter.dart';
import 'selection_adapter.dart';
import 'theme.dart';

/// Builder callback invoked when [TexMath] catches a [TexMathError].
typedef TexMathErrorBuilder =
    Widget Function(BuildContext context, String source, TexMathError error);

/// Renders a TeX math expression or pre-computed [DisplayList] inside Flutter
/// with OpenType `MATH` glyph path caching, alphabetic baseline alignment,
/// configurable overflow handling, spoken-text semantics, and `"copy as LaTeX"`
/// sub-expression selection.
final class TexMath extends StatefulWidget {
  /// Creates a math widget rendering [source] with [displayMode].
  const TexMath(
    this.source, {
    super.key,
    this.displayMode = TexMathDisplayMode.display,
    this.options,
    this.engine = const TexMathEngine(),
    this.font,
    this.overflow,
    this.pathCache,
    this.layouter,
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
    this.onLinkTap,
    this.debugOnLayout,
  }) : displayList = null,
       _inheritAncestorSelection = false;

  /// Creates an inline math widget (`TexMathDisplayMode.inline`).
  const TexMath.inline(
    this.source, {
    super.key,
    this.options,
    this.engine = const TexMathEngine(),
    this.font,
    this.overflow = TexMathOverflow.visible,
    this.pathCache,
    this.layouter,
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
    this.onLinkTap,
    this.debugOnLayout,
  }) : displayMode = TexMathDisplayMode.inline,
       displayList = null,
       _inheritAncestorSelection = false;

  /// Creates a block display math widget (`TexMathDisplayMode.display`).
  const TexMath.display(
    this.source, {
    super.key,
    this.options,
    this.engine = const TexMathEngine(),
    this.font,
    this.overflow = TexMathOverflow.scroll,
    this.pathCache,
    this.layouter,
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
    this.onLinkTap,
    this.debugOnLayout,
  }) : displayMode = TexMathDisplayMode.display,
       displayList = null,
       _inheritAncestorSelection = false;

  /// Creates a math widget directly from a pre-computed [DisplayList].
  const TexMath.displayList(
    DisplayList this.displayList, {
    super.key,
    this.source = '',
    this.displayMode = TexMathDisplayMode.display,
    this.options,
    this.engine = const TexMathEngine(),
    this.font,
    this.overflow,
    this.pathCache,
    this.layouter,
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.selectable = true,
    this.onLinkTap,
    this.debugOnLayout,
  }) : _inheritAncestorSelection = false;

  const TexMath._spanChild(
    this.source,
    this._inheritAncestorSelection, {
    this.options,
    this.engine = const TexMathEngine(),
    this.font,
    this.overflow = TexMathOverflow.visible,
    this.pathCache,
    this.layouter,
    this.textStyle,
    this.errorBuilder,
    this.semanticsLabel,
    this.onLinkTap,
    required this.selectable,
  }) : displayMode = TexMathDisplayMode.inline,
       displayList = null,
       debugOnLayout = null;

  /// TeX mathematical expression source string.
  final String source;

  /// Display mode (`inline` or `display`).
  final TexMathDisplayMode displayMode;

  /// Optional rendering and budget configuration passed to [engine].
  final TexMathOptions? options;

  /// Pure-Dart engine that parses and lays out [source].
  final TexMathEngine engine;

  /// Optional explicit [MathFont] overriding [engine].font and the bundled
  /// `NewCMMath-Regular.otf` font.
  final MathFont? font;

  /// Policy applied when the laid-out expression exceeds horizontal
  /// constraints.
  ///
  /// Defaults to [TexMathOverflow.scroll] for [TexMathDisplayMode.display] and
  /// [TexMathOverflow.visible] for [TexMathDisplayMode.inline].
  final TexMathOverflow? overflow;

  /// Optional glyph path cache overriding [TexMathPathCache.shared].
  final TexMathPathCache? pathCache;

  /// Optional background isolate layouter used for asynchronous off-thread
  /// rendering and LRU caching.
  final TexMathIsolateLayouter? layouter;

  /// Optional text style overriding ambient font size.
  final TextStyle? textStyle;

  /// Optional builder for custom error presentation when [engine] throws.
  final TexMathErrorBuilder? errorBuilder;

  /// Optional explicit accessibility label overriding the generated spoken
  /// math description.
  final String? semanticsLabel;

  /// Whether to wrap standalone output in a [SelectionArea] when no ancestor
  /// [SelectionContainer] exists.
  final bool selectable;

  /// Optional pre-laid-out [DisplayList] painted without invoking [engine].
  final DisplayList? displayList;

  /// Optional callback invoked with the target URI when a safe `\href` link
  /// inside the rendered math expression is tapped.
  final ValueChanged<String>? onLinkTap;

  /// Optional diagnostic callback invoked whenever TeX layout executes.
  @visibleForTesting
  final VoidCallback? debugOnLayout;

  final bool _inheritAncestorSelection;

  /// Effective overflow policy taking [overflow] and [displayMode] into account.
  TexMathOverflow get effectiveOverflow =>
      overflow ??
      (displayMode == TexMathDisplayMode.display
          ? TexMathOverflow.scroll
          : TexMathOverflow.visible);

  @override
  State<TexMath> createState() => _TexMathState();
}

final class _TexMathState extends State<TexMath> {
  MathFont? _bundledFont;
  RenderResult? _renderResult;
  RenderResult? _spokenLabelSource;
  String? _cachedSpokenLabel;
  TexMathError? _error;
  bool _isLoading = false;
  int _layoutToken = 0;

  MathFont? get _explicitFont => widget.font ?? widget.engine.font;

  MathFont? get _resolvedFont =>
      _explicitFont ?? _bundledFont ?? TexMathFontBundle.cachedMathFont;

  TexMathOptions get _effectiveOptions =>
      (widget.options ?? widget.engine.defaultOptions).copyWith(
        displayMode: widget.displayMode,
      );

  @override
  void initState() {
    super.initState();
    _prepareLayout();
  }

  @override
  void didUpdateWidget(TexMath oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.semanticsLabel != oldWidget.semanticsLabel) {
      _spokenLabelSource = null;
      _cachedSpokenLabel = null;
    }
    final bool layoutInputsChanged =
        widget.displayList != oldWidget.displayList ||
        widget.source != oldWidget.source ||
        widget.displayMode != oldWidget.displayMode ||
        widget.options != oldWidget.options ||
        widget.engine != oldWidget.engine ||
        widget.font != oldWidget.font ||
        !identical(widget.layouter, oldWidget.layouter);

    if (layoutInputsChanged) {
      _prepareLayout();
    }
  }

  void _setRenderResult(RenderResult? result) {
    _renderResult = result;
    if (!identical(_spokenLabelSource, result)) {
      _spokenLabelSource = null;
      _cachedSpokenLabel = null;
    }
  }

  void _prepareLayout() {
    final int token = ++_layoutToken;

    if (widget.displayList != null) {
      _setRenderResult(null);
      _error = null;
      _isLoading = false;
      return;
    }

    final TexMathOptions effectiveOptions = _effectiveOptions;
    final TexMathIsolateLayouter? layouter = widget.layouter;

    if (layouter != null) {
      final MathFont? explicitFont = _explicitFont;
      final MathFont? cacheLookupFont =
          explicitFont ?? (!layouter.hasFontBytes ? _resolvedFont : null);
      final RenderResult? cached = layouter.getCached(
        widget.source,
        options: effectiveOptions,
        font: cacheLookupFont,
      );
      if (cached != null) {
        _setRenderResult(cached);
        _error = null;
        _isLoading = false;
        return;
      }
      _setRenderResult(null);
      _error = null;
      _isLoading = true;
      unawaited(
        _runIsolateLayout(
          token: token,
          layouter: layouter,
          options: effectiveOptions,
          explicitFont: explicitFont,
        ),
      );
      return;
    }

    final MathFont? font = _resolvedFont;
    if (font != null) {
      _runSyncLayout(font: font, options: effectiveOptions);
      return;
    }

    final MathNode parsedTree;
    try {
      parsedTree = widget.engine.parse(
        widget.source,
        options: effectiveOptions,
      );
    } on TexMathError catch (error) {
      _setRenderResult(null);
      _error = error;
      _isLoading = false;
      return;
    }

    _setRenderResult(null);
    _error = null;
    _isLoading = true;
    unawaited(
      _loadFontAndLayout(
        token: token,
        syntaxTree: parsedTree,
        options: effectiveOptions,
      ),
    );
  }

  void _runSyncLayout({
    required MathFont font,
    required TexMathOptions options,
  }) {
    try {
      widget.debugOnLayout?.call();
      _setRenderResult(
        widget.engine.render(widget.source, options: options, font: font),
      );
      _error = null;
      _isLoading = false;
    } on TexMathError catch (error) {
      _setRenderResult(null);
      _error = error;
      _isLoading = false;
    }
  }

  void _runLayoutFromTree({
    required MathNode syntaxTree,
    required MathFont font,
    required TexMathOptions options,
  }) {
    try {
      widget.debugOnLayout?.call();
      final DisplayList displayList = widget.engine.layout(
        syntaxTree,
        options: options,
        font: font,
      );
      _setRenderResult(
        RenderResult(
          displayList: displayList,
          syntaxTree: syntaxTree,
          source: widget.source,
        ),
      );
      _error = null;
      _isLoading = false;
    } on TexMathError catch (error) {
      _setRenderResult(null);
      _error = error;
      _isLoading = false;
    }
  }

  Future<void> _loadFontAndLayout({
    required int token,
    required MathNode syntaxTree,
    required TexMathOptions options,
  }) async {
    try {
      final MathFont loadedFont = await TexMathFontBundle.loadMathFont();
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _bundledFont = loadedFont;
        _runLayoutFromTree(
          syntaxTree: syntaxTree,
          font: loadedFont,
          options: options,
        );
      });
    } on TexMathError catch (error) {
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _setRenderResult(null);
        _error = error;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _setRenderResult(null);
        _error = TexMathFontError('Unable to load bundled math font: $error');
        _isLoading = false;
      });
    }
  }

  Future<void> _runIsolateLayout({
    required int token,
    required TexMathIsolateLayouter layouter,
    required TexMathOptions options,
    required MathFont? explicitFont,
  }) async {
    try {
      MathFont? effectiveFont = explicitFont;
      if (!layouter.hasFontBytes && effectiveFont == null) {
        final MathFont? resolved = _resolvedFont;
        if (resolved != null) {
          effectiveFont = resolved;
        } else {
          final MathFont loadedFont = await TexMathFontBundle.loadMathFont();
          if (!mounted || token != _layoutToken) {
            return;
          }
          _bundledFont = loadedFont;
          effectiveFont = loadedFont;
        }
      }
      widget.debugOnLayout?.call();
      final RenderResult result = await layouter.renderInBackground(
        widget.source,
        options: options,
        engine: widget.engine,
        font: effectiveFont,
      );
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _setRenderResult(result);
        _error = null;
        _isLoading = false;
      });
    } on TexMathError catch (error) {
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _setRenderResult(null);
        _error = error;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || token != _layoutToken) {
        return;
      }
      setState(() {
        _setRenderResult(null);
        _error = TexMathFontError('Background layout failed: $error');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TexMathThemeData? inheritedTheme = TexMathTheme.maybeOf(context);
    final TexMathThemeData baseTheme =
        inheritedTheme ??
        TexMathThemeData.fromColorScheme(Theme.of(context).colorScheme);
    final Color? textStyleColor = widget.textStyle?.color;
    final TexMathThemeData theme = textStyleColor != null
        ? baseTheme.copyWith(foreground: textStyleColor)
        : baseTheme;
    final double candidateSize =
        widget.textStyle?.fontSize ??
        inheritedTheme?.fontSize ??
        DefaultTextStyle.of(context).style.fontSize ??
        theme.fontSize;
    final double baseSize = resolveSafeTexMathFontSize(
      candidateSize,
      theme: theme,
    );
    final double rawScaledFontSize = MediaQuery.textScalerOf(
      context,
    ).scale(baseSize);
    final double scaledFontSize = resolveSafeTexMathFontSize(
      rawScaledFontSize,
      theme: theme,
    );

    final TexMathError? activeError = _error;
    if (activeError != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, widget.source, activeError);
      }
      return TexMathErrorWidget(
        source: widget.source,
        error: activeError,
        displayMode: widget.displayMode,
        selectable: widget.selectable,
      );
    }

    final DisplayList? activeList =
        widget.displayList ?? _renderResult?.displayList;
    if (activeList == null) {
      final String pendingLabel =
          widget.semanticsLabel ??
          (widget.source.isNotEmpty ? widget.source : 'Math expression');
      return Semantics(
        label: pendingLabel,
        readOnly: true,
        child: SizedBox(width: 0.0, height: _isLoading ? scaledFontSize : 0.0),
      );
    }

    return _buildDisplayListWidget(
      context,
      list: activeList,
      result: _renderResult,
      theme: theme,
      fontSize: scaledFontSize,
      font: _resolvedFont,
    );
  }

  Widget _buildDisplayListWidget(
    BuildContext context, {
    required DisplayList list,
    required RenderResult? result,
    required TexMathThemeData theme,
    required double fontSize,
    required MathFont? font,
  }) {
    final double height = (list.metrics.totalHeightEm * fontSize).clamp(
      0.0,
      1e6,
    );
    final double baseline = (list.metrics.baselineEm * fontSize).clamp(
      0.0,
      height,
    );
    final TexMathPathCache pathCache =
        widget.pathCache ?? TexMathPathCache.shared;

    final String label = _resolveSemanticsLabel(list: list, result: result);

    final SelectionRegistrar? ancestorRegistrar =
        (widget.selectable || widget._inheritAncestorSelection)
        ? SelectionContainer.maybeOf(context)
        : null;

    if (widget.selectable && ancestorRegistrar == null) {
      return Semantics(
        label: label,
        readOnly: true,
        child: SelectionArea(
          child: Builder(
            builder: (BuildContext innerContext) {
              return _buildOverflowAndLeaf(
                list: list,
                syntaxTree: result?.syntaxTree,
                theme: theme,
                fontSize: fontSize,
                baseline: baseline,
                font: font,
                pathCache: pathCache,
                registrar: SelectionContainer.maybeOf(innerContext),
              );
            },
          ),
        ),
      );
    }

    return Semantics(
      label: label,
      readOnly: true,
      child: _buildOverflowAndLeaf(
        list: list,
        syntaxTree: result?.syntaxTree,
        theme: theme,
        fontSize: fontSize,
        baseline: baseline,
        font: font,
        pathCache: pathCache,
        registrar: ancestorRegistrar,
      ),
    );
  }

  Widget _buildOverflowAndLeaf({
    required DisplayList list,
    required MathNode? syntaxTree,
    required TexMathThemeData theme,
    required double fontSize,
    required double baseline,
    required MathFont? font,
    required TexMathPathCache pathCache,
    required SelectionRegistrar? registrar,
  }) {
    final TexMathOverflow overflowPolicy = widget.effectiveOverflow;
    final Widget leaf = TexMathRenderLeaf(
      displayList: list,
      syntaxTree: syntaxTree,
      source: widget.source,
      theme: theme,
      fontSize: fontSize,
      baseline: baseline,
      font: font,
      pathCache: pathCache,
      registrar: registrar,
      allowVisualOverflow: overflowPolicy == TexMathOverflow.visible,
      onLinkTap: widget.onLinkTap,
    );

    final Widget baselineAligned = Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: leaf,
    );

    switch (overflowPolicy) {
      case TexMathOverflow.scroll:
        return TexMathBaselineProxy(
          baseline: baseline,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: baselineAligned,
          ),
        );
      case TexMathOverflow.scaleToFit:
        return TexMathBaselineProxy(
          baseline: baseline,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: baselineAligned,
          ),
        );
      case TexMathOverflow.clip:
        return TexMathBaselineProxy(
          baseline: baseline,
          child: ClipRect(child: baselineAligned),
        );
      case TexMathOverflow.visible:
        return baselineAligned;
    }
  }

  String _resolveSemanticsLabel({
    required DisplayList list,
    required RenderResult? result,
  }) {
    final String? explicit = widget.semanticsLabel;
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    if (result != null) {
      if (!identical(_spokenLabelSource, result)) {
        _spokenLabelSource = result;
        _cachedSpokenLabel = result.toSpokenText().trim();
      }
      final String? spoken = _cachedSpokenLabel;
      if (spoken != null && spoken.isNotEmpty) {
        return spoken;
      }
    }
    if (widget.source.isNotEmpty) {
      return widget.source;
    }
    final String? listSource = list.source;
    if (listSource != null && listSource.isNotEmpty) {
      return listSource;
    }
    return 'Math expression';
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
    MathFont? font,
    TexMathOverflow overflow = TexMathOverflow.visible,
    TexMathPathCache? pathCache,
    TexMathIsolateLayouter? layouter,
    super.style,
    TexMathErrorBuilder? errorBuilder,
    String? semanticsLabel,
    bool? selectable,
    this.onLinkTap,
    super.alignment = PlaceholderAlignment.baseline,
    super.baseline = TextBaseline.alphabetic,
  }) : super(
         child: TexMath._spanChild(
           source,
           selectable == null,
           options: options,
           engine: engine,
           font: font,
           overflow: overflow,
           pathCache: pathCache,
           layouter: layouter,
           textStyle: style,
           errorBuilder: errorBuilder,
           semanticsLabel: semanticsLabel,
           onLinkTap: onLinkTap,
           selectable: selectable ?? false,
         ),
       );

  /// Optional callback invoked with the target URI when a safe `\href` link
  /// inside this inline math span is tapped.
  final ValueChanged<String>? onLinkTap;
}
