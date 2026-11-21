import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math_flutter_example/main.dart';

void main() {
  testWidgets('Example app renders display list, inline span, and font info', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TexMathExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('tex_math_flutter Example'), findsOneWidget);
    expect(find.text(r'E = mc^2'), findsOneWidget);
    expect(
      find.textContaining('Bundled font: NewComputerModernMath'),
      findsOneWidget,
    );
  });
}
