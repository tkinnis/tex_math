# Release Guide

`packages/tex_math` and `packages/tex_math_flutter` share strict **lockstep semantic versioning** (`X.Y.Z` or `X.Y.Z-pre`). Every release updates both packages together, passes every workspace quality gate, creates a matching `vX.Y.Z` (or `vX.Y.Z-pre`) git tag, and publishes `tex_math` to pub.dev before `tex_math_flutter`.

---

## 1. Lockstep Versioning Contract

`tool/check_versions.dart` enforces synchronization across the four authoritative publishable files (five lockstep version checks) and verifies that internal `publish_to: none` workspace pubspecs keep `any` constraints on every CI run and before any release tag:

* `packages/tex_math/pubspec.yaml`: `version: X.Y.Z`
* `packages/tex_math_flutter/pubspec.yaml`: `version: X.Y.Z`
* `packages/tex_math_flutter/pubspec.yaml`: `dependencies.tex_math: ^X.Y.Z`
* `packages/tex_math/CHANGELOG.md`: top heading `## X.Y.Z`
* `packages/tex_math_flutter/CHANGELOG.md`: top heading `## X.Y.Z`
* `pubspec.yaml`, `studio/pubspec.yaml`, and `packages/tex_math_flutter/example/pubspec.yaml`: internal `tex_math` and `tex_math_flutter` constraints pinned to `any`

The lockstep invariant ensures that every `tex_math_flutter` release pins the exact matching `^X.Y.Z` release of `tex_math` without cross-version skew, while [`REFERENCE.md`](../REFERENCE.md), package READMEs (`dart pub add` / `flutter pub add`), and internal `publish_to: none` workspace pubspecs avoid duplicating release version numbers.

---

## 2. Pre-Release Checklist

### Step 1: Bump Lockstep Version Metadata

1. Update `version:` in both `packages/tex_math/pubspec.yaml` and `packages/tex_math_flutter/pubspec.yaml` to the target `X.Y.Z` version.
2. Update `tex_math: ^X.Y.Z` under `dependencies:` in `packages/tex_math_flutter/pubspec.yaml` (internal `publish_to: none` workspace pubspecs in `pubspec.yaml`, `studio/pubspec.yaml`, and `packages/tex_math_flutter/example/pubspec.yaml` remain `any`).
3. Prepend a `## X.Y.Z` release section to both [`packages/tex_math/CHANGELOG.md`](../packages/tex_math/CHANGELOG.md) and [`packages/tex_math_flutter/CHANGELOG.md`](../packages/tex_math_flutter/CHANGELOG.md) summarizing user-visible changes.
4. Run `flutter pub get` at the repository root to refresh workspace resolution.

### Step 2: Run All Verification Gates

Execute the full workspace verification suite from the repository root and confirm zero errors, warnings, or info diagnostics:

```bash
dart format --output=none --set-exit-if-changed packages tool studio
dart analyze --fatal-infos
(cd packages/tex_math && dart test && dart run example/main.dart && dart doc --dry-run)
(cd packages/tex_math_flutter && flutter test)
(cd packages/tex_math_flutter/example && flutter test)
(cd studio && flutter test)
(cd tool/oracle && npm ci)
dart run tool/check_versions.dart
dart run tool/check_versions.dart --tag "vX.Y.Z"
dart run tool/verify_against_mathjax.dart
dart run tool/sync_reference.dart --verify
dart run tool/generate_doc_images.dart --check
dart run tool/benchmark_suite.dart --check-regressions
```

### Step 3: Validate `pub publish --dry-run`

Run dry-run publishing validation for both publishable packages:

```bash
(cd packages/tex_math && dart pub publish --dry-run)
(cd packages/tex_math_flutter && flutter pub publish --dry-run)
```

Verify that `packages/tex_math` passes `dart pub publish --dry-run` with zero errors or warnings. For `packages/tex_math_flutter`, `flutter pub publish --dry-run` validates package layout, `.pubignore` exclusions, and the bundled `NewCMMath-Regular.otf` + `GUST-FONT-LICENSE.txt` + `MANIFEST-NewCMMath.txt` assets; before `tex_math` `X.Y.Z` is live on pub.dev, `flutter pub publish --dry-run` flags only the unpublished `tex_math: ^X.Y.Z` dependency constraint.

---

## 3. Tagging & Publishing Order

Because `tex_math_flutter` depends on `tex_math: ^X.Y.Z`, **`tex_math` MUST be published to pub.dev before `tex_math_flutter`**.

### Step 1: Commit & Tag `vX.Y.Z`

1. Commit the release metadata changes using Conventional Commits (for example `chore(release): prepare vX.Y.Z`).
2. Create an annotated git tag matching the lockstep version and verify it locally:

```bash
git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
dart run tool/check_versions.dart --tag "vX.Y.Z"
```

3. Push the release commit and tag `vX.Y.Z` so `.github/workflows/ci.yml` executes the full CI suite with `--tag vX.Y.Z`.

### Step 2: Publish `packages/tex_math` First

Once CI passes on the tagged commit, publish the pure-Dart core package first:

```bash
(cd packages/tex_math && dart pub publish)
```

Confirm `tex_math` version `X.Y.Z` is resolved and listed on pub.dev before continuing to Step 3.

### Step 3: Publish `packages/tex_math_flutter` Second

After `tex_math` `X.Y.Z` is available on pub.dev, verify `flutter pub publish --dry-run` reports zero warnings inside `packages/tex_math_flutter` and publish:

```bash
(cd packages/tex_math_flutter && flutter pub publish --dry-run)
(cd packages/tex_math_flutter && flutter pub publish)
```

---

## 4. Post-Release Verification

* Confirm both package pages on pub.dev display matching `X.Y.Z` versions, complete READMEs, and MIT license metadata (plus GUST Font License documentation for `NewCMMath-Regular.otf`).
* Verify the Docsify portal built by `.github/workflows/pages.yml` renders updated changelogs, [`doc/COVERAGE.md`](COVERAGE.md), and [`doc/BENCHMARKS.md`](BENCHMARKS.md).
