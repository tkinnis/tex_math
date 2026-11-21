# Comparison Studio Guide

**`tex_math_studio`** (`studio/`) is a Flutter workbench designed for interactive side-by-side comparison of **`tex_math`**, the **MathJax `4.1.3`** reference oracle, and **KaTeX `0.19.1`**. It allows contributors to edit TeX expressions, toggle display vs inline math mode, inspect bounding-box alignment, and examine error parity across engines.

---

## 1. Architecture & Panes

The application entry point in `studio/lib/main.dart` defines `TexMathStudioApp` and `StudioWorkbenchPage`:

* **Preset Equation Bar**: Quick-select `ActionChip` presets covering fractions (`\frac{a + b}{c - d}`), integrals (`\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}`), and matrix environments (`\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}`).
* **TeX Source Input**: Monospace multiline `TextField` that updates all three comparison panes live as input changes.
* **Display Mode Selector**: `SegmentedButton<TexMathDisplayMode>` switching between `TexMathDisplayMode.display` (`$$...$$`) and `TexMathDisplayMode.inline` (`$...$`).
* **Three Side-by-Side Comparison Panes**:
  * **`tex_math (Pure Dart)`**: Renders live via the `TexMath(source, displayMode: _displayMode)` widget from `package:tex_math_flutter`, surfacing structured `TexMathErrorWidget` diagnostics whenever an expression triggers a `TexMathError`.
  * **`MathJax 4.1.3 Oracle`**: Dedicated comparison pane aligned to `tool/oracle/render.mjs` (`@mathjax/src` `4.1.3` + `@mathjax/mathjax-newcm-font` `4.1.3`), displaying a Phase 1 placeholder until live local oracle bridging lands.
  * **`KaTeX 0.19.1 Comparison`**: Secondary reference pane tracking KaTeX `0.19.1` layout differences for diagnostic context (KaTeX is a studio comparison reference only, not a parity contract for `tex_math`).

---

## 2. Running Tests & Launching Studio

### Prerequisites

Install Dart/Flutter workspace dependencies from the repository root and install the Node.js oracle dependencies under `tool/oracle/`:

```bash
flutter pub get
(cd tool/oracle && npm ci)
```

### Running Studio Widget Tests

Verify the studio widget suite inside `studio/`:

```bash
(cd studio && flutter test)
```

`studio/test/widget_test.dart` verifies that all three comparison panes render, `TexMathErrorWidget` handles Phase 1 unimplemented parser responses cleanly, and editing the `TextField` updates displayed source state.

### Running Studio as a Desktop Application

`studio/` ships as a workspace Flutter package without committed platform build trees (`macos/`, `linux/`, `windows/`). To launch the interactive desktop window locally on macOS, generate the local runner files or target your installed Flutter desktop device inside `studio/`:

```bash
cd studio
flutter create --platforms=macos .
flutter run -d macos
```

---

## 3. Direct CLI Comparison with the MathJax Oracle

For headless box-metric, glyph-position, and error-class comparisons outside the GUI, pipe JSON cases directly into `tool/oracle/render.mjs` from the repository root:

```bash
printf '[{"id":"sample","tex":"\\\\frac{a + b}{c - d}","display":true}]' | node tool/oracle/render.mjs --include-svg
```

### Oracle Input & Output Fields

* **Input Array**: Each object accepts `id` (string), `tex` (TeX source string), `display` (boolean), and optional `packages` (array of MathJax TeX package names; defaults to the 29 active JupyterLab packages excluding `noerrors` and `noundefined`).
* **Output Object**: Returns `{ mathjaxVersion: "4.1.3", font: "mathjax-newcm", results: [...] }` where each item reports `accepted`, `errorClass`, `errorMessage`, `box` (`width`, `height`, `depth` in ems), `glyphs` (`codePoint`, `x`, `y`, `scaleX`, `scaleY`), `rules` (`x`, `y`, `width`, `height`), and optional `svg` when `--include-svg` is passed.

To evaluate the full categorized verification suite and inspect parity metrics across all tiers, run:

```bash
dart run tool/verify_against_mathjax.dart
```

---

## 4. Reporting Rendering Mismatches

When comparing `tex_math` output against MathJax in Studio reveals a layout, glyph, or error discrepancy, capture the TeX source, a MathJax screenshot, and a `tex_math` screenshot, and submit them using the repository's rendering mismatch issue template.
