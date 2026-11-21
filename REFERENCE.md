# Reference Specification & Upstream Pins

This document is the **single source of truth** for the upstream MathJax, JupyterLab, font, and oracle package versions that **`tex_math`** targets, along with the package tier breakdown used across the verification corpus and automated tooling (`tool/sync_reference.dart`, `tool/verify_against_mathjax.dart`).

---

## Pinned Versions & Integrity

| Component | Version / Value | Notes |
| :--- | :--- | :--- |
| `tex_math` | See `packages/tex_math/pubspec.yaml` | Authoritative lockstep pure-Dart core package version (synchronized with `packages/tex_math/CHANGELOG.md` via `tool/check_versions.dart`). |
| `tex_math_flutter` | See `packages/tex_math_flutter/pubspec.yaml` | Authoritative lockstep Flutter widget and font bundle package version (synchronized with `packages/tex_math_flutter/CHANGELOG.md` via `tool/check_versions.dart`). |
| `mathjax` | `4.1.3` | Pinned MathJax meta-package (`mathjax/MathJax` tag `4.1.3`, commit `0bfa580685ca72e4a3a37657ccd754a65c1a42c6`). |
| `@mathjax/src` | `4.1.3` | Pinned MathJax 4 source (`mathjax/MathJax-src` tag `4.1.3`, commit `fb987178c2d279a99b0db5ea02e751691703955e`). |
| `@mathjax/mathjax-newcm-font` | `4.1.3` | Pinned MathJax New Computer Modern math font tables and SVG paths. |
| `@jupyterlab/mathjax-extension` | `4.6.6` | Stable JupyterLab baseline (`jupyterlab/jupyterlab@v4.6.6`, commit `8d57791d0254820dfa4a540e010105803e128bcd`, `mathjax-full@^3.2.2` loading `AllPackages.concat('require')`); pre-release `4.7.0-beta.2` (`main`, commit `c233d4b14d548fe55108a883aea5f9f52afe5594`) migrates to `@mathjax/src@^4.1.1`, `@mathjax/mathjax-tex-font`, and `@mathjax/mathjax-mhchem-font-extension`. |
| `katex` | `0.19.1` | Side-by-side comparison reference inside `studio/` only (not an oracle target for `tex_math`). |
| `NewCMMath-Regular.otf` | `8.1.1` | Default bundled OpenType `MATH` font (`GUST Font License 1.0`). |
| `tool/oracle/package-lock.json` | `3d110f70c3092b628f34cd2b245c834b3acb398e60014c4f9c32549ec2abd24a` | SHA-256 digest of the pinned `tool/oracle/` npm dependency graph. |

---

## MathJax `4.1.3` TeX Package Inventory (42 Packages)

Under `ts/input/tex/` in `mathjax/MathJax-src` (`4.1.3`), MathJax defines **42 TeX packages**:

`action`, `ams`, `amscd`, `autoload`, `base`, `bbm`, `bboldx`, `bbox`, `begingroup`, `boldsymbol`, `braket`, `bussproofs`, `cancel`, `cases`, `centernot`, `color`, `colortbl`, `colorv2`, `configmacros`, `dsfont`, `empheq`, `enclose`, `extpfeil`, `fontsizev3`, `gensymb`, `html`, `mathtools`, `mhchem`, `newcommand`, `noerrors`, `noundefined`, `physics`, `require`, `setoptions`, `tagformat`, `texhtml`, `textcomp`, `textmacros`, `unicode`, `units`, `upgreek`, `verb`.

---

## JupyterLab TeX Extension Configuration

Both JupyterLab `4.6.6` (`mathjax-full@^3.2.2`, `AllPackages.concat('require')`) and JupyterLab `4.7.0-beta.2` (`TEX_PACKAGES` in `packages/mathjax-extension/src/tex.ts`) enable the exact same **31 default TeX packages**:

`base`, `action`, `ams`, `amscd`, `bbox`, `boldsymbol`, `braket`, `bussproofs`, `cancel`, `cases`, `centernot`, `color`, `colortbl`, `empheq`, `enclose`, `extpfeil`, `gensymb`, `html`, `mathtools`, `mhchem`, `newcommand`, `noerrors`, `noundefined`, `upgreek`, `unicode`, `verb`, `configmacros`, `tagformat`, `textcomp`, `textmacros`, `require`.

* **Preloaded for `\require` in JupyterLab `4.7.0-beta.2` (3 packages)**: `colorv2`, `physics`, `setoptions`.
* **Remaining MathJax `4.1.3` packages (8 packages)**: `autoload`, `bbm`, `bboldx`, `begingroup`, `dsfont`, `fontsizev3`, `texhtml`, `units`.
* **Oracle Default Verification Set**: `tool/oracle/render.mjs` activates the 29 functional JupyterLab default packages excluding `noerrors` and `noundefined` so malformed expressions surface deterministic `TexError` failures during differential testing, while corpus cases targeting error-suppression behavior enable `noerrors` or `noundefined` explicitly.

---

## Coverage Tiers

| Tier | Scope | Included Packages & Features |
| :--- | :--- | :--- |
| **Tier 1** | Core TeX, AMS, Macros, Textmacros, Tag & ConfigMacros | `base`, `ams`, `newcommand`, `textmacros`, `tagformat`, `configmacros` |
| **Tier 2** | JupyterLab Standard Extensions | `action`, `amscd`, `bbox`, `boldsymbol`, `braket`, `bussproofs`, `cancel`, `cases`, `centernot`, `color`, `colortbl`, `empheq`, `enclose`, `extpfeil`, `gensymb`, `html`, `mathtools`, `mhchem`, `noerrors`, `noundefined`, `require`, `textcomp`, `unicode`, `upgreek`, `verb` |
| **Tier 3** | Remaining MathJax 4 Extensions | `autoload`, `bbm`, `bboldx`, `begingroup`, `colorv2`, `dsfont`, `fontsizev3`, `physics`, `setoptions`, `texhtml`, `units` |
