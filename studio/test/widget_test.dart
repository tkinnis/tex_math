import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';
import 'package:tex_math_studio/corpus_loader.dart';
import 'package:tex_math_studio/main.dart';
import 'package:tex_math_studio/metrics_inspector.dart';
import 'package:tex_math_studio/visual_diff_view.dart';
import 'package:tex_math_studio/webview_bridge.dart';

final class _FakeWebPaneController implements StudioWebPaneController {
  _FakeWebPaneController({required this.engineKind, this.captureImage})
    : _telemetry = ValueNotifier<StudioWebRenderTelemetry>(
        StudioWebRenderTelemetry(
          engineKind: engineKind,
          isReady: true,
          statusSummary: 'Mock Ready',
        ),
      );

  @override
  final StudioEngineKind engineKind;

  final StudioCapturedImage? captureImage;
  final ValueNotifier<StudioWebRenderTelemetry> _telemetry;
  final List<StudioWebRenderRequest> requests = <StudioWebRenderRequest>[];
  bool initialized = false;
  bool disposed = false;

  @override
  ValueListenable<StudioWebRenderTelemetry> get telemetry => _telemetry;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> render(StudioWebRenderRequest request) async {
    requests.add(request);
    _telemetry.value = _telemetry.value.copyWith(
      isReady: true,
      isRendering: false,
      clearError: true,
      renderTimeMs: 1.5,
      statusSummary: 'Rendered',
    );
  }

  @override
  Future<StudioCapturedImage?> captureRgba({
    int targetWidth = 480,
    int targetHeight = 220,
  }) async {
    return captureImage;
  }

  @override
  Widget buildView(BuildContext context) {
    final String latest = requests.isEmpty ? '' : requests.last.source;
    return Center(child: Text('${engineKind.title}: $latest'));
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _telemetry.dispose();
  }
}

void main() {
  group('Pure-Dart RGBA computePixelDiff', () {
    test('reports 100% match for identical buffers', () {
      final Uint8List a = Uint8List.fromList(<int>[
        10, 20, 30, 255, //
        40, 50, 60, 255,
        70, 80, 90, 255,
        100, 110, 120, 255,
      ]);
      final Uint8List b = Uint8List.fromList(a);

      final PixelDiffResult diff = computePixelDiff(a, b, 2, 2);

      expect(diff.width, 2);
      expect(diff.height, 2);
      expect(diff.totalPixels, 4);
      expect(diff.diffPixelCount, 0);
      expect(diff.exactMatchRatio, 1.0);
      expect(diff.matchPercentage, 100.0);
      expect(diff.maxChannelDelta, 0);
    });

    test('highlights mismatched pixels in magenta and reports exact %', () {
      final Uint8List a = Uint8List.fromList(<int>[
        255, 255, 255, 255, //
        0, 0, 0, 255,
        12, 34, 56, 255,
        200, 200, 200, 255,
      ]);
      final Uint8List b = Uint8List.fromList(<int>[
        255, 255, 255, 255, //
        0, 10, 0, 255, // Mismatch at pixel index 1 (delta = 10)
        12, 34, 56, 255,
        200, 200, 200, 255,
      ]);

      final PixelDiffResult strictDiff = computePixelDiff(a, b, 2, 2);
      expect(strictDiff.diffPixelCount, 1);
      expect(strictDiff.exactMatchRatio, 0.75);
      expect(strictDiff.matchPercentage, 75.0);
      expect(strictDiff.maxChannelDelta, 10);
      expect(strictDiff.diffRgba.sublist(4, 8), <int>[255, 0, 255, 255]);

      final PixelDiffResult tolerantDiff = computePixelDiff(
        a,
        b,
        2,
        2,
        channelTolerance: 10,
      );
      expect(tolerantDiff.diffPixelCount, 0);
      expect(tolerantDiff.matchPercentage, 100.0);
    });

    test('handles zero-area images and rejects mismatched buffer lengths', () {
      final PixelDiffResult empty = computePixelDiff(
        Uint8List(0),
        Uint8List(0),
        0,
        0,
      );
      expect(empty.totalPixels, 0);
      expect(empty.exactMatchRatio, 1.0);

      expect(
        () => computePixelDiff(Uint8List(4), Uint8List(8), 1, 1),
        throwsArgumentError,
      );
      expect(
        () => computePixelDiff(Uint8List(0), Uint8List(0), -1, 1),
        throwsArgumentError,
      );
    });

    test('alignCapturedPair pads mismatched dimensions cleanly', () {
      final StudioCapturedImage small = StudioCapturedImage(
        width: 2,
        height: 2,
        rgbaBytes: Uint8List.fromList(List<int>.filled(2 * 2 * 4, 100)),
      );
      final StudioCapturedImage large = StudioCapturedImage(
        width: 4,
        height: 4,
        rgbaBytes: Uint8List.fromList(List<int>.filled(4 * 4 * 4, 255)),
      );

      final ({StudioCapturedImage left, StudioCapturedImage right}) aligned =
          alignCapturedPair(small, large, backgroundColor: Colors.white);

      expect(aligned.left.width, 4);
      expect(aligned.left.height, 4);
      expect(aligned.right.width, 4);
      expect(aligned.right.height, 4);
      final PixelDiffResult diff = computePixelDiff(
        aligned.left.rgbaBytes,
        aligned.right.rgbaBytes,
        4,
        4,
      );
      expect(diff.diffPixelCount, 4);
      expect(diff.matchPercentage, 75.0);
    });
  });

  group('Corpus loader & web asset locator', () {
    test('loads all 352 .tex corpus entries from repository root', () {
      final StudioCorpusCatalog catalog = StudioCorpusLoader.load();

      expect(catalog.isFromDisk, isTrue);
      expect(catalog.length, 352);
      expect(catalog.availableTiers, canonicalCorpusTiers);
      expect(
        catalog
            .filter(acceptance: StudioCorpusAcceptanceFilter.accepted)
            .length,
        315,
      );
      expect(
        catalog.filter(acceptance: StudioCorpusAcceptanceFilter.refused).length,
        37,
      );

      final Map<String, List<StudioCorpusEntry>> byTier = catalog.groupEntries(
        catalog.entries,
        StudioCorpusGrouping.tier,
      );
      expect(byTier['Tier 1']?.length, 125);
      expect(byTier['Tier 2']?.length, 105);
      expect(byTier['Tier 3']?.length, 35);
      expect(byTier['Stretchy']?.length, 25);
      expect(byTier['Notebooks']?.length, 25);
      expect(byTier['Errors']?.length, 37);
    });

    test('falls back cleanly to embedded presets outside repo root', () {
      final StudioCorpusCatalog catalog = StudioCorpusLoader.load(
        startDirectory: Directory.systemTemp,
      );

      expect(catalog.isFromDisk, isFalse);
      expect(catalog.length, greaterThanOrEqualTo(6));
      expect(catalog.availableTiers, containsAll(canonicalCorpusTiers));
    });

    test(
      'serves oracle bundles via loopback server and guards traversal',
      () async {
        final StudioOracleAssets? assets = StudioOracleAssetLocator.locate();
        if (assets == null || !assets.hasMathJax || !assets.hasKatex) {
          return;
        }

        final StudioLocalAssetServer server = StudioLocalAssetServer(assets);
        try {
          final String origin = await server.start();
          expect(origin, startsWith('http://127.0.0.1:'));

          expect(
            server.resolveAssetFile('/mathjax/tex-svg.js')?.existsSync(),
            isTrue,
          );
          expect(
            server
                .resolveAssetFile(
                  '/mathjax/@mathjax/mathjax-newcm-font/js/svg/dynamic/calligraphic.js',
                )
                ?.existsSync(),
            isTrue,
          );
          expect(
            server.resolveAssetFile('/katex/katex.min.js')?.existsSync(),
            isTrue,
          );
          expect(
            server.resolveAssetFile('/mathjax/../katex/dist/katex.min.js'),
            isNull,
          );

          final Uri harnessUri = Uri.parse('$origin/mathjax-harness.html');
          final Socket socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            harnessUri.port,
          );
          try {
            socket.write(
              'GET ${harnessUri.path} HTTP/1.1\r\n'
              'Host: ${harnessUri.host}:${harnessUri.port}\r\n'
              'Connection: close\r\n\r\n',
            );
            await socket.flush();
            final String response = await utf8.decoder.bind(socket).join();
            expect(response, startsWith('HTTP/1.1 200 OK'));
            expect(response, contains('tex-svg.js'));
          } finally {
            await socket.close();
          }
        } finally {
          await server.close();
        }
      },
    );
  });

  group('Studio widget workbench', () {
    late MathFont loadedFont;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final TexMathFontAsset asset = await TexMathFontBundle.load();
      loadedFont = asset.decodeMathFont();
    });

    testWidgets(
      'renders 3-way panes, live TeX editing, error fallback, display/inline, '
      'theme toggle, and metrics/exports cleanly at 800x600',
      (WidgetTester tester) async {
        final List<_FakeWebPaneController> controllers =
            <_FakeWebPaneController>[];

        await tester.pumpWidget(
          TexMathStudioApp(
            initialFont: loadedFont,
            webPaneControllerFactory: (StudioEngineKind kind, _) {
              final _FakeWebPaneController controller = _FakeWebPaneController(
                engineKind: kind,
              );
              controllers.add(controller);
              return controller;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('tex_math Comparison Studio'), findsOneWidget);
        expect(find.text('tex_math (Pure Dart)'), findsOneWidget);
        expect(find.text('MathJax 4.1.3 Oracle'), findsOneWidget);
        expect(find.text('KaTeX 0.19.1 Comparison'), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);
        expect(find.text('widthEm'), findsOneWidget);
        expect(find.text('heightEm'), findsOneWidget);
        expect(find.text('depthEm'), findsOneWidget);
        expect(find.text('baselineEm'), findsOneWidget);
        expect(find.text('GlyphItem'), findsOneWidget);
        expect(find.text('RuleItem'), findsOneWidget);

        expect(controllers.length, 2);
        expect(
          controllers.every((_FakeWebPaneController c) => c.initialized),
          isTrue,
        );

        // Switch export inspector tabs.
        await tester.tap(find.text('SVG'));
        await tester.pumpAndSettle();
        expect(find.textContaining('<svg'), findsOneWidget);

        await tester.tap(find.text('MathML'));
        await tester.pumpAndSettle();
        expect(find.textContaining('<math'), findsOneWidget);

        await tester.tap(find.text('Spoken'));
        await tester.pumpAndSettle();
        expect(find.text('Spoken Text'), findsOneWidget);

        await tester.tap(find.text('Metrics'));
        await tester.pumpAndSettle();

        // Live TeX edit.
        final Finder editorFinder = find.widgetWithText(
          TextField,
          'TeX Source',
        );
        await tester.enterText(editorFinder, r'\alpha + \beta');
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);
        expect(controllers.first.requests.last.source, r'\alpha + \beta');

        // Display vs Inline toggle.
        await tester.tap(find.text('Inline'));
        await tester.pumpAndSettle();
        expect(
          controllers.first.requests.last.displayMode,
          TexMathDisplayMode.inline,
        );

        // Light / Dark theme toggle.
        await tester.tap(find.byTooltip('Toggle Light/Dark Theme'));
        await tester.pumpAndSettle();
        expect(controllers.first.requests.last.isDarkTheme, isTrue);

        // Verify Pixel Diff capture callback & live error/ready state.
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Run Pixel Diff'), findsOneWidget);

        // Return to Side-by-Side mode before exiting.
        await tester.tap(find.text('Side-by-Side'));
        await tester.pumpAndSettle();

        // Invalid TeX triggers TexMathErrorWidget + Failure metrics inspection.
        await tester.enterText(editorFinder, r'\undefinedcmd');
        await tester.pumpAndSettle();
        expect(find.byType(TexMathErrorWidget), findsOneWidget);
        expect(find.textContaining('undefinedControlSequence'), findsWidgets);
      },
    );

    testWidgets(
      'fake captureRgba controller exposes captured dimensions and telemetry',
      (WidgetTester tester) async {
        final StudioCapturedImage stubCapture = StudioCapturedImage(
          width: 4,
          height: 4,
          rgbaBytes: Uint8List(4 * 4 * 4),
        );
        final _FakeWebPaneController fake = _FakeWebPaneController(
          engineKind: StudioEngineKind.mathJax,
          captureImage: stubCapture,
        );
        await fake.initialize();
        final StudioCapturedImage? captured = await fake.captureRgba();
        expect(captured?.width, 4);
        expect(captured?.height, 4);
        await fake.dispose();
        expect(fake.disposed, isTrue);

        final StudioInspectionResult ok = inspectTexExpression(
          source: r'\frac{a + b}{c - d}',
          displayMode: TexMathDisplayMode.display,
          font: loadedFont,
        );
        expect(ok, isA<StudioInspectionSuccess>());
        final StudioInspectionSuccess success = ok as StudioInspectionSuccess;
        expect(success.metrics.widthEm, greaterThan(0));
        expect(success.glyphCount, greaterThan(0));
        expect(success.ruleCount, greaterThan(0));
        expect(success.svgXml, contains('<svg'));
        expect(success.mathMl, contains('<mfrac>'));
        expect(success.spokenText, isNotEmpty);

        final StudioInspectionResult err = inspectTexExpression(
          source: r'\undefinedcmd',
          displayMode: TexMathDisplayMode.display,
          font: loadedFont,
        );
        expect(err, isA<StudioInspectionFailure>());
        expect(
          (err as StudioInspectionFailure).error.errorClass,
          TexMathErrorClass.undefinedControlSequence,
        );
      },
    );

    testWidgets(
      'renders default TexMathStudioApp cleanly and switches corpus & diff tabs',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StudioCapturedPair samplePair = StudioCapturedPair(
          target: StudioDiffTarget.mathJax,
          texMathImage: StudioCapturedImage(
            width: 2,
            height: 2,
            rgbaBytes: Uint8List.fromList(<int>[
              255, 255, 255, 255, //
              0, 0, 0, 255,
              255, 255, 255, 255,
              255, 255, 255, 255,
            ]),
          ),
          targetImage: StudioCapturedImage(
            width: 2,
            height: 2,
            rgbaBytes: Uint8List.fromList(<int>[
              255, 255, 255, 255, //
              255, 0, 0, 255, // 1 mismatch pixel out of 4 => 75.00%
              255, 255, 255, 255,
              255, 255, 255, 255,
            ]),
          ),
        );

        await tester.pumpWidget(
          TexMathStudioApp(
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialCapturedPair: samplePair,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);

        // Filter corpus sidebar by query and select an error case.
        final Finder searchFinder = find.widgetWithText(
          TextField,
          'Filter corpus…',
        );
        await tester.enterText(searchFinder, 'undefined');
        await tester.pumpAndSettle();

        await tester.tap(find.text('undefined_command_sample'));
        await tester.pumpAndSettle();
        expect(find.byType(TexMathErrorWidget), findsOneWidget);

        // Clear search and select a valid case.
        await tester.enterText(searchFinder, 'gaussian');
        await tester.pumpAndSettle();
        await tester.tap(find.text('gaussian_integral'));
        await tester.pumpAndSettle();
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);

        // Switch to Pixel Diff mode and verify exact computed stats.
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);
        expect(find.text('Diff Pixels: 1 / 4'), findsOneWidget);

        // Switch to Curtain Diff mode, test drag gesture and slider.
        await tester.tap(find.text('Curtain Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Curtain: 50%'), findsOneWidget);

        final Slider slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged?.call(0.75);
        await tester.pumpAndSettle();
        expect(find.text('Curtain: 75%'), findsOneWidget);

        // Return to Side-by-Side mode and test preset chip + corpus grouping.
        await tester.tap(find.text('Side-by-Side'));
        await tester.pumpAndSettle();
        expect(find.text('MathJax 4.1.3 Oracle'), findsWidgets);

        final Finder presetChip = find.text(r'\ce{CO2 + C -> 2CO}');
        await tester.ensureVisible(presetChip);
        await tester.pumpAndSettle();
        await tester.tap(presetChip);
        await tester.pumpAndSettle();
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);
      },
    );
  });
}
