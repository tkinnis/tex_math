# tex_math

Pure-Dart TeX math parser, OpenType math layout engine, and standalone SVG, Presentation MathML, and spoken-text renderer aligned with MathJax `4.1.3` and JupyterLab defaults.

## Rendered Examples

All examples below are rendered synchronously in pure Dart via `DisplayList.toSvg()` using the OpenType math tables in `NewCMMath-Regular.otf`.

**Gaussian Integral** — Display limits, optical scripts, fractions, and stretchy square roots:

![Gaussian integral rendered by tex_math](https://raw.githubusercontent.com/tkinnis/tex_math/main/doc/images/showcase_gaussian_integral.svg)

```tex
\int_{-\infty}^{\infty} e^{-\alpha x^2}\,dx = \sqrt{\frac{\pi}{\alpha}} \quad (\alpha > 0)
```

**Piecewise Cases** — Extensible left brace, multi-row alignment, and embedded text mode:

![Piecewise cases rendered by tex_math](https://raw.githubusercontent.com/tkinnis/tex_math/main/doc/images/showcase_piecewise_cases.svg)

```tex
|x| = \begin{cases} x & \text{if } x \ge 0 \\ -x & \text{if } x < 0 \end{cases}
```

**Rotation Matrix** — Parenthesized matrix grid with named trigonometric operators and Greek glyphs:

![Rotation matrix rendered by tex_math](https://raw.githubusercontent.com/tkinnis/tex_math/main/doc/images/showcase_matrix_rotation.svg)

```tex
R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}
```

**Nested Radical** — Multi-level fraction scaling under an extensible radical bar:

![Nested radical rendered by tex_math](https://raw.githubusercontent.com/tkinnis/tex_math/main/doc/images/showcase_nested_radical.svg)

```tex
\sqrt{\frac{\frac{a}{b} + \frac{c}{d}}{\frac{e}{f} - \frac{g}{h}}}
```

**Chemical Equilibrium (`mhchem`)** — Stoichiometric coefficients, upright formulas, and equilibrium arrows:

![Chemical equilibrium rendered by tex_math](https://raw.githubusercontent.com/tkinnis/tex_math/main/doc/images/showcase_chemistry.svg)

```tex
\ce{N2 + 3H2 <=> 2NH3}
```

## Features

| Capability | Summary |
| :--- | :--- |
| **Pure-Dart Boundary** | Depends strictly on `package:meta` with zero Flutter, DOM, or filesystem imports, running deterministically on caller-provided strings and font bytes. |
| **Five-Stage TeX Pipeline** | `TexMathEngine` handles tokenization, on-demand macro expansion, immutable `MathNode` parsing, TeX Appendix G layout, and display-list export. |
| **42-Package Registry** | Supports core TeX and AMS, JupyterLab extensions such as `mhchem`, `mathtools`, and `bussproofs`, extended packages like `physics` and `units`, plus allowlisted `\require` loading. |
| **OpenType & Variable Fonts** | `MathFont.fromBytes` reads `MATH` constants, `ssty` script alternates, TrueType and CFF/CFF2 outlines, Type 2 stem hinting, and variation axes with fast payload `signature` identity. |
| **Multi-Format Exporters** | `RenderResult` and `DisplayList` emit standalone SVG paths, sanitized Presentation MathML, and natural-language spoken descriptions for assistive tools. |
| **Hardened Safety Budgets** | Configurable `TexMathBudgets` limits protect against runaway macros, deep nesting, oversized fonts, unsafe `\href` URIs, and invalid XML characters, throwing typed `TexMathError` exceptions. |

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

Tested against a live MathJax 4.1.3 oracle across 352 corpus entries, `tex_math` achieves **100.0% feature support**: **315/315** valid expressions render into clean vector output (0 unsupported), and **37/37** malformed inputs are refused with matching error classes. Strict ±0.02em bounding-box matching against MathJax (74/315 accepted expressions, 111/352 overall) serves as a diagnostic check against legacy `.tfm` font tables rather than an indicator of missing support, since `tex_math` derives spacing directly from OpenType math tables.

Native Dart AOT benchmarks on Apple M4 (`arm64`, macOS 15.6, Dart `3.13.5`) measure microsecond-scale layout and sub-millisecond cold font loading:

| Workload | Mean | Median (p50) | Scope |
| :--- | ---: | ---: | :--- |
| `math_font_from_bytes` | 302.78 us | 299.83 us | One-time font decode (`NewCMMath-Regular.otf`) |
| `cold_font_glyph_decode` | 438.38 us | 439.63 us | Cold font load plus initial glyph outline decode |
| `inline_expression_layout` | 4.09 us | 4.12 us | Parse and lay out typical inline math (`< 50 us` target) |
| `notebook_50_equations` | 474.49 us | 439.41 us | 50-equation notebook batch (`< 5 ms` target) |
| `cached_display_list_lookup` | 0.13 us | 0.13 us | Cached display-list hit |
| `corpus_full_dispatch` | 4.269 ms | 4.241 ms | All 352 corpus cases end to end |
| `display_list_to_svg_small` / `large` | 75.02 us / 428.90 us | 72.82 us / 422.19 us | Standalone SVG serialization across CFF outlines |

## Example & Documentation

Run the standalone CLI example from `packages/tex_math` with `dart run example/main.dart`. Full guides and reports live in the repository documentation:

* [API Manual](https://github.com/tkinnis/tex_math/blob/main/doc/API_MANUAL.md)
* [Architecture & Design](https://github.com/tkinnis/tex_math/blob/main/doc/ARCHITECTURE.md)
* [Corpus Coverage Matrix](https://github.com/tkinnis/tex_math/blob/main/doc/COVERAGE.md)
* [Benchmarks](https://github.com/tkinnis/tex_math/blob/main/doc/BENCHMARKS.md)
