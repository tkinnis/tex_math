---
name: sync-reference-mathjax
description: Checks npm and upstream GitHub releases for MathJax and @jupyterlab/mathjax-extension, updates tool/oracle package pins and lockfile SHA-256 hashes, updates REFERENCE.md, regenerates corpus expectations and coverage/benchmark docs, and verifies full parity and quality gates.
---

# Sync Reference MathJax & JupyterLab Skill (`sync-reference-mathjax`)

Use this skill whenever checking for new MathJax or `@jupyterlab/mathjax-extension` releases, updating `tool/oracle/` pins, refreshing `REFERENCE.md`, or re-baselining `corpus/expectations.json`, `doc/COVERAGE.md`, and `doc/BENCHMARKS.md`.

---

## 1. Check Reference Drift & Upstream Releases

Run the reference verifier and registry check from the repository root:

```bash
dart run tool/sync_reference.dart --verify
dart run tool/sync_reference.dart --check
dart run tool/sync_reference.dart --check --json
```

* `--verify` checks that [`REFERENCE.md`](../../../REFERENCE.md) matches `tool/oracle/package.json` (`mathjax`, `@mathjax/src`, `@mathjax/mathjax-newcm-font`, `katex`) and matches the SHA-256 digest of `tool/oracle/package-lock.json`.
* `--check` queries the npm registry for `mathjax` and `@jupyterlab/mathjax-extension` latest releases and compares them with [`REFERENCE.md`](../../../REFERENCE.md).

---

## 2. Update `tool/oracle/` Pins & Lockfile Hash

When adopting a new MathJax release:

1. Update exact versions for `mathjax`, `@mathjax/src`, and `@mathjax/mathjax-newcm-font` in `tool/oracle/package.json`.
2. Regenerate `tool/oracle/package-lock.json` and compute its SHA-256 digest:
   ```bash
   (cd tool/oracle && npm install)
   shasum -a 256 tool/oracle/package-lock.json
   ```
3. Verify `tool/oracle/render.mjs` still extracts box metrics, `<use data-c="...">` glyphs, `<rect>` rules, and `TexError` classes accurately against the updated `@mathjax/src` and `@mathjax/mathjax-newcm-font` ESM modules.
4. Inspect JupyterLab's `packages/mathjax-extension/src/tex.ts` and `packages/mathjax-extension/package.json` if updating the JupyterLab reference pin, confirming whether any default packages changed across `TEX_PACKAGES`.

---

## 3. Refresh `REFERENCE.md`, Expectations & Reports

1. Update [`REFERENCE.md`](../../../REFERENCE.md) with the new pinned versions, upstream tag/commit SHAs, package inventory changes, and exact `tool/oracle/package-lock.json` SHA-256 hash.
2. Update `corpus/` `.tex` cases if new MathJax TeX packages or edge cases are added, then refresh expectations, coverage tables, and AOT benchmarks:
   ```bash
   dart run tool/verify_against_mathjax.dart --update-expectations
   dart run tool/coverage_report.dart
   dart run tool/benchmark_suite.dart --update-docs --update-baseline
   dart run tool/generate_doc_images.dart
   ```
3. Update `README.md`, `packages/tex_math/README.md`, and `packages/tex_math_flutter/README.md` if coverage or benchmark figures in `doc/COVERAGE.md` or `doc/BENCHMARKS.md` changed.

---

## 4. Run Full Verification Gates

Before committing, verify every workspace gate passes with zero errors, warnings, or infos:

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
(cd packages/tex_math && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/tex_math_flutter && flutter test)
(cd packages/tex_math_flutter/example && flutter test)
(cd studio && flutter test)
dart run tool/check_versions.dart
dart run tool/verify_against_mathjax.dart
dart run tool/sync_reference.dart --verify
dart run tool/generate_doc_images.dart --check
dart run tool/benchmark_suite.dart --check-regressions
```

Confirm local git author configuration uses `tkinnis <219582735+tkinnis@users.noreply.github.com>` and commit using Conventional Commits without automated tool attributions.
