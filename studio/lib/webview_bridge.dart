import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;
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
  StudioWebRenderRequest({
    required this.source,
    required this.displayMode,
    required this.isDarkTheme,
    this.fontSize = 22.0,
    List<String>? packages,
  }) : packages = packages == null ? null : List<String>.unmodifiable(packages);

  /// TeX expression source string.
  final String source;

  /// Active TeX display vs inline typesetting mode.
  final TexMathDisplayMode displayMode;

  /// Whether the active studio surface uses dark theme colors.
  final bool isDarkTheme;

  /// Base CSS font size in logical pixels.
  final double fontSize;

  /// Optional unmodifiable MathJax package list from corpus metadata.
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioWebRenderTelemetry &&
          engineKind == other.engineKind &&
          isReady == other.isReady &&
          isRendering == other.isRendering &&
          errorMessage == other.errorMessage &&
          svgXml == other.svgXml &&
          widthPx == other.widthPx &&
          heightPx == other.heightPx &&
          renderTimeMs == other.renderTimeMs &&
          assetsAvailable == other.assetsAvailable &&
          statusSummary == other.statusSummary;

  @override
  int get hashCode => Object.hash(
    engineKind,
    isReady,
    isRendering,
    errorMessage,
    svgXml,
    widthPx,
    heightPx,
    renderTimeMs,
    assetsAvailable,
    statusSummary,
  );
}

/// Raw RGBA pixel capture of a rendered pane used by pixel and curtain diffs.
@immutable
final class StudioCapturedImage {
  /// Creates an RGBA capture record validating exact byte buffer length.
  StudioCapturedImage({
    required this.width,
    required this.height,
    required Uint8List rgbaBytes,
  }) : assert(width >= 0, 'width must be non-negative'),
       assert(height >= 0, 'height must be non-negative'),
       assert(
         rgbaBytes.length == width * height * 4,
         'rgbaBytes length must equal width * height * 4',
       ),
       rgbaBytes = rgbaBytes.asUnmodifiableView();

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Unmodifiable packed RGBA8888 pixel buffer (`width * height * 4` bytes).
  final Uint8List rgbaBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioCapturedImage &&
          width == other.width &&
          height == other.height &&
          (identical(rgbaBytes, other.rgbaBytes) ||
              _uint8ListEquals(rgbaBytes, other.rgbaBytes));

  @override
  int get hashCode {
    int hash = Object.hash(width, height, rgbaBytes.length);
    if (rgbaBytes.isEmpty) {
      return hash;
    }
    final int len = rgbaBytes.length;
    final int step = len <= 64 ? 1 : len ~/ 64;
    for (int i = 0; i < len; i += step) {
      hash = Object.hash(hash, rgbaBytes[i]);
    }
    return Object.hash(hash, rgbaBytes[len - 1]);
  }
}

bool _uint8ListEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioOracleAssets &&
          nodeModulesDir.path == other.nodeModulesDir.path &&
          mathJaxBundleFile?.path == other.mathJaxBundleFile?.path &&
          mathJaxDir?.path == other.mathJaxDir?.path &&
          mathJaxNewcmDynamicDir?.path == other.mathJaxNewcmDynamicDir?.path &&
          katexDistDir?.path == other.katexDistDir?.path &&
          katexJsFile?.path == other.katexJsFile?.path &&
          katexCssFile?.path == other.katexCssFile?.path &&
          katexMhchemJsFile?.path == other.katexMhchemJsFile?.path;

  @override
  int get hashCode => Object.hash(
    nodeModulesDir.path,
    mathJaxBundleFile?.path,
    mathJaxDir?.path,
    mathJaxNewcmDynamicDir?.path,
    katexDistDir?.path,
    katexJsFile?.path,
    katexCssFile?.path,
    katexMhchemJsFile?.path,
  );
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

  /// Restrictive Content-Security-Policy enforced on local harness HTML pages.
  static const String harnessContentSecurityPolicy =
      "default-src 'self'; script-src 'self' 'unsafe-inline'; "
      "style-src 'self' 'unsafe-inline'; font-src 'self'; "
      "img-src 'self' data: blob:; connect-src 'none'; frame-ancestors 'none'";

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

  /// Allowlisted safe MathJax TeX extension package names accepted in
  /// `studioRender` requests (explicitly excluding `texhtml` and arbitrary
  /// loader paths).
  static final Set<String> allowedMathJaxPackages = Set<String>.unmodifiable(
    <String>{
      ...defaultMathJaxPackages,
      'autoload',
      'bbm',
      'bboldx',
      'begingroup',
      'colorv2',
      'dsfont',
      'fontsizev3',
      'noerrors',
      'noundefined',
      'physics',
      'setoptions',
      'units',
    },
  );

  /// Filters [packages] against [allowedMathJaxPackages], falling back to
  /// [defaultMathJaxPackages] when empty.
  static List<String> sanitizePackages(Iterable<String> packages) {
    final List<String> filtered = <String>[];
    final Set<String> seen = <String>{};
    for (final String pkg in packages) {
      if (allowedMathJaxPackages.contains(pkg) && seen.add(pkg)) {
        filtered.add(pkg);
      }
    }
    return filtered.isEmpty ? defaultMathJaxPackages : filtered;
  }

  /// Generates the MathJax `4.1.3` SVG HTML harness page.
  ///
  /// When [sessionToken] is supplied, all script and asset requests are scoped
  /// under `<origin>/s/<sessionToken>/...`.
  static String buildMathJaxHtml({
    required String origin,
    String? sessionToken,
  }) {
    final String baseUrl = sessionToken != null && sessionToken.isNotEmpty
        ? '$origin/s/$sessionToken'
        : origin;
    final String defaultPackagesJson = jsonEncode(defaultMathJaxPackages);
    final String allowedPackagesJson = jsonEncode(
      allowedMathJaxPackages.toList()..sort(),
    );
    final String mathjaxPathJson = jsonEncode('$baseUrl/mathjax');
    final String fontsPathJson = jsonEncode('$baseUrl/fonts');
    // MathJax 4 provides the safe-mode extension at `ui/safe` (`mathjax/ui/safe.js`)
    // rather than `[tex]/safe`.
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
    -webkit-font-smoothing: antialiased;
  }
  #stage {
    box-sizing: border-box;
    min-height: 100%;
    display: flex;
    padding: 4px;
    overflow: auto;
  }
  #math-out {
    display: inline-block;
    margin: auto;
    color: var(--fg);
  }
  #error-box {
    display: none;
    margin: auto;
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
window.__latestRenderSeq = 0;
window.__currentFg = '#111827';
window.__currentBg = '#ffffff';
window.__defaultPackages = $defaultPackagesJson;
window.__allowedPackages = new Set($allowedPackagesJson);

function postBridge(payload) {
  if (window.StudioBridge && typeof window.StudioBridge.postMessage === 'function') {
    window.StudioBridge.postMessage(JSON.stringify(payload));
  }
}

function reportStartupError(message) {
  const detail = String(message || 'Unknown startup error');
  const applyDom = () => {
    const out = document.getElementById('math-out');
    const errBox = document.getElementById('error-box');
    if (out) {
      out.innerHTML = '';
      out.style.display = 'none';
    }
    if (errBox) {
      errBox.textContent = detail;
      errBox.style.display = 'block';
    }
  };
  if (document.getElementById('error-box')) {
    applyDom();
  } else {
    window.addEventListener('DOMContentLoaded', applyDom, { once: true });
  }
  postBridge({ type: 'startupError', errorMessage: detail });
}

function syncMathJaxStylesheet() {
  if (typeof MathJax === 'undefined' || typeof MathJax.svgStylesheet !== 'function') {
    return;
  }
  const sheet = MathJax.svgStylesheet();
  if (!sheet) {
    return;
  }
  const id = sheet.id || 'MJX-SVG-styles';
  const existing = document.getElementById(id);
  if (existing && existing.parentNode) {
    existing.parentNode.replaceChild(sheet, existing);
  } else if (document.head) {
    document.head.appendChild(sheet);
  }
}

window.addEventListener('error', (event) => {
  if (!window.__mjReady) {
    const detail = event && event.message ? event.message : 'Unknown script error';
    reportStartupError('MathJax startup error: ' + detail);
  }
});

window.addEventListener('unhandledrejection', (event) => {
  if (!window.__mjReady) {
    const reason = event && event.reason;
    const detail = reason && reason.message
      ? reason.message
      : String(reason || 'Unhandled promise rejection');
    reportStartupError('MathJax startup rejection: ' + detail);
  }
});

window.MathJax = {
  loader: {
    paths: {
      mathjax: $mathjaxPathJson,
      tex: '[mathjax]/input/tex/extensions',
      fonts: $fontsPathJson
    },
    load: ['ui/safe', ...window.__defaultPackages.filter(p => p !== 'base').map(p => '[tex]/' + p)],
    failed: (err) => {
      const pkg = err && err.package ? err.package : 'unknown';
      const detail = err && err.message ? err.message : String(err);
      reportStartupError('MathJax loader failed (' + pkg + '): ' + detail);
    }
  },
  options: {
    enableMenu: false,
    enableEnrichment: false,
    enableComplexity: false,
    enableSpeech: false,
    enableBraille: false,
    enableExplorer: false,
    menuOptions: {
      settings: {
        enrich: false,
        speech: false,
        braille: false,
        collapsible: false
      }
    },
    safeOptions: {
      allow: {
        URLs: 'safe',
        classes: 'safe',
        cssIDs: 'safe',
        styles: 'safe'
      },
      safeProtocols: {
        http: true,
        https: true,
        file: false,
        javascript: false,
        data: false
      }
    }
  },
  tex: {
    packages: window.__defaultPackages.slice(),
    formatError: (jax, err) => { throw err; }
  },
  svg: {
    fontCache: 'local',
    linebreaks: { inline: false }
  },
  startup: {
    typeset: false,
    ready: () => {
      MathJax.startup.defaultReady();
      syncMathJaxStylesheet();
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
  const seq = typeof req.seq === 'number' ? req.seq : null;
  if (seq !== null) {
    window.__latestRenderSeq = seq;
  }
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

  const sanitized = Array.isArray(req.packages)
    ? req.packages.filter(p => typeof p === 'string' && window.__allowedPackages.has(p))
    : [];
  const targetPackages = sanitized.length > 0
    ? sanitized
    : window.__defaultPackages;

  try {
    const toLoad = targetPackages
      .filter(p => p !== 'base')
      .map(p => '[tex]/' + p);
    await MathJax.loader.load(...toLoad);
    if (seq !== null && seq !== window.__latestRenderSeq) {
      return;
    }

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
    if (seq !== null && seq !== window.__latestRenderSeq) {
      return;
    }
    syncMathJaxStylesheet();
    const svgs = Array.from(wrapper.querySelectorAll('svg'));
    const pxSize = req.fontSize || 22;
    for (const svg of svgs) {
      const vb = (svg.getAttribute('viewBox') || '').trim().split(/\\s+/).map(Number);
      if (vb.length === 4 && Number.isFinite(vb[2]) && Number.isFinite(vb[3]) && vb[2] > 0 && vb[3] > 0) {
        svg.style.width = ((vb[2] / 1000) * pxSize) + 'px';
        svg.style.height = ((vb[3] / 1000) * pxSize) + 'px';
      }
    }
    out.innerHTML = '';
    out.appendChild(wrapper);
    errBox.style.display = 'none';
    out.style.display = 'inline-block';

    const rect = (svgs.length === 1 ? svgs[0] : (wrapper || out)).getBoundingClientRect();
    const serializer = new XMLSerializer();
    const svgXml = svgs.length === 1
      ? serializer.serializeToString(svgs[0])
      : svgs.map((svg) => serializer.serializeToString(svg)).join('');
    postBridge({
      type: 'rendered',
      seq: seq,
      svgXml: svgXml,
      widthPx: rect.width,
      heightPx: rect.height,
      renderTimeMs: performance.now() - t0
    });
  } catch (err) {
    if (seq !== null && seq !== window.__latestRenderSeq) {
      return;
    }
    out.innerHTML = '';
    out.style.display = 'none';
    const message = err && err.message ? String(err.message) : String(err);
    errBox.textContent = message;
    errBox.style.display = 'block';
    postBridge({
      type: 'error',
      seq: seq,
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
    const svgs = Array.from(document.querySelectorAll('#math-out svg'));
    if (svgs.length === 0) {
      resolve('');
      return;
    }
    const w = Math.max(1, targetW | 0);
    const h = Math.max(1, targetH | 0);
    const mjStyle = document.getElementById('MJX-SVG-styles');
    const styleText = mjStyle && mjStyle.textContent ? mjStyle.textContent : '';
    const serializer = new XMLSerializer();
    const availW = Math.max(1, w - 24);
    const availH = Math.max(1, h - 24);

    const measureSvg = (svg) => {
      const rect = svg.getBoundingClientRect();
      const styleW = parseFloat(svg.style.width);
      const styleH = parseFloat(svg.style.height);
      const drawW = Math.max(1, (rect.width > 0 ? rect.width : (Number.isFinite(styleW) && styleW > 0 ? styleW : w)));
      const drawH = Math.max(1, (rect.height > 0 ? rect.height : (Number.isFinite(styleH) && styleH > 0 ? styleH : h)));
      return { drawW, drawH };
    };

    const serializeSvg = (svg, outW, outH) => {
      const clone = svg.cloneNode(true);
      clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      if (styleText) {
        const styleEl = document.createElementNS('http://www.w3.org/2000/svg', 'style');
        styleEl.textContent = styleText;
        clone.insertBefore(styleEl, clone.firstChild);
      }
      clone.setAttribute('width', String(outW));
      clone.setAttribute('height', String(outH));
      const serialized = serializer.serializeToString(clone);
      return serialized.replaceAll('currentColor', window.__currentFg || '#111827');
    };

    const loadSvgImage = (serialized) => new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => res(img);
      img.onerror = rej;
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(serialized);
    });

    if (svgs.length === 1) {
      const svg = svgs[0];
      const { drawW, drawH } = measureSvg(svg);
      const scale = Math.min(availW / drawW, availH / drawH, 2.0);
      const outW = Math.max(1, drawW * scale);
      const outH = Math.max(1, drawH * scale);
      loadSvgImage(serializeSvg(svg, outW, outH))
        .then((img) => {
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
        })
        .catch(() => resolve(''));
      return;
    }

    const measured = svgs.map((svg) => ({ svg, ...measureSvg(svg) }));
    const totalW = Math.max(1, measured.reduce((sum, item) => sum + item.drawW, 0));
    const maxH = Math.max(1, ...measured.map((item) => item.drawH));
    const scale = Math.min(availW / totalW, availH / maxH, 2.0);
    const items = measured.map((item) => {
      const outW = Math.max(1, item.drawW * scale);
      const outH = Math.max(1, item.drawH * scale);
      return {
        outW,
        outH,
        serialized: serializeSvg(item.svg, outW, outH)
      };
    });
    const scaledTotalW = items.reduce((sum, item) => sum + item.outW, 0);

    Promise.all(items.map((item) => loadSvgImage(item.serialized)))
      .then((imgs) => {
        const canvas = document.createElement('canvas');
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = window.__currentBg || '#ffffff';
        ctx.fillRect(0, 0, w, h);
        let curX = (w - scaledTotalW) / 2;
        for (let i = 0; i < imgs.length; i++) {
          const item = items[i];
          const dx = Math.round(curX);
          const dy = Math.round((h - item.outH) / 2);
          ctx.drawImage(imgs[i], dx, dy, item.outW, item.outH);
          curX += item.outW;
        }
        resolve(canvas.toDataURL('image/png'));
      })
      .catch(() => resolve(''));
  });
};
</script>
<script src="$baseUrl/mathjax/tex-svg.js" onerror="reportStartupError('Failed to load local MathJax bundle (tex-svg.js).')"></script>
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
  ///
  /// When [sessionToken] is supplied, all stylesheet and script requests are
  /// scoped under `<origin>/s/<sessionToken>/...`.
  static String buildKatexHtml({required String origin, String? sessionToken}) {
    final String baseUrl = sessionToken != null && sessionToken.isNotEmpty
        ? '$origin/s/$sessionToken'
        : origin;
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<link rel="stylesheet" href="$baseUrl/katex/katex.min.css">
<style>
  @font-face {
    font-display: block;
    font-family: 'StudioKaTeXMathItalic';
    font-style: italic;
    font-weight: 400;
    src: url('$baseUrl/katex/fonts/KaTeX_Math-Italic.woff2') format('woff2');
  }
  .katex .mathnormal {
    font-family: 'StudioKaTeXMathItalic', KaTeX_Math;
    font-style: italic;
    font-weight: 400;
    font-synthesis: none;
  }
  :root { --fg: #111827; --bg: #ffffff; --err-fg: #dc2626; --err-bg: #fef2f2; }
  html, body {
    margin: 0; padding: 0; width: 100%; height: 100%;
    background: var(--bg); color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  #stage {
    box-sizing: border-box;
    min-height: 100%;
    display: flex;
    padding: 4px;
    overflow: auto;
  }
  #math-out {
    display: inline-block;
    margin: auto;
    color: var(--fg);
  }
  #error-box {
    display: none;
    margin: auto;
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
window.__currentFg = '#111827';
window.__currentBg = '#ffffff';
window.__startupErrorReported = false;

function postBridge(payload) {
  if (window.StudioBridge && typeof window.StudioBridge.postMessage === 'function') {
    window.StudioBridge.postMessage(JSON.stringify(payload));
  }
}

function reportStartupError(message) {
  window.__startupErrorReported = true;
  const detail = String(message || 'Unknown startup error');
  const applyDom = () => {
    const out = document.getElementById('math-out');
    const errBox = document.getElementById('error-box');
    if (out) {
      out.innerHTML = '';
      out.style.display = 'none';
    }
    if (errBox) {
      errBox.textContent = detail;
      errBox.style.display = 'block';
    }
  };
  if (document.getElementById('error-box')) {
    applyDom();
  } else {
    window.addEventListener('DOMContentLoaded', applyDom, { once: true });
  }
  postBridge({ type: 'startupError', errorMessage: detail });
}
</script>
<script src="$baseUrl/katex/katex.min.js" onerror="reportStartupError('Failed to load local KaTeX bundle (katex.min.js).')"></script>
<script src="$baseUrl/katex/contrib/mhchem.min.js"></script>
<script>
window.studioRender = function(req) {
  const seq = typeof req.seq === 'number' ? req.seq : null;
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
      seq: seq,
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
      seq: seq,
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
  if (typeof window.katex !== 'undefined') {
    postBridge({ type: 'ready' });
  } else if (!window.__startupErrorReported) {
    reportStartupError('Failed to load local KaTeX bundle (katex.min.js).');
  }
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
  StudioLocalAssetServer(this.assets) : _sessionToken = _generateSessionToken();

  static final RegExp _unsafeRawPercentPattern = RegExp(
    r'%(?:00|2f|5c)',
    caseSensitive: false,
  );

  static const Set<String> _optionalMathJaxFontExtensionStubs = <String>{
    '/fonts/mathjax-mhchem-font-extension/svg.js',
    '/fonts/mathjax-bbm-font-extension/svg.js',
    '/fonts/mathjax-bboldx-font-extension/svg.js',
    '/fonts/mathjax-dsfont-font-extension/svg.js',
  };

  static const Set<String> _optionalMathJaxFontExtensionPackages = <String>{
    'mathjax-mhchem-font-extension',
    'mathjax-bbm-font-extension',
    'mathjax-bboldx-font-extension',
    'mathjax-dsfont-font-extension',
  };

  /// Resolved MathJax and KaTeX filesystem bundles.
  final StudioOracleAssets assets;

  final String _sessionToken;
  HttpServer? _server;
  int? _port;
  Future<String>? _startFuture;
  bool _closed = false;

  static String _generateSessionToken() {
    final Random rng = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 24; i++) {
      buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Per-instance cryptographically random session token required in `/s/<token>/...`.
  String get sessionToken => _sessionToken;

  /// Bound loopback HTTP origin URL (`http://127.0.0.1:<port>`), or `null`
  /// before [start] completes or after [close].
  String? get origin => _port == null ? null : 'http://127.0.0.1:$_port';

  /// Tokenized loopback base URL (`http://127.0.0.1:<port>/s/<token>`), or
  /// `null` before [start] completes or after [close].
  String? get tokenizedOrigin =>
      _port == null ? null : 'http://127.0.0.1:$_port/s/$_sessionToken';

  /// Whether the loopback server is actively listening.
  bool get isRunning => !_closed && _server != null && _port != null;

  /// Returns the tokenized harness URI for [engineKind], or `null` when the
  /// server is not running.
  Uri? harnessUriFor(StudioEngineKind engineKind) {
    final String? base = tokenizedOrigin;
    if (base == null || _closed) {
      return null;
    }
    final String route = engineKind == StudioEngineKind.mathJax
        ? 'mathjax-harness.html'
        : 'katex-harness.html';
    return Uri.parse('$base/$route');
  }

  /// Starts listening on `127.0.0.1` using ephemeral port `0`.
  ///
  /// Concurrent calls share the same in-flight bind future without leaking sockets.
  Future<String> start() {
    if (_closed) {
      return Future<String>.error(
        StateError('StudioLocalAssetServer has been closed.'),
      );
    }
    if (_server != null && _port != null) {
      return Future<String>.value(origin!);
    }
    final Future<String>? existing = _startFuture;
    if (existing != null) {
      return existing;
    }
    final Future<String> pending = _bindAndStart();
    _startFuture = pending;
    return pending;
  }

  Future<String> _bindAndStart() async {
    try {
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      if (_closed) {
        await server.close(force: true);
        throw StateError('StudioLocalAssetServer was closed during startup.');
      }
      _server = server;
      _port = server.port;
      unawaited(_serveRequests(server));
      return origin!;
    } finally {
      _startFuture = null;
    }
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

  bool _isAllowedHostHeader(HttpRequest request) {
    final int? activePort = _port;
    if (activePort == null) {
      return false;
    }
    final List<String>? hostValues = request.headers[HttpHeaders.hostHeader];
    if (hostValues == null || hostValues.length != 1) {
      return false;
    }
    final String host = hostValues.first.trim().toLowerCase();
    return host == '127.0.0.1:$activePort' || host == 'localhost:$activePort';
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!_isAllowedHostHeader(request)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    final String method = request.method.toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    final String rawPath = request.uri.path;
    if (!rawPath.startsWith('/s/')) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    final int nextSlash = rawPath.indexOf('/', 3);
    if (nextSlash < 0) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    final String providedToken = rawPath.substring(3, nextSlash);
    if (!_constantTimeEquals(providedToken, _sessionToken)) {
      request.response
        ..statusCode = HttpStatus.forbidden
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    final String assetPath = rawPath.substring(nextSlash);
    final String activeOrigin = origin ?? 'http://127.0.0.1';

    if (assetPath == '/mathjax-harness.html') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..headers.set('X-Content-Type-Options', 'nosniff')
        ..headers.set(
          'Content-Security-Policy',
          StudioWebHarnessBuilder.harnessContentSecurityPolicy,
        )
        ..headers.set('Referrer-Policy', 'no-referrer');
      if (method == 'GET') {
        request.response.write(
          StudioWebHarnessBuilder.buildMathJaxHtml(
            origin: activeOrigin,
            sessionToken: _sessionToken,
          ),
        );
      }
      await request.response.close();
      return;
    }

    if (assetPath == '/katex-harness.html') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set('Cache-Control', 'no-store')
        ..headers.set('X-Content-Type-Options', 'nosniff')
        ..headers.set(
          'Content-Security-Policy',
          StudioWebHarnessBuilder.harnessContentSecurityPolicy,
        )
        ..headers.set('Referrer-Policy', 'no-referrer');
      if (method == 'GET') {
        request.response.write(
          StudioWebHarnessBuilder.buildKatexHtml(
            origin: activeOrigin,
            sessionToken: _sessionToken,
          ),
        );
      }
      await request.response.close();
      return;
    }

    final File? file = resolveAssetFile(assetPath);
    if (file == null || !file.existsSync()) {
      if (_optionalMathJaxFontExtensionStubs.contains(assetPath)) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType(
            'application',
            'javascript',
            charset: 'utf-8',
          )
          ..headers.set('Cache-Control', 'no-store')
          ..headers.set('X-Content-Type-Options', 'nosniff');
        if (method == 'GET') {
          request.response.write(
            '/* Offline stub for optional MathJax font extension. */\n',
          );
        }
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..headers.set('X-Content-Type-Options', 'nosniff');
      await request.response.close();
      return;
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentTypeForPath(file.path)
      ..headers.set('Cache-Control', 'no-store')
      ..headers.set('X-Content-Type-Options', 'nosniff');
    if (method == 'GET') {
      await request.response.addStream(file.openRead());
    }
    await request.response.close();
  }

  static bool _hasControlChars(String text) {
    for (int i = 0; i < text.length; i++) {
      final int code = text.codeUnitAt(i);
      if (code < 0x20 || code == 0x7F) {
        return true;
      }
    }
    return false;
  }

  /// Resolves an HTTP asset [requestPath] safely inside [assets], rejecting
  /// path-traversal, encoded separators, NUL bytes, and escaping symlinks.
  File? resolveAssetFile(String requestPath) {
    if (requestPath.isEmpty ||
        requestPath.contains('\x00') ||
        requestPath.contains('\\') ||
        _hasControlChars(requestPath) ||
        _unsafeRawPercentPattern.hasMatch(requestPath)) {
      return null;
    }

    final String rawPath = requestPath.split('?').first.split('#').first;
    if (rawPath.isEmpty ||
        rawPath.contains('\x00') ||
        rawPath.contains('\\') ||
        _unsafeRawPercentPattern.hasMatch(rawPath)) {
      return null;
    }

    final List<String> rawParts = rawPath
        .split('/')
        .where((String segment) => segment.isNotEmpty)
        .toList();
    if (rawParts.isEmpty) {
      return null;
    }

    final List<String> segments = <String>[];
    for (final String rawSegment in rawParts) {
      if (rawSegment == '.' || rawSegment == '..') {
        return null;
      }
      final String decoded;
      try {
        decoded = Uri.decodeComponent(rawSegment);
      } on ArgumentError {
        return null;
      }
      if (decoded.isEmpty ||
          decoded == '.' ||
          decoded == '..' ||
          decoded.contains('/') ||
          decoded.contains('\\') ||
          decoded.contains('\x00') ||
          _hasControlChars(decoded)) {
        return null;
      }
      segments.add(decoded);
    }

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

    if (segments.length >= 3 &&
        segments.first == 'fonts' &&
        _optionalMathJaxFontExtensionPackages.contains(segments[1])) {
      return _safeChildFile(assets.nodeModulesDir, <String>[
        '@mathjax',
        ...segments.sublist(1),
      ]);
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
    if (tailSegments.isEmpty || !root.existsSync()) {
      return null;
    }
    final String canonicalRoot;
    try {
      canonicalRoot = root.resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
    final String sep = Platform.pathSeparator;
    final String candidatePath = '${root.path}$sep${tailSegments.join(sep)}';
    final File candidate = File(candidatePath);
    if (!candidate.existsSync()) {
      return null;
    }
    final String canonicalTarget;
    try {
      canonicalTarget = candidate.resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
    final String rootNorm = canonicalRoot.replaceAll('\\', '/');
    final String rootPrefix = rootNorm.endsWith('/') ? rootNorm : '$rootNorm/';
    final String targetNorm = canonicalTarget.replaceAll('\\', '/');
    if (!targetNorm.startsWith(rootPrefix)) {
      return null;
    }
    if (FileSystemEntity.typeSync(canonicalTarget, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    return File(canonicalTarget);
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

  /// Shuts down the loopback HTTP server and waits for any in-flight bind to clean up.
  Future<void> close() async {
    _closed = true;
    final Future<String>? pendingStart = _startFuture;
    final HttpServer? server = _server;
    _server = null;
    _port = null;
    if (server != null) {
      await server.close(force: true);
    }
    if (pendingStart != null) {
      await pendingStart.then<void>((_) {}, onError: (_, _) {});
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

/// Abstract driver wrapping [WebViewController] so `WKWebView` lifecycle,
/// navigation gating, and JS bridge races can be unit-tested without native views.
@visibleForTesting
abstract interface class StudioWebViewDriver {
  /// Configures JavaScript execution mode.
  Future<void> setJavaScriptMode(JavaScriptMode mode);

  /// Sets the native view background color when supported by the platform.
  Future<void> setBackgroundColor(Color color);

  /// Registers a JS bridge channel handler.
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage) onMessageReceived,
  });

  /// Registers navigation policy and resource error handlers.
  Future<void> setNavigationCallbacks({
    required NavigationRequestCallback onNavigationRequest,
    required WebResourceErrorCallback onWebResourceError,
  });

  /// Enables or disables WebKit inspector debugging.
  Future<void> setInspectable(bool inspectable);

  /// Navigates the web view to [uri].
  Future<void> loadRequest(Uri uri);

  /// Executes [javaScript] inside the active document.
  Future<void> runJavaScript(String javaScript);

  /// Builds the Flutter widget hosting the platform web view.
  Widget buildWidget(BuildContext context);
}

final class _PlatformStudioWebViewDriver implements StudioWebViewDriver {
  _PlatformStudioWebViewDriver(this.controller);

  final WebViewController controller;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) {
    return controller.setJavaScriptMode(mode);
  }

  @override
  Future<void> setBackgroundColor(Color color) {
    return controller.setBackgroundColor(color);
  }

  @override
  Future<void> addJavaScriptChannel(
    String name, {
    required void Function(JavaScriptMessage) onMessageReceived,
  }) {
    return controller.addJavaScriptChannel(
      name,
      onMessageReceived: onMessageReceived,
    );
  }

  @override
  Future<void> setNavigationCallbacks({
    required NavigationRequestCallback onNavigationRequest,
    required WebResourceErrorCallback onWebResourceError,
  }) {
    return controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: onNavigationRequest,
        onWebResourceError: onWebResourceError,
      ),
    );
  }

  @override
  Future<void> setInspectable(bool inspectable) async {
    if (controller.platform case final WebKitWebViewController wkController) {
      await wkController.setInspectable(inspectable);
    }
  }

  @override
  Future<void> loadRequest(Uri uri) => controller.loadRequest(uri);

  @override
  Future<void> runJavaScript(String javaScript) {
    return controller.runJavaScript(javaScript);
  }

  @override
  Widget buildWidget(BuildContext context) {
    return WebViewWidget(controller: controller);
  }
}

/// Production macOS `WKWebView` implementation of [StudioWebPaneController]
/// powered by `webview_flutter` and `webview_flutter_wkwebview`.
final class WkWebViewStudioPaneController implements StudioWebPaneController {
  /// Creates a `WKWebView` controller bound to [engineKind] and [assetServer].
  WkWebViewStudioPaneController({
    required this.engineKind,
    required this.assetServer,
    @visibleForTesting this.driverFactory,
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

  /// Optional driver override used by headless unit tests.
  @visibleForTesting
  final StudioWebViewDriver Function()? driverFactory;
  final ValueNotifier<StudioWebRenderTelemetry> _telemetry;
  final Map<int, Completer<String?>> _pendingCaptures =
      <int, Completer<String?>>{};
  int _nextCaptureId = 1;
  int _nextRenderSeq = 1;
  int _activeRenderSeq = 0;
  StudioWebViewDriver? _driver;
  Uri? _activeHarnessUri;
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

  /// Evaluates whether [request] targets the active loopback harness URL,
  /// blocking all external, `javascript:`, `data:`, `file:`, and subframe
  /// navigations.
  @visibleForTesting
  static NavigationDecision evaluateNavigationRequest(
    NavigationRequest request,
    Uri? expectedHarnessUri,
  ) {
    if (!request.isMainFrame || expectedHarnessUri == null) {
      return NavigationDecision.prevent;
    }
    final Uri? target = Uri.tryParse(request.url);
    if (target == null ||
        target.scheme != expectedHarnessUri.scheme ||
        target.host != expectedHarnessUri.host ||
        target.port != expectedHarnessUri.port ||
        target.path != expectedHarnessUri.path ||
        target.userInfo.isNotEmpty ||
        target.hasQuery) {
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  /// Decodes a `data:image/png;base64,...` payload into packed RGBA8888 pixels.
  @visibleForTesting
  static Future<StudioCapturedImage?> decodePngDataUrl(String? dataUrl) async {
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
  }

  /// Whether a native or mock driver is currently attached.
  @visibleForTesting
  bool get hasAttachedDriver => _driver != null;

  @override
  ValueListenable<StudioWebRenderTelemetry> get telemetry => _telemetry;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      return;
    }
    if (!_hasAssets(engineKind, assetServer) ||
        (driverFactory == null && WebViewPlatform.instance == null)) {
      return;
    }

    try {
      await assetServer!.start();
      if (_disposed) {
        return;
      }

      final Uri? harnessUri = assetServer!.harnessUriFor(engineKind);
      if (harnessUri == null) {
        return;
      }

      final StudioWebViewDriver driver;
      if (driverFactory != null) {
        driver = driverFactory!();
      } else {
        final PlatformWebViewControllerCreationParams params =
            WebViewPlatform.instance is WebKitWebViewPlatform
            ? WebKitWebViewControllerCreationParams(
                allowsInlineMediaPlayback: true,
              )
            : const PlatformWebViewControllerCreationParams();
        driver = _PlatformStudioWebViewDriver(
          WebViewController.fromPlatformCreationParams(params),
        );
      }

      await driver.setJavaScriptMode(JavaScriptMode.unrestricted);
      if (_disposed) {
        return;
      }
      if (!Platform.isMacOS) {
        await driver.setBackgroundColor(Colors.transparent);
        if (_disposed) {
          return;
        }
      }
      await driver.addJavaScriptChannel(
        'StudioBridge',
        onMessageReceived: _handleBridgeMessage,
      );
      if (_disposed) {
        return;
      }
      _activeHarnessUri = harnessUri;
      await driver.setNavigationCallbacks(
        onNavigationRequest: (NavigationRequest request) {
          if (_disposed) {
            return NavigationDecision.prevent;
          }
          return evaluateNavigationRequest(request, _activeHarnessUri);
        },
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
      );
      if (_disposed) {
        return;
      }

      await driver.setInspectable(kDebugMode);
      if (_disposed) {
        return;
      }

      _driver = driver;
      await driver.loadRequest(harnessUri);
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
    handleBridgePayload(message.message);
  }

  /// Processes a raw JSON payload received from `StudioBridge`.
  @visibleForTesting
  void handleBridgePayload(String rawMessage) {
    if (_disposed) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(rawMessage);
      if (decoded is! Map<String, Object?>) {
        return;
      }
      final Object? rawType = decoded['type'];
      final String? type = rawType is String ? rawType : null;
      final int? seq = _asIntOrNull(decoded['seq']);
      switch (type) {
        case 'ready':
          if (_disposed) {
            return;
          }
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            statusSummary: 'Ready',
          );
          final StudioWebRenderRequest? pending = _lastRequest;
          if (pending != null && !_disposed) {
            unawaited(render(pending));
          }
        case 'startupError':
          if (_disposed) {
            return;
          }
          _telemetry.value = _telemetry.value.copyWith(
            isReady: false,
            isRendering: false,
            clearSvg: true,
            errorMessage:
                _asStringOrNull(decoded['errorMessage']) ??
                'Harness startup error',
            statusSummary: 'Harness error',
          );
        case 'rendered':
          if (_disposed || _isStaleRenderSequence(seq)) {
            return;
          }
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            isRendering: false,
            clearError: true,
            svgXml: _asStringOrNull(decoded['svgXml']),
            widthPx: _asFiniteDoubleOrNull(decoded['widthPx']),
            heightPx: _asFiniteDoubleOrNull(decoded['heightPx']),
            renderTimeMs: _asFiniteDoubleOrNull(decoded['renderTimeMs']),
            statusSummary: 'Rendered',
          );
        case 'error':
          if (_disposed || _isStaleRenderSequence(seq)) {
            return;
          }
          _telemetry.value = _telemetry.value.copyWith(
            isReady: true,
            isRendering: false,
            clearSvg: true,
            errorMessage:
                _asStringOrNull(decoded['errorMessage']) ?? 'Render error',
            renderTimeMs: _asFiniteDoubleOrNull(decoded['renderTimeMs']),
            statusSummary: 'Error',
          );
        case 'capture':
          final int? requestId = _asIntOrNull(decoded['requestId']);
          final String? dataUrl = _asStringOrNull(decoded['dataUrl']);
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

  bool _isStaleRenderSequence(int? seq) {
    if (_activeRenderSeq == 0) {
      return false;
    }
    return seq != null && seq != _activeRenderSeq;
  }

  static String? _asStringOrNull(Object? value) =>
      value is String ? value : null;

  static int? _asIntOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    return null;
  }

  static double? _asFiniteDoubleOrNull(Object? value) {
    if (value is num) {
      final double d = value.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }

  @override
  Future<void> render(StudioWebRenderRequest request) async {
    _lastRequest = request;
    if (_disposed) {
      return;
    }
    final StudioWebViewDriver? driver = _driver;
    if (driver == null || !_telemetry.value.isReady) {
      return;
    }

    final int seq = _nextRenderSeq++;
    _activeRenderSeq = seq;
    _telemetry.value = _telemetry.value.copyWith(
      isRendering: true,
      statusSummary: 'Rendering…',
    );
    final List<String>? safePackages = request.packages == null
        ? null
        : StudioWebHarnessBuilder.sanitizePackages(request.packages!);
    final String payload = jsonEncode(<String, Object?>{
      'seq': seq,
      'source': request.source,
      'display': request.displayMode == TexMathDisplayMode.display,
      'dark': request.isDarkTheme,
      'fontSize': request.fontSize,
      'packages': safePackages,
    });
    try {
      await driver.runJavaScript(
        'window.studioRender && window.studioRender($payload);',
      );
    } on Object catch (error) {
      if (_disposed || seq != _activeRenderSeq) {
        return;
      }
      _telemetry.value = _telemetry.value.copyWith(
        isRendering: false,
        clearSvg: true,
        errorMessage: error.toString(),
        statusSummary: 'JS error',
      );
    }
  }

  @override
  Future<StudioCapturedImage?> captureRgba({
    int targetWidth = 480,
    int targetHeight = 220,
  }) async {
    if (_disposed) {
      return null;
    }
    final StudioWebViewDriver? driver = _driver;
    if (driver == null || !_telemetry.value.isReady) {
      return null;
    }
    final int requestId = _nextCaptureId++;
    final Completer<String?> completer = Completer<String?>();
    _pendingCaptures[requestId] = completer;
    try {
      await driver.runJavaScript(
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
      if (_disposed) {
        return null;
      }
      return await decodePngDataUrl(dataUrl);
    } on Object {
      _pendingCaptures.remove(requestId);
      return null;
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final StudioWebViewDriver? driver = _driver;
    if (driver == null) {
      return _buildFallbackStatus(context);
    }
    return driver.buildWidget(context);
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
    _activeHarnessUri = null;
    _driver = null;
    for (final Completer<String?> completer in _pendingCaptures.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _pendingCaptures.clear();
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
