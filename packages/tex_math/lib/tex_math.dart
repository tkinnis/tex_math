/// Pure-Dart TeX math-mode parser, layout engine, and SVG/MathML/spoken-text
/// renderer aligned to MathJax TeX input.
library;

export 'src/ast.dart';
export 'src/display_list.dart';
export 'src/engine.dart';
export 'src/error.dart';
export 'src/export/mathml.dart';
export 'src/export/spoken_text.dart';
export 'src/font.dart';
export 'src/options.dart';
export 'src/parser/package_registry.dart'
    show TexPackageDescriptor, TexPackageRegistry, TexPackageTier;
export 'src/parser/symbol_map.dart'
    show TexSymbolSpec, mathUnicodeCodePoint, resolveTexColor;
export 'src/parser/tokenizer.dart'
    show TexCatCode, TexToken, TexTokenKind, tokenizeTex;
export 'src/source_span.dart';
