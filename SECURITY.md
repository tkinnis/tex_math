# Security Policy

## Security Model of `tex_math`

`tex_math` is designed to parse and render untrusted TeX math expressions into display lists, SVG paths, and Presentation MathML deterministically without executing arbitrary code, spawning subprocesses, or performing network or filesystem I/O:

1. **Zero DOM, Zero WebView & Zero Script Execution**:
   - The core engine in `packages/tex_math` runs in pure Dart with no headless browser, WebView, JavaScript runtime, or external runtime dependencies beyond `package:meta`.
   - All text, identifier, and error strings emitted into standalone SVG XML (`DisplayList.toSvg()` / `RenderResult.toSvg()`) and Presentation MathML (`RenderResult.toMathMl()`) are XML-escaped (`&`, `<`, `>`, `"`, `'`), preventing markup or script injection.
2. **Zero File & Network I/O in Core Engine**:
   - `packages/tex_math/lib/` never imports `dart:io`, `dart:html`, `dart:js*`, `dart:ui`, or `package:flutter`.
   - `MathFont.fromBytes(Uint8List)` operates solely on caller-supplied in-memory bytes, validating OpenType header structure and font budgets safely.
3. **Configurable DoS & Resource Exhaustion Guards (`TexMathBudgets`)**:
   - `TexMathBudgets.maxInputLength` bounds source TeX length in code units (default `50000`).
   - `TexMathBudgets.maxMacroDepth` (default `64`) and `TexMathBudgets.maxMacroExpansions` (default `10000`) prevent recursive `\def` / `\newcommand` expansion bombs.
   - `TexMathBudgets.maxNestingDepth` (default `64`) caps braced group and environment nesting depth.
   - `TexMathBudgets.maxOutputItems` (default `50000`) and `TexMathBudgets.maxSvgLength` (default `4000000`) bound emitted display items and SVG XML size, failing deterministically with `TexMathBudgetError`.
4. **Strict Error Reporting (`TexMathError`)**:
   - Invalid TeX input raises structured `TexMathError` subclasses (`TexMathSyntaxError`, `TexMathMacroError`, `TexMathBudgetError`, `TexMathFontError`, `TexMathUnsupportedError`) aligned with MathJax error classes (`TexMathErrorClass`) rather than silently swallowing malformed constructs or overflowing the stack.

---

## Supported Versions

Security fixes are applied to the current lockstep release line across `packages/tex_math` and `packages/tex_math_flutter` (see [`packages/tex_math/pubspec.yaml`](packages/tex_math/pubspec.yaml), [`packages/tex_math_flutter/pubspec.yaml`](packages/tex_math_flutter/pubspec.yaml), and [`REFERENCE.md`](REFERENCE.md)):

| Version | Supported |
| :--- | :---: |
| Latest release | Yes |
| Older releases | No |

---

## Reporting a Vulnerability

If you discover a security vulnerability in `tex_math` or `tex_math_flutter` (for example, an SVG/MathML XML escaping bypass, an unbounded macro expansion loop, an OpenType binary parser out-of-bounds read, or a resource exhaustion vector):

1. **Do not open a public GitHub issue.**
2. Report the vulnerability privately through [**GitHub Private Vulnerability Reporting**](https://github.com/tkinnis/tex_math/security/advisories/new) on this repository.
3. Include a minimal TeX snippet, font input description, or `TexMathOptions` / `TexMathBudgets` configuration that reproduces the issue, along with expected vs. actual behavior.

We will acknowledge receipt within 48 hours and coordinate validation, patching, and responsible disclosure.
