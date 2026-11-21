import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';
import 'package:tex_math_studio/corpus_loader.dart';
import 'package:tex_math_studio/main.dart';
import 'package:tex_math_studio/metrics_inspector.dart';
import 'package:tex_math_studio/visual_diff_view.dart';
import 'package:tex_math_studio/webview_bridge.dart';
import 'package:webview_flutter/webview_flutter.dart';

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

final class _MockStudioWebViewDriver implements StudioWebViewDriver {
  Completer<void>? pauseBeforeNavigationDelegate;
  NavigationRequestCallback? onNavigationRequest;
  WebResourceErrorCallback? onWebResourceError;
  void Function(JavaScriptMessage)? onMessageReceived;
  final List<String> executedScripts = <String>[];
  final List<Uri> loadedUris = <Uri>[];
  Error? runJsError;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage) onMessageReceived,
  }) async {
    this.onMessageReceived = onMessageReceived;
  }

  @override
  Future<void> setNavigationCallbacks({
    required NavigationRequestCallback onNavigationRequest,
    required WebResourceErrorCallback onWebResourceError,
  }) async {
    if (pauseBeforeNavigationDelegate != null) {
      await pauseBeforeNavigationDelegate!.future;
    }
    this.onNavigationRequest = onNavigationRequest;
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setInspectable(bool inspectable) async {}

  @override
  Future<void> loadRequest(Uri uri) async {
    loadedUris.add(uri);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    if (runJsError != null) {
      throw runJsError!;
    }
    executedScripts.add(javaScript);
  }

  @override
  Widget buildWidget(BuildContext context) {
    return const SizedBox(key: Key('mock-webview-widget'));
  }
}

Future<String> _sendRawHttpRequest(
  int port, {
  required String path,
  required String host,
}) async {
  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
  );
  try {
    socket.write(
      'GET $path HTTP/1.1\r\n'
      'Host: $host\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    return await utf8.decoder.bind(socket).join();
  } finally {
    await socket.close();
  }
}

StudioOracleAssets _createSyntheticOracleAssets(Directory root) {
  final String sep = Platform.pathSeparator;
  final Directory nodeModules = Directory('${root.path}${sep}node_modules')
    ..createSync(recursive: true);
  final Directory mathJaxDir = Directory('${nodeModules.path}${sep}mathjax')
    ..createSync(recursive: true);
  final Directory mathJaxUiDir = Directory('${mathJaxDir.path}${sep}ui')
    ..createSync(recursive: true);
  final Directory mathJaxDynamicDir = Directory(
    '${nodeModules.path}$sep@mathjax${sep}mathjax-newcm-font'
    '${sep}svg${sep}dynamic',
  )..createSync(recursive: true);
  final Directory katexDistDir = Directory(
    '${nodeModules.path}${sep}katex${sep}dist',
  )..createSync(recursive: true);

  final File mjBundle = File('${mathJaxDir.path}${sep}tex-svg.js')
    ..writeAsStringSync('// mathjax stub');
  File('${mathJaxUiDir.path}${sep}safe.js').writeAsStringSync('// safe stub');
  File('${mathJaxDynamicDir.path}${sep}calligraphic.js')
      .writeAsStringSync('// font stub');
  final File katexJs = File('${katexDistDir.path}${sep}katex.min.js')
    ..writeAsStringSync('// katex js');
  final File katexCss = File('${katexDistDir.path}${sep}katex.min.css')
    ..writeAsStringSync('/* katex css */');

  return StudioOracleAssets(
    nodeModulesDir: nodeModules,
    mathJaxBundleFile: mjBundle,
    mathJaxDir: mathJaxDir,
    mathJaxNewcmDynamicDir: mathJaxDynamicDir,
    katexDistDir: katexDistDir,
    katexJsFile: katexJs,
    katexCssFile: katexCss,
  );
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

    test('serves oracle bundles via tokenized loopback server and guards traversal', () async {
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
          server.resolveAssetFile('/mathjax/ui/safe.js')?.existsSync(),
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

        final Uri harnessUri = server.harnessUriFor(StudioEngineKind.mathJax)!;
        final String response = await _sendRawHttpRequest(
          harnessUri.port,
          path: harnessUri.path,
          host: '${harnessUri.host}:${harnessUri.port}',
        );
        expect(response, startsWith('HTTP/1.1 200 OK'));
        expect(response, contains('tex-svg.js'));
        expect(response, contains('ui/safe'));
      } finally {
        await server.close();
      }
    });

    test('enforces StudioLocalAssetServer concurrency, token auth, traversal, Host, and CSP', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'studio_server_sec_',
      );
      try {
        final File secretOutside = File('${tempDir.path}/secret.txt')
          ..writeAsStringSync('TOP_SECRET');
        final StudioOracleAssets assets = _createSyntheticOracleAssets(tempDir);
        final Link escapingLink = Link('${assets.mathJaxDir!.path}/leak.js')
          ..createSync(secretOutside.path);
        expect(escapingLink.existsSync(), isTrue);

        final StudioLocalAssetServer server = StudioLocalAssetServer(assets);
        try {
          // Concurrent start() coalesces onto one bound HttpServer.
          final List<String> origins = await Future.wait<String>(
            <Future<String>>[server.start(), server.start(), server.start()],
          );
          expect(origins.toSet().length, 1);

          final Uri mjHarness = server.harnessUriFor(StudioEngineKind.mathJax)!;
          final int port = mjHarness.port;
          final String validHost = '127.0.0.1:$port';

          // Missing or invalid token -> 403 Forbidden.
          final String missingTokenResp = await _sendRawHttpRequest(
            port,
            path: '/mathjax-harness.html',
            host: validHost,
          );
          expect(missingTokenResp, startsWith('HTTP/1.1 403 Forbidden'));

          final String wrongTokenResp = await _sendRawHttpRequest(
            port,
            path: '/s/wrongtoken/mathjax-harness.html',
            host: validHost,
          );
          expect(wrongTokenResp, startsWith('HTTP/1.1 403 Forbidden'));

          final String untokenizedAssetResp = await _sendRawHttpRequest(
            port,
            path: '/mathjax/tex-svg.js',
            host: validHost,
          );
          expect(untokenizedAssetResp, startsWith('HTTP/1.1 403 Forbidden'));

          // Invalid Host header -> 403 Forbidden.
          final String badHostResp = await _sendRawHttpRequest(
            port,
            path: mjHarness.path,
            host: 'evil.example:$port',
          );
          expect(badHostResp, startsWith('HTTP/1.1 403 Forbidden'));

          // %2f, %5c, backslash, NUL, dot segments, missing file, and escaping symlinks rejected.
          expect(
            server.resolveAssetFile('/mathjax/..%2f..%2fsecret.txt'),
            isNull,
          );
          expect(server.resolveAssetFile('/mathjax/%2e%2e/secret.txt'), isNull);
          expect(server.resolveAssetFile('/mathjax/..\\secret.txt'), isNull);
          expect(
            server.resolveAssetFile('/mathjax/%5c..%5csecret.txt'),
            isNull,
          );
          expect(server.resolveAssetFile('/mathjax/tex-svg.js\x00.js'), isNull);
          expect(server.resolveAssetFile('/mathjax/tex-svg.js%00'), isNull);
          expect(server.resolveAssetFile('/mathjax/leak.js'), isNull);
          expect(server.resolveAssetFile('/mathjax/nonexistent.js'), isNull);

          final String wireTraversalResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}/mathjax/..%2f..%2fsecret.txt',
            host: validHost,
          );
          expect(
            wireTraversalResp.startsWith('HTTP/1.1 404') ||
                wireTraversalResp.startsWith('HTTP/1.1 403'),
            isTrue,
          );
          expect(wireTraversalResp, isNot(contains('TOP_SECRET')));

          // Harness HTML includes restrictive CSP, nosniff, no CORS wildcard, and ui/safe.
          final String harnessResp = await _sendRawHttpRequest(
            port,
            path: mjHarness.path,
            host: validHost,
          );
          expect(harnessResp, startsWith('HTTP/1.1 200 OK'));
          expect(
            harnessResp.toLowerCase(),
            isNot(contains('access-control-allow-origin')),
          );
          expect(
            harnessResp.toLowerCase(),
            contains('x-content-type-options: nosniff'),
          );
          expect(
            harnessResp,
            contains(StudioWebHarnessBuilder.harnessContentSecurityPolicy),
          );
          expect(harnessResp, contains("'ui/safe'"));

          // Valid asset omits Access-Control-Allow-Origin and sets nosniff.
          final String assetResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}/mathjax/tex-svg.js',
            host: validHost,
          );
          expect(assetResp, startsWith('HTTP/1.1 200 OK'));
          expect(
            assetResp.toLowerCase(),
            isNot(contains('access-control-allow-origin')),
          );
          expect(
            assetResp.toLowerCase(),
            contains('x-content-type-options: nosniff'),
          );
          expect(assetResp, contains('// mathjax stub'));
        } finally {
          await server.close();
        }

        // Closing mid-bind immediately cleans up the newly bound HttpServer.
        final StudioLocalAssetServer midBindServer = StudioLocalAssetServer(
          assets,
        );
        final Future<String> startFuture = midBindServer.start();
        await midBindServer.close();
        await expectLater(startFuture, throwsStateError);
        expect(midBindServer.isRunning, isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'StudioWebHarnessBuilder allowlists packages and excludes texhtml',
      () {
        final List<String> sanitized = StudioWebHarnessBuilder.sanitizePackages(
          <String>['base', 'physics', 'texhtml', '../../evil', 'ams'],
        );
        expect(sanitized, <String>['base', 'physics', 'ams']);

        final List<String> fallback = StudioWebHarnessBuilder.sanitizePackages(
          <String>['texhtml', 'unknown'],
        );
        expect(fallback, StudioWebHarnessBuilder.defaultMathJaxPackages);

        final String html = StudioWebHarnessBuilder.buildMathJaxHtml(
          origin: 'http://127.0.0.1:9999',
          sessionToken: 'tok123',
        );
        expect(html, contains("load: ['ui/safe'"));
        expect(html, contains('http://127.0.0.1:9999/s/tok123/mathjax'));
        expect(html, contains('http://127.0.0.1:9999/s/tok123/fonts'));
        expect(html, contains('window.__allowedPackages'));
        expect(html, isNot(contains('"texhtml"')));
      },
    );

    test(
      'StudioCorpusEntry enforces immutability and safe expectation parsing',
      () async {
        final Directory tempDir = Directory.systemTemp.createTempSync(
          'studio_corpus_safe_',
        );
        try {
          final Directory corpusDir = Directory('${tempDir.path}/corpus')
            ..createSync(recursive: true);
          Directory('${tempDir.path}/tool/oracle').createSync(recursive: true);
          File('${corpusDir.path}/README.md').writeAsStringSync('# Corpus');
          Directory('${corpusDir.path}/tier1_core').createSync();
          File('${corpusDir.path}/tier1_core/sample.tex').writeAsStringSync(
            '% id: tier1_core/sample\n'
            '% packages: base, ams\n'
            'x + y\n',
          );
          File('${corpusDir.path}/expectations.json').writeAsStringSync(
            jsonEncode(<String, Object?>{
              'cases': <String, Object?>{
                'tier1_core/sample': <String, Object?>{
                  'texMathStatus': 12345, // non-string should not drop entry
                  'box': <String, Object?>{'width': 1.5, 'height': 0.8},
                },
              },
            }),
          );

          final StudioCorpusCatalog catalog = StudioCorpusLoader.load(
            startDirectory: tempDir,
          );
          expect(catalog.isFromDisk, isTrue);
          expect(catalog.length, 1);
          final StudioCorpusEntry entry = catalog.entries.first;
          expect(entry.expectationStatus, isNull);
          expect(entry.oracleBoxWidthEm, 1.5);
          expect(() => entry.packages!.add('evil'), throwsUnsupportedError);

          final StudioCorpusCatalog asyncCatalog =
              await StudioCorpusLoader.loadAsync(startDirectory: tempDir);
          expect(asyncCatalog, catalog);
        } finally {
          tempDir.deleteSync(recursive: true);
        }
      },
    );

    test('WkWebViewStudioPaneController enforces navigation policy, seq IDs, JS error recovery, PNG decode, and post-dispose safety', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'studio_ctrl_test_',
      );
      try {
        final StudioOracleAssets assets = _createSyntheticOracleAssets(tempDir);
        final StudioLocalAssetServer server = StudioLocalAssetServer(assets);

        // 1. Mid-initialize dispose guard (DF-5).
        final _MockStudioWebViewDriver pausedDriver = _MockStudioWebViewDriver()
          ..pauseBeforeNavigationDelegate = Completer<void>();
        final WkWebViewStudioPaneController midInitCtrl =
            WkWebViewStudioPaneController(
              engineKind: StudioEngineKind.mathJax,
              assetServer: server,
              driverFactory: () => pausedDriver,
            );
        final Future<void> initFuture = midInitCtrl.initialize();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await midInitCtrl.dispose();
        pausedDriver.pauseBeforeNavigationDelegate!.complete();
        await initFuture;
        expect(midInitCtrl.hasAttachedDriver, isFalse);

        // 2. Full initialization, navigation gating, monotonic seq, JS error, PNG decode.
        final _MockStudioWebViewDriver driver = _MockStudioWebViewDriver();
        final WkWebViewStudioPaneController ctrl =
            WkWebViewStudioPaneController(
              engineKind: StudioEngineKind.mathJax,
              assetServer: server,
              driverFactory: () => driver,
            );
        await ctrl.initialize();
        expect(ctrl.hasAttachedDriver, isTrue);
        expect(driver.loadedUris.length, 1);

        final Uri allowedUri = driver.loadedUris.single;
        expect(
          driver.onNavigationRequest!(
            NavigationRequest(url: allowedUri.toString(), isMainFrame: true),
          ),
          NavigationDecision.navigate,
        );
        expect(
          driver.onNavigationRequest!(
            NavigationRequest(url: allowedUri.toString(), isMainFrame: false),
          ),
          NavigationDecision.prevent,
        );
        expect(
          driver.onNavigationRequest!(
            const NavigationRequest(
              url: 'https://example.com',
              isMainFrame: true,
            ),
          ),
          NavigationDecision.prevent,
        );
        expect(
          driver.onNavigationRequest!(
            const NavigationRequest(
              url: 'javascript:alert(1)',
              isMainFrame: true,
            ),
          ),
          NavigationDecision.prevent,
        );
        expect(
          driver.onNavigationRequest!(
            const NavigationRequest(
              url: 'data:text/html,<script>alert(1)</script>',
              isMainFrame: true,
            ),
          ),
          NavigationDecision.prevent,
        );

        // Ready triggers pending/live renders with monotonic seq.
        ctrl.handleBridgePayload(
          jsonEncode(<String, Object?>{'type': 'ready'}),
        );
        expect(ctrl.telemetry.value.isReady, isTrue);

        await ctrl.render(
          StudioWebRenderRequest(
            source: 'x^2',
            displayMode: TexMathDisplayMode.display,
            isDarkTheme: false,
            packages: const <String>['base', 'texhtml'],
          ),
        );
        await ctrl.render(
          StudioWebRenderRequest(
            source: 'y^3',
            displayMode: TexMathDisplayMode.display,
            isDarkTheme: false,
          ),
        );
        expect(driver.executedScripts.length, 2);
        // texhtml was stripped before JS dispatch.
        expect(driver.executedScripts.first, isNot(contains('texhtml')));

        // Stale seq=1 response is ignored; seq=2 updates telemetry.
        ctrl.handleBridgePayload(
          jsonEncode(<String, Object?>{
            'type': 'rendered',
            'seq': 1,
            'svgXml': '<svg>stale</svg>',
            'widthPx': 10.0,
            'heightPx': 10.0,
          }),
        );
        expect(ctrl.telemetry.value.isRendering, isTrue);
        expect(ctrl.telemetry.value.svgXml, isNull);

        ctrl.handleBridgePayload(
          jsonEncode(<String, Object?>{
            'type': 'rendered',
            'seq': 2,
            'svgXml': '<svg>fresh</svg>',
            'widthPx': 24.0,
            'heightPx': 12.0,
            'renderTimeMs': 3.2,
          }),
        );
        expect(ctrl.telemetry.value.isRendering, isFalse);
        expect(ctrl.telemetry.value.svgXml, '<svg>fresh</svg>');
        expect(ctrl.telemetry.value.widthPx, 24.0);

        // JS error clears isRendering cleanly.
        driver.runJsError = StateError('eval failed');
        await ctrl.render(
          StudioWebRenderRequest(
            source: 'z',
            displayMode: TexMathDisplayMode.inline,
            isDarkTheme: true,
          ),
        );
        expect(ctrl.telemetry.value.isRendering, isFalse);
        expect(ctrl.telemetry.value.statusSummary, 'JS error');
        expect(ctrl.telemetry.value.errorMessage, contains('eval failed'));

        // Real PNG data URL decoding.
        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(recorder);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 2, 2),
          ui.Paint()..color = const Color(0xFF112233),
        );
        final ui.Picture pic = recorder.endRecording();
        final ui.Image img = await pic.toImage(2, 2);
        pic.dispose();
        final ByteData? pngBytes = await img.toByteData(
          format: ui.ImageByteFormat.png,
        );
        img.dispose();
        final String dataUrl =
            'data:image/png;base64,${base64Encode(pngBytes!.buffer.asUint8List())}';
        final StudioCapturedImage? decodedPng =
            await WkWebViewStudioPaneController.decodePngDataUrl(dataUrl);
        expect(decodedPng, isNotNull);
        expect(decodedPng!.width, 2);
        expect(decodedPng.height, 2);
        expect(decodedPng.rgbaBytes.length, 16);

        await ctrl.dispose();
        // Post-dispose bridge callbacks are no-ops.
        ctrl.handleBridgePayload(
          jsonEncode(<String, Object?>{'type': 'ready'}),
        );
        await server.close();
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'computeAlignedPixelDiffAsync offloads large buffers via Isolate.run',
      () async {
        final Uint8List a = Uint8List.fromList(
          List<int>.filled(80 * 80 * 4, 255),
        );
        final Uint8List b = Uint8List.fromList(a);
        b[0] = 0;
        final ({
          StudioCapturedImage left,
          StudioCapturedImage right,
          PixelDiffResult diff,
        })
        result = await computeAlignedPixelDiffAsync(
          StudioCapturedImage(width: 80, height: 80, rgbaBytes: a),
          StudioCapturedImage(width: 80, height: 80, rgbaBytes: b),
          backgroundColor: Colors.white,
        );
        expect(result.diff.totalPixels, 6400);
        expect(result.diff.diffPixelCount, 1);
        expect(result.diff.maxChannelDelta, 255);
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
        TexMathFontBundle.clearCache();
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
        await tester.runAsync(() async {
          await TexMathFontBundle.loadMathFont();
        });
        await tester.pumpAndSettle();

        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);

        // Switch to Pixel Diff mode and verify exact computed stats for initial capture.
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);
        expect(find.text('Diff Pixels: 1 / 4'), findsOneWidget);

        // Switch to Curtain Diff mode, test slider.
        await tester.tap(find.text('Curtain Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Curtain: 50%'), findsOneWidget);

        final Slider slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged?.call(0.75);
        await tester.pumpAndSettle();
        expect(find.text('Curtain: 75%'), findsOneWidget);

        // Return to Side-by-Side mode and test corpus filtering/selection + preset chip.
        await tester.tap(find.text('Side-by-Side'));
        await tester.pumpAndSettle();
        expect(find.text('MathJax 4.1.3 Oracle'), findsWidgets);

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

        // Selecting a corpus entry invalidates stale Pixel Diff captures (DF-9).
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsNothing);
        expect(find.text('Run Pixel Diff'), findsOneWidget);

        await tester.tap(find.text('Side-by-Side'));
        await tester.pumpAndSettle();

        final Finder presetChip = find.text(r'\ce{CO2 + C -> 2CO}');
        await tester.ensureVisible(presetChip);
        await tester.pumpAndSettle();
        await tester.tap(presetChip);
        await tester.pumpAndSettle();
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);
      },
    );

    testWidgets(
      'invalidates _capturedPair on target, source, mode, and theme changes; '
      'CurtainDiff prompts without mounting WebViewWidget when uncaptured',
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
              255, 0, 0, 255,
              255, 255, 255, 255,
              255, 255, 255, 255,
            ]),
          ),
        );

        await tester.pumpWidget(
          TexMathStudioApp(
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialFont: loadedFont,
            initialCapturedPair: samplePair,
          ),
        );
        await tester.pumpAndSettle();

        // Pixel Diff displays samplePair stats initially.
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);

        // Switching diffTarget invalidates _capturedPair cleanly.
        await tester.tap(find.text('KaTeX 0.19.1'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsNothing);
        expect(find.text('Run Pixel Diff'), findsOneWidget);

        // Uncaptured Curtain Diff prompts cleanly without clipping live WebViews.
        await tester.tap(find.text('Curtain Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Capture for Curtain Diff'), findsOneWidget);
        expect(find.byType(Slider), findsNothing);

        // Re-seed pair via fresh pump and verify source edit invalidates capture.
        await tester.pumpWidget(
          TexMathStudioApp(
            key: const ValueKey<String>('reseed-source'),
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialFont: loadedFont,
            initialCapturedPair: samplePair,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);

        await tester.enterText(
          find.widgetWithText(TextField, 'TeX Source'),
          'x + 1',
        );
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsNothing);
        expect(find.text('Run Pixel Diff'), findsOneWidget);

        // Re-seed pair and verify Display/Inline & Theme toggles invalidate capture.
        await tester.pumpWidget(
          TexMathStudioApp(
            key: const ValueKey<String>('reseed-toggle'),
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialFont: loadedFont,
            initialCapturedPair: samplePair,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);

        await tester.tap(find.text('Inline'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsNothing);

        await tester.pumpWidget(
          TexMathStudioApp(
            key: const ValueKey<String>('reseed-theme'),
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialFont: loadedFont,
            initialCapturedPair: samplePair,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pixel Diff'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsOneWidget);

        await tester.tap(find.byTooltip('Toggle Light/Dark Theme'));
        await tester.pumpAndSettle();
        expect(find.text('Match: 75.00%'), findsNothing);
      },
    );

    testWidgets('surfaces bundled font load failures in Studio UI', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        TexMathStudioApp(
          corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
          fontLoader: () =>
              Future<MathFont>.error(StateError('corrupt OTF bundle')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Font Load Error'), findsOneWidget);
      expect(find.textContaining('corrupt OTF bundle'), findsWidgets);
      expect(find.text('Loading NewCMMath-Regular.otf metrics…'), findsNothing);
    });
  });
}
