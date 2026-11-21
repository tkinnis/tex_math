# tex_math_flutter

Flutter widgets, Material `ColorScheme` theming, bundled `NewCMMath-Regular.otf` (`8.1.1`) OpenType `MATH` font assets, cached vector glyph `Path` painting, baseline-aligned `WidgetSpan` integration, `"copy as LaTeX"` sub-expression selection, and persistent background isolate layout for `tex_math`.

## Features

* **`TexMath`**: Display and inline TeX math widgets (`TexMath`, `TexMath.inline`, `TexMath.display`, `TexMath.displayList`) with automatic once-per-lifecycle decoding of `NewCMMath-Regular.otf` (`TexMathFontBundle.loadMathFont()`), configurable `TexMathOverflow` policies (`scroll`, `scaleToFit`, `clip`, `visible`), spoken-text `Semantics` labels, and `SelectionArea` sub-expression selection (`RenderTexMath` and `TexMathSelectionUtils`) that expands partial drags to the minimal enclosing `MathNode` slice.
* **`TexMathSpan`**: `WidgetSpan` aligned with `PlaceholderAlignment.baseline` and `TextBaseline.alphabetic` for embedding inline math inside `Text.rich` and `RichText`.
* **`TexMathDisplayPainter` & `TexMathPathCache`**: Bounded LRU `dart:ui.Path` cache keyed by `(MathFont, glyphId)` (`TexMathPathCache.shared`) so `TexMathTheme` color updates repaint without re-running TeX layout or rebuilding glyph paths.
* **`TexMathTheme` & `TexMathThemeData`**: Inherited theming mapping `TexMathColorRole` values (`foreground`, `accent`, `error`, `muted`, `custom`) cleanly to Material `ColorScheme`s.
* **`TexMathIsolateLayouter`**: Persistent background `Isolate` worker (`TexMathIsolateLayouter.withBundledFont`, `warmUp`, `dispose`) with single-transfer font initialization, in-flight deduplication, and bounded 256-entry LRU caching keyed by `(source, options, fontId)`.
* **`TexMathErrorWidget`**: Monospace diagnostic fallback displaying the original TeX source alongside structured `TexMathError` messages.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

Widget buildMathShowcase(BuildContext context) {
  return TexMathTheme(
    data: TexMathThemeData.fromColorScheme(
      Theme.of(context).colorScheme,
      fontSize: 20.0,
    ),
    child: SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const TexMath(
            r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
            overflow: TexMathOverflow.scroll,
          ),
          const SizedBox(height: 12.0),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Inline identity: '),
                TexMathSpan(r'a^2 + b^2 = c^2'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

## Corpus Coverage & Performance

`tex_math_flutter` renders output from the `tex_math` pure-Dart engine, verified across `352` corpus cases (`315/315` accepted expressions rendered into vector primitives with `0` Unsupported and `37/37` error-class refusals matched against MathJax `4.1.3`). On `Apple M4` native Dart AOT, core engine workloads measure `7.76 us` mean (`9.42 us` p95) for inline expressions (`< 50 us` target), `1.830 ms` mean (`2.149 ms` p95) for 50-equation notebook batches (`< 5 ms` target), `0.46 us` mean (`0.63 us` p95) for cached expression lookups, and `699.00 us` mean for one-time `NewCMMath-Regular.otf` decoding, paired with zero-relayout theme repaints via `TexMathPathCache` and off-thread rendering via `TexMathIsolateLayouter`.

## License

* **`tex_math_flutter`**: Copyright (c) 2026 Tony Kinnis — MIT License.
* **Bundled Font (`assets/fonts/NewCMMath-Regular.otf` `8.1.1`)**: New Computer Modern Math — GUST Font License 1.0 (`assets/fonts/GUST-FONT-LICENSE.txt`).
