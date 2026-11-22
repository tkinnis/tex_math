import 'dart:io';

import 'package:tex_math/tex_math.dart';

/// Demonstrates rendering TeX math into a vector [DisplayList] and standalone
/// SVG XML with OpenType `MATH` layout when an OpenType math font (such as
/// `NewCMMath-Regular.otf`) is supplied, or fontless AST/MathML/spoken-text
/// export otherwise.
void main(List<String> args) {
  const String source = r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}';
  final File? fontFile = _resolveFontFile(args);

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
    stdout.writeln(
      'Pass an OpenType MATH font path, e.g.: '
      'dart run example/main.dart path/to/NewCMMath-Regular.otf',
    );
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

File? _resolveFontFile(List<String> args) {
  if (args.isNotEmpty) {
    final File explicit = File(args.first);
    if (!explicit.existsSync()) {
      stderr.writeln('Font file not found: ${args.first}');
      exitCode = 2;
      return null;
    }
    return explicit;
  }
  const List<String> candidates = <String>[
    'NewCMMath-Regular.otf',
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
