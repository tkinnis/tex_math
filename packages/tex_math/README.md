# tex_math

Pure-Dart TeX math-mode parser, OpenType `MATH` layout engine, and standalone SVG, Presentation MathML, and spoken-text renderer aligned to MathJax `4.1.3` TeX input and JupyterLab defaults.

## Features

* **Strict Pure-Dart Boundary**: Depends exclusively on `package:meta` with zero `flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` imports, running synchronously and deterministically on caller-provided strings and in-memory font bytes.
* **Five-Stage TeX Pipeline**: `TexMathEngine` executes catcode tokenization (`tokenizeTex`), bounded macro expansion (`\newcommand`, `\renewcommand`, `\providecommand`, `\def`, `\let`, `\newenvironment`, `\renewenvironment`), immutable 16-variant sealed AST construction (`MathNode` with `SourceSpan`), TeX Appendix G OpenType `MATH` layout (`DisplayBreakHint`), and flat `DisplayList` generation (`toSvg()`, `toMathMl()`, `toSpokenText()`).
* **Full 42-Package Registry**: Supports all 42 MathJax `4.1.3` packages (`TexPackageRegistry`) across core TeX/AMS, JupyterLab extensions (`mhchem`, `mathtools`, `bussproofs`, `amscd`, `cancel`, `enclose`, `color`, `colortbl`, `extpfeil`, `braket`), and extended packages (`physics`, `units`, `bbm`, `bboldx`, `dsfont`, `begingroup`, `setoptions`, `autoload`), plus synchronous allowlist-checked `\require{pkg}` (`TexMathOptions.requireAllowlist`).
* **OpenType `MATH`, Variable Font & Hinting Reader**: `MathFont.fromBytes` decodes `head`, `maxp`, `hhea`, `hmtx`, `OS/2`, `name`, `cmap` (Format 4/12), `GSUB` (`ssty` optical script variants via `TexMathOptions.useOpticalScriptVariants`), `MATH` (`MathConstants`, `MathGlyphInfo`, `MathVariants` + `GlyphAssembly`), `fvar`/`avar`/`HVAR`/`GDEF` variation axes, `glyf`/`loca`, and `CFF`/`CFF2` outlines with optional Type 2 stem hinting (`enableHinting`).
* **Safety Budgets & Structured Errors**: Enforces `TexMathBudgets` limits on input length, macro depth, macro expansions, AST nesting depth, output items, and SVG size, raising sealed `TexMathError` exceptions aligned to MathJax's `TexMathErrorClass` taxonomy.

## Usage

```dart
import 'dart:typed_data';
import 'package:tex_math/tex_math.dart';

void renderEquation(Uint8List fontBytes) {
  final MathFont font = MathFont.fromBytes(fontBytes);
  final TexMathEngine engine = TexMathEngine(
    font: font,
    defaultOptions: const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      useOpticalScriptVariants: true,
    ),
  );

  final RenderResult result = engine.render(
    r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}',
  );
  final String svg = result.toSvg(fontSize: 20.0, title: 'Gaussian integral');
  final String mathMl = result.toMathMl();
  final String spoken = result.toSpokenText();

  assert(svg.contains('<path') && mathMl.contains('<math') && spoken.isNotEmpty);
}
```

## Corpus Verification & Native AOT Performance

Verified against pinned MathJax `4.1.3` (`@mathjax/mathjax-newcm-font`) across `352` corpus cases (`315` Oracle Accepted, `37` Oracle Refused): `315/315` accepted expressions render into standalone SVG `<path>`/`<rect>` primitives (`0` Unsupported), `37/37` error inputs match exact error classifications (`Refused Match`), and `74` accepted expressions match MathJax geometry within `0.02em` (`31.5%` overall Pass %, with `241` differences attributable to OpenType `MATH` constants vs legacy `.tfm` parameters, unencoded `GlyphAssembly` segments vs clipped SVG tiles, and unified `hmtx`/`cmap` vs virtual subfonts).

Native Dart AOT measurements on `Apple M4` (`arm64`, `macos` `Version 15.6 (Build 24G84)`, Dart `3.13.5`):

* **`math_font_from_bytes`**: `699.00 us` mean (`634.90 us` p50, `1.049 ms` p95) one-time decode of `NewCMMath-Regular.otf`.
* **`inline_expression_layout`**: `7.76 us` mean (`7.68 us` p50, `9.42 us` p95; target `< 50 us`).
* **`notebook_50_equations`**: `1.830 ms` mean (`1.809 ms` p50, `2.149 ms` p95; target `< 5 ms`).
* **`cached_display_list_lookup`**: `0.46 us` mean (`0.45 us` p50, `0.63 us` p95).
* **`corpus_full_dispatch` (`352` cases)**: `7.740 ms` mean (`4.090 ms` parse phase, `2.925 ms` layout phase).
* **`display_list_to_svg_small` / `large`**: `12.66 us` mean / `258.54 us` mean.

## Example & Documentation

Run the standalone CLI example from `packages/tex_math` with `dart run example/main.dart`. Full API, architecture, coverage, and benchmark reports are available in the [API Manual](https://github.com/tkinnis/tex_math/blob/main/doc/API_MANUAL.md), [Architecture Guide](https://github.com/tkinnis/tex_math/blob/main/doc/ARCHITECTURE.md), [Coverage Matrix](https://github.com/tkinnis/tex_math/blob/main/doc/COVERAGE.md), and [Benchmarks](https://github.com/tkinnis/tex_math/blob/main/doc/BENCHMARKS.md).
