import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  const TexMathEngine engine = TexMathEngine();

  group('Presentation MathML exporter', () {
    test('emits display/inline root attributes and escapes XML entities', () {
      final String displayMml = engine.toMathMl(r'\frac{a < b}{c \& d}');
      expect(
        displayMml,
        startsWith(
          '<math xmlns="http://www.w3.org/1998/Math/MathML" display="block">',
        ),
      );
      expect(displayMml, contains('<mfrac>'));
      expect(displayMml, contains('&lt;'));
      expect(displayMml, contains('&amp;'));
      expect(displayMml, endsWith('</math>'));

      final String inlineMml = engine.toMathMl(
        r'x^2',
        options: const TexMathOptions(displayMode: TexMathDisplayMode.inline),
      );
      expect(inlineMml, contains('display="inline"'));
      expect(inlineMml, contains('<msup>'));
    });

    test('emits radicals, limits, prescripts, matrices, and colors', () {
      final String rootMml = engine.toMathMl(r'\sqrt[3]{x + 1}');
      expect(rootMml, contains('<mroot>'));

      final String sumMml = engine.toMathMl(r'\sum_{i=1}^{n} i^2');
      expect(sumMml, contains('<munderover>'));

      final String prescriptMml = engine.toMathMl(
        r'\prescript{14}{6}{\mathrm{C}}',
      );
      expect(prescriptMml, contains('<mmultiscripts>'));
      expect(prescriptMml, contains('<mprescripts/>'));

      final String matrixMml = engine.toMathMl(
        r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}',
      );
      expect(matrixMml, contains('<mtable>'));
      expect(matrixMml, contains('<mtr>'));
      expect(matrixMml, contains('<mtd>'));

      final String colorMml = engine.toMathMl(r'\textcolor{red}{x}');
      expect(colorMml, contains('mathcolor="#FF0000"'));
    });

    test('emits columnalign on <mtd> for multline, multline*, and multlined', () {
      final String multlineMml = engine.toMathMl(
        r'\begin{multline}\shoveleft{a + b} \\ c + d \\ \shoveright{e + f}\end{multline}',
      );
      expect(multlineMml, contains('<mtr><mtd columnalign="left">'));
      expect(
        multlineMml,
        contains(
          '<mtr><mtd><mrow><mi>c</mi><mo>+</mo><mi>d</mi></mrow></mtd></mtr>',
        ),
      );
      expect(multlineMml, contains('<mtr><mtd columnalign="right">'));

      final String multlineLabelMml = engine.toMathMl(
        r'\begin{multline*} a \\ \shoveleft{b}\label{eq:1} \\ c \end{multline*}',
      );
      expect(
        multlineLabelMml,
        contains('<mtr><mtd columnalign="left"><mi>a</mi></mtd></mtr>'),
      );
      expect(
        multlineLabelMml,
        contains(
          '<mtr><mtd columnalign="left"><mrow><mi>b</mi><mspace id="eq:1"/></mrow></mtd></mtr>',
        ),
      );
      expect(
        multlineLabelMml,
        contains('<mtr><mtd columnalign="right"><mi>c</mi></mtd></mtr>'),
      );

      final String multlinedMml = engine.toMathMl(
        r'\begin{multlined} x \\ y \end{multlined}',
      );
      expect(
        multlinedMml,
        contains('<mtr><mtd columnalign="left"><mi>x</mi></mtd></mtr>'),
      );
      expect(
        multlinedMml,
        contains('<mtr><mtd columnalign="right"><mi>y</mi></mtd></mtr>'),
      );
    });
  });

  group('Spoken-text accessibility exporter', () {
    test('generates readable natural language descriptions', () {
      expect(
        engine.toSpokenText(r'\frac{a + b}{c - d}'),
        'a plus b over c minus d',
      );
      expect(
        engine.toSpokenText(r'\sqrt{x^2 + y^2}'),
        'square root of x squared plus y squared',
      );
      expect(engine.toSpokenText(r'\sqrt[3]{a}'), 'cube root of a');
      expect(engine.toSpokenText(r'\binom{n}{k}'), 'n choose k');
      expect(
        engine.toSpokenText(r'\alpha + \beta = \infty'),
        'alpha plus beta equals infinity',
      );
      expect(
        engine.toSpokenText(r'\sum_{i=1}^{n} x_i'),
        'sum from i equals 1 to n x sub i',
      );
      expect(
        engine.toSpokenText(r'\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}'),
        '2 by 2 matrix row 1: 1, 0, row 2: 0, 1',
      );
    });
  });
}
