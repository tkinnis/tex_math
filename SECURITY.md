# Security Policy

## Security Model of `tex_math`

`tex_math` parses and renders untrusted TeX math expressions into display lists, SVG paths, and Presentation MathML deterministically without executing arbitrary code, spawning subprocesses, or performing filesystem or network I/O.

### Pure-Dart Execution & Budget Guards

* **Zero DOM, WebView, or Script Execution**: Core engine code depends strictly on `package:meta` with no Flutter, UI, or I/O imports. `MathFont.fromBytes` reads only caller-provided byte buffers.
* **Cumulative Resource Budgets (`TexMathBudgets`)**: Shared token and macro-depth state travels across root parsing, sub-expression parsing, synthetic parsing, and `\edef` expansion so nested expressions cannot reset counters or trigger exponential macro bombs. Oversized inputs and limits fail deterministically with `TexMathBudgetError`.
* **Safe SVG & Presentation MathML Serialization**: Emitted XML text and attributes escape special XML characters and strip disallowed XML 1.0 control codes and lone surrogates. `\href` links allow only HTTP, HTTPS, `mailto:`, fragment links, and scheme-less relative paths, while invalid colors or CSS lengths raise `TexMathSyntaxError`.

| Guard / Subsystem | Default Limit | Protected Resource |
| :--- | :--- | :--- |
| `maxInputLength` | `50000` UTF-16 code units | Raw and synthetic TeX string length before tokenization. |
| `maxMacroDepth` | `64` levels | Inherited nested macro call stack depth. |
| `maxMacroExpansions` | `10000` expansions | Shared cumulative macro expansions per parse. |
| `maxTokens` | `100000` tokens | Shared cumulative tokens scanned or materialized during expansion. |
| `maxNestingDepth` | `64` levels | Group, parser, `mhchem`, and syntax-tree depth checked across parsing, layout, MathML, and spoken-text export. |
| Array `*{count}{body}` expansion | `256` repetitions | Caps column-spec repetition loops and skips empty or non-positive counts. |
| `physics` matrix generators | `4096` cells | Bounds `rows * cols` for `\imat`, `\xmat`, `\zmat`, and `\dmat` before AST construction. |
| `maxOutputItems` / `maxSvgLength` | `50000` items / `4000000` chars | Bounds emitted display items and serialized SVG XML size incrementally. |

### OpenType Binary Font Hardening

`MathFont.fromBytes` validates untrusted SFNT payloads defensively before allocating glyph outlines or metric tables, rejecting invalid containers with `TexMathFontError` or `TexMathBudgetError`:

| Decoder / Table | Enforced Limits & Hardening |
| :--- | :--- |
| **SFNT Directory & Subtables** | Enforces `16 MiB` default `maxBytes`, checks container signatures and table bounds, deduplicates repeated subtable offsets, and rejects unsorted or overlapping Format 2 coverage ranges. |
| **TrueType `glyf` Decoder** | Memoizes composite glyphs while enforcing a composite depth cap of `32`, visit cap of `4096`, point cap of `65536`, and path-command cap of `16384`. |
| **CFF / CFF2 CharString Interpreter** | Enforces call depth (`64`), subroutine calls (`4096`), opcodes (`65536`), stem hints (`1024`), and path commands (`16384`), validates finite coordinates, and rejects empty CFF2 `FDArray` tables. |

---

## Comparison Studio & CLI Tooling Security

`studio/` and `tool/` are local developer tools outside the publishable `tex_math` and `tex_math_flutter` packages:

* **Studio Loopback Asset Server**: Binds `127.0.0.1` on an ephemeral port and prefixes all harness and asset URLs with a per-instance 24-byte `Random.secure()` session token. It validates `Host` headers, omits wildcard CORS headers, and sets restrictive `Content-Security-Policy` and `nosniff` headers. Path resolution also blocks traversal segments, encoded separators, and escaping symlinks via canonical path checks.
* **Studio Web Panes & macOS Entitlements**: Configures MathJax `ui/safe` with an allowlisted package set excluding `texhtml`, sets `trust: false` on KaTeX, locks navigation to the active loopback URL, and gates debug capture behind `kDebugMode`. Local macOS entitlements disable App Sandbox solely so this developer tool can read workspace fixtures and oracle assets from disk.
* **MathJax CLI Oracle (`tool/oracle/render.mjs`)**: Rejects `texhtml` unless `--allow-texhtml` is passed explicitly and restricts dynamic module loading to known TeX packages and `@mathjax/` font chunks.

---

## Supported Versions

Security fixes apply to the current lockstep release line across `packages/tex_math` and `packages/tex_math_flutter` (see [`REFERENCE.md`](REFERENCE.md)):

| Version | Supported |
| :--- | :---: |
| Latest release | Yes |
| Older releases | No |

---

## Reporting a Vulnerability

If you discover a security vulnerability in `tex_math` or `tex_math_flutter` (such as an SVG/MathML escaping or URI scheme bypass, a macro or parser budget bypass, or an OpenType parser out-of-bounds read):

1. **Do not open a public GitHub issue.**
2. Report the vulnerability privately through [**GitHub Private Vulnerability Reporting**](https://github.com/tkinnis/tex_math/security/advisories/new) on this repository.
3. Include a minimal TeX snippet, font payload description, or `TexMathOptions` configuration that reproduces the issue alongside expected and actual behavior.

We will acknowledge receipt within 48 hours and coordinate validation, patching, and responsible disclosure.
