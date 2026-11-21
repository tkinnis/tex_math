# Contributing to `tex_math`

Thank you for your interest in contributing to **`tex_math`**. This monorepo builds a pure-Dart TeX math-mode parser, OpenType `MATH` layout engine, and Flutter renderer aligned with pinned MathJax `4.1.3` and JupyterLab TeX defaults.

Before opening an issue or submitting a pull request, review our architectural invariants, development workflow, and verification gates below.

---

## 1. Core Architectural Invariants

1. **Pure-Dart SDK Boundary (`packages/tex_math/lib/`)**:
   - Everything under `packages/tex_math/lib/` must use standard pure-Dart libraries (`dart:core`, `dart:math`, `dart:convert`, `dart:typed_data`) with `dependencies:` limited strictly to `package:meta`.
   - Never import `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` inside `packages/tex_math/lib/`. This keeps the core engine portable across Flutter mobile/desktop/web, Dart CLI tools, server executables, and background isolates.
2. **OpenType `MATH`-Driven Layout (Zero Hardcoded Font Metric Tables)**:
   - Box metrics, axis heights, radical gaps, script shifts, italics corrections, accent attachments, math kerns, and stretchy delimiter construction must read directly from OpenType `MATH` tables and font outlines rather than hardcoded per-font lookup tables.
3. **MathJax & JupyterLab Reference Parity**:
   - TeX grammar, macro semantics, package behavior, and error classes target exact parity with the pinned MathJax `4.1.3` and JupyterLab `@jupyterlab/mathjax-extension` baseline tracked in [`REFERENCE.md`](REFERENCE.md).
   - If a layout or grammar edge case involves an upstream MathJax difference, verify behavior against `tool/oracle/render.mjs` and check existing corpus cases under `corpus/`.
4. **Lockstep Package Versioning**:
   - `packages/tex_math` and `packages/tex_math_flutter` share lockstep versions (`version:` in both `pubspec.yaml` files, top headings in both `CHANGELOG.md` files, and `tex_math_flutter`'s `tex_math` dependency constraint), verified by `tool/check_versions.dart`.

---

## 2. Development Setup

### Prerequisites

- **Flutter & Dart SDK**: Flutter `>=3.47.0` with Dart `^3.13.0` (`pub` workspace support).
- **Node.js** *(for oracle verification)*: Needed to run `tool/oracle/render.mjs` and `tool/verify_against_mathjax.dart`.

### Installing Dependencies

```bash
git clone https://github.com/tkinnis/tex_math.git
cd tex_math
flutter pub get
(cd tool/oracle && npm ci)
```

---

## 3. Quality Gates & Verification

Every pull request must pass all repository quality gates:

### 1. Code Formatting

```bash
dart format --output=none --set-exit-if-changed packages tool studio
```

### 2. Static Analysis (Zero Warnings / Infos)

```bash
dart analyze --fatal-infos
```

### 3. Package, Example & Studio Test Suites

```bash
(cd packages/tex_math && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/tex_math_flutter && flutter test)
(cd packages/tex_math_flutter/example && flutter test)
(cd studio && flutter test)
```

### 4. Version, Reference, Oracle & Benchmark Gates

```bash
dart run tool/check_versions.dart
dart run tool/verify_against_mathjax.dart
dart run tool/sync_reference.dart --verify
dart run tool/generate_doc_images.dart --check
dart run tool/benchmark_suite.dart --check-regressions
```

---

## 4. Commit Message & Pull Request Guidelines

We follow the [**Conventional Commits**](https://www.conventionalcommits.org/) specification:

- `feat(scope): ...` — New TeX package features, layout rules, or Flutter widget capabilities.
- `fix(scope): ...` — Bug fixes in tokenization, macro expansion, parsing, OpenType layout, SVG/MathML emission, or Flutter painting.
- `docs(scope): ...` — Documentation, Dartdoc comments, coverage/benchmark reports, or reference updates.
- `refactor(scope): ...` — Internal code restructuring without behavioral changes.
- `test(scope): ...` — Unit, widget, golden, or corpus parity test additions.
- `chore(scope): ...` — Workspace config, CI workflows, dependency updates, or tooling scripts.

When submitting a pull request:

1. Keep changes focused on a single concern.
2. Add unit, widget, golden, or corpus tests covering any bug fix or new capability.
3. Omit automated tool credits, trailer attributions, or synthetic author tags from commit messages and pull request descriptions.
4. Keep Markdown prose paragraphs on a single line (no hard-wrapped prose lines inside paragraphs).

---

## 5. Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold its standards.
