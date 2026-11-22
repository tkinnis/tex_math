## 0.1.0

- Initial release of the pure-Dart five-stage TeX math engine (`TexMathEngine`), OpenType `MATH`/CFF/CFF2/`glyf` parser (`MathFont`), Appendix G layout engine, immutable AST and display-list models, SVG/MathML/spoken-text exporters, and safety budgets (`TexMathBudgets`).
- Configurable equation numbering via `TexMathTagMode` (`none`, `ams`, `all`), `TagNode.targetId` cross-reference targeting, and `TexMathOptions.multlineWidthEm`, `multline` / `multlined`, `\shoveleft`, and `\shoveright` layout support.
- Non-layout `AnchorItem` hitbox bounds (`widthEm`, `heightEm`, `depthEm`) and safe `href` handling (`AnchorItem.href`), SVG `<a>` link overlays, and `TexMathColorRole.accent` styling for `\href`, `\ref`, and `\eqref`.
- Structured `TexMathError` hierarchy with UTF-16 source spans, 1-based positions, and `formattedMessage` / `formatWithSource` diagnostics.
- Verified across 352 corpus expressions (315 rendered across 42 TeX/MathJax packages, 37 malformed inputs refused) against MathJax `4.1.3`.
