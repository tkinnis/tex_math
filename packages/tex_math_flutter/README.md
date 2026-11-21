# tex_math_flutter

Flutter widgets, theming, bundled `NewCMMath-Regular.otf` math font assets, cached vector glyph `Path` painting, baseline-aligned `WidgetSpan` integration, sub-expression `"copy as LaTeX"` selection, and persistent background isolate layout for `tex_math`.

## Features

`tex_math_flutter` provides:

* **`TexMath`**: Display and inline TeX math widgets (`TexMath`, `TexMath.inline`, `TexMath.display`, `TexMath.displayList`) with automatic once-per-lifecycle loading of `NewCMMath-Regular.otf`, configurable `TexMathOverflow` policies (`scroll`, `scaleToFit`, `clip`, `visible`), spoken-text `Semantics` labels, and `SelectionArea` sub-expression selection (`TexMathSelectionUtils`) that expands partial drags to the minimal enclosing `MathNode` slice.
* **`TexMathSpan`**: Baseline-aligned `WidgetSpan` for embedding inline math inside `Text.rich` and `RichText`.
* **`TexMathDisplayPainter` & `TexMathPathCache`**: Cached `dart:ui.Path` painting keyed by `(MathFont, glyphId)` so theme color changes repaint without re-running TeX layout or rebuilding glyph paths.
* **`TexMathTheme` & `TexMathThemeData`**: Inherited theming mapping `TexMathColorRole` values (`foreground`, `accent`, `error`, `muted`, `custom`) cleanly to Material `ColorScheme`s.
* **`TexMathIsolateLayouter`**: Persistent background `Isolate` layouter with bounded LRU caching keyed by `(source, options, fontId)` and single-transfer font initialization.
* **`TexMathErrorWidget`**: Monospace diagnostic fallback displaying the original TeX source alongside structured `TexMathError` messages.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

Widget buildFormula() {
  return const TexMathTheme(
    data: TexMathThemeData(
      foreground: Colors.black87,
      accent: Colors.indigo,
      error: Colors.red,
      muted: Colors.grey,
    ),
    child: TexMath(r'\frac{a + b}{c - d}'),
  );
}
```
