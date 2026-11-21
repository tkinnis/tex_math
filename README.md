# ![tex_math](doc/images/tex_math_logo.svg)

[![CI](https://img.shields.io/github/actions/workflow/status/tkinnis/tex_math/ci.yml?branch=main&label=CI&logo=github)](https://github.com/tkinnis/tex_math/actions/workflows/ci.yml) [![Reference MathJax 4.1.3](https://img.shields.io/badge/reference-MathJax%204.1.3-7c3aed)](REFERENCE.md) [![Default Font NewCMMath 8.1.1](https://img.shields.io/badge/font-NewCMMath%208.1.1-0ea5e9)](REFERENCE.md) [![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**`tex_math`** is a pure-Dart TeX math-mode parser, OpenType `MATH` layout engine, and Flutter rendering suite targeting layout, glyph, and error parity with pinned **MathJax `4.1.3`** and JupyterLab math rendering defaults, with zero WebView or JavaScript dependencies at runtime.

## Highlights

* **Pure-Dart Core Engine (`packages/tex_math`)**: Deterministic five-stage pipeline (catcode tokenizer, on-demand macro expansion + 42-package `\require` registry interleaved inside `_TexParser`, 16-variant sealed `MathNode` AST, Appendix G OpenType `MATH` layout engine, and `DisplayList` / `RenderResult` with SVG, Presentation MathML, and spoken-text exporters) depending strictly on `package:meta`, with zero `flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` imports.
* **OpenType `MATH`, Variable Font & Hinting Reader**: Decodes `head`, `maxp`, `hhea`, `hmtx`, `OS/2`, `name`, `cmap` (Format 4/12), `GSUB` (`ssty`), `MATH`, `fvar`/`avar`/`HVAR`/`GDEF` variations, `glyf`/`loca`, and `CFF`/`CFF2` (including Type 2 stem hinting) from in-memory bytes (`MathFont.fromBytes`) with fast payload `signature` identity.
* **Flutter Integration (`packages/tex_math_flutter`)**: Single-import barrel re-exporting core `tex_math` types, `TexMathPathCache` keyed by `(fontSignature, glyphId)` for zero-relayout `TexMathTheme` updates across isolates, off-thread bundled `NewCMMath-Regular.otf` (`8.1.1`) decoding, proportional `TexMathSpan` / `scaleToFit` baseline alignment, `"copy as LaTeX"` `SelectionArea` support, spoken-text `Semantics`, and persistent crash-recovering `TexMathIsolateLayouter`.
* **Safety Budgets & Hardening**: Enforces cumulative `TexMathBudgets` (`maxInputLength`, `maxMacroDepth`, `maxMacroExpansions`, `maxTokens`, `maxNestingDepth`, `maxOutputItems`, `maxSvgLength`), SFNT offset deduplication and outline recursion caps, `\href` safe URI allowlisting, XML 1.0 character filtering, and structured `TexMathError` exceptions mapped to `TexMathErrorClass`.
* **Differential Verification & 3-Way Studio**: Verified against a pinned MathJax `4.1.3` oracle (`tool/oracle/`) across a 352-case corpus (`corpus/`) and inspectable interactively in the macOS 3-Way Comparison Studio (`studio/`) with Side-by-Side, Pixel Diff, and Curtain Diff modes.

## Display List SVG Preview

Generated directly by `DisplayList.toSvg()` via [`tool/generate_doc_images.dart`](tool/generate_doc_images.dart):

| DisplayList Sample | DisplayMetrics Box Model |
| :---: | :---: |
| ![DisplayList Sample](doc/images/display_list_sample.svg) | ![DisplayMetrics Box Model](doc/images/box_metrics_diagram.svg) |

## Workspace Packages & Structure

| Component | Path | Purpose |
| :--- | :--- | :--- |
| **`tex_math`** | [`packages/tex_math/`](packages/tex_math/README.md) | Pure-Dart TeX parser, OpenType `MATH` layout engine, SVG / MathML / spoken-text exporters. |
| **`tex_math_flutter`** | [`packages/tex_math_flutter/`](packages/tex_math_flutter/README.md) | Flutter `TexMath` / `TexMathSpan` widgets, `TexMathPathCache`, theming, selection, persistent isolate layouter, and bundled `NewCMMath-Regular.otf`. |
| **Flutter Example** | [`packages/tex_math_flutter/example/`](packages/tex_math_flutter/example/lib/main.dart) | Flutter showcase and 50-equation notebook app demonstrating theme toggling, `SelectionArea`, and `TexMathIsolateLayouter`. |
| **Comparison Studio** | [`studio/`](studio/README.md) | macOS desktop workbench (`studio/macos/`) comparing `tex_math`, MathJax `4.1.3`, and KaTeX `0.19.1` with Pixel Diff and Curtain Diff views. |
| **Reference & Coverage** | [`REFERENCE.md`](REFERENCE.md) · [`doc/COVERAGE.md`](doc/COVERAGE.md) | Pinned upstream targets, package tiers, and measured corpus parity reports. |

## Quick Start

### Pure Dart (`packages/tex_math`)

```dart
import 'dart:io';
import 'package:tex_math/tex_math.dart';

void main() {
  final MathFont font = MathFont.fromBytes(
    File('packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf')
        .readAsBytesSync(),
  );
  final TexMathEngine engine = TexMathEngine(font: font);
  final RenderResult result = engine.render(
    r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}',
  );

  print(result.toSvg(fontSize: 20.0));
  print(result.toMathMl());
  print(result.toSpokenText());
}
```

### Flutter (`packages/tex_math_flutter`)

```dart
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

Widget buildFormula() {
  return const TexMath(
    r'\frac{a + b}{c - d}',
    displayMode: TexMathDisplayMode.display,
    overflow: TexMathOverflow.scroll,
  );
}
```

## Corpus Coverage & Native AOT Benchmarks

Measured corpus parity from [`doc/COVERAGE.md`](doc/COVERAGE.md) (`corpus/expectations.json` verified against `MathJax 4.1.3` with `mathjax-newcm`) covers **352** total corpus cases (**315** Oracle Accepted, **37** Oracle Refused). `TexMathEngine` renders `315/315` accepted expressions into vector `DisplayList` and SVG primitives (`0` Unsupported), matches `37/37` error-class refusals (`Refused Match`), and matches strict `0.02em` MathJax geometry on `74` accepted expressions (`74` Pass, `241` Differs, `31.5%` Pass % — see [Architecture: OpenType MATH Conformance](doc/ARCHITECTURE.md#opentype-math-conformance-vs-mathjax-4-js-fontdata-divergences) for the OpenType `MATH` vs. `.tfm`/tile/subfont causes of the `241` numeric differences):

| Tier | Pass | Differs | Unsupported | Refused Match | Total | Pass % |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tier 1 (Core TeX, AMS, Macros, Textmacros, Tag/ConfigMacros) | 38 | 87 | 0 | 0 | 125 | 30.4% |
| Tier 2 (JupyterLab Standard Extensions) | 26 | 79 | 0 | 0 | 105 | 24.8% |
| Tier 3 (Remaining MathJax 4 Extensions) | 7 | 28 | 0 | 0 | 35 | 20.0% |
| Stretchy (Delimiters, Radicals, Braces, Wide Accents) | 3 | 22 | 0 | 0 | 25 | 12.0% |
| Notebooks (Physics, Calculus, Linear Algebra, ML, Chemistry) | 0 | 25 | 0 | 0 | 25 | 0.0% |
| Errors (Malformed Inputs & Macro/Delimiter Violations) | 0 | 0 | 0 | 37 | 37 | 100.0% |
| **Total** | **74** | **241** | **0** | **37** | **352** | **31.5%** |

Native Dart AOT highlights on `Apple M4` (`arm64`, `macos` `Version 15.6 (Build 24G84)`, `32 GiB`, Dart `3.13.5`) from [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) pass every target budget (`1.5x` p50 regression gate; see [`doc/BENCHMARKS.md`](doc/BENCHMARKS.md) for all 13 benchmarks, `ProcessInfo.currentRss` telemetry, and charts):

| Benchmark | Mean | Median (p50) | p95 | Target |
| :--- | ---: | ---: | ---: | :--- |
| `math_font_from_bytes` | 302.78 us | 299.83 us | 361.10 us | Once per font |
| `cold_font_glyph_decode` | 438.38 us | 439.63 us | 507.40 us | Cold font + decode |
| `inline_expression_layout` | 4.09 us | 4.12 us | 4.45 us | `< 50 us` |
| `notebook_50_equations` | 474.49 us | 439.41 us | 1.126 ms | `< 5 ms` |
| `cached_display_list_lookup` | 0.13 us | 0.13 us | 0.16 us | Paint-only cost |
| `lru_cache_mixed_eviction` | 62.82 us | 62.49 us | 71.11 us | Bounded 32-entry LRU |
| `corpus_full_dispatch` (`352` cases) | 4.269 ms | 4.241 ms | 4.620 ms | — |
| `display_list_to_svg_small` / `large` | 75.02 us / 428.90 us | 72.82 us / 422.19 us | 81.23 us / 458.93 us | Real CFF SVG |

## Documentation

| Guide | Description |
| :--- | :--- |
| **[Architecture & Design](doc/ARCHITECTURE.md)** | Five-stage TeX pipeline, OpenType `MATH` usage, OpenType vs. MathJax FontData divergences, accessibility, budgets, and design contracts. |
| **[API Manual](doc/API_MANUAL.md)** | Public types across `tex_math` and `tex_math_flutter`. |
| **[Reference Pins](REFERENCE.md)** | Pinned MathJax `4.1.3`, JupyterLab `@jupyterlab/mathjax-extension`, font versions, and package tiers. |
| **[Coverage Matrix](doc/COVERAGE.md)** | Generated corpus coverage across Tier 1, Tier 2, Tier 3, stretchy constructs, notebooks, and error cases. |
| **[Benchmarks](doc/BENCHMARKS.md)** | Native Dart AOT measurements, RSS telemetry, and regression baseline. |
| **[Studio Guide](doc/STUDIO_GUIDE.md)** | macOS 3-Way Comparison Studio workbench architecture, security controls, and headless tests. |
| **[Reference Sync](doc/REFERENCE_SYNC.md)** | Procedure for verifying and updating upstream reference pins. |
| **[Releasing](doc/RELEASING.md)** | Lockstep `vX.Y.Z` verification, tagging, and pub.dev release order. |
| **[Security Policy](SECURITY.md)** | Budget guards, font hardening, safe URI/XML emission, Studio isolation, and vulnerability reporting. |

## License

* **`tex_math` & `tex_math_flutter`**: Copyright (c) 2026 Tony Kinnis — [MIT License](LICENSE).
* **Bundled Math Font (`NewCMMath-Regular.otf` `8.1.1`)**: New Computer Modern Math — GUST Font License 1.0 (`packages/tex_math_flutter/assets/fonts/GUST-FONT-LICENSE.txt`).
