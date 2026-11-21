## Summary

<!-- Briefly describe what this pull request changes and why. -->

## Reference & Tier Scope

- [ ] **Tier 1 (Core TeX, AMS, Macros, Textmacros, Tag/ConfigMacros)**
- [ ] **Tier 2 (JupyterLab Standard Extensions)**
- [ ] **Tier 3 (Remaining MathJax 4 Extensions)**
- [ ] **OpenType Font / Layout Engine / SVG / MathML / Accessibility**
- [ ] **Flutter Integration (`packages/tex_math_flutter`) / Studio (`studio/`) / Tooling / Docs**

## Quality Gate Checklist

- [ ] `dart format --output=none --set-exit-if-changed packages tool studio` passes.
- [ ] `dart analyze --fatal-infos` reports 0 issues across the workspace.
- [ ] `dart test` passes in `packages/tex_math`, and `dart run example/main.dart` plus `dart doc --dry-run` succeed.
- [ ] `flutter test` passes in `packages/tex_math_flutter`, `packages/tex_math_flutter/example`, and `studio`.
- [ ] `dart run tool/check_versions.dart`, `dart run tool/verify_against_mathjax.dart`, `dart run tool/sync_reference.dart --verify`, and `dart run tool/benchmark_suite.dart --check-regressions` pass.
- [ ] Pure-Dart boundary preserved (`packages/tex_math/lib/` contains no `package:flutter`, `dart:ui`, `dart:io`, or `dart:html` imports).
