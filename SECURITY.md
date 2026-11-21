# Security Policy

## Security Model of `tex_math`

`tex_math` parses and renders untrusted TeX math expressions into display lists, SVG paths, and Presentation MathML deterministically without executing arbitrary code, spawning subprocesses, or performing network or filesystem I/O:

1. **Zero DOM, Zero WebView & Zero Script Execution**:
   - `packages/tex_math/lib/` runs in pure Dart with no WebView, JavaScript runtime, or third-party dependencies beyond `package:meta`, and never imports `dart:io`, `dart:html`, `dart:js*`, `dart:ui`, or `package:flutter`.
   - `MathFont.fromBytes(Uint8List)` operates solely on caller-supplied in-memory bytes.
2. **Configurable DoS & Budget Guards (`TexMathBudgets`)**:
   - `maxInputLength` (default `50000` UTF-16 code units) caps raw and synthetic TeX input sizes before tokenization.
   - `maxMacroDepth` (default `64`), `maxMacroExpansions` (default `10000`), and `maxTokens` (default `100000`) are enforced cumulatively via shared `TexTokenBudgetState` and inherited macro depth across the root `TexTokenCursor`, `parseSubTokens`, `parseSyntheticTex`, and `\edef` expansion to block exponential macro bombs and subexpression resets.
   - `maxNestingDepth` (default `64`) guards all recursive parser and `mhchem` paths (`\color`, style/font switches, `\not`, unbraced arguments, text mode, `\ce`/`\pu`, and `array` star expansion) and is verified across `parse()`, `layout()`, `toMathMl()`, and `toSpokenText()`. Array `*{count}{body}` star expansions skip empty/non-positive bodies and cap repetitions at `256`, while `physics` matrix generators (`\imat`, `\xmat`, `\zmat`, `\dmat`) cap `rows * cols` at `4096` cells before AST construction.
   - `maxOutputItems` (default `50000`) and `maxSvgLength` (default `4000000`, checked incrementally) cap emitted display items and serialized SVG XML size, failing deterministically with `TexMathBudgetError`.
3. **OpenType Binary Font Hardening (`MathFont.fromBytes`)**:
   - Enforces `maxBytes` (`16 MiB` default), validates SFNT container headers and table bounds, deduplicates repeated subtable offsets (`ItemVariationStore`, `GSUB` `AlternateSubst`, `MathVariants`) against decoded record caps, and rejects unsorted or overlapping Format 2 `CoverageTable` ranges.
   - `GlyfDecoder` memoizes composite glyphs with depth (`32`), visit (`4096`), and path-command (`16384`) caps; `Type2CharStringInterpreter` enforces call-depth (`64`), subroutine-call (`4096`), opcode (`65536`), stem-hint (`1024`), and path-command (`16384`) limits, validates finite numeric values, and rejects empty CFF2 `FDArray` tables (`TexMathFontError`).
4. **Safe SVG & Presentation MathML Serialization**:
   - All emitted SVG and MathML text and attributes escape `&`, `<`, `>`, `"`, and `'` and strip disallowed XML 1.0 control characters and lone surrogates (`format_utils.dart`, `\unicode`, `\char`).
   - `\href` parsing (`parser.dart`) and `mathNodeToMathMl()` restrict links via `isSafeHrefUri` to `http`, `https`, `mailto`, `#` fragments, and scheme-less relative paths (blocking `javascript:`, `data:`, and `vbscript:`), and `sanitizeMathMlColor` validates MathML `mathcolor`/`mathbackground` strings.
   - Non-finite color channels (`\color[rgb]`, `\color[gray]`) and CSS lengths (`\bbox`) are rejected cleanly with `TexMathSyntaxError`.

---

## Comparison Studio & CLI Tooling Security

`studio/` and `tool/` run local development tooling outside the publishable `tex_math` and `tex_math_flutter` packages:

* **Studio Loopback Asset Server (`StudioLocalAssetServer`)**: Binds `127.0.0.1` on an ephemeral port, enforces a per-instance 24-byte `Random.secure()` session token (`/s/<token>/...`), validates `Host` (`127.0.0.1:<port>` or `localhost:<port>`), omits wildcard CORS headers, sends `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `Cache-Control: no-store`, and a restrictive `Content-Security-Policy` on harness HTML, and blocks path traversal, encoded separators (`%2f`, `%5c`, `\`, NUL), and escaping symlinks via `resolveSymbolicLinksSync()`.
* **Studio `WKWebView` & Developer Sandbox Note**: The MathJax `4.1.3` harness loads `ui/safe` (`safeOptions` disabling `file:`, `javascript:`, and `data:`) and restricts `packages` to `allowedMathJaxPackages` (excluding `texhtml`); KaTeX sets `trust: false`; `NavigationDelegate.onNavigationRequest` (`evaluateNavigationRequest`) locks navigation strictly to the active main-frame loopback harness URL; and `TEX_MATH_STUDIO_CAPTURE_SPEC` automation is gated behind `kDebugMode`. `studio/macos/Runner/*.entitlements` disables Apple App Sandbox (`com.apple.security.app-sandbox: false`) solely because this local developer workbench (`publish_to: none`) reads workspace `corpus/` fixtures and gitignored `tool/oracle/node_modules/` bundles directly from disk.
* **MathJax CLI Oracle (`tool/oracle/render.mjs`)**: Rejects `texhtml` unless `--allow-texhtml` is passed explicitly and constrains `mathjax.asyncLoad` and `LOADERCONFIG.require` to known `ALL_TEX_PACKAGES` `[tex]/...` specifiers and `@mathjax/` dynamic font chunks.

---

## Supported Versions

Security fixes apply to the current lockstep release line across `packages/tex_math` and `packages/tex_math_flutter` (see [`packages/tex_math/pubspec.yaml`](packages/tex_math/pubspec.yaml), [`packages/tex_math_flutter/pubspec.yaml`](packages/tex_math_flutter/pubspec.yaml), and [`REFERENCE.md`](REFERENCE.md)):

| Version | Supported |
| :--- | :---: |
| Latest release | Yes |
| Older releases | No |

---

## Reporting a Vulnerability

If you discover a security vulnerability in `tex_math` or `tex_math_flutter` (for example, an SVG/MathML escaping or URI scheme bypass, a macro or parser budget bypass, or an OpenType parser out-of-bounds read):

1. **Do not open a public GitHub issue.**
2. Report the vulnerability privately through [**GitHub Private Vulnerability Reporting**](https://github.com/tkinnis/tex_math/security/advisories/new) on this repository.
3. Include a minimal TeX snippet, font input description, or `TexMathOptions` / `TexMathBudgets` configuration that reproduces the issue, along with expected vs. actual behavior.

We will acknowledge receipt within 48 hours and coordinate validation, patching, and responsible disclosure.
