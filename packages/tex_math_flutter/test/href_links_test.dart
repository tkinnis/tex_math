import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

Rect _anchorGlobalRect(RenderTexMath renderMath, AnchorItem anchor) {
  final DisplayMetrics metrics = renderMath.displayList.metrics;
  final double fontSize = renderMath.fontSize;
  final Rect localRect = Rect.fromLTWH(
    anchor.xEm * fontSize,
    (metrics.baselineEm - (anchor.yEm + anchor.heightEm)) * fontSize,
    anchor.widthEm * fontSize,
    (anchor.heightEm + anchor.depthEm) * fontSize,
  );
  return MatrixUtils.transformRect(renderMath.getTransformTo(null), localRect);
}

Future<({ByteData rgba, int width, int height})> _captureBoundaryRgba(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  final RenderRepaintBoundary boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
  try {
    final ByteData? rgba = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    expect(rgba, isNotNull);
    return (rgba: rgba!, width: image.width, height: image.height);
  } finally {
    image.dispose();
  }
}

int _countMatchingPixels(
  ByteData rgba,
  int width,
  int height,
  bool Function(int r, int g, int b, int a) predicate,
) {
  int count = 0;
  for (int i = 0; i < width * height; i++) {
    final int offset = i * 4;
    final int r = rgba.getUint8(offset);
    final int g = rgba.getUint8(offset + 1);
    final int b = rgba.getUint8(offset + 2);
    final int a = rgba.getUint8(offset + 3);
    if (predicate(r, g, b, a)) {
      count++;
    }
  }
  return count;
}

void main() {
  group(r'\href clickable links and accent theming', () {
    testWidgets(
      r'\href{https://example.org}{E = mc^2} paints in theme.accent and inner \color overrides it',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        const Color accentBlue = Color(0xFF0044FF);
        const Color darkFg = Color(0xFF111827);
        final GlobalKey plainKey = GlobalKey();
        final GlobalKey overrideKey = GlobalKey();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              backgroundColor: Colors.white,
              body: TexMathTheme(
                data: const TexMathThemeData(
                  foreground: darkFg,
                  accent: accentBlue,
                  error: Color(0xFFDC2626),
                  muted: Color(0xFF6B7280),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    RepaintBoundary(
                      key: plainKey,
                      child: ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TexMath(
                            r'\href{https://example.org}{E = mc^2}',
                            font: font,
                            textStyle: const TextStyle(fontSize: 36.0),
                          ),
                        ),
                      ),
                    ),
                    RepaintBoundary(
                      key: overrideKey,
                      child: ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TexMath(
                            r'\href{https://example.org}{E + {\color{red} R}}',
                            font: font,
                            textStyle: const TextStyle(fontSize: 36.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final ({ByteData rgba, int width, int height}) plainPixels =
            (await tester.runAsync(
              () => _captureBoundaryRgba(tester, plainKey),
            ))!;
        final int plainBlueCount = _countMatchingPixels(
          plainPixels.rgba,
          plainPixels.width,
          plainPixels.height,
          (int r, int g, int b, int a) =>
              a > 200 && b > 180 && b > r + 100 && b > g + 80,
        );
        final int plainDarkCount = _countMatchingPixels(
          plainPixels.rgba,
          plainPixels.width,
          plainPixels.height,
          (int r, int g, int b, int a) => a > 200 && r < 60 && g < 60 && b < 60,
        );
        expect(plainBlueCount, greaterThan(40));
        expect(plainDarkCount, 0);

        final ({ByteData rgba, int width, int height}) overridePixels =
            (await tester.runAsync(
              () => _captureBoundaryRgba(tester, overrideKey),
            ))!;
        final int overrideBlueCount = _countMatchingPixels(
          overridePixels.rgba,
          overridePixels.width,
          overridePixels.height,
          (int r, int g, int b, int a) =>
              a > 200 && b > 180 && b > r + 100 && b > g + 80,
        );
        final int overrideRedCount = _countMatchingPixels(
          overridePixels.rgba,
          overridePixels.width,
          overridePixels.height,
          (int r, int g, int b, int a) =>
              a > 200 && r > 180 && r > g + 100 && r > b + 100,
        );
        expect(overrideBlueCount, greaterThan(20));
        expect(overrideRedCount, greaterThan(20));
      },
    );

    testWidgets(
      r'tapping inside \href hitbox invokes onLinkTap, outside does not, and drag past kTouchSlop cancels',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final List<String> tapped = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'x + \href{https://example.org}{E = mc^2} + y',
                  font: font,
                  textStyle: const TextStyle(fontSize: 32.0),
                  onLinkTap: tapped.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath renderMath = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        final AnchorItem hrefAnchor = renderMath.displayList.items
            .whereType<AnchorItem>()
            .singleWhere((AnchorItem item) => item.href != null);
        final Rect linkGlobalRect = _anchorGlobalRect(renderMath, hrefAnchor);
        final Rect fullBoxRect = MatrixUtils.transformRect(
          renderMath.getTransformTo(null),
          Offset.zero & renderMath.size,
        );

        // Tap outside the \href hitbox (near leading 'x') -> no callback.
        final Offset outsideLinkPos = Offset(
          fullBoxRect.left + 4.0,
          linkGlobalRect.center.dy,
        );
        expect(linkGlobalRect.contains(outsideLinkPos), isFalse);
        await tester.tapAt(outsideLinkPos);
        await tester.pumpAndSettle();
        expect(tapped, isEmpty);

        // Tap inside the \href hitbox -> invokes onLinkTap('https://example.org').
        await tester.tapAt(linkGlobalRect.center);
        await tester.pumpAndSettle();
        expect(tapped, <String>['https://example.org']);

        // Secondary mouse button tap inside hitbox -> ignored.
        final TestGesture rightClick = await tester.startGesture(
          linkGlobalRect.center,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await tester.pump();
        await rightClick.up();
        await tester.pumpAndSettle();
        expect(tapped, <String>['https://example.org']);

        // Drag starting inside hitbox past kTouchSlop -> canceled, does not fire.
        final Offset dragStart = Offset(
          linkGlobalRect.left + 4.0,
          linkGlobalRect.center.dy,
        );
        final Offset dragEnd = Offset(
          dragStart.dx + kTouchSlop + 8.0,
          dragStart.dy,
        );
        expect(linkGlobalRect.contains(dragEnd), isTrue);
        final TestGesture drag = await tester.startGesture(
          dragStart,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag.moveTo(dragEnd);
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();
        expect(tapped, <String>['https://example.org']);

        // Non-selectable TexMath also delivers link taps.
        final List<String> nonSelectableTapped = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'\href{https://example.org}{E = mc^2}',
                  font: font,
                  selectable: false,
                  textStyle: const TextStyle(fontSize: 32.0),
                  onLinkTap: nonSelectableTapped.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath nonSelectableRender = tester
            .renderObject<RenderTexMath>(find.byType(TexMathRenderLeaf));
        final AnchorItem nsAnchor = nonSelectableRender.displayList.items
            .whereType<AnchorItem>()
            .singleWhere((AnchorItem item) => item.href != null);
        await tester.tapAt(
          _anchorGlobalRect(nonSelectableRender, nsAnchor).center,
        );
        await tester.pumpAndSettle();
        expect(nonSelectableTapped, <String>['https://example.org']);
      },
    );

    testWidgets(
      r'hovering over \href hitbox with onLinkTap != null transitions cursor to SystemMouseCursors.click and reverts on exit',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        ValueChanged<String>? activeHandler = (_) {};

        Widget buildSubject() {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: TexMath(
                  r'x + \href{https://example.org}{E = mc^2} + y',
                  font: font,
                  textStyle: const TextStyle(fontSize: 32.0),
                  onLinkTap: activeHandler,
                ),
              ),
            ),
          );
        }

        await tester.pumpWidget(buildSubject());
        await tester.pumpAndSettle();

        final RenderTexMath renderMath = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        final AnchorItem hrefAnchor = renderMath.displayList.items
            .whereType<AnchorItem>()
            .singleWhere((AnchorItem item) => item.href != null);
        final Rect linkGlobalRect = _anchorGlobalRect(renderMath, hrefAnchor);
        final Rect fullBoxRect = MatrixUtils.transformRect(
          renderMath.getTransformTo(null),
          Offset.zero & renderMath.size,
        );

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );

        // Move onto non-link glyph inside RenderTexMath ('x').
        final Offset nonLinkInsideMath = Offset(
          fullBoxRect.left + 4.0,
          linkGlobalRect.center.dy,
        );
        await mouse.moveTo(nonLinkInsideMath);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );

        // Move into the \href hitbox -> transitions to SystemMouseCursors.click.
        await mouse.moveTo(linkGlobalRect.center);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        // Move out of hitbox back onto non-link glyph inside RenderTexMath -> reverts.
        await mouse.moveTo(nonLinkInsideMath);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );

        // Move back in, then rebuild with onLinkTap == null -> reverts without moving.
        await mouse.moveTo(linkGlobalRect.center);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        activeHandler = null;
        await tester.pumpWidget(buildSubject());
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.basic,
        );
      },
    );

    testWidgets(
      'TexMathSpan forwards onLinkTap inside Text.rich and SelectionArea',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final List<String> tapped = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionArea(
                child: Center(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 24.0),
                      children: <InlineSpan>[
                        const TextSpan(text: 'See '),
                        TexMathSpan(
                          r'\href{https://example.org}{E = mc^2}',
                          font: font,
                          onLinkTap: tapped.add,
                        ),
                        const TextSpan(text: ' here.'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final RenderTexMath spanRender = tester.renderObject<RenderTexMath>(
          find.byType(TexMathRenderLeaf),
        );
        final AnchorItem hrefAnchor = spanRender.displayList.items
            .whereType<AnchorItem>()
            .singleWhere((AnchorItem item) => item.href != null);
        final Rect linkGlobalRect = _anchorGlobalRect(spanRender, hrefAnchor);

        final TestGesture mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          pointer: 1,
        );
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: Offset.zero);
        await tester.pump();

        await mouse.moveTo(linkGlobalRect.center);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );

        // Moving back onto surrounding selectable text reverts to text cursor.
        final Offset proseOffset =
            tester.getTopLeft(find.byType(RichText)) + const Offset(8.0, 12.0);
        await mouse.moveTo(proseOffset);
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.text,
        );

        await tester.tapAt(linkGlobalRect.center);
        await tester.pumpAndSettle();
        expect(tapped, <String>['https://example.org']);

        // TexMath.inline, TexMath.display, and TexMath.displayList forward onLinkTap.
        final List<String> constructorTapped = <String>[];
        final DisplayList prebuiltList = const TexMathEngine()
            .render(r'\href{https://prebuilt.example}{Z}', font: font)
            .displayList;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TexMath.inline(
                    r'\href{https://inline.example}{I}',
                    font: font,
                    textStyle: const TextStyle(fontSize: 28.0),
                    onLinkTap: (String uri) =>
                        constructorTapped.add('inline:$uri'),
                  ),
                  TexMath.display(
                    r'\href{https://display.example}{D}',
                    font: font,
                    textStyle: const TextStyle(fontSize: 28.0),
                    onLinkTap: (String uri) =>
                        constructorTapped.add('display:$uri'),
                  ),
                  TexMath.displayList(
                    prebuiltList,
                    font: font,
                    textStyle: const TextStyle(fontSize: 28.0),
                    onLinkTap: (String uri) =>
                        constructorTapped.add('list:$uri'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final List<RenderTexMath> leaves = tester
            .renderObjectList<RenderTexMath>(find.byType(TexMathRenderLeaf))
            .toList();
        expect(leaves.length, 3);
        for (final RenderTexMath leaf in leaves) {
          final AnchorItem anchor = leaf.displayList.items
              .whereType<AnchorItem>()
              .singleWhere((AnchorItem item) => item.href != null);
          await tester.tapAt(_anchorGlobalRect(leaf, anchor).center);
          await tester.pumpAndSettle();
        }
        expect(constructorTapped, <String>[
          'inline:https://inline.example',
          'display:https://display.example',
          'list:https://prebuilt.example',
        ]);
      },
    );

    testWidgets(
      r'SelectionArea drag selection on \href{https://example.org}{E = mc^2} still works',
      (WidgetTester tester) async {
        final MathFont font = await _ensureFontLoaded(tester);
        final List<String> tapped = <String>[];
        String? clipboardCopied;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (
              MethodCall call,
            ) async {
              if (call.method == 'Clipboard.setData') {
                final Map<Object?, Object?> args =
                    call.arguments as Map<Object?, Object?>;
                clipboardCopied = args['text'] as String?;
              }
              return null;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SelectionArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: TexMath(
                      r'\href{https://example.org}{E = mc^2}',
                      font: font,
                      textStyle: const TextStyle(fontSize: 36.0),
                      onLinkTap: tapped.add,
                    ),
                  ),
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

        final TestGesture drag = await tester.startGesture(
          topLeft - const Offset(12.0, 0.0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await drag.moveTo(
          topLeft + Offset(mathSize.width + 12.0, mathSize.height),
        );
        await tester.pump();
        await drag.up();
        await tester.pumpAndSettle();

        expect(tapped, isEmpty);
        expect(
          renderMath.getSelectedContent()?.plainText,
          r'\href{https://example.org}{E = mc^2}',
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        if (clipboardCopied != null) {
          expect(clipboardCopied, r'\href{https://example.org}{E = mc^2}');
        }
      },
    );
  });
}
