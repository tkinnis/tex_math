# tex_math

Pure-Dart TeX math-mode parser, OpenType `MATH` layout engine, and standalone SVG, MathML, and spoken-text renderer aligned to MathJax TeX input.

## Features

`tex_math` provides a zero-Flutter, zero-`dart:io` pure-Dart math rendering core built around typed Dart 3 sealed AST nodes (`MathNode`), structured error categories (`TexMathError` / `TexMathErrorClass`), resource safety limits (`TexMathBudgets`), an immutable flat `DisplayList` model with standalone XML SVG serialization (`DisplayList.toSvg()`), and the `TexMathEngine` pipeline entry points (`parse`, `layout`, `render`, `renderToSvg`, `toMathMl`, `toSpokenText`).

## Phase 1 Status

Phase 1 establishes the public API contract, safety budgets, AST hierarchy, display list primitives, and standalone SVG serializer, while full TeX parsing, macro expansion, OpenType `MATH` layout, MathML emission, and spoken-text generation throw `TexMathUnsupportedError` after budget checks.

## Usage

```dart
import 'package:tex_math/tex_math.dart';

void main() {
  const DisplayList displayList = DisplayList(
    metrics: DisplayMetrics(
      widthEm: 2.0,
      heightEm: 1.0,
      depthEm: 0.5,
    ),
    items: <DisplayItem>[
      RuleItem(xEm: 0.0, yEm: 0.25, widthEm: 2.0, heightEm: 0.05),
      GlyphItem(glyphId: 1, codePoint: 0x0078, xEm: 0.7, yEm: 0.5),
    ],
  );
  final String svg = displayList.toSvg(fontSize: 20);
}
```

## Example

Run the standalone CLI example from `packages/tex_math` with `dart run example/main.dart`.
