import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:tex_math/tex_math.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'corpus_loader.dart';

/// Comparison web engine hosted inside a `WKWebView` comparison pane.
enum StudioEngineKind {
  /// MathJax `4.1.3` SVG output with `mathjax-newcm`.
  mathJax('MathJax 4.1.3 Oracle'),

  /// KaTeX `0.19.1` reference comparison pane.
  katex('KaTeX 0.19.1 Comparison');

  const StudioEngineKind(this.title);

  /// Display title shown in the studio pane header.
  final String title;
}

/// Parameters dispatched to a web comparison pane on every TeX/theme change.
@immutable
final class StudioWebRenderRequest {
  /// Creates an immutable web render request.
  const StudioWebRenderRequest({
    required this.source,
    required this.displayMode,
    required this.isDarkTheme,
    this.fontSize = 22.0,
    this.packages,
  });

  /// TeX expression source string.
  final String source;

  /// Active TeX display vs inline typesetting mode.
  final TexMathDisplayMode displayMode;

  /// Whether the active studio surface uses dark theme colors.
  final bool isDarkTheme;

  /// Base CSS font size in logical pixels.
  final double fontSize;

  /// Optional MathJax package list from corpus metadata.
  final List<String>? packages;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioWebRenderRequest &&
          source == other.source &&
          displayMode == other.displayMode &&
          isDarkTheme == other.isDarkTheme &&
          fontSize == other.fontSize &&
          listEquals(packages, other.packages);

  @override
  int get hashCode => Object.hash(
    source,
    displayMode,
    isDarkTheme,
    fontSize,
    packages == null ? null : Object.hashAll(packages!),
  );
}

/// Live status and geometry telemetry reported back from a web comparison pane.
@immutable
final class StudioWebRenderTelemetry {
  /// Creates an immutable telemetry snapshot.
  const StudioWebRenderTelemetry({
    required this.engineKind,
    this.isReady = false,
    this.isRendering = false,
    this.errorMessage,
    this.svgXml,
    this.widthPx,
    this.heightPx,
    this.renderTimeMs,
    this.assetsAvailable = true,
    this.statusSummary = 'Initializing…',
  });

  /// Target comparison engine.
  final StudioEngineKind engineKind;

  /// Whether the embedded web harness has finished initializing.
  final bool isReady;

  /// Whether a render pass is currently running in the web view.
  final bool isRendering;

  /// Diagnostic error message reported by MathJax/KaTeX or asset loading.
  final String? errorMessage;

  /// Serialized SVG markup produced by the web engine when available.
  final String? svgXml;

  /// Rendered DOM bounding box width in CSS pixels.
  final double? widthPx;

  /// Rendered DOM bounding box height in CSS pixels.
  final double? heightPx;

  /// Client-side render duration in milliseconds.
  final double? renderTimeMs;

  /// Whether local `tool/oracle/node_modules/` assets were located on disk.
  final bool assetsAvailable;

  /// Short human-readable status message.
  final String statusSummary;

  /// Returns a copy of this telemetry record with selected overrides.
  StudioWebRenderTelemetry copyWith({
    bool? isReady,
    bool? isRendering,
    String? errorMessage,
    bool clearError = false,
    String? svgXml,
    bool clearSvg = false,
    double? widthPx,
    double? heightPx,
    double? renderTimeMs,
    bool? assetsAvailable,
    String? statusSummary,
  }) {
    return StudioWebRenderTelemetry(
      engineKind: engineKind,
      isReady: isReady ?? this.isReady,
      isRendering: isRendering ?? this.isRendering,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      svgXml: clearSvg ? null : (svgXml ?? this.svgXml),
      widthPx: widthPx ?? this.widthPx,
      heightPx: heightPx ?? this.heightPx,
      renderTimeMs: renderTimeMs ?? this.renderTimeMs,
      assetsAvailable: assetsAvailable ?? this.assetsAvailable,
      statusSummary: statusSummary ?? this.statusSummary,
    );
  }
}

/// Raw RGBA pixel capture of a rendered pane used by pixel and curtain diffs.
@immutable
final class StudioCapturedImage {
  /// Creates an RGBA capture record validating exact byte buffer length.
  StudioCapturedImage({
    required this.width,
    required this.height,
    required this.rgbaBytes,
  }) : assert(width >= 0, 'width must be non-negative'),
       assert(height >= 0, 'height must be non-negative'),
       assert(
         rgbaBytes.length == width * height * 4,
         'rgbaBytes length must equal width * height * 4',
       );

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Packed RGBA8888 pixel buffer (`width * height * 4` bytes).
  final Uint8List rgbaBytes;
}

/// Resolved filesystem handles for MathJax `4.1.3` and KaTeX `0.19.1` bundles
/// installed inside `tool/oracle/node_modules/`.
@immutable
final class StudioOracleAssets {
  /// Creates an oracle asset descriptor.
  const StudioOracleAssets({
    required this.nodeModulesDir,
    this.mathJaxBundleFile,
    this.mathJaxDir,
    this.mathJaxNewcmDynamicDir,
    this.katexDistDir,
    this.katexJsFile,
    this.katexCssFile,
    this.katexMhchemJsFile,
  });

  /// Root `tool/oracle/node_modules` directory.
  final Directory nodeModulesDir;

  /// `mathjax/tex-svg.js` browser bundle file.
  final File? mathJaxBundleFile;

  /// `mathjax/` directory containing TeX extensions.
  final Directory? mathJaxDir;

  /// `@mathjax/mathjax-newcm-font/svg/dynamic/` directory for dynamic font chunks.
  final Directory? mathJaxNewcmDynamicDir;

  /// `katex/dist/` directory containing JS, CSS, and font files.
  final Directory? katexDistDir;

  /// `katex/dist/katex.min.js`.
  final File? katexJsFile;

  /// `katex/dist/katex.min.css`.
  final File? katexCssFile;

  /// `katex/dist/contrib/mhchem.min.js`.
  final File? katexMhchemJsFile;

  /// Whether MathJax `4.1.3` browser assets are present on disk.
  bool get hasMathJax =>
      mathJaxBundleFile != null && mathJaxBundleFile!.existsSync();

  /// Whether KaTeX `0.19.1` browser assets are present on disk.
  bool get hasKatex =>
      katexJsFile != null &&
      katexCssFile != null &&
      katexJsFile!.existsSync() &&
      katexCssFile!.existsSync();
}

/// Locates third-party JS/font assets under `tool/oracle/node_modules/` relative
/// to the active working directory without hardcoding private filesystem paths.
final class StudioOracleAssetLocator {
  const StudioOracleAssetLocator._();

  /// Searches relative to [startDirectory] (defaulting to [Directory.current])
  /// for `tool/oracle/node_modules/`. Returns `null` when unavailable.
  static StudioOracleAssets? locate({Directory? startDirectory}) {
    final Directory? repoRoot = findRepositoryRoot(
      startDirectory: startDirectory,
    );
    if (repoRoot == null) {
      return null;
    }

    final String sep = Platform.pathSeparator;
    final Directory nodeModules = Directory(
      '${repoRoot.path}${sep}tool${sep}oracle${sep}node_modules',
    );
    if (!nodeModules.existsSync()) {
      return null;
    }

    final Directory mathJaxDir = Directory('${nodeModules.path}${sep}mathjax');
    final File mathJaxBundle = File('${mathJaxDir.path}${sep}tex-svg.js');
    final Directory mathJaxNewcmDynamic = Directory(
      '${nodeModules.path}$sep@mathjax${sep}mathjax-newcm-font'
      '${sep}svg${sep}dynamic',
    );

    final Directory katexDistDir = Directory(
      '${nodeModules.path}${sep}katex${sep}dist',
    );
    final File katexJs = File('${katexDistDir.path}${sep}katex.min.js');
    final File katexCss = File('${katexDistDir.path}${sep}katex.min.css');
    final File katexMhchem = File(
      '${katexDistDir.path}${sep}contrib${sep}mhchem.min.js',
    );

    return StudioOracleAssets(
      nodeModulesDir: nodeModules,
      mathJaxBundleFile: mathJaxBundle.existsSync() ? mathJaxBundle : null,
      mathJaxDir: mathJaxDir.existsSync() ? mathJaxDir : null,
      mathJaxNewcmDynamicDir: mathJaxNewcmDynamic.existsSync()
          ? mathJaxNewcmDynamic
          : null,
      katexDistDir: katexDistDir.existsSync() ? katexDistDir : null,
      katexJsFile: katexJs.existsSync() ? katexJs : null,
      katexCssFile: katexCss.existsSync() ? katexCss : null,
      katexMhchemJsFile: katexMhchem.existsSync() ? katexMhchem : null,
    );
  }
}

/// Builds offline HTML5 harnesses for rendering MathJax `4.1.3` and KaTeX
/// `0.19.1` inside a `WKWebView` served from loopback HTTP.
final class StudioWebHarnessBuilder {
  const StudioWebHarnessBuilder._();

  /// Default JupyterLab active MathJax TeX packages excluding `noerrors` and
  /// `noundefined`.
  static const List<String> defaultMathJaxPackages = <String>[
    'base',
    'action',
    'ams',
    'amscd',
    'bbox',
    'boldsymbol',
    'braket',
    'bussproofs',
    'cancel',
    'cases',
    'centernot',
    'color',
    'colortbl',
    'empheq',
    'enclose',
    'extpfeil',
    'gensymb',
    'html',
    'mathtools',
    'mhchem',
    'newcommand',
    'upgreek',
    'unicode',
    'verb',
    'configmacros',
    'tagformat',
    'textcomp',
    'textmacros',
    'require',
  ];

  /// Generates the MathJax `4.1.3` SVG HTML harness page.
  static String buildMathJaxHtml({required String origin}) {
    final String defaultPackagesJson = jsonEncode(defaultMathJaxPackages);
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  :root { --fg: #111827; --bg: #ffffff; --err-fg: #dc2626; --err-bg: #fef2f2; }
  html, body {
    margin: 0; padding: 0; width: 100%; height: 100%;
    background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  }
  #stage {
    box-sizing: border-box;
    min-height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    overflow: auto;
  }
  #math-out {
    display: inline-block;
    color: var(--fg);
  }
  #error-box {
    display: none;
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid rgba(220, 38, 38, 0.45);
    background: var(--err-bg);
    color: var(--err-fg);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    white-space: pre-wrap;
    max-width: 100%;
  }
</style>
<script>
window.__mjReady = false;
window.__pendingRender = null;
window.__currentFg = '#111827';
window.__currentBg = '#ffffff';
window.__defaultPackages = $defaultPackagesJson;

function postBridge(payload) {
  if (window.StudioBridge && typeof window.StudioBridge.postMessage === 'function') {
    window.StudioBridge.postMessage(JSON.stringify(payload));
  }
}

window.MathJax = {
  loader: {
    paths: {
      mathjax: '$origin/mathjax',
      tex: '[mathjax]/input/tex/extensions'
    },
    load: window.__defaultPackages.filter(p => p !== 'base').map(p => '[tex]/' + p)
  },
  tex: {
    packages: window.__defaultPackages.slice(),
    formatError: (jax, err) => { throw err; }
  },
  svg: {
    fontCache: 'local'
  },
  startup: {
    typeset: false,
    ready: () => {
      MathJax.startup.defaultReady();
      window.__mjReady = true;
      postBridge({ type: 'ready' });
      if (window.__pendingRender) {
        const next = window.__pendingRender;
        window.__pendingRender = null;
        window.studioRender(next);
      }
    }
  }
};

window.studioRender = async function(req) {
  if (!window.__mjReady) {
    window.__pendingRender = req;
    return;
  }
  const t0 = performance.now();
  const stage = document.getElementById('stage');
  const out = document.getElementById('math-out');
  const errBox = document.getElementById('error-box');

  const fg = req.dark ? '#f8fafc' : '#111827';
  const bg = req.dark ? '#0f172a' : '#ffffff';
  window.__currentFg = fg;
  window.__currentBg = bg;
  document.documentElement.style.setProperty('--fg', fg);
  document.documentElement.style.setProperty('--bg', bg);
  document.documentElement.style.setProperty('--err-bg', req.dark ? 'rgba(220,38,38,0.16)' : '#fef2f2');
  out.style.fontSize = (req.fontSize || 22) + 'px';

  const targetPackages = Array.isArray(req.packages) && req.packages.length > 0
    ? req.packages
    : window.__defaultPackages;

  try {
    const toLoad = targetPackages
      .filter(p => p !== 'base')
      .map(p => '[tex]/' + p);
    await MathJax.loader.load(...toLoad);

    const prevPackages = (MathJax.config.tex && MathJax.config.tex.packages) || [];
    if (JSON.stringify(prevPackages) !== JSON.stringify(targetPackages)) {
      MathJax.config.tex.packages = targetPackages.slice();
      if (targetPackages.includes('noerrors')) {
        MathJax.config.tex.formatError = (jax, err) => jax.formatError(err);
      } else {
        MathJax.config.tex.formatError = (jax, err) => { throw err; };
      }
      MathJax.startup.getComponents();
      MathJax.startup.makeMethods();
    }

    if (typeof MathJax.texReset === 'function') {
      MathJax.texReset();
    }
    const wrapper = await MathJax.tex2svgPromise(req.source || '', { display: !!req.display });
    const svg = wrapper.querySelector('svg');
    out.innerHTML = '';
    out.appendChild(wrapper);
    errBox.style.display = 'none';
    out.style.display = 'inline-block';

    const rect = (svg || out).getBoundingClientRect();
    const svgXml = svg ? new XMLSerializer().serializeToString(svg) : '';
    postBridge({
      type: 'rendered',
      svgXml: svgXml,
      widthPx: rect.width,
      heightPx: rect.height,
      renderTimeMs: performance.now() - t0
    });
  } catch (err) {
    out.innerHTML = '';
    out.style.display = 'none';
    const message = err && err.message ? String(err.message) : String(err);
    errBox.textContent = message;
    errBox.style.display = 'block';
    postBridge({
      type: 'error',
      errorMessage: message,
      renderTimeMs: performance.now() - t0
    });
  }
};

window.studioRequestCapture = function(requestId, targetW, targetH) {
  window.studioCapturePng(targetW, targetH)
    .then((dataUrl) => postBridge({ type: 'capture', requestId: requestId, dataUrl: dataUrl || '' }))
    .catch(() => postBridge({ type: 'capture', requestId: requestId, dataUrl: '' }));
};

window.studioCapturePng = function(targetW, targetH) {
  return new Promise((resolve) => {
    const svg = document.querySelector('#math-out svg');
    if (!svg) {
      resolve('');
      return;
    }
    const w = Math.max(1, targetW | 0);
    const h = Math.max(1, targetH | 0);
    const clone = svg.cloneNode(true);
    clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');

    const rect = svg.getBoundingClientRect();
    const drawW = Math.max(1, rect.width || w);
    const drawH = Math.max(1, rect.height || h);
    const scale = Math.min((w - 24) / drawW, (h - 24) / drawH, 2.0);
    const outW = Math.max(1, drawW * scale);
    const outH = Math.max(1, drawH * scale);
    clone.setAttribute('width', String(outW));
    clone.setAttribute('height', String(outH));

    let serialized = new XMLSerializer().serializeToString(clone);
    serialized = serialized.replaceAll('currentColor', window.__currentFg || '#111827');

    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = window.__currentBg || '#ffffff';
      ctx.fillRect(0, 0, w, h);
      const dx = Math.round((w - outW) / 2);
      const dy = Math.round((h - outH) / 2);
      ctx.drawImage(img, dx, dy, outW, outH);
      resolve(canvas.toDataURL('image/png'));
    };
    img.onerror = () => resolve('');
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(serialized);
  });
};
</script>
<script src="$origin/mathjax/tex-svg.js"></script>
</head>
<body>
  <div id="stage">
    <div id="math-out"></div>
    <pre id="error-box"></pre>
  </div>
</body>
</html>''';
  }

  /// Generates the KaTeX `0.19.1` HTML harness page.
  static String buildKatexHtml({required String origin}) {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="$origin/katex/katex.min.css">
<style>
  :root { --fg: #111827; --bg: #ffffff; --err-fg: #dc2626; --err-bg: #fef2f2; }
  html, body {
    margin: 0; padding: 0; width: 100%; height: 100%;
    background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  }
  #stage {
    box-sizing: border-box;
    min-height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    overflow: auto;
  }
  #math-out {
    display: inline-block;
    color: var(--fg);
  }
  #error-box {
    display: none;
    padding: 10px 12px;
    border-radius: 6px;
    border: 1px solid rgba(220, 38, 38, 0.45);
    background: var(--err-bg);
    color: var(--err-fg);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    white-space: pre-wrap;
    max-width: 100%;
  }
</style>
<script src="$origin/katex/katex.min.js"></script>
<script src="$origin/katex/contrib/mhchem.min.js"></script>
<script>
window.__currentFg = '#111827';
window.__currentBg = '#ffffff';

function postBridge(payload) {
  if (window.StudioBridge && typeof window.StudioBridge.postMessage === 'function') {
    window.StudioBridge.postMessage(JSON.stringify(payload));
  }
}

window.studioRender = function(req) {
  const t0 = performance.now();
  const out = document.getElementById('math-out');
  const errBox = document.getElementById('error-box');
  const fg = req.dark ? '#f8fafc' : '#111827';
  const bg = req.dark ? '#0f172a' : '#ffffff';
  window.__currentFg = fg;
  window.__currentBg = bg;
  document.documentElement.style.setProperty('--fg', fg);
  document.documentElement.style.setProperty('--bg', bg);
  document.documentElement.style.setProperty('--err-bg', req.dark ? 'rgba(220,38,38,0.16)' : '#fef2f2');
  out.style.fontSize = (req.fontSize || 22) + 'px';

  try {
    katex.render(req.source || '', out, {
      displayMode: !!req.display,
      throwOnError: true,
      strict: false,
      trust: false
    });
    errBox.style.display = 'none';
    out.style.display = 'inline-block';
    const rect = out.getBoundingClientRect();
    postBridge({
      type: 'rendered',
      widthPx: rect.width,
      heightPx: rect.height,
      renderTimeMs: performance.now() - t0
    });
  } catch (err) {
    out.innerHTML = '';
    out.style.display = 'none';
    const message = err && err.message ? String(err.message) : String(err);
    errBox.textContent = message;
    errBox.style.display = 'block';
    postBridge({
      type: 'error',
      errorMessage: message,
      renderTimeMs: performance.now() - t0
    });
  }
};

window.studioRequestCapture = function(requestId, targetW, targetH) {
  window.studioCapturePng(targetW, targetH)
    .then((dataUrl) => postBridge({ type: 'capture', requestId: requestId, dataUrl: dataUrl || '' }))
    .catch(() => postBridge({ type: 'capture', requestId: requestId, dataUrl: '' }));
};

window.studioCapturePng = function(targetW, targetH) {
  return new Promise((resolve) => {
    const out = document.getElementById('math-out');
    if (!out || out.style.display === 'none') {
      resolve('');
      return;
    }
    const w = Math.max(1, targetW | 0);
    const h = Math.max(1, targetH | 0);
    const rect = out.getBoundingClientRect();
    const html = '<div xmlns="http://www.w3.org/1999/xhtml" style="width:' + w + 'px;height:' + h +
      'px;display:flex;align-items:center;justify-content:center;color:' + (window.__currentFg || '#111827') +
      ';background:' + (window.__currentBg || '#ffffff') + ';font-size:' + (out.style.fontSize || '22px') + ';">' +
      out.innerHTML + '</div>';
    const svgDoc = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '">' +
      '<foreignObject width="100%" height="100%">' + html + '</foreignObject></svg>';
    const img = new Image();
    img.onload = () => {
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = window.__currentBg || '#ffffff';
      ctx.fillRect(0, 0, w, h);
      ctx.drawImage(img, 0, 0, w, h);
      resolve(canvas.toDataURL('image/png'));
    };
    img.onerror = () => {
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = window.__currentBg || '#ffffff';
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = window.__currentFg || '#111827';
      ctx.font = '14px monospace';
      ctx.textAlign = 'center';
      ctx.fillText('KaTeX (' + Math.round(rect.width) + 'x' + Math.round(rect.height) + ')', w / 2, h / 2);
      resolve(canvas.toDataURL('image/png'));
    };
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svgDoc);
  });
};

window.addEventListener('load', () => {
  postBridge({ type: 'ready' });
});
</script>
</head>
<body>
  <div id="stage">
    <div id="math-out"></div>
    <pre id="error-box"></pre>
  </div>
</body>
</html>''';
  }
}

/// Loopback HTTP server serving local MathJax `4.1.3` and KaTeX `0.19.1` JS,
/// CSS, font, and HTML harness files from [assets] on an ephemeral port.
final class StudioLocalAssetServer {
  /// Creates an asset server backed by [assets].
  StudioLocalAssetServer(this.assets);

  /// Resolved MathJax and KaTeX filesystem bundles.
  final StudioOracleAssets assets;

  HttpServer? _server;
  int? _port;

  /// Bound loopback HTTP origin URL (`http://127.0.0.1:<port>`), or `null`
  /// before [start] completes.
  String? get origin => _port == null ? null : 'http://127.0.0.1:$_port';

  /// Whether the loopback server is actively listening.
  bool get isRunning => _server != null && _port != null;

  /// Starts listening on `127.0.0.1` using ephemeral port `0`.
  Future<String> start() async {
    if (_server != null && _port != null) {
      return origin!;
    }
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    _server = server;
    _port = server.port;
    unawaited(_serveRequests(server));
    return origin!;
  }

  Future<void> _serveRequests(HttpServer server) async {
    await for (final HttpRequest request in server) {
      try {
        await _handleRequest(request);
      } on Object {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // Ignore broken pipe when client disconnects early.
        }
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final String path = request.uri.path;
    final String activeOrigin = origin ?? 'http://127.0.0.1';

    if (path == '/mathjax-harness.html') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..write(StudioWebHarnessBuilder.buildMathJaxHtml(origin: activeOrigin));
      await request.response.close();
      return;
    }

    if (path == '/katex-harness.html') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..write(StudioWebHarnessBuilder.buildKatexHtml(origin: activeOrigin));
      await request.response.close();
      return;
    }

    final File? file = resolveAssetFile(path);
    if (file == null || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentTypeForPath(file.path)
      ..headers.set('Access-Control-Allow-Origin', '*');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  /// Resolves an HTTP request [requestPath] safely inside [assets], rejecting
  /// path-traversal segments.
  File? resolveAssetFile(String requestPath) {
    final String rawPath = requestPath.split('?').first.split('#').first;
    final List<String> rawSegments = rawPath
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .map(Uri.decodeComponent)
        .toList();
    if (rawSegments.isEmpty ||
        rawSegments.any(
          (String segment) =>
              segment == '..' || segment == '.' || segment.contains('\\'),
        )) {
      return null;
    }
    final List<String> segments = rawSegments;

    const List<String> mjDynamicJsPrefix = <String>[
      'mathjax',
      '@mathjax',
      'mathjax-newcm-font',
      'js',
      'svg',
      'dynamic',
    ];
    const List<String> mjDynamicPrefix = <String>[
      '@mathjax',
      'mathjax-newcm-font',
      'js',
      'svg',
      'dynamic',
    ];
    const List<String> fontsDynamicPrefix = <String>[
      'fonts',
      'mathjax-newcm-font',
      'svg',
      'dynamic',
    ];

    if (_startsWithSegments(segments, mjDynamicJsPrefix) &&
        assets.mathJaxNewcmDynamicDir != null) {
      return _safeChildFile(
        assets.mathJaxNewcmDynamicDir!,
        segments.sublist(mjDynamicJsPrefix.length),
      );
    }
    if (_startsWithSegments(segments, mjDynamicPrefix) &&
        assets.mathJaxNewcmDynamicDir != null) {
      return _safeChildFile(
        assets.mathJaxNewcmDynamicDir!,
        segments.sublist(mjDynamicPrefix.length),
      );
    }
    if (_startsWithSegments(segments, fontsDynamicPrefix) &&
        assets.mathJaxNewcmDynamicDir != null) {
      return _safeChildFile(
        assets.mathJaxNewcmDynamicDir!,
        segments.sublist(fontsDynamicPrefix.length),
      );
    }

    if (segments.first == 'mathjax' && assets.mathJaxDir != null) {
      return _safeChildFile(assets.mathJaxDir!, segments.sublist(1));
    }

    if (segments.first == 'katex' && assets.katexDistDir != null) {
      return _safeChildFile(assets.katexDistDir!, segments.sublist(1));
    }

    return null;
  }

  static bool _startsWithSegments(List<String> segments, List<String> prefix) {
    if (segments.length <= prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if (segments[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  static File? _safeChildFile(Directory root, List<String> tailSegments) {
    if (tailSegments.isEmpty) {
      return null;
    }
    final String sep = Platform.pathSeparator;
    final String candidatePath = '${root.path}$sep${tailSegments.join(sep)}';
    final File file = File(candidatePath);
    final String rootNorm = root.absolute.path.replaceAll('\\', '/');
    final String fileNorm = file.absolute.path.replaceAll('\\', '/');
    if (!fileNorm.startsWith('$rootNorm/')) {
      return null;
    }
    return file;
  }

  static ContentType _contentTypeForPath(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (lower.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
    if (lower.endsWith('.html')) {
      return ContentType.html;
    }
    if (lower.endsWith('.svg')) {
      return ContentType('image', 'svg+xml', charset: 'utf-8');
    }
    if (lower.endsWith('.woff2')) {
      return ContentType('font', 'woff2');
    }
    if (lower.endsWith('.woff')) {
      return ContentType('font', 'woff');
    }
    if (lower.endsWith('.ttf')) {
      return ContentType('font', 'ttf');
    }
    return ContentType.binary;
  }

  /// Shuts down the loopback HTTP server.
  Future<void> close() async {
    final HttpServer? server = _server;
    _server = null;
    _port = null;
    if (server != null) {
      await server.close(force: true);
    }
  }
}

/// Abstract pane controller interface enabling headless `flutter test`
/// verification without instantiating platform `WebViewWidget` views.
abstract interface class StudioWebPaneController {
  /// Target comparison engine.
  StudioEngineKind get engineKind;

  /// Reactive telemetry stream describing readiness, SVG markup, and errors.
  ValueListenable<StudioWebRenderTelemetry> get telemetry;

  /// Initializes the underlying web harness or headless stub.
  Future<void> initialize();

  /// Renders [request] inside the comparison pane.
  Future<void> render(StudioWebRenderRequest request);

  /// Captures the rendered pane into packed RGBA8888 bytes for visual diffing.
  Future<StudioCapturedImage?> captureRgba({
    int targetWidth = 480,
    int targetHeight = 220,
  });

  /// Builds the widget displayed inside the comparison card.
  Widget buildView(BuildContext context);

  /// Releases resources owned by this controller.
  Future<void> dispose();
}

/// Factory creating a [StudioWebPaneController] for a given [StudioEngineKind].
typedef StudioWebPaneControllerFactory = StudioWebPaneController Function(
  StudioEngineKind kind,
  StudioLocalAssetServer? server,
);

/// Production macOS `WKWebView` implementation of [StudioWebPaneController]
/// powered by `webview_flutter` and `webview_flutter_wkwebview`.
final class WkWebViewStudioPaneController implements StudioWebPaneController {
  /// Creates a `WKWebView` controller bound to [engineKind] and [assetServer].
  WkWebViewStudioPaneController({
    required this.engineKind,
    required this.assetServer,
  }) : _telemetry = ValueNotifier<StudioWebRenderTelemetry>(
         StudioWebRenderTelemetry(
           engineKind: engineKind,
           assetsAvailable: _hasAssets(engineKind, assetServer),
           statusSummary: _hasAssets(engineKind, assetServer)
               ? 'Loading harness…'
               : 'Oracle JS assets missing in tool/oracle/node_modules/',
         ),
       );

  @override
  final StudioEngineKind engineKind;

  /// Local loopback HTTP server serving MathJax/KaTeX JS and fonts.
  final StudioLocalAssetServer? assetServer;

  final ValueNotifier<StudioWebRenderTelemetry> _telemetry;
  final Map<int, Completer<String?>> _pendingCaptures =
      <int, Completer<String?>>{};
  int _nextCaptureId = 1;
  WebViewController? _webController;
  StudioWebRenderRequest? _lastRequest;
  bool _disposed = false;

  static bool _hasAssets(
    StudioEngineKind kind,
    StudioLocalAssetServer? server,
  ) {
    if (server == null) {
      return false;
    }
    switch (kind) {
      case StudioEngineKind.mathJax:
        return server.assets.hasMathJax;
      case StudioEngineKind.katex:
        return server.assets.hasKatex;
    }
  }

  @override
  ValueListenable<StudioWebRenderTelemetry> get telemetry => _telemetry;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      return;
    }
    if (!_hasAssets(engineKind, assetServer) ||
        WebViewPlatform.instance == null) {
      return;
    }

    try {
      final String origin = await assetServer!.start();
      if (_disposed) {
        return;
      }

      final PlatformWebViewControllerCreationParams params =
          WebViewPlatform.instance is WebKitWebViewPlatform
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
            )
          : const PlatformWebViewControllerCreationParams();

      final WebViewController controller =
          WebViewController.fromPlatformCreationParams(params);
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (!Platform.isMacOS) {
        await controller.setBackgroundColor(Colors.transparent);
      }
      await controller.addJavaScriptChannel(
        'StudioBridge',
        onMessageReceived: _handleBridgeMessage,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            if (_disposed) {
              return;
            }
            _telemetry.value = _telemetry.value.copyWith(
              isRendering: false,
              errorMessage: error.description,
              statusSummary: 'Resource error',
            );
          },
        ),
      );

      if (controller.platform case final WebKitWebViewController wkController) {
        await wkController.setInspectable(kDebugMode);
      }

      _webController = controller;
      final String route = engineKind == StudioEngineKind.mathJax
          ? '/mathjax-harness.html'
          : '/katex-harness.html';
      await controller.loadRequest(Uri.parse('$origin$route'));
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      _telemetry.value = _telemetry.value.copyWith(
        isRendering: false,
        errorMessage: error.toString(),
        statusSummary: 'Init error',
      );
    }
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    if (_disposed) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map<String, Object?>) {
        return;
      }
      final String? type = decoded['type'] as String?;
      switch (type) {
        case 'ready':
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            statusSummary: 'Ready',
          );
          final StudioWebRenderRequest? pending = _lastRequest;
          if (pending != null) {
            unawaited(render(pending));
          }
        case 'rendered':
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            isRendering: false,
            clearError: true,
            svgXml: decoded['svgXml'] as String?,
            widthPx: (decoded['widthPx'] as num?)?.toDouble(),
            heightPx: (decoded['heightPx'] as num?)?.toDouble(),
            renderTimeMs: (decoded['renderTimeMs'] as num?)?.toDouble(),
            statusSummary: 'Rendered',
          );
        case 'error':
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            isRendering: false,
            clearSvg: true,
            errorMessage: decoded['errorMessage'] as String? ?? 'Render error',
            renderTimeMs: (decoded['renderTimeMs'] as num?)?.toDouble(),
            statusSummary: 'Error',
          );
        case 'capture':
          final int? requestId = (decoded['requestId'] as num?)?.toInt();
          final String? dataUrl = decoded['dataUrl'] as String?;
          if (requestId != null) {
            final Completer<String?>? completer = _pendingCaptures.remove(
              requestId,
            );
            if (completer != null && !completer.isCompleted) {
              completer.complete(dataUrl);
            }
          }
      }
    } on Object {
      // Ignore malformed bridge payloads.
    }
  }

  @override
  Future<void> render(StudioWebRenderRequest request) async {
    _lastRequest = request;
    if (_disposed) {
      return;
    }
    final WebViewController? controller = _webController;
    if (controller == null || !_telemetry.value.isReady) {
      return;
    }

    _telemetry.value = _telemetry.value.copyWith(
      isRendering: true,
      statusSummary: 'Rendering…',
    );
    final String payload = jsonEncode(<String, Object?>{
      'source': request.source,
      'display': request.displayMode == TexMathDisplayMode.display,
      'dark': request.isDarkTheme,
      'fontSize': request.fontSize,
      'packages': request.packages,
    });
    await controller.runJavaScript(
      'window.studioRender && window.studioRender($payload);',
    );
  }

  @override
  Future<StudioCapturedImage?> captureRgba({
    int targetWidth = 480,
    int targetHeight = 220,
  }) async {
    if (_disposed) {
      return null;
    }
    final WebViewController? controller = _webController;
    if (controller == null || !_telemetry.value.isReady) {
      return null;
    }
    final int requestId = _nextCaptureId++;
    final Completer<String?> completer = Completer<String?>();
    _pendingCaptures[requestId] = completer;
    try {
      await controller.runJavaScript(
        'window.studioRequestCapture && '
        'window.studioRequestCapture($requestId, $targetWidth, $targetHeight);',
      );
      final String? dataUrl = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _pendingCaptures.remove(requestId);
          return null;
        },
      );
      const String prefix = 'data:image/png;base64,';
      if (dataUrl == null || !dataUrl.startsWith(prefix)) {
        return null;
      }
      final Uint8List pngBytes = base64Decode(dataUrl.substring(prefix.length));
      final ui.Codec codec = await ui.instantiateImageCodec(pngBytes);
      try {
        final ui.FrameInfo frame = await codec.getNextFrame();
        final ui.Image image = frame.image;
        try {
          final ByteData? rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (rgba == null) {
            return null;
          }
          return StudioCapturedImage(
            width: image.width,
            height: image.height,
            rgbaBytes: rgba.buffer.asUint8List(),
          );
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } on Object {
      _pendingCaptures.remove(requestId);
      return null;
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final WebViewController? controller = _webController;
    if (controller == null) {
      return _buildFallbackStatus(context);
    }
    return WebViewWidget(controller: controller);
  }

  Widget _buildFallbackStatus(BuildContext context) {
    return ValueListenableBuilder<StudioWebRenderTelemetry>(
      valueListenable: _telemetry,
      builder: (BuildContext context, StudioWebRenderTelemetry info, _) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text(
              info.errorMessage ?? info.statusSummary,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        );
      },
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final Completer<String?> completer in _pendingCaptures.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pendingCaptures.clear();
    _webController = null;
    _telemetry.dispose();
  }
}

/// Deterministic headless [StudioWebPaneController] used when no platform
/// `WebViewPlatform` is registered (such as headless `flutter test` runs).
final class HeadlessOraclePaneController implements StudioWebPaneController {
  /// Creates a headless comparison controller for [engineKind].
  HeadlessOraclePaneController({
    required this.engineKind,
    this.assetsAvailable = false,
  }) : _telemetry = ValueNotifier<StudioWebRenderTelemetry>(
         StudioWebRenderTelemetry(
           engineKind: engineKind,
           isReady: true,
           assetsAvailable: assetsAvailable,
           statusSummary: 'Headless preview',
         ),
       );

  @override
  final StudioEngineKind engineKind;

  /// Whether oracle JS assets exist on disk.
  final bool assetsAvailable;

  final ValueNotifier<StudioWebRenderTelemetry> _telemetry;
  StudioWebRenderRequest? _lastRequest;

  @override
  ValueListenable<StudioWebRenderTelemetry> get telemetry => _telemetry;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> render(StudioWebRenderRequest request) async {
    _lastRequest = request;
    _telemetry.value = _telemetry.value.copyWith(
      isReady: true,
      isRendering: false,
      clearError: true,
      statusSummary: 'Headless preview',
    );
  }

  @override
  Future<StudioCapturedImage?> captureRgba({
    int targetWidth = 480,
    int targetHeight = 220,
  }) async {
    return null;
  }

  @override
  Widget buildView(BuildContext context) {
    final String source = _lastRequest?.source ?? '';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              engineKind.title,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8.0),
            Text(
              source,
              style: const TextStyle(fontFamily: 'monospace'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _telemetry.dispose();
  }
}

/// Captures RGBA8888 pixel data from a Flutter [RepaintBoundary] identified by
/// [boundaryKey].
Future<StudioCapturedImage?> captureRepaintBoundaryRgba(
  GlobalKey boundaryKey, {
  double pixelRatio = 2.0,
}) async {
  final RenderObject? renderObject = boundaryKey.currentContext
      ?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || !renderObject.attached) {
    return null;
  }
  final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
  try {
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (data == null) {
      return null;
    }
    return StudioCapturedImage(
      width: image.width,
      height: image.height,
      rgbaBytes: data.buffer.asUint8List(),
    );
  } finally {
    image.dispose();
  }
}
