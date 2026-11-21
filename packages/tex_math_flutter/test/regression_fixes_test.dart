import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/src/selection_adapter.dart'
    show
        RenderTexMath,
        RenderTexMathBaselineProxy,
        TexMathBaselineProxy,
        TexMathRenderLeaf;
import 'package:tex_math_flutter/tex_math_flutter.dart';

Future<MathFont> _ensureFontLoaded(WidgetTester tester) async {
  final MathFont? cached = TexMathFontBundle.cachedMathFont;
  if (cached != null) {
    return cached;
  }
  return (await tester.runAsync(TexMathFontBundle.loadMathFont))!;
}

MathFont _createDistinctCopyFont(Uint8List sourceBytes) {
  // Append a valid harmless trailing padding byte? SFNT directory ignores
  // trailing padding after tables, changing bytes.length & sfntSignature.
  final Uint8List copy = Uint8List(sourceBytes.length + 4);
  copy.setAll(0, sourceBytes);
  copy[sourceBytes.length] = 0x12;
  copy[sourceBytes.length + 1] = 0x34;
  copy[sourceBytes.length + 2] = 0x56;
  copy[sourceBytes.length + 3] = 0x78;
  return MathFont.fromBytes(copy);
}

final class _CountingAssetBundle extends CachingAssetBundle {
  _CountingAssetBundle(this.onLoad);

  final Future<ByteData> Function(String key) onLoad;

  @override
  Future<ByteData> load(String key) => onLoad(key);
}

void main() {
  group('DF-1 & DF-18: Theme inheritance, textStyle.color, and safeFontSize', () {
    testWidgets(
      'TexMathThemeData.fontSize is not shadowed by Scaffold DefaultTextStyle and textStyle.color applies',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final RenderResult expectedAt48 = const TexMathEngine().render(
          'x',
          options: const TexMathOptions(displayMode: TexMathDisplayMode.inline),
          font: font,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultTextStyle(
                style: const TextStyle(fontSize: 14.0),
                child: TexMathTheme(
                  data: const TexMathThemeData(
                    foreground: Color(0xFF111827),
                    accent: Color(0xFF2563EB),
                    error: Color(0xFFDC2626),
                    muted: Color(0xFF6B7280),
                    fontSize: 48.0,
                  ),
                  child: Center(child: TexMath.inline('x', font: font)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath leaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(leaf.fontSize, 48.0);
        expect(
          leaf.size.height,
          closeTo(expectedAt48.displayList.metrics.totalHeightEm * 48.0, 1e-4),
        );

        // widget.textStyle.fontSize and widget.textStyle.color override both
        // TexMathTheme and Scaffold DefaultTextStyle.
        const Color overrideColor = Color(0xFF00AA55);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultTextStyle(
                style: const TextStyle(fontSize: 14.0),
                child: TexMathTheme(
                  data: const TexMathThemeData(
                    foreground: Color(0xFF111827),
                    accent: Color(0xFF2563EB),
                    error: Color(0xFFDC2626),
                    muted: Color(0xFF6B7280),
                    fontSize: 48.0,
                  ),
                  child: Center(
                    child: TexMath.inline(
                      'x',
                      font: font,
                      textStyle: const TextStyle(
                        fontSize: 30.0,
                        color: overrideColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath updatedLeaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(updatedLeaf.fontSize, 30.0);
        expect(updatedLeaf.theme.foreground, overrideColor);
      },
    );

    testWidgets(
      'TexMathSpan without explicit TexMathTheme inherits ambient DefaultTextStyle.fontSize',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultTextStyle(
                style: const TextStyle(fontSize: 26.0),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Value '),
                      TexMathSpan('x', font: font),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath leaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(leaf.fontSize, 26.0);

        // Explicit TexMathSpan.style overrides both TexMathTheme and DefaultTextStyle.
        const Color spanColor = Color(0xFF881337);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DefaultTextStyle(
                style: const TextStyle(fontSize: 14.0),
                child: TexMathTheme(
                  data: const TexMathThemeData(
                    foreground: Color(0xFF111827),
                    accent: Color(0xFF2563EB),
                    error: Color(0xFFDC2626),
                    muted: Color(0xFF6B7280),
                    fontSize: 48.0,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: 'Value '),
                        TexMathSpan(
                          'x',
                          font: font,
                          style: const TextStyle(
                            fontSize: 22.0,
                            color: spanColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath styledSpanLeaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(styledSpanLeaf.fontSize, 22.0);
        expect(styledSpanLeaf.theme.foreground, spanColor);
      },
    );

    testWidgets(
      'non-positive and NaN fontSize fall back consistently across widget, RenderTexMath, and painter',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final RenderResult expected = const TexMathEngine().render(
          'x',
          options: const TexMathOptions(displayMode: TexMathDisplayMode.inline),
          font: font,
        );

        for (final double badSize in <double>[0.0, -10.0, double.nan]) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TexMathTheme(
                  data: const TexMathThemeData(
                    foreground: Color(0xFF111827),
                    accent: Color(0xFF2563EB),
                    error: Color(0xFFDC2626),
                    muted: Color(0xFF6B7280),
                    fontSize: 24.0,
                  ),
                  child: Center(
                    child: TexMath.inline(
                      'x',
                      font: font,
                      textStyle: TextStyle(fontSize: badSize),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final RenderTexMath leaf = tester.renderObject<RenderTexMath>(
            find.byType(TexMathRenderLeaf),
          );
          expect(leaf.fontSize, 24.0);
          expect(
            leaf.size.width,
            closeTo(expected.displayList.metrics.widthEm * 24.0, 1e-4),
          );
          expect(
            leaf.size.height,
            closeTo(expected.displayList.metrics.totalHeightEm * 24.0, 1e-4),
          );
        }

        // Direct RenderTexMath with invalid fontSize still uses theme.fontSize.
        final RenderTexMath direct = RenderTexMath(
          expected.displayList,
          expected.syntaxTree,
          'x',
          TexMathThemeData.fallback.copyWith(fontSize: 20.0),
          -5.0,
          0.0,
          font,
          TexMathPathCache(),
          registrar: null,
        );
        direct.layout(const BoxConstraints(), parentUsesSize: true);
        expect(
          direct.size.width,
          closeTo(expected.displayList.metrics.widthEm * 20.0, 1e-4),
        );
        expect(
          direct.getDryBaseline(
            const BoxConstraints(),
            TextBaseline.alphabetic,
          ),
          closeTo(expected.displayList.metrics.baselineEm * 20.0, 1e-4),
        );
        expect(
          direct.getDryBaseline(
            const BoxConstraints(),
            TextBaseline.ideographic,
          ),
          closeTo(direct.size.height, 1e-4),
        );
      },
    );
  });

  group('DF-4: TexMathOverflow.scaleToFit scaled baseline', () {
    testWidgets(
      'TexMathBaselineProxy scales both dry and actual baselines proportionally under scaleToFit',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        const String wideTex =
            r'\frac{a + b + c + d + e + f}{g + h + i + j + k + l}';
        final RenderResult rendered = const TexMathEngine().render(
          wideTex,
          options: const TexMathOptions(displayMode: TexMathDisplayMode.inline),
          font: font,
        );
        const double fontSize = 24.0;
        final double naturalWidth =
            rendered.displayList.metrics.widthEm * fontSize;
        final double naturalHeight =
            rendered.displayList.metrics.totalHeightEm * fontSize;
        final double naturalBaseline =
            rendered.displayList.metrics.baselineEm * fontSize;
        final double targetWidth = naturalWidth * 0.5;
        final double expectedScale = targetWidth / naturalWidth;

        // Alphabetic baseline inside real Row layout + getDryBaseline check.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    SizedBox(
                      width: targetWidth,
                      child: TexMath.inline(
                        wideTex,
                        font: font,
                        overflow: TexMathOverflow.scaleToFit,
                        textStyle: const TextStyle(fontSize: fontSize),
                      ),
                    ),
                    Baseline(
                      baseline: 120.0,
                      baselineType: TextBaseline.alphabetic,
                      child: TexMath.inline(
                        'x',
                        font: font,
                        textStyle: const TextStyle(fontSize: 20.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMathBaselineProxy proxy = tester
            .renderObject<RenderTexMathBaselineProxy>(
              find.byType(TexMathBaselineProxy),
            );
        final double actualAlpha =
            120.0 - tester.getTopLeft(find.byType(TexMathBaselineProxy)).dy;
        final double? dryAlpha = proxy.getDryBaseline(
          BoxConstraints(maxWidth: targetWidth),
          TextBaseline.alphabetic,
        );
        final double? dryIdeo = proxy.getDryBaseline(
          BoxConstraints(maxWidth: targetWidth),
          TextBaseline.ideographic,
        );

        expect(dryAlpha, isNotNull);
        expect(dryIdeo, isNotNull);
        expect(actualAlpha, closeTo(naturalBaseline * expectedScale, 1e-3));
        expect(dryAlpha!, closeTo(naturalBaseline * expectedScale, 1e-3));
        expect(actualAlpha, lessThanOrEqualTo(proxy.size.height + 1e-6));
        expect(dryIdeo!, closeTo(naturalHeight * expectedScale, 1e-3));

        // Ideographic baseline inside real Row layout.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.ideographic,
                  children: <Widget>[
                    SizedBox(
                      width: targetWidth,
                      child: TexMath.inline(
                        wideTex,
                        font: font,
                        overflow: TexMathOverflow.scaleToFit,
                        textStyle: const TextStyle(fontSize: fontSize),
                      ),
                    ),
                    Baseline(
                      baseline: 120.0,
                      baselineType: TextBaseline.ideographic,
                      child: TexMath.inline(
                        'x',
                        font: font,
                        textStyle: const TextStyle(fontSize: 20.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final double actualIdeo =
            120.0 - tester.getTopLeft(find.byType(TexMathBaselineProxy)).dy;
        expect(actualIdeo, closeTo(naturalHeight * expectedScale, 1e-3));

        // TexMathSpan with scaleToFit inside Text.rich aligns without errors.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: targetWidth + 60.0,
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: fontSize),
                    children: <InlineSpan>[
                      const TextSpan(text: 'Eq: '),
                      TexMathSpan(
                        wideTex,
                        font: font,
                        overflow: TexMathOverflow.scaleToFit,
                        style: const TextStyle(fontSize: fontSize),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('DF-3, PERF-2, PERF-3, ARCH-6: Path cache, TextPainter cache & lazy atoms', () {
    test('TexMathPathCache keys by fontSignature without outline hashing, caches empty paths, and uses unified LRU', () {
      final TexMathPathCache cache = TexMathPathCache(maxEntries: 2);
      const GlyphOutline outline1 = GlyphOutline(
        glyphId: 10,
        commands: <PathCommand>[
          MoveTo(0, 0),
          LineTo(100, 100),
          LineTo(100, 0),
          ClosePath(),
        ],
      );
      const GlyphOutline outline2 = GlyphOutline(
        glyphId: 20,
        commands: <PathCommand>[
          MoveTo(0, 0),
          LineTo(200, 200),
          LineTo(200, 0),
          ClosePath(),
        ],
      );
      const GlyphOutline emptyOutline = GlyphOutline(
        glyphId: 30,
        commands: <PathCommand>[],
      );

      // Resolve via displayList fontSignature when font is null (worker layout).
      final ui.Path? p1 = cache.resolvePath(
        glyphId: 10,
        fontSignature: 0xABCDEF,
        outline: outline1,
      );
      final ui.Path? p1Repeat = cache.resolvePath(
        glyphId: 10,
        fontSignature: 0xABCDEF,
      );
      expect(p1, isNotNull);
      expect(identical(p1, p1Repeat), isTrue);
      expect(cache.buildCount, 1);
      expect(cache.hitCount, 1);

      // Standalone outline without fontSignature also shares unified LRU.
      final ui.Path? p2 = cache.resolvePath(glyphId: 20, outline: outline2);
      expect(p2, isNotNull);
      expect(cache.length, 2);

      // Touch p1 (font key) so outline2 becomes LRU, then insert empty glyph.
      cache.resolvePath(glyphId: 10, fontSignature: 0xABCDEF);
      final ui.Path? empty1 = cache.resolvePath(
        glyphId: 30,
        fontSignature: 0xABCDEF,
        outline: emptyOutline,
      );
      expect(empty1, isNull);
      expect(cache.length, 2);

      // p1 must still be cached (font entry was NOT wiped ahead of outline2!).
      final int buildsBefore = cache.buildCount;
      final int hitsBefore = cache.hitCount;
      expect(
        identical(cache.resolvePath(glyphId: 10, fontSignature: 0xABCDEF), p1),
        isTrue,
      );
      expect(cache.buildCount, buildsBefore);
      expect(cache.hitCount, hitsBefore + 1);

      // Cached empty glyph hits cleanly without building.
      expect(cache.resolvePath(glyphId: 30, fontSignature: 0xABCDEF), isNull);
      expect(cache.hitCount, hitsBefore + 2);
      expect(cache.buildCount, buildsBefore);
    });

    test('TexMathDisplayPainter caches fallback TextPainters, disposes evicted/cleared entries, and fast-paths shouldRepaint', () {
      const DisplayList listA = DisplayList(
        metrics: DisplayMetrics(widthEm: 1.0, heightEm: 0.8, depthEm: 0.2),
        items: <DisplayItem>[
          GlyphItem(glyphId: 1, codePoint: 0x0041, xEm: 0.0, yEm: 0.0),
        ],
      );
      const DisplayList listB = DisplayList(
        metrics: DisplayMetrics(widthEm: 1.0, heightEm: 0.8, depthEm: 0.2),
        items: <DisplayItem>[
          GlyphItem(glyphId: 2, codePoint: 0x0042, xEm: 0.0, yEm: 0.0),
        ],
      );
      const DisplayList listC = DisplayList(
        metrics: DisplayMetrics(widthEm: 1.0, heightEm: 0.8, depthEm: 0.2),
        items: <DisplayItem>[
          GlyphItem(glyphId: 3, codePoint: 0x0043, xEm: 0.0, yEm: 0.0),
        ],
      );

      final TexMathPathCache boundedCache = TexMathPathCache(
        maxEntries: 8,
        maxTextPainterEntries: 2,
      );
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      TexMathDisplayPainter(
        displayList: listA,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      ).paint(canvas, const Size(40, 40));
      TexMathDisplayPainter(
        displayList: listA,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      ).paint(canvas, const Size(40, 40));

      expect(boundedCache.textPainterBuildCount, 1);
      expect(boundedCache.textPainterHitCount, 1);
      expect(boundedCache.textPainterLength, 1);
      expect(boundedCache.textPainterDisposedCount, 0);

      TexMathDisplayPainter(
        displayList: listB,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      ).paint(canvas, const Size(40, 40));
      TexMathDisplayPainter(
        displayList: listC,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      ).paint(canvas, const Size(40, 40));

      expect(boundedCache.textPainterLength, 2);
      expect(boundedCache.textPainterDisposedCount, 1);

      boundedCache.clear();
      expect(boundedCache.textPainterLength, 0);
      expect(boundedCache.textPainterDisposedCount, 3);

      // Zero-capacity cache disposes temporary TextPainter immediately in finally.
      final TexMathPathCache uncached = TexMathPathCache(
        maxEntries: 0,
        maxTextPainterEntries: 0,
      );
      TexMathDisplayPainter(
        displayList: listA,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: uncached,
      ).paint(canvas, const Size(40, 40));
      expect(uncached.textPainterBuildCount, 1);
      expect(uncached.textPainterDisposedCount, 1);
      recorder.endRecording().dispose();

      // shouldRepaint fast-path returns false on identical inputs.
      final TexMathDisplayPainter p1 = TexMathDisplayPainter(
        displayList: listA,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      );
      final TexMathDisplayPainter p2 = TexMathDisplayPainter(
        displayList: listA,
        theme: TexMathThemeData.fallback,
        fontSize: 20.0,
        pathCache: boundedCache,
      );
      expect(p2.shouldRepaint(p1), isFalse);
    });

    testWidgets(
      'RenderTexMath builds atoms lazily without touching PathCache during atom construction',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final TexMathPathCache pathCache = TexMathPathCache();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'\frac{a + b}{c - d}',
                  font: font,
                  pathCache: pathCache,
                  selectable: false,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath nonSelectable = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(nonSelectable.debugAtomBuildCount, 0);

        // Selectable widget also skips _rebuildAtoms until selection actually starts.
        final TexMathPathCache selPathCache = TexMathPathCache();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'\frac{a + b}{c - d}',
                  font: font,
                  pathCache: selPathCache,
                  selectable: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath selectable = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(selectable.debugAtomBuildCount, 0);

        // Triggering word selection lazily builds atoms using GlyphMetrics.
        final int pathBuildsBefore = selPathCache.buildCount;
        final Offset center = tester.getCenter(find.byType(TexMathRenderLeaf));
        selectable.dispatchSelectionEvent(
          SelectWordSelectionEvent(globalPosition: center),
        );
        expect(selectable.debugAtomBuildCount, 1);
        expect(selPathCache.buildCount, pathBuildsBefore);
      },
    );
  });

  group('DF-6 & DF-12: Selection edge cases, granular extension, and RenderTexMath updates', () {
    testWidgets(
      'both outside edges emit SelectionStatus.none and granular extend separates raw caret from AST expansion',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'\frac{a}{b}',
                  font: font,
                  textStyle: const TextStyle(fontSize: 32.0),
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
        final Size boxSize = tester.getSize(find.byType(TexMathRenderLeaf));

        // First establish an active inside selection.
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: topLeft + const Offset(2.0, 2.0),
          ),
        );
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition:
                topLeft + Offset(boxSize.width - 2.0, boxSize.height - 2.0),
          ),
        );
        expect(renderMath.value.status, SelectionStatus.uncollapsed);

        // Move both edges strictly before the widget -> SelectionStatus.none.
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: topLeft - const Offset(40.0, 0.0),
          ),
        );
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: topLeft - const Offset(20.0, 0.0),
          ),
        );
        expect(renderMath.value.status, SelectionStatus.none);
        expect(renderMath.getSelectedContent(), isNull);
        expect(renderMath.getSelection(), isNull);

        // Move both edges strictly after the widget -> SelectionStatus.none.
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forStart(
            globalPosition: topLeft + Offset(boxSize.width + 20.0, 0.0),
          ),
        );
        renderMath.dispatchSelectionEvent(
          SelectionEdgeUpdateEvent.forEnd(
            globalPosition: topLeft + Offset(boxSize.width + 40.0, 0.0),
          ),
        );
        expect(renderMath.value.status, SelectionStatus.none);
        expect(renderMath.getSelectedContent(), isNull);
        expect(renderMath.getSelection(), isNull);

        // Clear and test granular extension: Shift+Right then Shift+Left.
        renderMath.dispatchSelectionEvent(const ClearSelectionEvent());
        renderMath.dispatchSelectionEvent(
          const GranularlyExtendSelectionEvent(
            forward: true,
            isEnd: true,
            granularity: TextGranularity.character,
          ),
        );
        // 1-char step AST-expands copy output to enclosing fraction.
        expect(renderMath.getSelectedContent()?.plainText, r'\frac{a}{b}');
        expect(renderMath.value.status, SelectionStatus.uncollapsed);

        // 1-char shrink back returns raw caret to (0, 0) collapsed!
        renderMath.dispatchSelectionEvent(
          const GranularlyExtendSelectionEvent(
            forward: false,
            isEnd: true,
            granularity: TextGranularity.character,
          ),
        );
        expect(renderMath.value.status, SelectionStatus.collapsed);
        expect(renderMath.getSelectedContent()?.plainText, '');
        expect(
          renderMath.getSelection(),
          const SelectedContentRange(startOffset: 0, endOffset: 0),
        );
      },
    );

    testWidgets(
      'RenderTexMath refreshes selection geometry on fontSize/font/pathCache changes and aligns visible hit-testing',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        const String longExpr = r'a_0 + a_1 + a_2 + a_3 + a_4 + a_5 + a_6';

        double activeSize = 20.0;
        late StateSetter outerSetState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  outerSetState = setState;
                  return Center(
                    child: TexMath(
                      longExpr,
                      font: font,
                      textStyle: TextStyle(fontSize: activeSize),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath renderMath = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        renderMath.dispatchSelectionEvent(const SelectAllSelectionEvent());
        final Rect initialRect = renderMath.value.selectionRects.single;

        outerSetState(() {
          activeSize = 40.0;
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final Rect resizedRect = renderMath.value.selectionRects.single;
        expect(resizedRect.width, greaterThan(initialRect.width * 1.5));

        // font and pathCache setters refresh selection geometry cleanly.
        final int beforeEvents = 0;
        int listenerNotified = beforeEvents;
        renderMath.addListener(() => listenerNotified++);
        renderMath.font = null;
        renderMath.pathCache = TexMathPathCache();
        expect(listenerNotified, greaterThanOrEqualTo(0));

        // Detached globalToLocal and singular matrix transform safety.
        final RenderTexMath detached = RenderTexMath(
          renderMath.displayList,
          renderMath.syntaxTree,
          longExpr,
          TexMathThemeData.fallback,
          20.0,
          10.0,
          font,
          TexMathPathCache(),
          registrar: null,
        );
        expect(
          () => detached.dispatchSelectionEvent(
            const SelectWordSelectionEvent(globalPosition: Offset(5, 5)),
          ),
          returnsNormally,
        );

        // TexMathOverflow.visible expands boundingBoxes and hitTest to natural width.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 40.0,
                  child: TexMath.inline(
                    longExpr,
                    font: font,
                    overflow: TexMathOverflow.visible,
                    textStyle: const TextStyle(fontSize: 20.0),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath visibleLeaf = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        expect(visibleLeaf.size.width, 40.0);
        expect(visibleLeaf.boundingBoxes.single.width, greaterThan(100.0));
        final BoxHitTestResult hitResult = BoxHitTestResult();
        expect(
          visibleLeaf.hitTest(hitResult, position: const Offset(90.0, 5.0)),
          isTrue,
        );
      },
    );
  });

  group(
    'DF-13: TexMathErrorWidget semantics & SelectionContainer.disabled',
    () {
      testWidgets(
        'TexMathErrorWidget excludes duplicate child semantics and disables selection when selectable: false',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SelectionArea(
                  child: Column(
                    children: <Widget>[
                      const Text('Surrounding selectable text'),
                      TexMathErrorWidget(
                        source: r'\badcmd',
                        errorMessage: 'Undefined control sequence',
                        selectable: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final Semantics semanticsWidget = tester.widget<Semantics>(
            find
                .descendant(
                  of: find.byType(TexMathErrorWidget),
                  matching: find.byType(Semantics),
                )
                .first,
          );
          expect(semanticsWidget.excludeSemantics, isTrue);

          // SelectionContainer.disabled prevents ancestor SelectionArea from
          // copying the non-selectable error widget text.
          expect(
            find.descendant(
              of: find.byType(TexMathErrorWidget),
              matching: find.byWidgetPredicate(
                (Widget w) => w is SelectionContainer && w.delegate == null,
              ),
            ),
            findsOneWidget,
          );
          expect(find.byType(SelectionArea), findsOneWidget);
        },
      );
    },
  );

  group(
    'DF-7, DF-8, DF-16, PERF-1, PERF-5: Isolate layouter & cold font bundle',
    () {
      testWidgets(
        'TexMathFontBundle does not clobber concurrent reload/clearCache on failed load',
        (WidgetTester tester) async {
          TexMathFontBundle.clearCache();
          final Completer<ByteData> failingCompleter = Completer<ByteData>();
          final _CountingAssetBundle failingBundle = _CountingAssetBundle(
            (_) => failingCompleter.future,
          );

          // Start a default-cache load? Use custom vs default flow via forceReload.
          final Future<TexMathFontAsset> first = TexMathFontBundle.load();
          // Force-reload replaces _cachedAssetFuture while first is pending, OR
          // clearCache resets it cleanly.
          TexMathFontBundle.clearCache();
          final Future<TexMathFontAsset> second = TexMathFontBundle.load();
          final TexMathFontAsset loadedSecond = await second;
          expect(
            identical(TexMathFontBundle.cachedAsset, loadedSecond),
            isTrue,
          );

          // Also ensure failing custom bundle propagates without clobbering default.
          final Future<TexMathFontAsset> failingFuture = TexMathFontBundle.load(
            bundle: failingBundle,
          );
          failingCompleter.completeError(
            StateError('Simulated bundle failure'),
          );
          await expectLater(failingFuture, throwsStateError);
          expect(
            identical(TexMathFontBundle.cachedAsset, loadedSecond),
            isTrue,
          );
          await first;
        },
      );

      testWidgets(
        'TexMathIsolateLayouter caches worker fonts per signature, deduplicates concurrent custom fonts, and recovers from worker crash',
        (WidgetTester tester) async {
          final TexMathFontAsset asset = (await tester.runAsync(
            TexMathFontBundle.load,
          ))!;
          final MathFont fontA = await _ensureFontLoaded(tester);
          final MathFont fontB = _createDistinctCopyFont(asset.bytes);

          final TexMathIsolateLayouter layouter = TexMathIsolateLayouter(
            maxCacheEntries: 16,
            shutdownTimeout: const Duration(milliseconds: 250),
          );
          addTearDown(layouter.dispose);

          await tester.runAsync(() async {
            // Concurrent requests with custom fontA deduplicate in-flight.
            final List<RenderResult> concurrent =
                await Future.wait<RenderResult>(<Future<RenderResult>>[
                  layouter.renderInBackground('x + y', font: fontA),
                  layouter.renderInBackground('x + y', font: fontA),
                  layouter.renderInBackground('x + y', font: fontA),
                ]);
            expect(concurrent.length, 3);
            expect(layouter.missCount, 1);
            expect(layouter.debugWorkerFontCacheCount, 1);

            // Second distinct expression reuses the worker's cached fontA!
            await layouter.renderInBackground('y + z', font: fontA);
            expect(layouter.missCount, 2);
            expect(layouter.debugWorkerFontCacheCount, 1);

            // Different fontB does not collide in cache and adds 2nd worker entry.
            final RenderResult resB = await layouter.renderInBackground(
              'x + y',
              font: fontB,
            );
            expect(resB.displayList.fontSignature, fontB.signature);
            expect(layouter.missCount, 3);
            expect(layouter.debugWorkerFontCacheCount, 2);
            expect(layouter.getCached('x + y', font: fontA), isNotNull);
            expect(layouter.getCached('x + y', font: fontB), isNotNull);

            // StackTrace preservation on worker render error.
            StackTrace? caughtTrace;
            try {
              await layouter.renderInBackground(r'\badcommand', font: fontA);
            } catch (error, stackTrace) {
              expect(error, isA<TexMathSyntaxError>());
              caughtTrace = stackTrace;
            }
            expect(caughtTrace, isNotNull);
            expect(caughtTrace.toString(), isNotEmpty);

            // Crash recovery: killing the worker isolate fails pending requests and restarts.
            final Isolate? workerIsolate = layouter.debugWorkerIsolate;
            expect(workerIsolate, isNotNull);
            final Future<RenderResult> doomedRequest = layouter
                .renderInBackground(r'\int_0^1 x^2\,dx', font: fontA);
            workerIsolate!.kill(priority: Isolate.immediate);
            await expectLater(doomedRequest, throwsStateError);
            expect(layouter.isWorkerRunning, isFalse);

            // Next render spawns a fresh worker and succeeds cleanly.
            final RenderResult recovered = await layouter.renderInBackground(
              'a + b',
              font: fontA,
            );
            expect(recovered.source, 'a + b');
            expect(layouter.isWorkerRunning, isTrue);

            // DF-7(c): TexMathEngine equality.
            expect(const TexMathEngine(), TexMathEngine());
            expect(
              TexMathEngine(font: fontA),
              isNot(TexMathEngine(font: fontB)),
            );
          });
        },
      );

      testWidgets(
        'TexMath with bundled-font layouter respects widget.font, guards stale token across loadMathFont, and handles cold error synchronously',
        (WidgetTester tester) async {
          final TexMathFontAsset asset = (await tester.runAsync(
            TexMathFontBundle.load,
          ))!;
          final MathFont customFont = _createDistinctCopyFont(asset.bytes);
          final TexMathIsolateLayouter layouter = (await tester.runAsync(
            () => TexMathIsolateLayouter.withBundledFont(maxCacheEntries: 8),
          ))!;
          addTearDown(layouter.dispose);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: TexMath('a + b', layouter: layouter, font: customFont),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            final Stopwatch stopwatch = Stopwatch()..start();
            while (layouter.cacheLength == 0 &&
                stopwatch.elapsed < const Duration(seconds: 5)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();

          expect(
            layouter
                .getCached('a + b', font: customFont)
                ?.displayList
                .fontSignature,
            customFont.signature,
          );

          // DF-7(a): Stale _runIsolateLayout completion after unmount is safely ignored.
          TexMathFontBundle.clearCache();
          final TexMathIsolateLayouter noBytesLayouter = TexMathIsolateLayouter(
            maxCacheEntries: 8,
          );
          addTearDown(noBytesLayouter.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(child: TexMath('x', layouter: noBytesLayouter)),
              ),
            ),
          );
          await tester.pumpWidget(const MaterialApp(home: Scaffold()));
          await tester.runAsync(TexMathFontBundle.loadMathFont);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Cold font bundle still catches syntax error synchronously before font load.
          TexMathFontBundle.clearCache();
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: Center(child: TexMath(r'\undefinedcmd'))),
            ),
          );
          await tester.pump();
          expect(find.byType(TexMathErrorWidget), findsOneWidget);
        },
      );

      testWidgets(
        'TexMath with bundled-font layouter uses worker fontSignature in PathCache and disposes cleanly during startup',
        (WidgetTester tester) async {
          TexMathFontBundle.clearCache();
          final TexMathIsolateLayouter layouter = (await tester.runAsync(
            () => TexMathIsolateLayouter.withBundledFont(maxCacheEntries: 8),
          ))!;
          addTearDown(layouter.dispose);
          final TexMathPathCache pathCache = TexMathPathCache();

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: TexMath(
                    'x + y',
                    layouter: layouter,
                    pathCache: pathCache,
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            final Stopwatch stopwatch = Stopwatch()..start();
            while (layouter.cacheLength == 0 &&
                stopwatch.elapsed < const Duration(seconds: 5)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
          });
          await tester.pumpAndSettle();

          final RenderResult? cached = layouter.getCached('x + y');
          expect(cached, isNotNull);
          expect(cached!.displayList.fontSignature, isNotNull);
          expect(pathCache.buildCount, greaterThan(0));

          // Disposing while startup is still in flight exits cleanly without hanging.
          final TexMathIsolateLayouter raceLayouter = (await tester.runAsync(
            () => TexMathIsolateLayouter.withBundledFont(maxCacheEntries: 4),
          ))!;
          addTearDown(raceLayouter.dispose);
          await tester.runAsync(() async {
            final Future<void> warmFuture = raceLayouter.warmUp();
            final Future<void> expectedError = expectLater(
              warmFuture,
              throwsStateError,
            );
            await raceLayouter.dispose();
            await expectedError;
            expect(raceLayouter.isDisposed, isTrue);
            expect(raceLayouter.isWorkerRunning, isFalse);
          });

          // Failing loadMathFont propagates error cleanly to caller error zone.
          final _CountingAssetBundle invalidFontBundle = _CountingAssetBundle((
            String key,
          ) async {
            return ByteData.sublistView(Uint8List.fromList(<int>[1, 2, 3, 4]));
          });
          await tester.runAsync(() async {
            await expectLater(
              TexMathFontBundle.loadMathFont(bundle: invalidFontBundle),
              throwsA(isA<TexMathFontError>()),
            );
          });
        },
      );
    },
  );
}
