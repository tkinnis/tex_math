# `tex_math` Verification Corpus

The `corpus/` directory stores 352 hand-authored TeX expressions used to verify parsing, error rejection, bounding-box metrics, rule geometry, and glyph placement against the pinned MathJax `4.1.3` oracle (`tool/oracle/render.mjs`) using the `mathjax-newcm` font.

## Directory Layout and Tier Definitions

| Directory | Tier Key | Coverage Scope | Case Count |
| --- | --- | --- | --- |
| `corpus/tier1_core/` | `1` | Core TeX, AMS, macros, text macros, tagging, and config macros | 125 |
| `corpus/tier2_jupyter/` | `2` | Standard JupyterLab TeX extensions | 105 |
| `corpus/tier3_extended/` | `3` | Remaining MathJax `4.1.3` extensions | 35 |
| `corpus/stretchy/` | `stretchy` | Tall delimiters, horizontal braces and brackets, wide accents, extensible arrows, and deep radicals | 25 |
| `corpus/notebooks/` | `notebooks` | Realistic physics, calculus, linear algebra, probability/ML, and chemistry notebook equations | 25 |
| `corpus/errors/` | `errors` | Deliberately invalid TeX verified to be refused by MathJax | 37 |

Generated reference expectations are recorded separately in `corpus/expectations.json` via `tool/verify_against_mathjax.dart --update-expectations`.

## `.tex` Case File Format

Every `.tex` fixture begins with `%` metadata header lines followed by the raw TeX math-mode body without outer `$...$` or `$$...$$` delimiters:

```tex
% id: tier1_core/base/fraction_basic
% tier: 1
% package: base
% feature: fractions
% display: display
% accepted: true
\frac{a + b}{c - d}
```

| Header | Required | Values / Notes |
| :--- | :--- | :--- |
| `% id:` | Yes | Unique fixture identifier matching its relative path. |
| `% tier:` | Yes | `1`, `2`, `3`, `stretchy`, `notebooks`, or `errors`. |
| `% package:` | Yes | Primary TeX package under test. |
| `% feature:` | Yes | Feature category within that package. |
| `% display:` | Yes | `display` or `inline`. |
| `% accepted:` | Yes | `true` for valid expressions, `false` for expected refusals. |
| `% error_class:` | If refused | Canonical `TexMathErrorClass` expected on failure. |
| `% packages:` | Optional | Comma-separated package list overriding the default 29-package set. |

When `% packages:` is omitted, the oracle enables the 29 active JupyterLab default TeX packages below. `noerrors` and `noundefined` are excluded by default so malformed TeX and undefined macros fail deterministically unless a fixture opts into them explicitly:

```text
base, action, ams, amscd, bbox, boldsymbol, braket, bussproofs, cancel, cases,
centernot, color, colortbl, empheq, enclose, extpfeil, gensymb, html, mathtools,
mhchem, newcommand, upgreek, unicode, verb, configmacros, tagformat, textcomp,
textmacros, require
```

## Error Classes

Refused fixtures in `corpus/errors/` assert deterministic rejection across the 14 TeX error classes mapped from MathJax exceptions. The remaining two values of `TexMathErrorClass` (`invalidFont` and `unsupportedFeature`) cover engine and font errors.

| Error Class | Meaning | Representative MathJax `TexError` IDs |
| --- | --- | --- |
| `undefinedControlSequence` | Unrecognized macro outside `noundefined` | `UndefinedControlSequence` |
| `missingBrace` | Unclosed `{` group or missing closing `}` or `]` | `MissingCloseBrace`, `ExtraOpenMissingClose`, `MissingCloseBracket` |
| `extraBrace` | Unmatched closing `}` delimiter | `ExtraCloseMissingOpen`, `ExtraCloseLooking` |
| `misplacedAlignmentTab` | Invalid `&` or extra column outside valid alignment slots | `Misplaced` (`&`), `XalignOverflow`, `MultlineRowsOneCol` |
| `misplacedNewline` | Misplaced `\cr`, `\hline`, or invalid `\\` spacing | `Misplaced` (`\cr`, `\hline`), `BracketMustBeDimension` |
| `missingDelimiter` | Unclosed `\left` or invalid delimiter token | `ExtraLeftMissingRight`, `MissingOrUnrecognizedDelim` |
| `extraDelimiter` | Unmatched `\right` or stray `\middle` | `MissingLeftExtraRight`, `ExtraMiddle` |
| `mismatchedEnvironment` | Unclosed `\begin` or mismatched `\begin`/`\end` pair | `EnvBadEnd`, `EnvMissingEnd`, `MissingBeginExtraEnd` |
| `doubleScript` | Ambiguous consecutive superscripts, subscripts, or primes | `DoubleExponent`, `DoubleSubscripts`, `DoubleExponentPrime` |
| `missingArgument` | Missing mandatory macro or `\verb` delimiter argument | `MissingArgFor`, `NoClosingDelim` |
| `invalidMacroDefinition` | Malformed `\def`, `\newcommand`, or parameter template | `MissingCS`, `MissingReplacementString`, `IllegalParamNumber` |
| `unknownEnvironment` | Reference to an unregistered environment name | `UnknownEnv` |
| `budgetExceeded` | Runaway macro recursion or buffer limit exceeded | `MaxMacroSub1`, `MaxMacroSub2`, `MaxBufferSize` |
| `syntaxError` | Disallowed `\require` or remaining TeX syntax failures | `BadRequire`, `InvalidOption`, other `TexError` IDs |

## Oracle Verification and Ad-Hoc SymPy Stress Testing

To inspect raw oracle output for a JSON batch on standard input, pipe entries into `node tool/oracle/render.mjs` (pass `--include-svg` when serialized SVG strings are needed, and `--allow-texhtml` only when testing `texhtml`, since dynamic imports are otherwise restricted to known TeX packages and font chunks). Full repository verification runs via `dart run tool/verify_against_mathjax.dart`, which validates `.tex` metadata against live MathJax output, `corpus/expectations.json`, and `TexMathEngine`.

Ad-hoc symbolic stress expressions can be generated locally with `python3 tool/generate_sympy_corpus.py` when `sympy` is installed. That generator writes temporary `.tex` files strictly into the gitignored `build/sympy_corpus/` directory and pipes them through the oracle so generated third-party output is never placed inside `corpus/` or committed to version control.
