# tex_math_flutter

Flutter widgets, Material `ColorScheme` theming, bundled `NewCMMath-Regular.otf` (`8.1.1`) OpenType `MATH` font assets, cached vector glyph `Path` painting, baseline-aligned `WidgetSpan` integration, `"copy as LaTeX"` sub-expression selection, and persistent background isolate layout for `tex_math`.

## Features

* **Single-Import Convenience**: `package:tex_math_flutter/tex_math_flutter.dart` re-exports core `tex_math` public types (`TexMathDisplayMode`, `TexMathOptions`, `TexMathBudgets`, `TexMathEngine`, `MathFont`, `DisplayList`, `RenderResult`, `TexMathError`, etc.) alongside the Flutter rendering API.
* **`TexMath` & `TexMathSpan`**: Display, inline, and `TexMath.displayList` widgets plus `WidgetSpan` (`PlaceholderAlignment.baseline`, `TextBaseline.alphabetic` and `ideographic` support, proportional `scaleToFit` baseline scaling, and `textStyle > TexMathTheme > DefaultTextStyle > fallback` font-size precedence). Auto-loads and decodes `NewCMMath-Regular.otf` off the UI thread (`TexMathFontBundle.loadMathFont()`) once per lifecycle without double-parsing, enforces `TexMathOverflow` policies (`scroll`, `scaleToFit`, `clip`, `visible`), exposes cached spoken-text `Semantics`, and supports lazy `"copy as LaTeX"` sub-expression selection (`TexMathSelectionUtils`).
* **`TexMathDisplayPainter` & `TexMathPathCache`**: Bounded LRU `dart:ui.Path` cache (`TexMathPathCache.shared`) keyed by `(fontSignature, glyphId, ppemBucket?)` (with `GlyphOutline` fallback) plus bounded fallback `TextPainter` caching so `TexMathTheme` color updates and isolate-laid-out expressions repaint without re-running TeX layout or rebuilding glyph paths.
* **`TexMathTheme` & `TexMathThemeData`**: Inherited theming mapping `TexMathColorRole` values (`foreground`, `accent`, `error`, `muted`, `custom`) to Material `ColorScheme`s.
* **`TexMathIsolateLayouter`**: Persistent background `Isolate` worker (`withBundledFont`, `warmUp`, `dispose`) with single-transfer font initialization, worker-side font caching by `signature`, in-flight deduplication across custom fonts, bounded 256-entry LRU caching keyed by `TexMathLayoutCacheKey(source, options, fontId, fontSignature)`, and `onExit`/`onError` crash recovery.
* **`TexMathErrorWidget`**: Monospace diagnostic fallback displaying the original TeX source alongside structured `TexMathError` messages with accessible semantics (`excludeSemantics: true`) and `SelectionContainer.disabled` respect when `selectable` is `false`.

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

`tex_math_flutter` renders output from the `tex_math` pure-Dart engine, verified across `352` corpus cases (`315/315` accepted expressions rendered into vector primitives with `0` Unsupported and `37/37` error-class refusals matched against MathJax `4.1.3`). On `Apple M4` native Dart AOT, core engine workloads measure `4.09 us` mean (`4.45 us` p95) for inline expressions (`< 50 us` target), `474.49 us` mean (`1.126 ms` p95) for 50-equation notebook batches (`< 5 ms` target), `0.13 us` mean (`0.16 us` p95) for cached expression lookups, and `302.78 us` mean for one-time `NewCMMath-Regular.otf` decoding, paired with zero-relayout theme repaints via `TexMathPathCache` and off-thread rendering via `TexMathIsolateLayouter`. Full documentation is available in the [API Manual](https://github.com/tkinnis/tex_math/blob/main/doc/API_MANUAL.md), [Architecture Guide](https://github.com/tkinnis/tex_math/blob/main/doc/ARCHITECTURE.md), and [Benchmarks](https://github.com/tkinnis/tex_math/blob/main/doc/BENCHMARKS.md).

## License

* **`tex_math_flutter`**: Copyright (c) 2026 Tony Kinnis — MIT License.
* **Bundled Font (`assets/fonts/NewCMMath-Regular.otf` `8.1.1`)**: New Computer Modern Math — GUST Font License 1.0 (`assets/fonts/GUST-FONT-LICENSE.txt`).
