/// Flutter widgets, theming, asset font bundle, glyph path cache,
/// sub-expression selection, and background isolate layout integration for
/// `tex_math`.
library;

export 'package:tex_math/tex_math.dart'
    show
        AnchorItem,
        DisplayItem,
        DisplayList,
        DisplayMetrics,
        GlyphOutline,
        MathFont,
        MathNode,
        MathRootNode,
        PathCommand,
        RenderResult,
        SourceSpan,
        TexMathBudgetError,
        TexMathBudgets,
        TexMathColorRole,
        TexMathDisplayMode,
        TexMathEngine,
        TexMathError,
        TexMathErrorClass,
        TexMathFontError,
        TexMathMacroError,
        TexMathOptions,
        TexMathSyntaxError,
        TexMathTagMode,
        TexMathUnsupportedError;

export 'src/display_painter.dart' show TexMathDisplayPainter, TexMathPathCache;
export 'src/error_widget.dart' show TexMathErrorWidget;
export 'src/font_bundle.dart' show TexMathFontAsset, TexMathFontBundle;
export 'src/isolate_layouter.dart'
    show TexMathIsolateLayouter, TexMathLayoutCacheKey;
export 'src/selection_adapter.dart' show TexMathOverflow, TexMathSelectionUtils;
export 'src/tex_math_widget.dart'
    show TexMath, TexMathErrorBuilder, TexMathSpan;
export 'src/theme.dart' show TexMathTheme, TexMathThemeData;
