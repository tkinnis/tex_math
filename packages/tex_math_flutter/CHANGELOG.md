## 0.1.1

- Scoped `package:flutter/material.dart` imports in `error_widget.dart`, `tex_math_widget.dart`, and `theme.dart` to `package:flutter/widgets.dart` plus targeted `show` clauses with deprecation ignores for Flutter 3.50+ analyzer compatibility while preserving Flutter 3.32–3.47+ `package:flutter/material.dart` type compatibility.
- Removed the unused `package:flutter/material.dart` import from `selection_adapter.dart` and updated its doc comment reference.
- Added live pub.dev version badges, `flutter pub add` install commands, and pub.dev package and API reference links across the repository README, package README, and API manual.

## 0.1.0

- Initial release of `TexMath` and `TexMathSpan` widgets with `TexMathTheme` / Material `ColorScheme` inheritance, bundled `NewCMMath-Regular.otf` (`8.1.1`) font asset loading (`TexMathFontBundle`), unified `(fontSignature, glyphId)` `TexMathPathCache` (including synthetic `glyphId == 0` stroke isolation), `TexMathOverflow` baseline-preserving policies, `SelectionArea` AST copy-as-LaTeX support, spoken-text `Semantics`, and `TexMathErrorWidget` span/position diagnostics.
- Interactive `\href` link tap callbacks (`onLinkTap` on `TexMath` and `TexMathSpan`) with hover pointer cursor feedback while preserving `SelectionArea` drag selection, plus re-exported `TexMathTagMode` and `AnchorItem`.
- Persistent worker-isolate layout and off-thread font decoding (`TexMathIsolateLayouter` and `TexMathFontBundle`) on native platforms with seamless conditional-import Web/Wasm fallbacks across all 6 Flutter platforms.
