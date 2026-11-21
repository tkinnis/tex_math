# Repository Instructions

Follow the architectural invariants, package boundaries, formatting standards, reference pins, and quality gates defined in **[AGENTS.md](../AGENTS.md)** and **[REFERENCE.md](../REFERENCE.md)**.

Key rules at a glance:

- **Pure-Dart SDK Boundary (`packages/tex_math/lib/`)**: Never import `package:flutter`, `dart:ui`, `dart:io`, `dart:html`, or `dart:js*`, and keep `dependencies:` limited to `package:meta`.
- **Lockstep Package Versioning**: Keep `packages/tex_math/pubspec.yaml`, `packages/tex_math_flutter/pubspec.yaml`, their `CHANGELOG.md` top entries, and `packages/tex_math_flutter`'s `tex_math` dependency constraint synchronized.
- **Reference Target**: Align TeX grammar, package behavior, error classes, and layout metrics with pinned MathJax `4.1.3` and JupyterLab `@jupyterlab/mathjax-extension` documented in `REFERENCE.md`, driven dynamically by OpenType `MATH` tables in `NewCMMath-Regular.otf`.
- **Verification Gates**: Ensure `dart format --output=none --set-exit-if-changed packages tool studio`, `dart analyze --fatal-infos`, all `dart test` and `flutter test` suites, `tool/check_versions.dart`, `tool/verify_against_mathjax.dart`, `tool/sync_reference.dart --verify`, and `tool/benchmark_suite.dart --check-regressions` pass before completion.
- **Commit Policy**: Use Conventional Commits and omit automated tool credits, trailer attributions, or synthetic author tags from commit messages, pull request descriptions, and comments.
