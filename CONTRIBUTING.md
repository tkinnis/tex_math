# Contributing to `tex_math`

Thank you for contributing to **`tex_math`**. This monorepo houses a pure-Dart TeX math parser, OpenType math layout engine, and Flutter rendering suite aligned with MathJax `4.1.3` and JupyterLab defaults.

Before opening an issue or submitting a pull request, review the architectural invariants, setup instructions, and verification gates below.

---

## 1. Core Architectural Invariants

1. **Pure-Dart SDK Boundary**: Everything under `packages/tex_math/lib/` must use standard pure-Dart libraries with `dependencies:` restricted strictly to `meta`. Never import Flutter, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*` inside the core package so it stays portable across mobile, desktop, web, CLI tools, and background isolates.
2. **OpenType Math-Driven Layout**: Box metrics, axis heights, radical gaps, script shifts, italics corrections, accent attachments, math kerns, and stretchy delimiter recipes must read directly from parsed OpenType math tables and font outlines rather than hardcoded per-font lookup tables.
3. **MathJax & JupyterLab Reference Parity**: TeX syntax, macro behavior, package support, and error classes target the pinned MathJax `4.1.3` and JupyterLab baseline tracked in [`REFERENCE.md`](REFERENCE.md). When investigating layout or grammar edge cases, check behavior against `tool/oracle/render.mjs` and existing tests in `corpus/`.
4. **Lockstep Package Versioning**: `packages/tex_math` and `packages/tex_math_flutter` share identical versions across both `pubspec.yaml` files, both changelogs, and the core dependency constraint, verified by `tool/check_versions.dart`.

---

## 2. Development Setup

### Prerequisites

* **Flutter & Dart SDK**: Flutter `>=3.47.0` with Dart `^3.13.0` (`pub` workspace support).
* **Node.js** *(for oracle verification)*: Required to run `tool/oracle/render.mjs` and `tool/verify_against_mathjax.dart`.

### Installing Dependencies

```bash
git clone https://github.com/tkinnis/tex_math.git
cd tex_math
flutter pub get
(cd tool/oracle && npm ci)
```

---

## 3. Quality Gates & Verification

Every pull request must pass all repository formatting, static analysis, test, parity, and benchmark checks:

### Code Formatting & Static Analysis

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
```

### Package, Example & Studio Test Suites

```bash
(cd packages/tex_math && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/tex_math_flutter && flutter test)
(cd packages/tex_math_flutter/example && flutter test)
(cd studio && flutter test)
```

### Version, Reference, Oracle & Benchmark Gates

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

| Prefix | Usage |
| :--- | :--- |
| `feat(scope): ...` | New TeX package support, layout rules, or Flutter widget capabilities. |
| `fix(scope): ...` | Bug fixes in tokenization, macro expansion, parsing, OpenType layout, SVG/MathML export, or Flutter painting. |
| `docs(scope): ...` | Documentation, dartdoc comments, coverage or benchmark reports, and reference updates. |
| `refactor(scope): ...` | Internal restructuring without behavioral changes. |
| `test(scope): ...` | Unit, widget, golden, or corpus parity test additions. |
| `chore(scope): ...` | Workspace config, CI workflows, dependency updates, or tooling scripts. |

When submitting a pull request:

1. Keep changes focused on a single concern.
2. Add unit, widget, golden, or corpus tests covering any bug fix or new capability.
3. Omit automated tool credits, trailer attributions, or synthetic author tags from commit messages and pull request descriptions.
4. Keep Markdown prose paragraphs on a single line with no hard-wrapped line breaks inside paragraphs.

---

## 5. Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold its standards.
