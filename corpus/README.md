# `tex_math` Verification Corpus

The `corpus/` directory holds hand-authored TeX expressions for verifying `tex_math` parsing, error rejection, bounding-box metrics, rule geometry, and glyph placement against the pinned MathJax `4.1.3` oracle (`tool/oracle/render.mjs`) using the `mathjax-newcm` font.

## Directory Layout and Tier Definitions

| Directory | Tier Key | Coverage Scope | Case Count |
| --- | --- | --- | --- |
| `corpus/tier1_core/` | `1` | Core `base`, `ams`, `newcommand`, `textmacros`, `tagformat`, and `configmacros` | 125 |
| `corpus/tier2_jupyter/` | `2` | Remaining JupyterLab default extensions (`action`, `amscd`, `bbox`, `boldsymbol`, `braket`, `bussproofs`, `cancel`, `cases`, `centernot`, `color`, `colortbl`, `empheq`, `enclose`, `extpfeil`, `gensymb`, `html`, `mathtools`, `mhchem`, `noerrors`, `noundefined`, `require`, `textcomp`, `unicode`, `upgreek`, `verb`) | 105 |
| `corpus/tier3_extended/` | `3` | Remaining MathJax `4.1.3` extensions (`autoload`, `bbm`, `bboldx`, `begingroup`, `colorv2`, `dsfont`, `fontsizev3`, `physics`, `setoptions`, `texhtml`, `units`) | 35 |
| `corpus/stretchy/` | `stretchy` | Tall nested `\left...\right`, `\middle`, `\big`–`\Bigg` delimiters, horizontal braces and brackets, wide accents, extensible arrows, and deep radicals | 25 |
| `corpus/notebooks/` | `notebooks` | Realistic physics, calculus, linear algebra, probability/ML, and chemistry (`\ce`, `\pu`) notebook expressions | 25 |
| `corpus/errors/` | `errors` | Deliberately invalid TeX verified to be refused by MathJax | 37 |

Generated reference expectations are stored separately in `corpus/expectations.json` by `tool/verify_against_mathjax.dart --update-expectations`.

## `.tex` Case File Format

Every `.tex` file begins with `%` metadata header lines followed by the raw TeX math-mode body (without outer `$...$` or `$$...$$` delimiters).

```tex
% id: tier1_core/base/fraction_basic
% tier: 1
% package: base
% feature: fractions
% display: display
% accepted: true
\frac{a + b}{c - d}
```

Required metadata headers are `% id:`, `% tier:`, `% package:`, `% feature:`, `% display:` (`display` or `inline`), and `% accepted:` (`true` or `false`). Cases expecting refusal include `% error_class: <class>`, and cases requiring non-default TeX extensions include a comma-separated `% packages: ...` header.

When `% packages:` is omitted, `tool/oracle/render.mjs` enables the 29 JupyterLab default TeX packages excluding `noerrors` and `noundefined`: `base`, `action`, `ams`, `amscd`, `bbox`, `boldsymbol`, `braket`, `bussproofs`, `cancel`, `cases`, `centernot`, `color`, `colortbl`, `empheq`, `enclose`, `extpfeil`, `gensymb`, `html`, `mathtools`, `mhchem`, `newcommand`, `upgreek`, `unicode`, `verb`, `configmacros`, `tagformat`, `textcomp`, `textmacros`, and `require`. Both `noerrors` and `noundefined` are excluded by default so malformed TeX and undefined macros are strictly rejected unless a case explicitly opts into them.

## Error Classes

Refused cases in `corpus/errors/` assert deterministic rejection across the 14 TeX error classes mapped from MathJax `TexError` exceptions (the remaining 2 of the 16 `TexMathErrorClass` values, `invalidFont` and `unsupportedFeature`, represent engine/font errors).

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

To inspect raw oracle output for a JSON batch on standard input, pipe items into `node tool/oracle/render.mjs` (passing `--include-svg` when serialized SVG strings are needed, and `--allow-texhtml` only when testing `texhtml`, as `render.mjs` disables `texhtml` and constrains dynamic imports to `[tex]/...` and `@mathjax/` font chunks by default). Full repository verification runs via `dart run tool/verify_against_mathjax.dart`, which validates `.tex` metadata against live `tool/oracle/render.mjs`, `corpus/expectations.json`, and `TexMathEngine`.

Ad-hoc symbolic stress expressions can be generated locally with `python3 tool/generate_sympy_corpus.py` when `sympy` is installed in the local Python environment. That generator writes temporary `.tex` files strictly into the gitignored `build/sympy_corpus/` directory and pipes them through `node tool/oracle/render.mjs`; generated third-party SymPy output is never placed inside `corpus/` or committed to version control.
