# tex_math_flutter

Flutter widgets, theming, bundled `NewCMMath-Regular.otf` math font assets, baseline-aligned `WidgetSpan` integration, and background isolate layout helpers for `tex_math`.

## Features

`tex_math_flutter` exposes `TexMath` (`display` and `inline` constructors plus `TexMath.displayList`), `TexMathSpan` (`WidgetSpan` helper for inline equations inside `Text.rich`), `TexMathErrorWidget`, `TexMathTheme` and `TexMathThemeData`, `TexMathFontBundle`, and `TexMathIsolateLayouter` with `Semantics` and `SelectionArea` support.

## Phase 1 Status

Phase 1 provides the widget shell, theme color role resolution, once-only asset loading of `NewCMMath-Regular.otf` with its GUST Font License and manifest, vector `DisplayList` painting, background isolate dispatch, and monospace error fallback rendering while the core `tex_math` parser and layout engine throw `TexMathUnsupportedError`.

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
