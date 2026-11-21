import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'webview_bridge.dart';

/// Visual comparison mode presented in the main studio workspace.
enum StudioComparisonMode {
  /// Three-column live comparison across `tex_math`, MathJax, and KaTeX.
  sideBySide('Side-by-Side'),

  /// Per-pixel RGBA comparison highlighting differences in magenta.
  pixelDiff('Pixel Diff'),

  /// Interactive vertical wipe curtain comparing two rendered captures.
  curtainDiff('Curtain Diff');

  const StudioComparisonMode(this.label);

  /// Display label shown on mode selector segments.
  final String label;
}

/// External reference engine selected for two-way pixel and curtain diffs.
enum StudioDiffTarget {
  /// Compare `tex_math` against MathJax `4.1.3`.
  mathJax('MathJax 4.1.3'),

  /// Compare `tex_math` against KaTeX `0.19.1`.
  katex('KaTeX 0.19.1');

  const StudioDiffTarget(this.label);

  /// Display label shown on target toggle controls.
  final String label;
}

/// Pure-Dart result of comparing two equally sized RGBA8888 pixel buffers.
@immutable
final class PixelDiffResult {
  /// Creates a pixel diff result.
  PixelDiffResult({
    required this.width,
    required this.height,
    required this.totalPixels,
    required this.diffPixelCount,
    required this.exactMatchRatio,
    required this.maxChannelDelta,
    required Uint8List diffRgba,
  }) : diffRgba = diffRgba.asUnmodifiableView();

  /// Image width in pixels.
  final int width;

  /// Image height in pixels.
  final int height;

  /// Total number of pixels (`width * height`).
  final int totalPixels;

  /// Number of pixels whose maximum RGBA channel delta exceeded tolerance.
  final int diffPixelCount;

  /// Ratio of matching pixels in `[0.0, 1.0]`.
  final double exactMatchRatio;

  /// Maximum per-channel absolute difference across all pixels (`0..255`).
  final int maxChannelDelta;

  /// Unmodifiable highlighted RGBA8888 visualization buffer (`diff` pixels in
  /// magenta).
  final Uint8List diffRgba;

  /// Percentage of matching pixels in `[0.0, 100.0]`.
  double get matchPercentage => exactMatchRatio * 100.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PixelDiffResult &&
          width == other.width &&
          height == other.height &&
          totalPixels == other.totalPixels &&
          diffPixelCount == other.diffPixelCount &&
          exactMatchRatio == other.exactMatchRatio &&
          maxChannelDelta == other.maxChannelDelta &&
          (identical(diffRgba, other.diffRgba) ||
              _bytesEqual(diffRgba, other.diffRgba));

  @override
  int get hashCode {
    int hash = Object.hash(
      width,
      height,
      totalPixels,
      diffPixelCount,
      exactMatchRatio,
      maxChannelDelta,
      diffRgba.length,
    );
    if (diffRgba.isEmpty) {
      return hash;
    }
    final int len = diffRgba.length;
    final int step = len <= 64 ? 1 : len ~/ 64;
    for (int i = 0; i < len; i += step) {
      hash = Object.hash(hash, diffRgba[i]);
    }
    return Object.hash(hash, diffRgba[len - 1]);
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
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

/// Pair of same-dimension captures ready for pixel diffing and curtain wipe.
@immutable
final class StudioCapturedPair {
  /// Creates a capture pair comparing [texMathImage] with [targetImage].
  const StudioCapturedPair({
    required this.texMathImage,
    required this.targetImage,
    required this.target,
  });

  /// Capture of the `tex_math` Flutter widget.
  final StudioCapturedImage texMathImage;

  /// Capture of the selected external reference engine.
  final StudioCapturedImage targetImage;

  /// External reference engine represented by [targetImage].
  final StudioDiffTarget target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudioCapturedPair &&
          texMathImage == other.texMathImage &&
          targetImage == other.targetImage &&
          target == other.target;

  @override
  int get hashCode => Object.hash(texMathImage, targetImage, target);
}

/// Computes per-pixel RGBA difference between equally sized buffers [a] and
/// [b], highlighting mismatched pixels in magenta (`#FFFF00FF`) and reporting
/// exact match ratio and diff pixel count.
PixelDiffResult computePixelDiff(
  Uint8List a,
  Uint8List b,
  int width,
  int height, {
  int channelTolerance = 0,
}) {
  if (width < 0 || height < 0) {
    throw ArgumentError('Image dimensions must be non-negative.');
  }
  if (channelTolerance < 0) {
    throw ArgumentError('channelTolerance must be non-negative.');
  }
  final int totalPixels = width * height;
  final int expectedBytes = totalPixels * 4;
  if (a.length != expectedBytes) {
    throw ArgumentError(
      'Buffer a length (${a.length}) does not match $expectedBytes bytes.',
    );
  }
  if (b.length != expectedBytes) {
    throw ArgumentError(
      'Buffer b length (${b.length}) does not match $expectedBytes bytes.',
    );
  }

  final Uint8List diffRgba = Uint8List(expectedBytes);
  int diffPixelCount = 0;
  int maxChannelDelta = 0;

  for (int i = 0; i < expectedBytes; i += 4) {
    final int rA = a[i];
    final int gA = a[i + 1];
    final int bA = a[i + 2];
    final int aA = a[i + 3];

    final int dr = (rA - b[i]).abs();
    final int dg = (gA - b[i + 1]).abs();
    final int db = (bA - b[i + 2]).abs();
    final int da = (aA - b[i + 3]).abs();
    final int pixelDelta = math.max(math.max(dr, dg), math.max(db, da));
    if (pixelDelta > maxChannelDelta) {
      maxChannelDelta = pixelDelta;
    }

    if (pixelDelta > channelTolerance) {
      diffPixelCount++;
      diffRgba[i] = 255;
      diffRgba[i + 1] = 0;
      diffRgba[i + 2] = 255;
      diffRgba[i + 3] = 255;
    } else {
      diffRgba[i] = rA;
      diffRgba[i + 1] = gA;
      diffRgba[i + 2] = bA;
      diffRgba[i + 3] = (aA * 0.25).round();
    }
  }

  final double exactMatchRatio = totalPixels == 0
      ? 1.0
      : (totalPixels - diffPixelCount) / totalPixels;

  return PixelDiffResult(
    width: width,
    height: height,
    totalPixels: totalPixels,
    diffPixelCount: diffPixelCount,
    exactMatchRatio: exactMatchRatio,
    maxChannelDelta: maxChannelDelta,
    diffRgba: diffRgba,
  );
}

/// Pads two captures into a common centered canvas size when their pixel
/// dimensions differ.
({StudioCapturedImage left, StudioCapturedImage right}) alignCapturedPair(
  StudioCapturedImage left,
  StudioCapturedImage right, {
  required Color backgroundColor,
}) {
  if (left.width == right.width && left.height == right.height) {
    return (left: left, right: right);
  }
  final int targetW = math.max(left.width, right.width);
  final int targetH = math.max(left.height, right.height);
  return (
    left: _padCentered(left, targetW, targetH, backgroundColor),
    right: _padCentered(right, targetW, targetH, backgroundColor),
  );
}

StudioCapturedImage _padCentered(
  StudioCapturedImage image,
  int targetW,
  int targetH,
  Color backgroundColor,
) {
  if (image.width == targetW && image.height == targetH) {
    return image;
  }
  final Uint8List out = Uint8List(targetW * targetH * 4);
  final int bgR = (backgroundColor.r * 255.0).round() & 0xFF;
  final int bgG = (backgroundColor.g * 255.0).round() & 0xFF;
  final int bgB = (backgroundColor.b * 255.0).round() & 0xFF;
  final int bgA = (backgroundColor.a * 255.0).round() & 0xFF;
  for (int i = 0; i < out.length; i += 4) {
    out[i] = bgR;
    out[i + 1] = bgG;
    out[i + 2] = bgB;
    out[i + 3] = bgA;
  }
  final int offsetX = math.max(0, (targetW - image.width) ~/ 2);
  final int offsetY = math.max(0, (targetH - image.height) ~/ 2);
  final int copyW = math.min(image.width, targetW - offsetX);
  final int copyH = math.min(image.height, targetH - offsetY);
  for (int y = 0; y < copyH; y++) {
    final int srcRowStart = y * image.width * 4;
    final int dstRowStart = ((y + offsetY) * targetW + offsetX) * 4;
    out.setRange(
      dstRowStart,
      dstRowStart + copyW * 4,
      image.rgbaBytes,
      srcRowStart,
    );
  }
  return StudioCapturedImage(width: targetW, height: targetH, rgbaBytes: out);
}

/// Offloads [alignCapturedPair] and [computePixelDiff] to a background worker
/// isolate via [Isolate.run] to keep desktop UI frames responsive.
Future<
  ({StudioCapturedImage left, StudioCapturedImage right, PixelDiffResult diff})
>
computeAlignedPixelDiffAsync(
  StudioCapturedImage texMathImage,
  StudioCapturedImage targetImage, {
  required Color backgroundColor,
  int channelTolerance = 0,
}) {
  final int bgArgb = backgroundColor.toARGB32();
  return Isolate.run(
    () => _alignAndDiff(
      texMathImage,
      targetImage,
      bgArgb: bgArgb,
      channelTolerance: channelTolerance,
    ),
  );
}

({StudioCapturedImage left, StudioCapturedImage right, PixelDiffResult diff})
_alignAndDiff(
  StudioCapturedImage texMathImage,
  StudioCapturedImage targetImage, {
  required int bgArgb,
  required int channelTolerance,
}) {
  final ({StudioCapturedImage left, StudioCapturedImage right}) aligned =
      alignCapturedPair(
        texMathImage,
        targetImage,
        backgroundColor: Color(bgArgb),
      );
  final PixelDiffResult diff = computePixelDiff(
    aligned.left.rgbaBytes,
    aligned.right.rgbaBytes,
    aligned.left.width,
    aligned.left.height,
    channelTolerance: channelTolerance,
  );
  return (left: aligned.left, right: aligned.right, diff: diff);
}

/// Decodes packed RGBA8888 bytes into a Flutter [ui.Image].
Future<ui.Image> rgbaToUiImage(Uint8List rgba, int width, int height) {
  if (width <= 0 || height <= 0) {
    return Future<ui.Image>.error(
      ArgumentError('Image dimensions must be positive ($width x $height).'),
    );
  }
  if (rgba.length != width * height * 4) {
    return Future<ui.Image>.error(
      ArgumentError(
        'RGBA byte length (${rgba.length}) does not match ${width * height * 4}.',
      ),
    );
  }
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Interactive comparison stage rendering Side-by-Side (3-Way), Pixel Diff, or
/// Curtain Diff views.
final class StudioComparisonView extends StatefulWidget {
  /// Creates the interactive comparison stage.
  const StudioComparisonView({
    super.key,
    required this.mode,
    required this.diffTarget,
    required this.onDiffTargetChanged,
    required this.texMathBoundaryKey,
    required this.texMathPane,
    required this.mathJaxController,
    required this.katexController,
    required this.onCaptureRequested,
    this.capturedPair,
    this.isCapturing = false,
    this.isolateDiffPixelThreshold = 4096,
  });

  /// Active comparison display mode.
  final StudioComparisonMode mode;

  /// Selected external reference engine for two-way diffs.
  final StudioDiffTarget diffTarget;

  /// Invoked when the user switches the diff target engine.
  final ValueChanged<StudioDiffTarget> onDiffTargetChanged;

  /// Boundary key wrapping the `tex_math` render canvas for RGBA capture.
  final GlobalKey texMathBoundaryKey;

  /// Live `tex_math` pane widget.
  final Widget texMathPane;

  /// Controller managing the MathJax `4.1.3` comparison pane.
  final StudioWebPaneController mathJaxController;

  /// Controller managing the KaTeX `0.19.1` comparison pane.
  final StudioWebPaneController katexController;

  /// Invoked when the user triggers a live RGBA capture pass.
  final VoidCallback onCaptureRequested;

  /// Latest captured pair of images for pixel and curtain diffing.
  final StudioCapturedPair? capturedPair;

  /// Whether a capture operation is currently running.
  final bool isCapturing;

  /// Pixel count threshold above which diff alignment and pixel comparison
  /// run in [Isolate.run].
  final int isolateDiffPixelThreshold;

  @override
  State<StudioComparisonView> createState() => _StudioComparisonViewState();
}

final class _StudioComparisonViewState extends State<StudioComparisonView> {
  double _curtainFraction = 0.5;
  int _channelTolerance = 0;

  ui.Image? _leftImage;
  ui.Image? _rightImage;
  ui.Image? _diffImage;
  PixelDiffResult? _diffResult;
  int _decodeGeneration = 0;

  bool _hasComputedDiff = false;
  StudioCapturedPair? _lastComputedPair;
  Color? _lastComputedBg;
  int? _lastComputedTolerance;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleDiffAndDecodeIfChanged();
  }

  @override
  void didUpdateWidget(StudioComparisonView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.capturedPair != widget.capturedPair ||
        oldWidget.diffTarget != widget.diffTarget) {
      _scheduleDiffAndDecodeIfChanged();
    }
  }

  @override
  void dispose() {
    _decodeGeneration++;
    _disposeDecodedImages();
    super.dispose();
  }

  void _disposeDecodedImages() {
    _leftImage?.dispose();
    _rightImage?.dispose();
    _diffImage?.dispose();
    _leftImage = null;
    _rightImage = null;
    _diffImage = null;
  }

  StudioCapturedPair? get _effectivePair {
    final StudioCapturedPair? pair = widget.capturedPair;
    if (pair == null || pair.target != widget.diffTarget) {
      return null;
    }
    if (pair.texMathImage.width <= 0 ||
        pair.texMathImage.height <= 0 ||
        pair.targetImage.width <= 0 ||
        pair.targetImage.height <= 0) {
      return null;
    }
    return pair;
  }

  void _scheduleDiffAndDecodeIfChanged() {
    final StudioCapturedPair? pair = _effectivePair;
    final Color bg = _paneCanvasBackground(context);
    if (_hasComputedDiff &&
        _lastComputedPair == pair &&
        _lastComputedBg == bg &&
        _lastComputedTolerance == _channelTolerance) {
      return;
    }
    _hasComputedDiff = true;
    _lastComputedPair = pair;
    _lastComputedBg = bg;
    _lastComputedTolerance = _channelTolerance;

    final int gen = ++_decodeGeneration;
    if (pair == null) {
      _disposeDecodedImages();
      _diffResult = null;
      return;
    }

    final int maxPixels = math.max(
      pair.texMathImage.width * pair.texMathImage.height,
      pair.targetImage.width * pair.targetImage.height,
    );
    if (maxPixels <= widget.isolateDiffPixelThreshold) {
      final ({
        StudioCapturedImage left,
        StudioCapturedImage right,
        PixelDiffResult diff,
      })
      computed = _alignAndDiff(
        pair.texMathImage,
        pair.targetImage,
        bgArgb: bg.toARGB32(),
        channelTolerance: _channelTolerance,
      );
      _diffResult = computed.diff;
      unawaited(
        _decodeImagesAsync(gen, computed.left, computed.right, computed.diff),
      );
      return;
    }

    _disposeDecodedImages();
    _diffResult = null;
    unawaited(_computeDiffAndDecodeAsync(gen, pair, bg, _channelTolerance));
  }

  Future<void> _computeDiffAndDecodeAsync(
    int gen,
    StudioCapturedPair pair,
    Color bg,
    int channelTolerance,
  ) async {
    try {
      final ({
        StudioCapturedImage left,
        StudioCapturedImage right,
        PixelDiffResult diff,
      })
      computed = await computeAlignedPixelDiffAsync(
        pair.texMathImage,
        pair.targetImage,
        backgroundColor: bg,
        channelTolerance: channelTolerance,
      );
      if (!mounted || gen != _decodeGeneration) {
        return;
      }
      setState(() {
        _diffResult = computed.diff;
      });
      await _decodeImagesAsync(
        gen,
        computed.left,
        computed.right,
        computed.diff,
      );
    } on Object {
      // Ignore canceled or failed background diff passes.
    }
  }

  Future<void> _decodeImagesAsync(
    int gen,
    StudioCapturedImage left,
    StudioCapturedImage right,
    PixelDiffResult diff,
  ) async {
    bool batchAborted = false;
    ui.Image? leftImg;
    ui.Image? rightImg;
    ui.Image? diffImg;

    Future<ui.Image> trackedDecode(
      Uint8List bytes,
      int width,
      int height,
      void Function(ui.Image) assign,
    ) async {
      final ui.Image img = await rgbaToUiImage(bytes, width, height);
      if (batchAborted || !mounted || gen != _decodeGeneration) {
        img.dispose();
        throw StateError('Image decode batch superseded.');
      }
      assign(img);
      return img;
    }

    try {
      await Future.wait<ui.Image>(<Future<ui.Image>>[
        trackedDecode(
          left.rgbaBytes,
          left.width,
          left.height,
          (ui.Image img) => leftImg = img,
        ),
        trackedDecode(
          right.rgbaBytes,
          right.width,
          right.height,
          (ui.Image img) => rightImg = img,
        ),
        trackedDecode(
          diff.diffRgba,
          diff.width,
          diff.height,
          (ui.Image img) => diffImg = img,
        ),
      ]);
      if (!mounted || gen != _decodeGeneration) {
        leftImg?.dispose();
        rightImg?.dispose();
        diffImg?.dispose();
        return;
      }
      setState(() {
        _disposeDecodedImages();
        _leftImage = leftImg;
        _rightImage = rightImg;
        _diffImage = diffImg;
      });
    } on Object {
      batchAborted = true;
      leftImg?.dispose();
      rightImg?.dispose();
      diffImg?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.mode) {
      case StudioComparisonMode.sideBySide:
        return _buildSideBySide(context);
      case StudioComparisonMode.pixelDiff:
        return _buildPixelDiff(context);
      case StudioComparisonMode.curtainDiff:
        return _buildCurtainDiff(context);
    }
  }

  Color _paneCanvasBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : Colors.white;
  }

  Widget _buildSideBySide(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _PaneCard(
            title: 'tex_math (Pure Dart)',
            child: RepaintBoundary(
              key: widget.texMathBoundaryKey,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: _paneCanvasBackground(context),
                child: widget.texMathPane,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(child: _WebPaneCard(controller: widget.mathJaxController)),
        const SizedBox(width: 10.0),
        Expanded(child: _WebPaneCard(controller: widget.katexController)),
      ],
    );
  }

  Widget _buildTargetBar(BuildContext context, {Widget? trailing}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          SegmentedButton<StudioDiffTarget>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: StudioDiffTarget.values
                .map(
                  (StudioDiffTarget target) => ButtonSegment<StudioDiffTarget>(
                    value: target,
                    label: Text(target.label),
                  ),
                )
                .toList(),
            selected: <StudioDiffTarget>{widget.diffTarget},
            onSelectionChanged: (Set<StudioDiffTarget> next) {
              widget.onDiffTargetChanged(next.first);
            },
          ),
          const SizedBox(width: 8.0),
          FilledButton.tonalIcon(
            onPressed: widget.isCapturing ? null : widget.onCaptureRequested,
            icon: const Icon(Icons.camera_alt_outlined, size: 16.0),
            label: Text(widget.isCapturing ? 'Capturing…' : 'Capture & Diff'),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 8.0),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildPixelDiff(BuildContext context) {
    final PixelDiffResult? result = _diffResult;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildTargetBar(
              context,
              trailing: DropdownButton<int>(
                value: _channelTolerance,
                isDense: true,
                onChanged: (int? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _channelTolerance = value;
                    _scheduleDiffAndDecodeIfChanged();
                  });
                },
                items: const <DropdownMenuItem<int>>[
                  DropdownMenuItem<int>(value: 0, child: Text('Tolerance: 0')),
                  DropdownMenuItem<int>(value: 8, child: Text('Tolerance: 8')),
                  DropdownMenuItem<int>(
                    value: 24,
                    child: Text('Tolerance: 24'),
                  ),
                ],
              ),
            ),
            const Divider(height: 12.0),
            if (result != null) ...<Widget>[
              Wrap(
                spacing: 8.0,
                runSpacing: 6.0,
                children: <Widget>[
                  Chip(
                    label: Text(
                      'Match: ${result.matchPercentage.toStringAsFixed(2)}%',
                    ),
                  ),
                  Chip(
                    label: Text(
                      'Diff Pixels: ${result.diffPixelCount} / '
                      '${result.totalPixels}',
                    ),
                  ),
                  Chip(label: Text('Max Δ: ${result.maxChannelDelta}')),
                  Chip(label: Text('${result.width}×${result.height} px')),
                ],
              ),
              const SizedBox(height: 8.0),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(
                      child: _ImagePreviewFrame(
                        label: 'tex_math Capture',
                        image: _leftImage,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: _ImagePreviewFrame(
                        label: '${widget.diffTarget.label} Capture',
                        image: _rightImage,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: _ImagePreviewFrame(
                        label: 'RGBA Diff (Magenta)',
                        image: _diffImage,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_effectivePair != null)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 8.0),
                      Text('Computing RGBA diff…'),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'Capture live panes to compute per-pixel RGBA diff.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8.0),
                        OutlinedButton.icon(
                          onPressed: widget.isCapturing
                              ? null
                              : widget.onCaptureRequested,
                          icon: const Icon(Icons.compare),
                          label: const Text('Run Pixel Diff'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurtainDiff(BuildContext context) {
    final StudioCapturedPair? pair = _effectivePair;
    if (pair == null) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildTargetBar(context),
              const Divider(height: 12.0),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text(
                          'Capture live panes to inspect interactive curtain diff.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8.0),
                        OutlinedButton.icon(
                          onPressed: widget.isCapturing
                              ? null
                              : widget.onCaptureRequested,
                          icon: const Icon(Icons.compare),
                          label: const Text('Capture for Curtain Diff'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Color surfaceColor = Theme.of(context).colorScheme.surface;
    final Widget leftOverlay = Container(
      color: surfaceColor,
      alignment: Alignment.center,
      child: _leftImage != null
          ? RawImage(image: _leftImage, fit: BoxFit.contain)
          : const SizedBox.shrink(),
    );

    final Widget rightUnderlay = Container(
      color: surfaceColor,
      alignment: Alignment.center,
      child: _rightImage != null
          ? RawImage(image: _rightImage, fit: BoxFit.contain)
          : const SizedBox.shrink(),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildTargetBar(
              context,
              trailing: Text(
                'Curtain: ${(_curtainFraction * 100).round()}%',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            const Divider(height: 12.0),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double width = constraints.maxWidth > 0
                      ? constraints.maxWidth
                      : 1.0;
                  final double splitX = width * _curtainFraction;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails details) {
                      setState(() {
                        _curtainFraction = (details.localPosition.dx / width)
                            .clamp(0.0, 1.0);
                      });
                    },
                    onHorizontalDragUpdate: (DragUpdateDetails details) {
                      setState(() {
                        _curtainFraction = (details.localPosition.dx / width)
                            .clamp(0.0, 1.0);
                      });
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          rightUnderlay,
                          ClipRect(
                            clipper: _CurtainClipper(_curtainFraction),
                            child: leftOverlay,
                          ),
                          Positioned(
                            top: 8.0,
                            left: 8.0,
                            child: _CurtainLabelBadge(label: 'tex_math'),
                          ),
                          Positioned(
                            top: 8.0,
                            right: 8.0,
                            child: _CurtainLabelBadge(
                              label: widget.diffTarget.label,
                            ),
                          ),
                          Positioned(
                            left: (splitX - 1.5).clamp(0.0, width - 3.0),
                            top: 0.0,
                            bottom: 0.0,
                            width: 3.0,
                            child: ColoredBox(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Positioned(
                            left: (splitX - 14.0).clamp(0.0, width - 28.0),
                            top: (constraints.maxHeight / 2.0 - 14.0).clamp(
                              0.0,
                              math.max(0.0, constraints.maxHeight - 28.0),
                            ),
                            child: Container(
                              width: 28.0,
                              height: 28.0,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.compare_arrows,
                                size: 16.0,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6.0),
            Slider(
              value: _curtainFraction,
              onChanged: (double next) {
                setState(() {
                  _curtainFraction = next;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _CurtainClipper extends CustomClipper<Rect> {
  const _CurtainClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0.0, 0.0, size.width * fraction, size.height);
  }

  @override
  bool shouldReclip(_CurtainClipper oldClipper) {
    return oldClipper.fraction != fraction;
  }
}

final class _CurtainLabelBadge extends StatelessWidget {
  const _CurtainLabelBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

final class _ImagePreviewFrame extends StatelessWidget {
  const _ImagePreviewFrame({required this.label, required this.image});

  final String label;
  final ui.Image? image;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4.0),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: image == null
                ? const Center(child: Text('No image'))
                : Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: RawImage(image: image, fit: BoxFit.contain),
                  ),
          ),
        ),
      ],
    );
  }
}

final class _PaneCard extends StatelessWidget {
  const _PaneCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: 8.0),
                  Flexible(child: trailing!),
                ],
              ],
            ),
            const Divider(height: 12.0),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

final class _WebPaneCard extends StatelessWidget {
  const _WebPaneCard({required this.controller});

  final StudioWebPaneController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<StudioWebRenderTelemetry>(
      valueListenable: controller.telemetry,
      builder: (BuildContext context, StudioWebRenderTelemetry info, _) {
        final String subtitle = info.renderTimeMs != null
            ? '${info.renderTimeMs!.toStringAsFixed(1)} ms'
            : info.statusSummary;
        return _PaneCard(
          title: controller.engineKind.title,
          trailing: Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          child: controller.buildView(context),
        );
      },
    );
  }
}
