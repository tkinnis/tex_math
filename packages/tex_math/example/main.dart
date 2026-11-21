import 'dart:io';

import 'package:tex_math/tex_math.dart';

/// Demonstrates rendering TeX math into a vector [DisplayList] and standalone
/// SVG XML with OpenType `MATH` layout when `NewCMMath-Regular.otf` is present.
void main() {
  const String source = r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}';
  final File? fontFile = _locateBundledFont();

  if (fontFile != null) {
    final MathFont font = MathFont.fromBytes(fontFile.readAsBytesSync());
    final TexMathEngine engine = TexMathEngine(font: font);
    final RenderResult result = engine.render(source);
    final String svg = result.toSvg(fontSize: 20, title: source);
    stdout.writeln(
      'Rendered ${result.displayList.items.length} items '
      '(${result.displayList.metrics.widthEm.toStringAsFixed(3)}em wide, '
      '${svg.length} SVG bytes).',
    );
    stdout.writeln('MathML: ${result.toMathMl()}');
    stdout.writeln('Spoken: ${result.toSpokenText()}');
    stdout.writeln(svg);
  } else {
    final MathNode tree = parseTex(source);
    stdout.writeln('Parsed AST: ${tree.runtimeType}');
    stdout.writeln('MathML: ${mathNodeToMathMl(tree)}');
    stdout.writeln('Spoken: ${mathNodeToSpokenText(tree)}');
  }

  // Budget enforcement example.
  const TexMathEngine boundedEngine = TexMathEngine(
    defaultOptions: TexMathOptions(budgets: TexMathBudgets(maxInputLength: 16)),
  );
  try {
    boundedEngine.parse(r'\sum_{i=1}^{n} x_i^2 + y_i^2');
  } on TexMathBudgetError catch (err) {
    stdout.writeln('Budget error (${err.budgetName}): ${err.message}');
  }
}

File? _locateBundledFont() {
  const List<String> candidates = <String>[
    '../tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
    'packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
  ];
  for (final String path in candidates) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return null;
}
