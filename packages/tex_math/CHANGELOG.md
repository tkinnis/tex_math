## 0.1.0

- Initial release of the pure-Dart five-stage TeX math engine (`TexMathEngine`), OpenType `MATH`/CFF/CFF2/`glyf` parser (`MathFont`), Appendix G layout engine, immutable AST and display-list models, SVG/MathML/spoken-text exporters, and safety budgets (`TexMathBudgets`).
- Structured `TexMathError` hierarchy with UTF-16 source spans, 1-based positions, and `formattedMessage` / `formatWithSource` diagnostics.
- Verified across 352 corpus expressions (315 rendered across 42 TeX/MathJax packages, 37 malformed inputs refused) against MathJax `4.1.3`.
