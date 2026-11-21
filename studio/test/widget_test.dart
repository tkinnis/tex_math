import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';
import 'package:tex_math_studio/main.dart';

void main() {
  testWidgets('Studio renders three comparison panes and updates TeX source', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TexMathStudioApp());

    expect(find.text('tex_math Comparison Studio'), findsOneWidget);
    expect(find.text('tex_math (Pure Dart)'), findsOneWidget);
    expect(find.text('MathJax 4.1.3 Oracle'), findsOneWidget);
    expect(find.text('KaTeX 0.19.1 Comparison'), findsOneWidget);
    expect(find.byType(TexMathErrorWidget), findsOneWidget);

    await tester.enterText(find.byType(TextField), r'\alpha + \beta');
    await tester.pump();

    expect(find.text(r'\alpha + \beta'), findsWidgets);
  });
}
