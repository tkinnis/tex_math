import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String method = 'GET',
}) async {
  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
  );
  try {
    socket.write(
      '$method $path HTTP/1.1\r\n'
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

    test('StudioLocalAssetServer serves offline MathJax font-extension stubs and enforces auth, real-file precedence, 404, and traversal guards', () async {
      final Directory tempDir = Directory.systemTemp.createTempSync(
        'studio_font_stubs_',
      );
      try {
        final StudioOracleAssets assets = _createSyntheticOracleAssets(tempDir);
        final StudioLocalAssetServer server = StudioLocalAssetServer(assets);
        try {
          await server.start();
          final Uri mjHarness = server.harnessUriFor(StudioEngineKind.mathJax)!;
          final int port = mjHarness.port;
          final String validHost = '127.0.0.1:$port';
          const List<String> stubPaths = <String>[
            '/fonts/mathjax-mhchem-font-extension/svg.js',
            '/fonts/mathjax-bbm-font-extension/svg.js',
            '/fonts/mathjax-bboldx-font-extension/svg.js',
            '/fonts/mathjax-dsfont-font-extension/svg.js',
          ];

          // Absent on disk -> 200 OK offline JS stub with security headers.
          for (final String stubPath in stubPaths) {
            final String resp = await _sendRawHttpRequest(
              port,
              path: '/s/${server.sessionToken}$stubPath',
              host: validHost,
            );
            expect(resp, startsWith('HTTP/1.1 200 OK'));
            final String lower = resp.toLowerCase();
            expect(
              lower,
              contains('content-type: application/javascript; charset=utf-8'),
            );
            expect(lower, contains('cache-control: no-store'));
            expect(lower, contains('x-content-type-options: nosniff'));
            expect(
              resp,
              contains(
                '/* Offline stub for optional MathJax font extension. */',
              ),
            );
          }

          // HEAD returns 200 OK with headers and empty body.
          final String headResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}${stubPaths.first}',
            host: validHost,
            method: 'HEAD',
          );
          expect(headResp, startsWith('HTTP/1.1 200 OK'));
          expect(
            headResp,
            isNot(contains('Offline stub for optional MathJax')),
          );

          // Auth and Host header still enforced on stub paths.
          final String noTokenResp = await _sendRawHttpRequest(
            port,
            path: stubPaths.first,
            host: validHost,
          );
          expect(noTokenResp, startsWith('HTTP/1.1 403 Forbidden'));

          final String wrongTokenResp = await _sendRawHttpRequest(
            port,
            path: '/s/wrongtoken${stubPaths.first}',
            host: validHost,
          );
          expect(wrongTokenResp, startsWith('HTTP/1.1 403 Forbidden'));

          final String badHostResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}${stubPaths.first}',
            host: 'evil.example:$port',
          );
          expect(badHostResp, startsWith('HTTP/1.1 403 Forbidden'));

          // Arbitrary /fonts/... paths still return 404.
          final String unknownFontResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}/fonts/arbitrary-font/svg.js',
            host: validHost,
          );
          expect(unknownFontResp, startsWith('HTTP/1.1 404 Not Found'));

          final String unknownSubfileResp = await _sendRawHttpRequest(
            port,
            path:
                '/s/${server.sessionToken}/fonts/mathjax-mhchem-font-extension/other.js',
            host: validHost,
          );
          expect(unknownSubfileResp, startsWith('HTTP/1.1 404 Not Found'));

          // Traversal attempts are still rejected.
          expect(
            server.resolveAssetFile(
              '/fonts/mathjax-mhchem-font-extension/..%2fsecret.txt',
            ),
            isNull,
          );
          final String traversalResp = await _sendRawHttpRequest(
            port,
            path:
                '/s/${server.sessionToken}/fonts/mathjax-mhchem-font-extension/..%2fsecret.txt',
            host: validHost,
          );
          expect(traversalResp, startsWith('HTTP/1.1 404 Not Found'));

          // If a real extension file exists on disk, serve its bytes instead of the stub.
          final File realMhchemFontExt = File(
            '${assets.nodeModulesDir.path}/@mathjax/mathjax-mhchem-font-extension/svg.js',
          )..createSync(recursive: true);
          realMhchemFontExt.writeAsStringSync('// real mhchem font ext');

          final String realResp = await _sendRawHttpRequest(
            port,
            path: '/s/${server.sessionToken}${stubPaths.first}',
            host: validHost,
          );
          expect(realResp, startsWith('HTTP/1.1 200 OK'));
          expect(realResp, contains('// real mhchem font ext'));
          expect(
            realResp,
            isNot(
              contains('Offline stub for optional MathJax font extension.'),
            ),
          );
        } finally {
          await server.close();
        }
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
        expect(html, contains('failed: (err) =>'));
        expect(html, contains('reportStartupError'));
        expect(html, contains("type: 'startupError'"));
        expect(html, contains('unhandledrejection'));
        expect(html, contains('enableMenu: false'));
        expect(html, contains('enableEnrichment: false'));
        expect(html, contains('enableComplexity: false'));
        expect(html, contains('enableSpeech: false'));
        expect(html, contains('enableBraille: false'));
        expect(html, contains('enableExplorer: false'));
        expect(html, contains('menuOptions:'));
        expect(html, contains('enrich: false'));
        expect(html, contains('speech: false'));
        expect(
          html,
          contains(
            "onerror=\"reportStartupError('Failed to load local MathJax bundle (tex-svg.js).')\"",
          ),
        );

        final String katexHtml = StudioWebHarnessBuilder.buildKatexHtml(
          origin: 'http://127.0.0.1:9999',
          sessionToken: 'tok123',
        );
        expect(katexHtml, contains('reportStartupError'));
        expect(katexHtml, contains("type: 'startupError'"));
        expect(
          katexHtml,
          contains(
            "onerror=\"reportStartupError('Failed to load local KaTeX bundle (katex.min.js).')\"",
          ),
        );
      },
    );

    test('StudioWebHarnessBuilder centers with margin auto and pins regular KaTeX_Math-Italic weight', () {
      String cssRuleBody(String html, String selector) {
        final RegExp pattern = RegExp(
          '${RegExp.escape(selector)}\\s*\\{([^}]*)\\}',
        );
        final RegExpMatch? match = pattern.firstMatch(html);
        expect(
          match,
          isNotNull,
          reason: 'Expected CSS rule for $selector in harness HTML',
        );
        return match!.group(1)!;
      }

      final String mathJaxHtml = StudioWebHarnessBuilder.buildMathJaxHtml(
        origin: 'http://127.0.0.1:9999',
        sessionToken: 'tok123',
      );
      final String katexHtml = StudioWebHarnessBuilder.buildKatexHtml(
        origin: 'http://127.0.0.1:9999',
        sessionToken: 'tok123',
      );

      for (final String html in <String>[mathJaxHtml, katexHtml]) {
        final String stageCss = cssRuleBody(html, '#stage');
        expect(stageCss, contains('display: flex;'));
        expect(stageCss, contains('padding: 4px;'));
        expect(stageCss, contains('overflow: auto;'));
        expect(stageCss, isNot(contains('justify-content: center;')));
        expect(stageCss, isNot(contains('align-items: center;')));

        final String mathOutCss = cssRuleBody(html, '#math-out');
        expect(mathOutCss, contains('margin: auto;'));

        final String errorBoxCss = cssRuleBody(html, '#error-box');
        expect(errorBoxCss, contains('margin: auto;'));
      }

      expect(mathJaxHtml, contains('syncMathJaxStylesheet'));
      expect(mathJaxHtml, contains('MathJax.svgStylesheet'));
      expect(mathJaxHtml, contains('MJX-SVG-styles'));

      final String katexBodyCss = cssRuleBody(katexHtml, 'html, body');
      expect(katexBodyCss, contains('-webkit-font-smoothing: antialiased;'));

      final int cssLinkIndex = katexHtml.indexOf(
        '<link rel="stylesheet" href="http://127.0.0.1:9999/s/tok123/katex/katex.min.css">',
      );
      final int fontFaceIndex = katexHtml.indexOf(
        "font-family: 'StudioKaTeXMathItalic';",
      );
      expect(cssLinkIndex, greaterThanOrEqualTo(0));
      expect(fontFaceIndex, greaterThan(cssLinkIndex));

      final String fontFaceCss = cssRuleBody(katexHtml, '@font-face');
      expect(fontFaceCss, contains("font-family: 'StudioKaTeXMathItalic';"));
      expect(fontFaceCss, contains('font-style: italic;'));
      expect(fontFaceCss, contains('font-weight: 400;'));
      expect(
        fontFaceCss,
        contains(
          "url('http://127.0.0.1:9999/s/tok123/katex/fonts/KaTeX_Math-Italic.woff2') format('woff2')",
        ),
      );

      final String mathNormalCss = cssRuleBody(katexHtml, '.katex .mathnormal');
      expect(
        mathNormalCss,
        contains("font-family: 'StudioKaTeXMathItalic', KaTeX_Math;"),
      );
      expect(mathNormalCss, contains('font-style: italic;'));
      expect(mathNormalCss, contains('font-weight: 400;'));
      expect(mathNormalCss, contains('font-synthesis: none;'));
      expect(katexHtml, isNot(contains('.boldsymbol')));
    });

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

        // startupError resets readiness, clears SVG, and surfaces Harness error.
        ctrl.handleBridgePayload(
          jsonEncode(<String, Object?>{
            'type': 'startupError',
            'errorMessage': 'loader boom',
          }),
        );
        expect(ctrl.telemetry.value.isReady, isFalse);
        expect(ctrl.telemetry.value.isRendering, isFalse);
        expect(ctrl.telemetry.value.svgXml, isNull);
        expect(ctrl.telemetry.value.statusSummary, 'Harness error');
        expect(ctrl.telemetry.value.errorMessage, 'loader boom');

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

    testWidgets(
      'navigates corpus entries via ArrowDown/ArrowUp/Home/End across headers and clamps at boundaries',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StudioCorpusCatalog catalog =
            StudioCorpusCatalog.embeddedFallback();
        await tester.pumpWidget(
          TexMathStudioApp(corpusCatalog: catalog, initialFont: loadedFont),
        );
        await tester.pumpAndSettle();

        String sourceText() {
          final TextField field = tester.widget<TextField>(
            find.widgetWithText(TextField, 'TeX Source'),
          );
          return field.controller!.text;
        }

        // Tap the first corpus entry ("fraction_basic") to select and focus list.
        await tester.tap(find.text('fraction_basic'));
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[0].tex);
        expect(find.byType(TexMath), findsOneWidget);

        // Clamping at top: ArrowUp at first entry stays at first entry.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[0].tex);

        // ArrowDown steps through Tier 1 and crosses the Tier 2 group header.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[1].tex);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[2].tex);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[3].tex);

        // ArrowUp steps back across the Tier 2 header into Tier 1.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries[2].tex);

        // End jumps to the last entry (Errors -> TexMathErrorWidget).
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries.last.tex);
        expect(find.byType(TexMathErrorWidget), findsOneWidget);

        // Clamping at bottom: ArrowDown at last entry stays at last entry.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries.last.tex);
        expect(find.byType(TexMathErrorWidget), findsOneWidget);

        // Home jumps back to the first entry.
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(sourceText(), catalog.entries.first.tex);
        expect(find.byType(TexMath), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsNothing);
      },
    );

    testWidgets(
      'keyboard-focused corpus ListTile navigates to next entry on ArrowDown without tapping',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StudioCorpusCatalog catalog =
            StudioCorpusCatalog.embeddedFallback();
        await tester.pumpWidget(
          TexMathStudioApp(corpusCatalog: catalog, initialFont: loadedFont),
        );
        await tester.pumpAndSettle();

        // Focus the 2nd tile ("gaussian_integral") via FocusNode without tapping.
        final FocusNode tileFocus = Focus.of(
          tester.element(find.text('gaussian_integral')),
        );
        tileFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(tileFocus.hasPrimaryFocus, isTrue);

        // Focusing alone should not have changed selection from default preset.
        final TextField sourceField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'TeX Source'),
        );
        expect(sourceField.controller!.text, r'\frac{a + b}{c - d}');

        // Pressing ArrowDown selects the entry after the focused tile ("identity_matrix").
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, catalog.entries[2].tex);
      },
    );

    testWidgets(
      'ArrowDown inside TeX Source or Filter corpus TextField does not alter corpus selection',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StudioCorpusCatalog catalog =
            StudioCorpusCatalog.embeddedFallback();
        await tester.pumpWidget(
          TexMathStudioApp(corpusCatalog: catalog, initialFont: loadedFont),
        );
        await tester.pumpAndSettle();

        // Select first corpus entry so a baseline selection exists.
        await tester.tap(find.text('fraction_basic'));
        await tester.pumpAndSettle();
        final TextField sourceField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'TeX Source'),
        );
        expect(sourceField.controller!.text, catalog.entries[0].tex);

        // Focus TeX Source and press ArrowDown -> selection must remain unchanged.
        await tester.tap(find.widgetWithText(TextField, 'TeX Source'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, catalog.entries[0].tex);

        // Focus Filter corpus… and press ArrowDown -> selection must remain unchanged.
        await tester.tap(find.widgetWithText(TextField, 'Filter corpus…'));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, catalog.entries[0].tex);
      },
    );

    testWidgets(
      'auto-scrolls tall multi-group corpus sidebar cleanly via ArrowDown, PageDown, End, and Home',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<StudioCorpusEntry> entries = <StudioCorpusEntry>[
          for (int i = 0; i < 20; i++)
            StudioCorpusEntry(
              id: 'tier1_core/base/case_${i.toString().padLeft(2, '0')}',
              relativePath: 'corpus/tier1_core/base/case_$i.tex',
              tier: 'Tier 1',
              package: 'base',
              feature: 'basic',
              display: true,
              accepted: true,
              tex: 'x_{$i} + 1',
            ),
          for (int i = 20; i < 40; i++)
            StudioCorpusEntry(
              id: 'tier2_jupyter/ams/case_${i.toString().padLeft(2, '0')}',
              relativePath: 'corpus/tier2_jupyter/ams/case_$i.tex',
              tier: 'Tier 2',
              package: 'ams',
              feature: 'matrices',
              display: true,
              accepted: true,
              tex: 'y_{$i} + 2',
            ),
          for (int i = 40; i < 50; i++)
            StudioCorpusEntry(
              id: 'errors/err_${i.toString().padLeft(2, '0')}',
              relativePath: 'corpus/errors/err_$i.tex',
              tier: 'Errors',
              package: 'base',
              feature: 'error',
              display: true,
              accepted: false,
              errorClass: 'undefinedControlSequence',
              tex: '\\unknowncmd$i',
            ),
        ];

        final StudioCorpusCatalog tallCatalog = StudioCorpusCatalog(
          entries: entries,
          isFromDisk: true,
        );

        await tester.pumpWidget(
          TexMathStudioApp(corpusCatalog: tallCatalog, initialFont: loadedFont),
        );
        await tester.pumpAndSettle();

        final TextField sourceField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'TeX Source'),
        );

        // Last entry is far off-screen initially.
        expect(find.text('err_49'), findsNothing);

        // Tap first entry, then press ArrowDown 15 times to scroll past viewport.
        await tester.tap(find.text('case_00'));
        await tester.pumpAndSettle();
        for (int i = 0; i < 15; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(sourceField.controller!.text, entries[15].tex);
        expect(find.text('case_15'), findsOneWidget);

        // Verify selected tile sits inside the ListView viewport bounds.
        final Rect listRect = tester.getRect(find.byType(ListView));
        final Rect tile15Rect = tester.getRect(
          find.ancestor(
            of: find.text('case_15'),
            matching: find.byType(ListTile),
          ),
        );
        expect(tile15Rect.top, greaterThanOrEqualTo(listRect.top - 0.5));
        expect(tile15Rect.bottom, lessThanOrEqualTo(listRect.bottom + 0.5));

        // PageDown (+10 -> index 25, crossing into Tier 2).
        await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, entries[25].tex);
        expect(find.text('case_25'), findsOneWidget);

        // PageUp (-10 -> back to index 15 in Tier 1).
        await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, entries[15].tex);
        expect(find.text('case_15'), findsOneWidget);

        // End jumps to the far off-screen last entry and scrolls it into view.
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, entries.last.tex);
        expect(find.text('err_49'), findsOneWidget);
        expect(find.byType(TexMathErrorWidget), findsOneWidget);
        final Rect tileLastRect = tester.getRect(
          find.ancestor(
            of: find.text('err_49'),
            matching: find.byType(ListTile),
          ),
        );
        expect(tileLastRect.top, greaterThanOrEqualTo(listRect.top - 0.5));
        expect(tileLastRect.bottom, lessThanOrEqualTo(listRect.bottom + 0.5));

        // Home jumps back to the first entry and scrolls back to the top.
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pumpAndSettle();
        expect(sourceField.controller!.text, entries.first.tex);
        expect(find.text('case_00'), findsOneWidget);
        expect(find.byType(TexMath), findsOneWidget);
        final Rect tileFirstRect = tester.getRect(
          find.ancestor(
            of: find.text('case_00'),
            matching: find.byType(ListTile),
          ),
        );
        expect(tileFirstRect.top, greaterThanOrEqualTo(listRect.top - 0.5));
        expect(tileFirstRect.bottom, lessThanOrEqualTo(listRect.bottom + 0.5));
      },
    );

    testWidgets(
      'StudioMetricsInspector displays error position, span, and caret source snippet',
      (WidgetTester tester) async {
        const String failingSource = "x^2'";
        final StudioInspectionResult result = inspectTexExpression(
          source: failingSource,
          displayMode: TexMathDisplayMode.display,
          font: loadedFont,
        );
        expect(result, isA<StudioInspectionFailure>());
        final StudioInspectionFailure failure =
            result as StudioInspectionFailure;
        expect(failure.source, failingSource);
        expect(failure.error.errorClass, TexMathErrorClass.doubleScript);
        expect(failure.error.position, 4);
        expect(failure.error.span, const SourceSpan(3, 4));

        final StudioInspectionFailure sameFailure = StudioInspectionFailure(
          error: failure.error,
          source: failingSource,
        );
        final StudioInspectionFailure otherSourceFailure =
            StudioInspectionFailure(error: failure.error, source: 'y^2\'');
        expect(failure, sameFailure);
        expect(failure.hashCode, sameFailure.hashCode);
        expect(failure, isNot(otherSourceFailure));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StudioMetricsInspector(inspection: failure)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Error Class: doubleScript'), findsOneWidget);
        expect(find.text('Position: 4 (span 3..4)'), findsOneWidget);
        expect(find.textContaining('(at position 4)'), findsOneWidget);
        final String expectedSnippet = failure.error.formatWithSource(
          failingSource,
        );
        expect(expectedSnippet, contains("x^2'\n   ^"));
        final Finder snippetFinder = find.text(expectedSnippet);
        expect(snippetFinder, findsOneWidget);
        final SelectableText snippetWidget = tester.widget<SelectableText>(
          find.ancestor(
            of: snippetFinder,
            matching: find.byType(SelectableText),
          ),
        );
        expect(snippetWidget.style?.fontFamily, 'monospace');

        // Without source, formattedMessage and Position still appear without caret snippet.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StudioMetricsInspector(
                inspection: StudioInspectionFailure(error: failure.error),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Position: 4 (span 3..4)'), findsOneWidget);
        expect(find.text(failure.error.formattedMessage), findsOneWidget);
        expect(find.textContaining("x^2'\n   ^"), findsNothing);

        // Without span, Position and "(at position ...)" are omitted.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StudioMetricsInspector(
                inspection: StudioInspectionFailure(
                  error: const TexMathFontError('Empty font'),
                  source: 'x',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Error Class: invalidFont'), findsOneWidget);
        expect(find.text('Empty font'), findsOneWidget);
        expect(find.textContaining('Position:'), findsNothing);
        expect(find.textContaining('(at position'), findsNothing);
      },
    );

    testWidgets(
      "TexMathStudioApp on x^2' displays Position: 4, (at position 4), and caret snippet",
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          TexMathStudioApp(
            corpusCatalog: StudioCorpusCatalog.embeddedFallback(),
            initialFont: loadedFont,
            initialSource: "x^2'",
            webPaneControllerFactory: (StudioEngineKind kind, _) {
              return _FakeWebPaneController(engineKind: kind);
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TexMathErrorWidget), findsOneWidget);

        final Finder inspector = find.byType(StudioMetricsInspector);
        expect(inspector, findsOneWidget);
        expect(
          find.descendant(
            of: inspector,
            matching: find.text('Error Class: doubleScript'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: inspector,
            matching: find.text('Position: 4 (span 3..4)'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: inspector,
            matching: find.textContaining('(at position 4)'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: inspector,
            matching: find.textContaining("x^2'\n   ^"),
          ),
          findsOneWidget,
        );
      },
    );
  });
}
