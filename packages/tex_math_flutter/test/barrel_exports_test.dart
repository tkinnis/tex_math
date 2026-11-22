import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

void main() {
  test(
    'tex_math_flutter barrel exposes core tex_math types used in public APIs',
    () {
      const TexMathBudgets budgets = TexMathBudgets();
      const TexMathOptions options = TexMathOptions(
        displayMode: TexMathDisplayMode.inline,
        budgets: budgets,
      );
      const TexMathEngine engine = TexMathEngine(defaultOptions: options);
      const MathFont stubFont = MathFont.stub();
      const DisplayList list = DisplayList(
        metrics: DisplayMetrics(widthEm: 1.0, heightEm: 1.0, depthEm: 0.0),
        items: <DisplayItem>[],
      );
      const RenderResult result = RenderResult(
        displayList: list,
        syntaxTree: MathRootNode(
          span: SourceSpan(0, 1),
          children: <MathNode>[],
        ),
        source: 'x',
      );
      const AnchorItem anchor = AnchorItem(
        id: 'href:https://example.org',
        xEm: 0.0,
        yEm: 0.0,
        widthEm: 1.0,
        heightEm: 0.7,
        depthEm: 0.1,
        label: 'https://example.org',
      );
      const TexMathSyntaxError error = TexMathSyntaxError(
        'syntax error',
        errorClass: TexMathErrorClass.undefinedControlSequence,
      );

      expect(engine, const TexMathEngine(defaultOptions: options));
      expect(stubFont.familyName, 'NewComputerModernMath');
      expect(result.displayList, list);
      expect(anchor.href, 'https://example.org');
      expect(TexMathTagMode.ams, isNotNull);
      expect(error.errorClass, TexMathErrorClass.undefinedControlSequence);
      expect(TexMathColorRole.foreground, isNotNull);
    },
  );
}
