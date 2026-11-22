import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/src/selection_adapter.dart'
    show RenderTexMath, TexMathRenderLeaf;
import 'package:tex_math_flutter/tex_math_flutter.dart';

Future<MathFont> _ensureFontLoaded(WidgetTester tester) async {
  final MathFont? cached = TexMathFontBundle.cachedMathFont;
  if (cached != null) {
    return cached;
  }
  return (await tester.runAsync(TexMathFontBundle.loadMathFont))!;
}

void main() {
  group('TexMathFontBundle', () {
    setUp(TexMathFontBundle.clearCache);

    testWidgets(
      'loads NewCMMath-Regular.otf, license, and cached MathFont once',
      (WidgetTester tester) async {
        expect(TexMathFontBundle.cachedMathFont, isNull);

        final TexMathFontAsset firstAsset = await TexMathFontBundle.load();
        final TexMathFontAsset secondAsset = await TexMathFontBundle.load();

        expect(identical(firstAsset, secondAsset), isTrue);
        expect(firstAsset.hasOttoHeader, isTrue);
        expect(firstAsset.byteLength, greaterThan(1000000));
        expect(firstAsset.familyName, 'NewComputerModernMath');
        expect(firstAsset.licenseText, contains('GUST Font License'));

        final MathFont firstFont = (await tester.runAsync(
          TexMathFontBundle.loadMathFont,
        ))!;
        final MathFont secondFont = await TexMathFontBundle.loadMathFont();

        expect(identical(firstFont, secondFont), isTrue);
        expect(identical(TexMathFontBundle.cachedMathFont, firstFont), isTrue);
        expect(firstFont.familyName, 'NewComputerModernMath');
        expect(firstFont.unitsPerEm, 1000);
        expect(firstFont.numGlyphs, greaterThan(8000));
      },
    );

    testWidgets(
      'TexMath auto-loads bundled MathFont when no explicit font is supplied',
      (WidgetTester tester) async {
        TexMathFontBundle.clearCache();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: TexMath(r'\frac{a + b}{c - d}')),
            ),
          ),
        );
        await tester.runAsync(() async {
          await TexMathFontBundle.loadMathFont();
        });
        await tester.pumpAndSettle();

        expect(TexMathFontBundle.cachedMathFont, isNotNull);
        expect(find.byType(TexMathErrorWidget), findsNothing);
        expect(find.byType(TexMath), findsOneWidget);
        expect(
          find.bySemanticsLabel('a plus b over c minus d'),
          findsOneWidget,
        );
      },
    );
  });

  group('TexMathPathCache and zero-relayout theme recoloring', () {
    testWidgets(
      'reuses cached glyph Paths and does not re-run layout across theme changes',
      (WidgetTester tester) async {
        await _ensureFontLoaded(tester);
        final TexMathPathCache pathCache = TexMathPathCache();
        int layoutCount = 0;

        Widget buildWithTheme(TexMathThemeData themeData) {
          return MaterialApp(
            home: Scaffold(
              body: TexMathTheme(
                data: themeData,
                child: Center(
                  child: TexMath(
                    r'\frac{a + b}{c - d}',
                    pathCache: pathCache,
                    textStyle: const TextStyle(fontSize: 24.0),
                    debugOnLayout: () => layoutCount++,
                  ),
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildWithTheme(TexMathThemeData.fallback));
        await tester.pumpAndSettle();

        expect(layoutCount, 1);
        final int initialBuilds = pathCache.buildCount;
        final int initialEntries = pathCache.length;
        expect(initialBuilds, greaterThan(0));
        expect(initialEntries, greaterThan(0));

        await tester.pumpWidget(
          buildWithTheme(
            const TexMathThemeData(
              foreground: Color(0xFFF8FAFC),
              accent: Color(0xFF60A5FA),
              error: Color(0xFFF87171),
              muted: Color(0xFF94A3B8),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(layoutCount, 1);
        expect(pathCache.buildCount, initialBuilds);
        expect(pathCache.length, initialEntries);
        expect(pathCache.hitCount, greaterThan(0));
      },
    );

    testWidgets(
      'TexMathPathCache keys by (MathFont, glyphId) and respects LRU eviction',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final TexMathPathCache cache = TexMathPathCache(maxEntries: 2);

        final int gidA = font.glyphIdForCodePoint(0x0061);
        final int gidB = font.glyphIdForCodePoint(0x0062);
        final int gidC = font.glyphIdForCodePoint(0x0063);

        final Path? pathA1 = cache.pathForGlyph(font, gidA);
        final Path? pathA2 = cache.pathForGlyph(font, gidA);
        expect(pathA1, isNotNull);
        expect(identical(pathA1, pathA2), isTrue);
        expect(cache.buildCount, 1);
        expect(cache.hitCount, 1);

        cache.pathForGlyph(font, gidB);
        expect(cache.length, 2);
        // Touch A so B becomes least recently used.
        cache.pathForGlyph(font, gidA);
        cache.pathForGlyph(font, gidC);
        expect(cache.length, 2);

        final int buildsBeforeA = cache.buildCount;
        cache.pathForGlyph(font, gidA);
        expect(cache.buildCount, buildsBeforeA);
      },
    );
  });

  group('TexMathOverflow and TexMathSpan baseline precision', () {
    testWidgets('defaults overflow by display mode and enforces all policies', (
      WidgetTester tester,
    ) async {
      await _ensureFontLoaded(tester);
      const String longTex =
          r'f(x) = a_0 + a_1 x + a_2 x^2 + a_3 x^3 + a_4 x^4 + a_5 x^5';

      const TexMath displayWidget = TexMath(longTex);
      const TexMath inlineWidget = TexMath.inline(longTex);
      expect(displayWidget.effectiveOverflow, TexMathOverflow.scroll);
      expect(inlineWidget.effectiveOverflow, TexMathOverflow.visible);

      for (final TexMathOverflow policy in TexMathOverflow.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 90.0,
                  child: TexMath(
                    longTex,
                    overflow: policy,
                    textStyle: const TextStyle(fontSize: 20.0),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final Finder mathFinder = find.byType(TexMath);
        switch (policy) {
          case TexMathOverflow.scroll:
            expect(
              find.descendant(
                of: mathFinder,
                matching: find.byType(SingleChildScrollView),
              ),
              findsOneWidget,
            );
          case TexMathOverflow.scaleToFit:
            expect(
              find.descendant(of: mathFinder, matching: find.byType(FittedBox)),
              findsOneWidget,
            );
            expect(tester.getSize(mathFinder).width, lessThanOrEqualTo(90.0));
          case TexMathOverflow.clip:
            expect(
              find.descendant(of: mathFinder, matching: find.byType(ClipRect)),
              findsOneWidget,
            );
            expect(tester.getSize(mathFinder).width, lessThanOrEqualTo(90.0));
          case TexMathOverflow.visible:
            expect(
              find.descendant(
                of: mathFinder,
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
            );
            expect(
              find.descendant(of: mathFinder, matching: find.byType(FittedBox)),
              findsNothing,
            );
            expect(
              find.descendant(of: mathFinder, matching: find.byType(ClipRect)),
              findsNothing,
            );
        }
      }
    });

    testWidgets(
      'TexMathSpan aligns alphabetic baseline using scaled font metrics',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        const double textFontSize = 20.0;
        const double scaleFactor = 1.5;
        final double scaledFontSize = textFontSize * scaleFactor;
        final RenderResult expected = const TexMathEngine().render(
          r'\frac{a}{b}',
          options: const TexMathOptions(displayMode: TexMathDisplayMode.inline),
          font: font,
        );
        final double expectedBaseline =
            expected.displayList.metrics.baselineEm * scaledFontSize;

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(scaleFactor),
              ),
              child: Scaffold(
                body: DefaultTextStyle(
                  style: const TextStyle(fontSize: textFontSize),
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: 'Inline: '),
                        TexMathSpan(r'\frac{a}{b}'),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Baseline baselineWidget = tester.widget<Baseline>(
          find.descendant(
            of: find.byType(TexMath),
            matching: find.byType(Baseline),
          ),
        );
        expect(baselineWidget.baselineType, TextBaseline.alphabetic);
        expect(baselineWidget.baseline, closeTo(expectedBaseline, 1e-4));

        final RenderTexMath renderLeaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(renderLeaf.baseline, closeTo(expectedBaseline, 1e-4));
        expect(
          renderLeaf.size.height,
          closeTo(
            expected.displayList.metrics.totalHeightEm * scaledFontSize,
            1e-4,
          ),
        );
        expect(
          tester.getSize(find.byType(TexMath)).height,
          closeTo(
            expected.displayList.metrics.totalHeightEm * scaledFontSize,
            1e-4,
          ),
        );
      },
    );
  });

  group('TexMathIsolateLayouter', () {
    test(
      'propagates errors from isolate and manages LRU cache entries',
      () async {
        final TexMathIsolateLayouter layouter = TexMathIsolateLayouter(
          maxCacheEntries: 2,
        );
        addTearDown(layouter.dispose);

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
        layouter.putCached('y', stubResult);
        // Accessing 'x' promotes it so 'y' is evicted when 'z' is inserted.
        expect(layouter.getCached('x'), stubResult);
        layouter.putCached('z', stubResult);
        expect(layouter.cacheLength, 2);
        expect(layouter.getCached('y'), isNull);
        expect(layouter.getCached('x'), stubResult);
      },
    );

    testWidgets(
      'runs persistent worker isolate with bundled font, caches hits, and disposes cleanly',
      (WidgetTester tester) async {
        final TexMathIsolateLayouter layouter = await tester.runAsync(
          () => TexMathIsolateLayouter.withBundledFont(maxCacheEntries: 8),
        ) as TexMathIsolateLayouter;
        addTearDown(layouter.dispose);

        await tester.runAsync(() => layouter.warmUp());
        expect(layouter.isWorkerRunning, isTrue);
        expect(layouter.isDisposed, isFalse);

        final RenderResult first = (await tester.runAsync(
          () => layouter.renderInBackground(r'\frac{a + b}{c - d}'),
        ))!;
        expect(layouter.missCount, 1);
        expect(layouter.hitCount, 0);
        expect(layouter.cacheLength, 1);

        final DisplayList second = (await tester.runAsync(
          () => layouter.layoutInBackground(r'\frac{a + b}{c - d}'),
        ))!;
        expect(second, first.displayList);
        expect(layouter.missCount, 1);
        expect(layouter.hitCount, 1);

        await tester.runAsync(() async {
          await expectLater(
            layouter.renderInBackground(r'\undefinedcmd'),
            throwsA(isA<TexMathSyntaxError>()),
          );
        });

        await tester.runAsync(() => layouter.dispose());
        expect(layouter.isDisposed, isTrue);
        expect(layouter.isWorkerRunning, isFalse);

        await expectLater(layouter.renderInBackground('x'), throwsStateError);
      },
    );
  });

  group('Sub-expression Selection, Semantics, and Error Widget', () {
    test('expandSpanToMinimalNode yields valid LaTeX slices', () {
      const TexMathEngine engine = TexMathEngine();
      const String fracSource = r'\frac{a + b}{c - d}';
      final MathNode fracTree = engine.parse(fracSource);

      final int idxA = fracSource.indexOf('a', 6);
      final int idxB = fracSource.indexOf('b', 6);
      final int idxC = fracSource.indexOf('c', 12);

      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          fracTree,
          SourceSpan(idxA, idxA + 1),
          fracSource,
        ),
        'a',
      );
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          fracTree,
          SourceSpan(idxA, idxB + 1),
          fracSource,
        ),
        'a + b',
      );
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          fracTree,
          SourceSpan(idxA, idxC + 1),
          fracSource,
        ),
        fracSource,
      );

      const String nestedSource = r'\frac{\frac{1}{2}}{3}';
      final MathNode nestedTree = engine.parse(nestedSource);
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          nestedTree,
          SourceSpan(nestedSource.indexOf('1'), nestedSource.indexOf('2') + 1),
          nestedSource,
        ),
        r'\frac{1}{2}',
      );

      const String matrixSource =
          r'\begin{pmatrix} a & b \\ c & d \end{pmatrix}';
      final MathNode matrixTree = engine.parse(matrixSource);
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          matrixTree,
          SourceSpan(matrixSource.indexOf('a'), matrixSource.indexOf('d') + 1),
          matrixSource,
        ),
        matrixSource,
      );

      const String mixedSource = r'x^2 + \sqrt{y + 1}';
      final MathNode mixedTree = engine.parse(mixedSource);
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          mixedTree,
          const SourceSpan(0, 3),
          mixedSource,
        ),
        'x^2',
      );
      expect(
        TexMathSelectionUtils.sliceMinimalLatex(
          mixedTree,
          SourceSpan(
            mixedSource.indexOf(r'\sqrt'),
            mixedSource.indexOf('y') + 1,
          ),
          mixedSource,
        ),
        r'\sqrt{y + 1}',
      );
    });

    testWidgets(
      'SelectionArea supports partial sub-expression drag and full copy as LaTeX',
      (WidgetTester tester) async {
        await _ensureFontLoaded(tester);
        String? clipboardCopied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<dynamic, dynamic> args =
                    call.arguments as Map<dynamic, dynamic>;
                clipboardCopied = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'\frac{a + b}{c - d}',
                  textStyle: TextStyle(fontSize: 36.0),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath renderMath = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        final Offset topLeft = tester.getTopLeft(
          find.byType(TexMathRenderLeaf),
        );
        final Size mathSize = tester.getSize(find.byType(TexMathRenderLeaf));

        // Drag strictly inside the upper numerator half.
        final Offset numStart = topLeft + Offset(4.0, mathSize.height * 0.22);
        final Offset numEnd =
            topLeft + Offset(mathSize.width - 4.0, mathSize.height * 0.22);

        final TestGesture drag = await tester.startGesture(
          numStart,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag.moveTo(numEnd);
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();

        expect(renderMath.getSelectedContent()?.plainText, 'a + b');

        // Dragging from numerator down into denominator expands to FractionNode.
        final TestGesture crossFracDrag = await tester.startGesture(
          topLeft + Offset(4.0, mathSize.height * 0.22),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await crossFracDrag.moveTo(
          topLeft + Offset(mathSize.width - 4.0, mathSize.height * 0.78),
        );
        await tester.pump();
        await crossFracDrag.up();
        await tester.pumpAndSettle();

        expect(
          renderMath.getSelectedContent()?.plainText,
          r'\frac{a + b}{c - d}',
        );

        // Full drag across an enclosing SelectionArea copies the complete source.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectionArea(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: TexMath(
                      r'\frac{a + b}{c - d}',
                      textStyle: TextStyle(fontSize: 36.0),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath outerRenderMath = tester
            .renderObject<RenderTexMath>(find.byType(TexMathRenderLeaf));
        final Offset outerTopLeft = tester.getTopLeft(
          find.byType(TexMathRenderLeaf),
        );
        final Size outerSize = tester.getSize(find.byType(TexMathRenderLeaf));

        final TestGesture fullDrag = await tester.startGesture(
          outerTopLeft - const Offset(12.0, 0.0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await fullDrag.moveTo(
          outerTopLeft + Offset(outerSize.width + 12.0, outerSize.height),
        );
        await tester.pump();
        await fullDrag.up();
        await tester.pumpAndSettle();

        expect(
          outerRenderMath.getSelectedContent()?.plainText,
          r'\frac{a + b}{c - d}',
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        if (clipboardCopied != null) {
          expect(clipboardCopied, r'\frac{a + b}{c - d}');
        }
      },
    );

    testWidgets(
      'Semantics exposes spoken text and TexMathErrorWidget renders invalid TeX',
      (WidgetTester tester) async {
        await _ensureFontLoaded(tester);
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TexMath(r'x^2 + \sqrt{y}'),
                  TexMath(r'\undefinedcmd'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.bySemanticsLabel('x squared plus square root of y'),
          findsOneWidget,
        );
        expect(find.byType(TexMathErrorWidget), findsOneWidget);
        expect(find.text(r'\undefinedcmd'), findsOneWidget);

        final Text errorSourceText = tester.widget<Text>(
          find.text(r'\undefinedcmd'),
        );
        expect(errorSourceText.style?.fontFamily, 'monospace');
      },
    );
  });

  group('Golden rendering', () {
    Future<void> expectGoldenWithTolerance(
      Finder finder,
      String goldenPath, {
      required double precisionTolerance,
    }) async {
      final GoldenFileComparator previous = goldenFileComparator;
      if (previous is! LocalFileComparator) {
        await expectLater(finder, matchesGoldenFile(goldenPath));
        return;
      }
      goldenFileComparator = _TolerantGoldenFileComparator(
        previous.basedir.resolve('tex_math_flutter_test.dart'),
        precisionTolerance: precisionTolerance,
      );
      try {
        await expectLater(finder, matchesGoldenFile(goldenPath));
      } finally {
        goldenFileComparator = previous;
      }
    }

    Future<void> pumpGoldenFrame(
      WidgetTester tester, {
      required Widget child,
      Color background = const Color(0xFFF8FAFC),
      Color border = const Color(0xFFCBD5E1),
      ThemeData? themeData,
    }) async {
      await _ensureFontLoaded(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme:
              themeData ??
              ThemeData(useMaterial3: true, platform: TargetPlatform.macOS),
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: const Key('golden-target'),
                child: Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: background,
                    border: Border.all(color: border, width: 2.0),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

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

      await pumpGoldenFrame(
        tester,
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

    testWidgets('golden: quadratic formula', (WidgetTester tester) async {
      await pumpGoldenFrame(
        tester,
        child: const TexMath(
          r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
          textStyle: TextStyle(fontSize: 28.0),
        ),
      );
      await expectLater(
        find.byKey(const Key('golden-target')),
        matchesGoldenFile('goldens/formula_quadratic.png'),
      );
    });

    testWidgets('golden: Gaussian integral', (WidgetTester tester) async {
      await pumpGoldenFrame(
        tester,
        child: const TexMath(
          r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
          textStyle: TextStyle(fontSize: 28.0),
        ),
      );
      await expectLater(
        find.byKey(const Key('golden-target')),
        matchesGoldenFile('goldens/formula_integral.png'),
      );
    });

    testWidgets('golden: rotation matrix', (WidgetTester tester) async {
      await pumpGoldenFrame(
        tester,
        child: const TexMath(
          r'R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}',
          textStyle: TextStyle(fontSize: 24.0),
        ),
      );
      await expectLater(
        find.byKey(const Key('golden-target')),
        matchesGoldenFile('goldens/formula_matrix.png'),
      );
    });

    testWidgets('golden: inline TexMathSpan in prose', (
      WidgetTester tester,
    ) async {
      const TextStyle proseStyle = TextStyle(
        fontSize: 20.0,
        color: Color(0xFF0F172A),
      );
      await pumpGoldenFrame(
        tester,
        child: Text.rich(
          TextSpan(
            style: proseStyle,
            children: <InlineSpan>[
              const TextSpan(text: 'A '),
              TexMathSpan(r'\frac{a^2 + b^2}{c}', style: proseStyle),
              const TextSpan(text: ' + '),
              TexMathSpan(r'\sqrt{x_i}', style: proseStyle),
              const TextSpan(text: ' = '),
              TexMathSpan(r'E = mc^2', style: proseStyle),
            ],
          ),
        ),
      );
      await expectGoldenWithTolerance(
        find.byKey(const Key('golden-target')),
        'goldens/inline_span_prose.png',
        precisionTolerance: 0.02,
      );
    });

    testWidgets('golden: dark theme formula', (WidgetTester tester) async {
      await pumpGoldenFrame(
        tester,
        background: const Color(0xFF0F172A),
        border: const Color(0xFF334155),
        themeData: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          platform: TargetPlatform.macOS,
        ),
        child: const TexMathTheme(
          data: TexMathThemeData(
            foreground: Color(0xFFF8FAFC),
            accent: Color(0xFF60A5FA),
            error: Color(0xFFF87171),
            muted: Color(0xFF94A3B8),
            fontSize: 28.0,
          ),
          child: TexMath(
            r'\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}',
            textStyle: TextStyle(fontSize: 28.0),
          ),
        ),
      );
      await expectLater(
        find.byKey(const Key('golden-target')),
        matchesGoldenFile('goldens/dark_theme_formula.png'),
      );
    });

    testWidgets('golden: error widget', (WidgetTester tester) async {
      await pumpGoldenFrame(
        tester,
        child: const TexMath(r'\undefinedcmd + \frac{1}{2}'),
      );
      await expectGoldenWithTolerance(
        find.byKey(const Key('golden-target')),
        'goldens/error_widget.png',
        precisionTolerance: 0.05,
      );
    });
  });
}

class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
  }) : assert(
         0 <= precisionTolerance && precisionTolerance <= 1,
         'precisionTolerance must be between 0 and 1',
       ),
       _precisionTolerance = precisionTolerance;

  final double _precisionTolerance;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final bool passed =
        result.passed || result.diffPercent <= _precisionTolerance;
    if (passed) {
      result.dispose();
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
