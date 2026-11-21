import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';
import 'package:tex_math_flutter_example/main.dart';

void main() {
  testWidgets(
    'Example app renders showcase, toggles theme without re-layout, and loads notebook',
    (WidgetTester tester) async {
      await tester.pumpWidget(const TexMathExampleApp());
      await tester.pumpAndSettle();

      expect(find.text('tex_math_flutter Example'), findsOneWidget);
      expect(
        find.text('Display Equations (Cached OpenType MATH Paths)'),
        findsOneWidget,
      );

      final Finder showcaseScrollable = find.descendant(
        of: find.byKey(const Key('showcase-list')),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );

      await tester.scrollUntilVisible(
        find.byType(TexMathErrorWidget),
        200.0,
        scrollable: showcaseScrollable,
      );
      expect(find.byType(TexMathErrorWidget), findsOneWidget);
      expect(find.text(r'\undefinedcmd + \frac{1}{2}'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.textContaining('Bundled font: NewComputerModernMath'),
        200.0,
        scrollable: showcaseScrollable,
      );
      expect(
        find.textContaining('Bundled font: NewComputerModernMath'),
        findsOneWidget,
      );
      expect(find.textContaining('Quadratic layout runs: 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('theme-toggle-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Quadratic layout runs: 1'), findsOneWidget);

      await tester.tap(find.text('Notebook (50)'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();

      expect(
        find.text('50 Notebook Equations (Persistent Isolate)'),
        findsOneWidget,
      );
      expect(find.text('[1]'), findsOneWidget);
      expect(find.byType(TexMath), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    },
  );
}
