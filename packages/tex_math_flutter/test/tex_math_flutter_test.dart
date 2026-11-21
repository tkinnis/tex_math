import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

void main() {
  group('TexMathFontBundle', () {
    setUp(TexMathFontBundle.clearCache);

    testWidgets(
      'loads NewCMMath-Regular.otf and GUST license once from assets',
      (WidgetTester tester) async {
        final TexMathFontAsset first = await TexMathFontBundle.load();
        final TexMathFontAsset second = await TexMathFontBundle.load();

        expect(identical(first, second), isTrue);
        expect(first.hasOttoHeader, isTrue);
        expect(first.byteLength, greaterThan(1000000));
        expect(first.familyName, 'NewComputerModernMath');
        expect(first.licenseText, contains('GUST Font License'));
        final MathFont decoded = first.decodeMathFont();
        expect(decoded.familyName, 'NewComputerModernMath');
        expect(decoded.unitsPerEm, 1000);
        expect(decoded.numGlyphs, greaterThan(8000));
      },
    );
  });

  group('TexMathTheme and widgets', () {
    testWidgets('TexMath shows monospace error fallback in Phase 1', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TexMathTheme(
              data: TexMathThemeData.fallback,
              child: Center(child: TexMath(r'\frac{a + b}{c - d}')),
            ),
          ),
        ),
      );

      expect(find.byType(TexMathErrorWidget), findsOneWidget);
      expect(find.text(r'\frac{a + b}{c - d}'), findsOneWidget);
      expect(find.textContaining('MathFont'), findsOneWidget);

      final Text sourceText = tester.widget<Text>(
        find.text(r'\frac{a + b}{c - d}'),
      );
      expect(sourceText.style?.fontFamily, 'monospace');
    });

    testWidgets('TexMathSpan embeds inline math inside Text.rich', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  const TextSpan(text: 'Inline: '),
                  TexMathSpan(r'E = mc^2'),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TexMath), findsOneWidget);
      expect(find.byType(TexMathErrorWidget), findsOneWidget);
      expect(find.text(r'E = mc^2'), findsOneWidget);
    });

    testWidgets('TexMath.displayList renders themed rules and path glyphs', (
      WidgetTester tester,
    ) async {
      const DisplayList list = DisplayList(
        source: r'\frac{\Delta}{x}',
        metrics: DisplayMetrics(
          widthEm: 2.2,
          heightEm: 1.2,
          depthEm: 0.9,
          unitsPerEm: 1000,
        ),
        items: <DisplayItem>[
          GlyphItem(
            glyphId: 1,
            codePoint: 0x0394,
            xEm: 0.65,
            yEm: 0.42,
            outline: GlyphOutline(
              glyphId: 1,
              commands: <PathCommand>[
                MoveTo(0, 0),
                LineTo(450, 750),
                LineTo(900, 0),
                ClosePath(),
              ],
            ),
          ),
          RuleItem(
            xEm: 0.15,
            yEm: 0.22,
            widthEm: 1.9,
            heightEm: 0.08,
            colorRole: TexMathColorRole.accent,
          ),
          GlyphItem(
            glyphId: 2,
            codePoint: 0x25A1,
            xEm: 0.72,
            yEm: -0.68,
            colorRole: TexMathColorRole.custom,
            customColor: 0xFF0F766E,
            outline: GlyphOutline(
              glyphId: 2,
              commands: <PathCommand>[
                MoveTo(0, 0),
                LineTo(760, 0),
                LineTo(760, 560),
                LineTo(0, 560),
                ClosePath(),
              ],
            ),
          ),
          AnchorItem(id: 'golden-anchor', xEm: 2.1, yEm: 0.0),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: const Key('golden-target'),
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                      width: 2.0,
                    ),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: const TexMathTheme(
                    data: TexMathThemeData(
                      foreground: Color(0xFF0F172A),
                      accent: Color(0xFF2563EB),
                      error: Color(0xFFDC2626),
                      muted: Color(0xFF64748B),
                      fontSize: 48.0,
                    ),
                    child: TexMath.displayList(
                      list,
                      semanticsLabel: 'Vector fraction display list',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel('Vector fraction display list'),
        findsOneWidget,
      );
      await expectLater(
        find.byKey(const Key('golden-target')),
        matchesGoldenFile('goldens/tex_math_display_list.png'),
      );
    });
  });

  group('TexMathIsolateLayouter', () {
    test('propagates errors from isolate and manages cache entries', () async {
      final TexMathIsolateLayouter layouter = TexMathIsolateLayouter(
        maxCacheEntries: 2,
      );

      await expectLater(
        layouter.renderInBackground(r'\frac{a}{b}'),
        throwsA(isA<TexMathFontError>()),
      );

      const RenderResult stubResult = RenderResult(
        displayList: DisplayList(
          metrics: DisplayMetrics(widthEm: 1.0, heightEm: 0.8, depthEm: 0.2),
          items: <DisplayItem>[],
        ),
        syntaxTree: MathRootNode(
          span: SourceSpan(0, 1),
          children: <MathNode>[],
        ),
        source: 'x',
      );
      layouter.putCached('x', stubResult);
      expect(layouter.cacheLength, 1);
      expect(layouter.getCached('x'), stubResult);

      layouter.putCached('y', stubResult);
      layouter.putCached('z', stubResult);
      expect(layouter.cacheLength, 2);
      expect(layouter.getCached('x'), isNull);
    });
  });
}
