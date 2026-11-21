# Repository Guidelines for `tex_math`

This document defines the architectural invariants, monorepo boundaries, reference tracking rules, and quality gates for contributors and automated engineering workflows in **`tex_math`**.

---

## 1. Project Purpose & Workspace Layout

`tex_math` is a pure-Dart TeX math-mode parser, OpenType `MATH` layout engine, and Flutter rendering suite targeting layout, glyph, and error parity with MathJax `4.1.3` and JupyterLab math rendering defaults without a WebView or JavaScript runtime.

| Path | Role | SDK / Publishing |
| :--- | :--- | :--- |
| `packages/tex_math/` | Pure-Dart TeX tokenizer, macro expander, AST parser, Appendix G layout engine, OpenType `MATH` reader, display list, SVG/MathML/spoken-text exporters. | Pure Dart (`^3.13.0`), `meta` only, published to pub.dev. |
| `packages/tex_math_flutter/` | Flutter `TexMath` / `TexMathSpan` widgets, theme color roles, glyph `Path` cache, `SelectionArea` / `Semantics` hooks, background isolate layouter, bundled `NewCMMath-Regular.otf`. | Flutter (`>=3.27.0`), depends on `tex_math`, published to pub.dev. |
| `packages/tex_math_flutter/example/` | Standalone Flutter example app exercising `TexMath` and `TexMathSpan`. | `publish_to: none`. |
| `studio/` | Desktop comparison workbench comparing `tex_math`, MathJax, and KaTeX side by side. | `publish_to: none`. |
| `tool/` | Differential MathJax oracle (`tool/oracle/`), version lockstep checks, coverage/benchmark generators, reference sync checker, and doc image generator. | Dart CLI + Node.js dev tooling. |
| `corpus/` | Categorized `.tex` verification corpus across Tiers 1–3, stretchy delimiters, notebook equations, and error cases, plus `expectations.json`. | Verification fixtures. |
| `doc/` | Engineering documentation and Docsify portal (`ARCHITECTURE.md`, `API_MANUAL.md`, `COVERAGE.md`, `BENCHMARKS.md`, `STUDIO_GUIDE.md`, `REFERENCE_SYNC.md`, `RELEASING.md`). | GitHub Pages site source. |

---

## 2. Core Architectural Invariants

### A. Pure-Dart SDK Boundary (`packages/tex_math/lib/`)

* **Strict Core Imports**: Code under `packages/tex_math/lib/` must never import `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*`.
* **Minimal Dependencies**: `packages/tex_math/pubspec.yaml` `dependencies:` contains strictly `meta`. Do not add third-party XML, font, or parser packages to `packages/tex_math`.
* **Zero File I/O & Determinism**: `MathFont.fromBytes(Uint8List)` and `TexMathEngine` run synchronously on caller-provided bytes and strings with zero filesystem access, zero network calls, and zero global mutable state across renders.

### B. OpenType `MATH`-Driven Layout

* All TeX Appendix G layout constants, glyph metrics, italics corrections, top accent attachment coordinates, math kerns, size variants, and extensible `GlyphAssembly` parts must come from the parsed OpenType `MATH` table (`NewCMMath-Regular.otf` by default) rather than hardcoded per-font tables.
* Display lists (`DisplayList`) reference glyphs by font glyph ID (`GlyphItem`) alongside rules (`RuleItem`) and semantic anchors (`AnchorItem`), allowing both standalone SVG path emission (`DisplayList.toSvg()`) and Flutter `Canvas.drawPath` caching.

### C. Five-Stage Pipeline & Safety Contracts

1. **Stage 1 — Tokenizer**: Converts input TeX into catcode-annotated tokens preserving `SourceSpan`.
2. **Stage 2 — Macro Expander**: Expands `\newcommand`, `\renewcommand`, `\def`, `\let`, `\newenvironment`, and `\renewenvironment` within `TexMathBudgets` (`maxMacroDepth`, `maxMacroExpansions`).
3. **Stage 3 — Parser**: Produces a Dart 3 `sealed class MathNode` syntax tree retaining `SourceSpan` on every node.
4. **Stage 4 — Layout Engine**: Applies TeX math styles (`D`, `T`, `S`, `SS` plus cramped forms), atom spacing, and OpenType `MATH` rules to build a positioned box tree.
5. **Stage 5 — Display List & Exporters**: Emits flat `DisplayList` items and metrics (`DisplayMetrics`) in ems/font units, standalone SVG XML (`toSvg()`), Presentation MathML (`toMathMl()`), and plain spoken text (`toSpokenText()`).

* **Strict Error Parity**: Malformed TeX or exceeded safety limits must throw typed `sealed class TexMathError` subclasses (`TexMathSyntaxError`, `TexMathMacroError`, `TexMathBudgetError`, `TexMathFontError`, `TexMathUnsupportedError`) mapped to `TexMathErrorClass` rather than silently rendering invalid output.
* **Dart 3 Standards**: Enable `strict-casts`, `strict-inference`, `strict-raw-types`, `always_declare_return_types`, `directives_ordering`, and `prefer_single_quotes`. Write dartdoc comments on every public API symbol and avoid `print()` calls in `lib/`.

### D. Reference Pinning & Lockstep Versioning

* **[`REFERENCE.md`](REFERENCE.md) is the single source of truth** for pinned MathJax (`4.1.3`), JupyterLab `@jupyterlab/mathjax-extension`, KaTeX (`0.19.1` studio comparison only), `NewCMMath-Regular.otf` (`8.1.1`), `tool/oracle/package-lock.json` SHA-256 integrity, and TeX package coverage tiers.
* **Lockstep Package Versions**: `packages/tex_math/pubspec.yaml`, `packages/tex_math_flutter/pubspec.yaml`, the top `## <version>` heading in both package `CHANGELOG.md` files, and `packages/tex_math_flutter`'s `tex_math: ^<version>` dependency must always agree, enforced by `tool/check_versions.dart`.

---

## 3. Quality Gates & Verification

Before completing any task or committing changes, verify all workspace gates pass with zero errors, warnings, or infos:

1. **Formatting**:
   ```bash
   dart format --output=none --set-exit-if-changed packages tool studio
   ```
2. **Static Analysis**:
   ```bash
   dart analyze --fatal-infos
   ```
3. **Package, Example & Studio Tests**:
   ```bash
   (cd packages/tex_math && dart test && dart run example/main.dart && dart doc --dry-run)
   (cd packages/tex_math_flutter && flutter test)
   (cd packages/tex_math_flutter/example && flutter test)
   (cd studio && flutter test)
   ```
4. **Version Lockstep, Oracle Parity, Reference Integrity & Benchmarks**:
   ```bash
   dart run tool/check_versions.dart
   (cd tool/oracle && npm ci)
   dart run tool/verify_against_mathjax.dart
   dart run tool/sync_reference.dart --verify
   dart run tool/benchmark_suite.dart --check-regressions
   ```
5. **Publish Readiness**:
   ```bash
   (cd packages/tex_math && dart pub publish --dry-run)
   (cd packages/tex_math_flutter && flutter pub publish --dry-run)
   ```

---

## 4. Reference Sync, Documentation & Commit Rules

* Follow [`doc/REFERENCE_SYNC.md`](doc/REFERENCE_SYNC.md) and [`.agents/skills/sync-reference-mathjax/SKILL.md`](.agents/skills/sync-reference-mathjax/SKILL.md) when updating pinned MathJax or JupyterLab versions, regenerating `corpus/expectations.json`, `doc/COVERAGE.md`, and `doc/BENCHMARKS.md`.
* Keep every Markdown prose paragraph on a single line without hard-wrapped line breaks inside paragraphs.
* Never commit private filesystem paths, third-party `node_modules/`, temporary SymPy output, or unverified coverage/benchmark counts.
* Use **Conventional Commits** (`feat(parser): ...`, `fix(layout): ...`, `docs(reference): ...`, `chore(ci): ...`) and omit automated tool credits, trailer attributions, or synthetic author tags from commit messages, PR descriptions, and code comments.
