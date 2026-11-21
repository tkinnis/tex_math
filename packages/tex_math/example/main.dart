import 'dart:io';

import 'package:tex_math/tex_math.dart';

/// Builds a sample [DisplayList] depicting `\frac{a+b}{c}` using vector
/// rules, glyph items, and an equation anchor, writes standalone SVG XML to
/// stdout or an optional output path argument, and exercises engine budget
/// error handling.
void main(List<String> args) {
  const DisplayList sample = DisplayList(
    source: r'\frac{a + b}{c}',
    metrics: DisplayMetrics(
      widthEm: 2.8,
      heightEm: 1.15,
      depthEm: 0.75,
      baselineEm: 1.15,
      unitsPerEm: 1000,
    ),
    items: <DisplayItem>[
      GlyphItem(
        glyphId: 1,
        codePoint: 0x0061,
        xEm: 0.2,
        yEm: 0.55,
        advanceEm: 0.55,
        span: SourceSpan(6, 7),
      ),
      GlyphItem(
        glyphId: 2,
        codePoint: 0x002B,
        xEm: 0.95,
        yEm: 0.55,
        advanceEm: 0.78,
        colorRole: TexMathColorRole.accent,
        span: SourceSpan(8, 9),
      ),
      GlyphItem(
        glyphId: 3,
        codePoint: 0x0062,
        xEm: 1.9,
        yEm: 0.55,
        advanceEm: 0.5,
        span: SourceSpan(10, 11),
      ),
      RuleItem(
        xEm: 0.1,
        yEm: 0.24,
        widthEm: 2.4,
        heightEm: 0.05,
        span: SourceSpan(0, 14),
      ),
      GlyphItem(
        glyphId: 4,
        codePoint: 0x0063,
        xEm: 1.05,
        yEm: -0.45,
        advanceEm: 0.45,
        span: SourceSpan(13, 14),
      ),
      AnchorItem(id: 'eq-sample', xEm: 2.7, yEm: 0.0, label: 'fraction'),
    ],
  );

  final String svg = sample.toSvg(
    fontSize: 24.0,
    title: 'Sample fraction display list',
  );

  if (args.isNotEmpty) {
    File(args.first).writeAsStringSync('$svg\n');
    stdout.writeln('Wrote ${svg.length} SVG characters to ${args.first}.');
  } else {
    stdout.writeln(svg);
  }

  const TexMathEngine engine = TexMathEngine(
    defaultOptions: TexMathOptions(budgets: TexMathBudgets(maxInputLength: 16)),
  );
  try {
    engine.render(r'\sum_{i=1}^{n} x_i^2');
  } on TexMathBudgetError catch (error) {
    stderr.writeln('Budget check enforced: $error');
  } on TexMathUnsupportedError catch (error) {
    stderr.writeln('Phase 1 engine boundary: $error');
  }
}
