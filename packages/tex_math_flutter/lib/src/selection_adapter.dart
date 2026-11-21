import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:tex_math/tex_math.dart';

import 'display_painter.dart';
import 'theme.dart';

/// Policy controlling how [TexMath] handles rendered equations wider than the
/// available horizontal layout constraints.
enum TexMathOverflow {
  /// Wraps the equation in a horizontal [SingleChildScrollView] so long
  /// formulas remain readable at full size.
  scroll,

  /// Scales the rendered equation down uniformly via [FittedBox] to fit within
  /// the available horizontal constraints.
  scaleToFit,

  /// Clips overflowing portions cleanly at the widget boundary.
  clip,

  /// Allows overflowing glyphs and rules to paint outside the bounded width
  /// without clipping or scrolling.
  visible,
}

/// Utilities mapping display-item [SourceSpan] ranges to syntactically valid
/// TeX sub-expressions via the parsed [MathNode] tree.
abstract final class TexMathSelectionUtils {
  /// Expands [targetSpan] to the minimal enclosing [MathNode.span] inside
  /// [syntaxTree] and slices [source] to guarantee syntactically valid LaTeX.
  ///
  /// When [targetSpan] spans a proper contiguous slice of top-level children in
  /// [MathRootNode], the merged spans of those complete children are returned;
  /// when it covers all top-level children or falls outside [syntaxTree], the
  /// complete [source] span `SourceSpan(0, source.length)` is returned.
  static SourceSpan expandSpanToMinimalNode(
    MathNode? syntaxTree,
    SourceSpan targetSpan,
    String source,
  ) {
    if (source.isEmpty) {
      return SourceSpan.zero;
    }
    final SourceSpan fullSpan = SourceSpan(0, source.length);
    if (syntaxTree == null) {
      return fullSpan;
    }
    if (targetSpan.isEmpty ||
        targetSpan.start < 0 ||
        targetSpan.end > source.length) {
      return fullSpan;
    }
    final SourceSpan raw =
        _findMinimalSpan(syntaxTree, targetSpan, source.length) ?? fullSpan;
    return _normalizeNodeSpan(raw, source);
  }

  /// Convenience helper returning `expandSpanToMinimalNode(...).slice(source)`.
  static String sliceMinimalLatex(
    MathNode? syntaxTree,
    SourceSpan targetSpan,
    String source,
  ) {
    final SourceSpan expanded = expandSpanToMinimalNode(
      syntaxTree,
      targetSpan,
      source,
    );
    if (source.isEmpty || expanded.isEmpty) {
      return '';
    }
    return expanded.slice(source);
  }

  static SourceSpan? _findMinimalSpan(
    MathNode node,
    SourceSpan target,
    int sourceLength,
  ) {
    final List<MathNode> children = _childrenOf(node);

    MathNode? bestEnclosingChild;
    for (final MathNode child in children) {
      if (_isValidSpan(child.span, sourceLength) &&
          _encloses(child.span, target)) {
        if (bestEnclosingChild == null ||
            child.span.length < bestEnclosingChild.span.length) {
          bestEnclosingChild = child;
        }
      }
    }
    if (bestEnclosingChild != null) {
      return _findMinimalSpan(bestEnclosingChild, target, sourceLength) ??
          bestEnclosingChild.span;
    }

    if (node is MathRootNode) {
      final List<MathNode> validChildren = children
          .where((MathNode c) => _isValidSpan(c.span, sourceLength))
          .toList();
      final List<MathNode> touched = validChildren
          .where((MathNode c) => _overlaps(c.span, target))
          .toList();
      if (touched.isNotEmpty && touched.length < validChildren.length) {
        return touched.first.span.merge(touched.last.span);
      }
      return SourceSpan(0, sourceLength);
    }

    if (_isValidSpan(node.span, sourceLength) && _encloses(node.span, target)) {
      return node.span;
    }
    return null;
  }

  static SourceSpan _normalizeNodeSpan(SourceSpan span, String source) {
    final int start = span.start.clamp(0, source.length);
    int end = span.end.clamp(start, source.length);
    final String slice = source.substring(start, end);

    if (slice.endsWith(r'\end')) {
      end = _consumeOptionalBracedGroup(source, end);
    } else if (slice.endsWith(r'\right')) {
      end = _consumeDelimiterToken(source, end);
    }

    return _balanceBraces(source, SourceSpan(start, end));
  }

  static int _consumeOptionalBracedGroup(String source, int index) {
    int i = index;
    while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    if (i < source.length && source.codeUnitAt(i) == 0x7B /* { */ ) {
      int depth = 1;
      i++;
      while (i < source.length && depth > 0) {
        final int code = source.codeUnitAt(i);
        if (code == 0x5C /* \ */ ) {
          i = math.min(i + 2, source.length);
          continue;
        }
        if (code == 0x7B) {
          depth++;
        } else if (code == 0x7D) {
          depth--;
        }
        i++;
      }
      return i;
    }
    return index;
  }

  static int _consumeDelimiterToken(String source, int index) {
    int i = index;
    while (i < source.length && _isWhitespace(source.codeUnitAt(i))) {
      i++;
    }
    if (i >= source.length) {
      return index;
    }
    if (source.codeUnitAt(i) == 0x5C /* \ */ ) {
      i++;
      if (i < source.length && _isAsciiLetter(source.codeUnitAt(i))) {
        while (i < source.length && _isAsciiLetter(source.codeUnitAt(i))) {
          i++;
        }
      } else if (i < source.length) {
        i++;
      }
      return i;
    }
    return i + 1;
  }

  static SourceSpan _balanceBraces(String source, SourceSpan span) {
    final int start = span.start.clamp(0, source.length);
    int end = span.end.clamp(start, source.length);
    int depth = 0;
    for (int i = start; i < end; i++) {
      final int code = source.codeUnitAt(i);
      if (code == 0x5C /* \ */ ) {
        i++;
        continue;
      }
      if (code == 0x7B /* { */ ) {
        depth++;
      } else if (code == 0x7D /* } */ && depth > 0) {
        depth--;
      }
    }
    while (depth > 0 && end < source.length) {
      final int code = source.codeUnitAt(end);
      if (code == 0x5C /* \ */ ) {
        end = math.min(end + 2, source.length);
        continue;
      }
      if (code == 0x7B /* { */ ) {
        depth++;
      } else if (code == 0x7D /* } */ ) {
        depth--;
      }
      end++;
    }
    return SourceSpan(start, end);
  }

  static bool _isWhitespace(int codeUnit) =>
      codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;

  static bool _isAsciiLetter(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
      (codeUnit >= 0x61 && codeUnit <= 0x7A);

  static List<MathNode> _childrenOf(MathNode node) {
    switch (node) {
      case MathRootNode(:final List<MathNode> children):
      case MathGroupNode(:final List<MathNode> children):
      case DelimiterNode(:final List<MathNode> children):
      case StyleNode(:final List<MathNode> children):
      case ColorNode(:final List<MathNode> children):
      case TextNode(:final List<MathNode> children):
        return children;
      case FractionNode(:final MathNode numerator, :final MathNode denominator):
        return <MathNode>[numerator, denominator];
      case ScriptNode(
        :final MathNode base,
        :final MathNode? subscript,
        :final MathNode? superscript,
        :final MathNode? presubscript,
        :final MathNode? presuperscript,
      ):
        return <MathNode>[
          ?presubscript,
          ?presuperscript,
          base,
          ?subscript,
          ?superscript,
        ];
      case RadicalNode(:final MathNode radicand, :final MathNode? index):
        return <MathNode>[?index, radicand];
      case AccentNode(:final MathNode base):
        return <MathNode>[base];
      case MatrixNode(:final List<List<MathNode>> rows):
        return <MathNode>[for (final List<MathNode> row in rows) ...row];
      case TagNode(:final MathNode? body):
        return <MathNode>[?body];
      case SymbolNode():
      case OperatorNode():
      case SpaceNode():
      case ErrorNode():
        return const <MathNode>[];
    }
  }

  static bool _isValidSpan(SourceSpan span, int sourceLength) =>
      !span.isEmpty && span.start >= 0 && span.end <= sourceLength;

  static bool _encloses(SourceSpan outer, SourceSpan inner) =>
      outer.start <= inner.start && outer.end >= inner.end;

  static bool _overlaps(SourceSpan a, SourceSpan b) =>
      a.start < b.end && b.start < a.end;
}

/// Proxy render box forwarding alphabetic baseline metrics across wrappers
/// such as [SingleChildScrollView] or [FittedBox] without clipping descenders.
final class TexMathBaselineProxy extends SingleChildRenderObjectWidget {
  /// Creates a baseline proxy reporting [baseline] for its subtree.
  const TexMathBaselineProxy({
    super.key,
    required this.baseline,
    required super.child,
  });

  /// Alphabetic baseline offset from the top of the rendered math box.
  final double baseline;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTexMathBaselineProxy(baseline);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTexMathBaselineProxy renderObject,
  ) {
    renderObject.baseline = baseline;
  }
}

/// Proxy render box forwarding [baseline] across scrollable or scaled wrappers.
final class RenderTexMathBaselineProxy extends RenderProxyBox {
  /// Creates a baseline proxy reporting [_baseline].
  RenderTexMathBaselineProxy(this._baseline);

  double get baseline => _baseline;
  double _baseline;
  set baseline(double value) {
    if (_baseline == value) {
      return;
    }
    _baseline = value;
    markNeedsLayout();
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return this.baseline;
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    return this.baseline;
  }
}

/// Leaf render object widget painting a [DisplayList] via [TexMathDisplayPainter]
/// and participating in [SelectionArea] sub-expression selection.
final class TexMathRenderLeaf extends LeafRenderObjectWidget {
  /// Creates a selectable math leaf render widget.
  const TexMathRenderLeaf({
    super.key,
    required this.displayList,
    required this.syntaxTree,
    required this.source,
    required this.theme,
    required this.fontSize,
    required this.baseline,
    required this.font,
    required this.pathCache,
    required this.registrar,
  });

  /// Laid-out display list to paint.
  final DisplayList displayList;

  /// Parsed AST enabling minimal enclosing LaTeX selection expansion.
  final MathNode? syntaxTree;

  /// Original TeX source string.
  final String source;

  /// Active theme providing semantic colors.
  final TexMathThemeData theme;

  /// Effective logical pixel size for `1.0` em.
  final double fontSize;

  /// Alphabetic baseline distance from the top of the box in logical pixels.
  final double baseline;

  /// Active math font used for path caching.
  final MathFont? font;

  /// Path cache used when rendering glyph outlines.
  final TexMathPathCache pathCache;

  /// Active selection registrar when selectable, or `null`.
  final SelectionRegistrar? registrar;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderTexMath(
      displayList,
      syntaxTree,
      source,
      theme,
      fontSize,
      baseline,
      font,
      pathCache,
      registrar: registrar,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderTexMath renderObject,
  ) {
    renderObject
      ..displayList = displayList
      ..syntaxTree = syntaxTree
      ..source = source
      ..theme = theme
      ..fontSize = fontSize
      ..baseline = baseline
      ..font = font
      ..pathCache = pathCache
      ..registrar = registrar;
  }
}

final class _SelectableAtom {
  const _SelectableAtom({
    required this.rect,
    required this.span,
    required this.isHorizontalRule,
  });

  final Rect rect;
  final SourceSpan? span;
  final bool isHorizontalRule;
}

/// Custom [RenderBox] painting [DisplayList] items via [TexMathDisplayPainter],
/// exposing exact alphabetic baseline metrics, and implementing [Selectable]
/// with AST-expanded `"copy as LaTeX"` sub-expression selection.
final class RenderTexMath extends RenderBox
    with Selectable, SelectionRegistrant {
  /// Creates a math render box.
  RenderTexMath(
    this._displayList,
    this._syntaxTree,
    this._source,
    this._theme,
    this._fontSize,
    this._baseline,
    this._font,
    this._pathCache, {
    required SelectionRegistrar? registrar,
  }) {
    _rebuildAtoms();
    _selectionGeometry = _buildSelectionGeometry();
    this.registrar = registrar;
  }

  final ObserverList<VoidCallback> _listeners = ObserverList<VoidCallback>();

  DisplayList _displayList;
  MathNode? _syntaxTree;
  String _source;
  TexMathThemeData _theme;
  double _fontSize;
  double _baseline;
  MathFont? _font;
  TexMathPathCache _pathCache;

  List<_SelectableAtom> _atoms = const <_SelectableAtom>[];
  bool _isAllSelected = false;
  Offset? _startAnchor;
  Offset? _endAnchor;
  bool _startOutsidePrev = false;
  bool _startOutsideNext = false;
  bool _endOutsidePrev = false;
  bool _endOutsideNext = false;
  SourceSpan? _explicitSpan;
  int? _cursorSourceOffset;

  LayerLink? _startHandleLayerLink;
  LayerLink? _endHandleLayerLink;

  late SelectionGeometry _selectionGeometry;

  /// Laid-out display list rendered by this box.
  DisplayList get displayList => _displayList;
  set displayList(DisplayList value) {
    if (_displayList == value) {
      return;
    }
    _displayList = value;
    _clearSelectionState(notify: false);
    _rebuildAtoms();
    markNeedsLayout();
    _updateSelectionGeometry();
  }

  /// Parsed AST supporting expansion of partial drags to minimal valid LaTeX
  /// nodes.
  MathNode? get syntaxTree => _syntaxTree;
  set syntaxTree(MathNode? value) {
    if (_syntaxTree == value) {
      return;
    }
    _syntaxTree = value;
    _clearSelectionState(notify: false);
    _updateSelectionGeometry();
  }

  /// TeX source string corresponding to [displayList].
  String get source => _source;
  set source(String value) {
    if (_source == value) {
      return;
    }
    _source = value;
    _clearSelectionState(notify: false);
    _updateSelectionGeometry();
  }

  /// Active theme colors applied during [paint].
  TexMathThemeData get theme => _theme;
  set theme(TexMathThemeData value) {
    if (_theme == value) {
      return;
    }
    _theme = value;
    markNeedsPaint();
  }

  /// Scaled pixel font size corresponding to `1.0` em.
  double get fontSize => _fontSize;
  set fontSize(double value) {
    if (_fontSize == value) {
      return;
    }
    _fontSize = value;
    _rebuildAtoms();
    markNeedsLayout();
    _updateSelectionGeometry();
  }

  /// Alphabetic baseline offset from the top of the box in logical pixels.
  double get baseline => _baseline;
  set baseline(double value) {
    if (_baseline == value) {
      return;
    }
    _baseline = value;
    markNeedsLayout();
  }

  /// Active math font used for glyph path lookup.
  MathFont? get font => _font;
  set font(MathFont? value) {
    if (_font == value) {
      return;
    }
    _font = value;
    _rebuildAtoms();
    markNeedsPaint();
  }

  /// Cache used for glyph [Path] construction.
  TexMathPathCache get pathCache => _pathCache;
  set pathCache(TexMathPathCache value) {
    if (identical(_pathCache, value)) {
      return;
    }
    _pathCache = value;
    _rebuildAtoms();
    markNeedsPaint();
  }

  String get _effectiveSource =>
      _source.isNotEmpty ? _source : (_displayList.source ?? '');

  double get _naturalWidth =>
      (_displayList.metrics.widthEm * _fontSize).clamp(0.0, 1e6);

  double get _naturalHeight =>
      (_displayList.metrics.totalHeightEm * _fontSize).clamp(0.0, 1e6);

  double get _clampedBaseline => _baseline.clamp(0.0, _naturalHeight);

  @override
  SelectionGeometry get value => _selectionGeometry;

  @override
  int get contentLength => _effectiveSource.length;

  @override
  List<Rect> get boundingBoxes => <Rect>[Offset.zero & size];

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    final List<VoidCallback> listeners = _listeners.toList(growable: false);
    for (final VoidCallback listener in listeners) {
      if (_listeners.contains(listener)) {
        listener();
      }
    }
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (!attached) {
      return;
    }
    if (_startHandleLayerLink != startHandle) {
      _startHandleLayerLink = startHandle;
      markNeedsPaint();
    }
    if (_endHandleLayerLink != endHandle) {
      _endHandleLayerLink = endHandle;
      markNeedsPaint();
    }
  }

  @override
  bool hitTestSelf(Offset position) => registrar != null && contentLength > 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.constrain(Size(_naturalWidth, _naturalHeight));
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    return _clampedBaseline;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    return _clampedBaseline;
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size(_naturalWidth, _naturalHeight));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final List<Rect> highlightRects = _selectionGeometry.hasSelection
        ? _selectionGeometry.selectionRects
        : const <Rect>[];
    final TexMathDisplayPainter painter = TexMathDisplayPainter(
      displayList: _displayList,
      theme: _theme,
      fontSize: _fontSize,
      font: _font,
      pathCache: _pathCache,
      selectionRects: highlightRects,
    );
    context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    painter.paint(context.canvas, size);
    context.canvas.restore();

    if (_selectionGeometry.hasSelection) {
      if (_startHandleLayerLink != null &&
          _selectionGeometry.startSelectionPoint != null) {
        context.pushLayer(
          LeaderLayer(
            link: _startHandleLayerLink!,
            offset:
                offset + _selectionGeometry.startSelectionPoint!.localPosition,
          ),
          (PaintingContext context, Offset offset) {},
          Offset.zero,
        );
      }
      if (_endHandleLayerLink != null &&
          _selectionGeometry.endSelectionPoint != null) {
        context.pushLayer(
          LeaderLayer(
            link: _endHandleLayerLink!,
            offset:
                offset + _selectionGeometry.endSelectionPoint!.localPosition,
          ),
          (PaintingContext context, Offset offset) {},
          Offset.zero,
        );
      }
    }
  }

  @override
  SelectedContent? getSelectedContent() {
    if (_effectiveSource.isEmpty || !_hasActiveSelection) {
      return null;
    }
    if (_isAllSelected) {
      return SelectedContent(plainText: _effectiveSource);
    }
    final SourceSpan? resolved = _resolvedSelectedSpan();
    if (resolved == null) {
      if (_cursorSourceOffset != null) {
        return const SelectedContent(plainText: '');
      }
      return null;
    }
    if (resolved.isEmpty) {
      return const SelectedContent(plainText: '');
    }
    return SelectedContent(plainText: resolved.slice(_effectiveSource));
  }

  @override
  SelectedContentRange? getSelection() {
    if (_effectiveSource.isEmpty || !_hasActiveSelection) {
      return null;
    }
    if (_isAllSelected) {
      return SelectedContentRange(
        startOffset: 0,
        endOffset: _effectiveSource.length,
      );
    }
    final SourceSpan? resolved = _resolvedSelectedSpan();
    if (resolved != null) {
      return SelectedContentRange(
        startOffset: resolved.start,
        endOffset: resolved.end,
      );
    }
    if (_cursorSourceOffset != null) {
      return SelectedContentRange(
        startOffset: _cursorSourceOffset!,
        endOffset: _cursorSourceOffset!,
      );
    }
    return null;
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final SelectedContentRange? before = getSelection();
    late final SelectionResult result;

    switch (event.type) {
      case SelectionEventType.startEdgeUpdate:
      case SelectionEventType.endEdgeUpdate:
        final SelectionEdgeUpdateEvent edgeEvent =
            event as SelectionEdgeUpdateEvent;
        result = _handleEdgeUpdate(
          edgeEvent.globalPosition,
          isEnd: event.type == SelectionEventType.endEdgeUpdate,
        );
      case SelectionEventType.clear:
        _clearSelectionState(notify: false);
        result = SelectionResult.none;
      case SelectionEventType.selectAll:
        _selectAll();
        result = SelectionResult.none;
      case SelectionEventType.selectWord:
        final SelectWordSelectionEvent wordEvent =
            event as SelectWordSelectionEvent;
        result = _handleSelectWord(wordEvent.globalPosition);
      case SelectionEventType.selectParagraph:
        final SelectParagraphSelectionEvent paraEvent =
            event as SelectParagraphSelectionEvent;
        if (paraEvent.absorb) {
          _selectAll();
          result = SelectionResult.next;
        } else {
          final Offset localPos = _globalToLocal(paraEvent.globalPosition);
          final Rect bounds = Offset.zero & size;
          if (bounds.contains(localPos)) {
            _selectAll();
            result = SelectionResult.none;
          } else {
            result = SelectionUtils.getResultBasedOnRect(bounds, localPos);
          }
        }
      case SelectionEventType.granularlyExtendSelection:
        final GranularlyExtendSelectionEvent granularEvent =
            event as GranularlyExtendSelectionEvent;
        result = _handleGranularlyExtend(granularEvent);
      case SelectionEventType.directionallyExtendSelection:
        final DirectionallyExtendSelectionEvent dirEvent =
            event as DirectionallyExtendSelectionEvent;
        result = _handleDirectionallyExtend(dirEvent);
    }

    final SelectedContentRange? after = getSelection();
    if (before != after ||
        event.type == SelectionEventType.clear ||
        event.type == SelectionEventType.selectAll ||
        event.type == SelectionEventType.startEdgeUpdate ||
        event.type == SelectionEventType.endEdgeUpdate) {
      markNeedsPaint();
      _updateSelectionGeometry();
    }
    return result;
  }

  bool get _hasActiveSelection =>
      _isAllSelected ||
      _explicitSpan != null ||
      (_startAnchor != null && _endAnchor != null);

  void _selectAll() {
    _isAllSelected = _effectiveSource.isNotEmpty;
    _explicitSpan = null;
    _cursorSourceOffset = null;
    _startAnchor = Offset.zero;
    _endAnchor = Offset(size.width, size.height);
    _startOutsidePrev = true;
    _startOutsideNext = false;
    _endOutsidePrev = false;
    _endOutsideNext = true;
  }

  void _clearSelectionState({required bool notify}) {
    _isAllSelected = false;
    _explicitSpan = null;
    _cursorSourceOffset = null;
    _startAnchor = null;
    _endAnchor = null;
    _startOutsidePrev = false;
    _startOutsideNext = false;
    _endOutsidePrev = false;
    _endOutsideNext = false;
    if (notify) {
      markNeedsPaint();
      _updateSelectionGeometry();
    }
  }

  SelectionResult _handleEdgeUpdate(
    Offset globalPosition, {
    required bool isEnd,
  }) {
    final Offset localPos = _globalToLocal(globalPosition);
    final Rect bounds = Offset.zero & size;
    final SelectionResult result = SelectionUtils.getResultBasedOnRect(
      bounds,
      localPos,
    );
    final Offset adjusted = SelectionUtils.adjustDragOffset(bounds, localPos);

    _isAllSelected = false;
    _explicitSpan = null;
    if (isEnd) {
      _endAnchor = adjusted;
      _endOutsidePrev = result == SelectionResult.previous;
      _endOutsideNext = result == SelectionResult.next;
    } else {
      _startAnchor = adjusted;
      _startOutsidePrev = result == SelectionResult.previous;
      _startOutsideNext = result == SelectionResult.next;
    }

    if ((_startOutsidePrev && _endOutsideNext) ||
        (_endOutsidePrev && _startOutsideNext)) {
      _isAllSelected = _effectiveSource.isNotEmpty;
    } else if ((_startOutsidePrev && _endOutsidePrev) ||
        (_startOutsideNext && _endOutsideNext)) {
      _cursorSourceOffset = (_startOutsidePrev && _endOutsidePrev)
          ? 0
          : _effectiveSource.length;
    } else {
      _cursorSourceOffset = _nearestSourceOffset(adjusted);
    }

    return result;
  }

  SelectionResult _handleSelectWord(Offset globalPosition) {
    final Offset localPos = _globalToLocal(globalPosition);
    final Rect bounds = Offset.zero & size;
    if (!bounds.contains(localPos)) {
      return SelectionUtils.getResultBasedOnRect(bounds, localPos);
    }
    final _SelectableAtom? hit = _closestAtom(localPos);
    if (hit == null || hit.span == null || _effectiveSource.isEmpty) {
      _selectAll();
      return SelectionResult.end;
    }
    _isAllSelected = false;
    _startAnchor = hit.rect.topLeft;
    _endAnchor = hit.rect.bottomRight;
    _startOutsidePrev = false;
    _startOutsideNext = false;
    _endOutsidePrev = false;
    _endOutsideNext = false;
    _explicitSpan = TexMathSelectionUtils.expandSpanToMinimalNode(
      _syntaxTree,
      hit.span!,
      _effectiveSource,
    );
    return SelectionResult.end;
  }

  SelectionResult _handleGranularlyExtend(
    GranularlyExtendSelectionEvent event,
  ) {
    final int len = _effectiveSource.length;
    if (len == 0) {
      return SelectionResult.none;
    }
    if (event.granularity == TextGranularity.document) {
      _selectAll();
      return SelectionResult.none;
    }

    final SelectedContentRange current =
        getSelection() ??
        const SelectedContentRange(startOffset: 0, endOffset: 0);
    int start = current.startOffset;
    int end = current.endOffset;
    final int delta = event.forward ? 1 : -1;

    if (event.isEnd) {
      end = (end + delta).clamp(0, len);
    } else {
      start = (start + delta).clamp(0, len);
    }
    final int lo = math.min(start, end);
    final int hi = math.max(start, end);
    _isAllSelected = lo == 0 && hi == len;
    if (!_isAllSelected) {
      if (lo == hi) {
        _explicitSpan = null;
        _cursorSourceOffset = lo;
      } else {
        _explicitSpan = TexMathSelectionUtils.expandSpanToMinimalNode(
          _syntaxTree,
          SourceSpan(lo, hi),
          _effectiveSource,
        );
      }
    }
    if (event.forward && hi >= len) {
      return SelectionResult.next;
    }
    if (!event.forward && lo <= 0) {
      return SelectionResult.previous;
    }
    return SelectionResult.end;
  }

  SelectionResult _handleDirectionallyExtend(
    DirectionallyExtendSelectionEvent event,
  ) {
    final Rect bounds = Offset.zero & size;
    final Offset localPos = _globalToLocal(Offset(event.dx, 0.0));
    final double clampedX = localPos.dx.clamp(bounds.left, bounds.right);
    final Offset targetPoint = switch (event.direction) {
      SelectionExtendDirection.previousLine => Offset(clampedX, bounds.top),
      SelectionExtendDirection.nextLine => Offset(clampedX, bounds.bottom),
      SelectionExtendDirection.forward ||
      SelectionExtendDirection.backward => Offset(clampedX, bounds.center.dy),
    };

    if (!hasSelection) {
      _startAnchor =
          event.direction == SelectionExtendDirection.backward ||
              event.direction == SelectionExtendDirection.previousLine
          ? bounds.bottomRight
          : bounds.topLeft;
      _endAnchor = targetPoint;
    } else if (event.isEnd) {
      _endAnchor = targetPoint;
    } else {
      _startAnchor = targetPoint;
    }
    _isAllSelected = false;
    _explicitSpan = null;
    _cursorSourceOffset = _nearestSourceOffset(targetPoint);
    return SelectionResult.end;
  }

  bool get _hasSelection => _selectionGeometry.hasSelection;
  bool get hasSelection => _hasSelection;

  SourceSpan? _resolvedSelectedSpan() {
    if (_effectiveSource.isEmpty) {
      return null;
    }
    if (_isAllSelected) {
      return SourceSpan(0, _effectiveSource.length);
    }
    if (_explicitSpan != null) {
      return _explicitSpan;
    }
    if (_startAnchor == null || _endAnchor == null) {
      return null;
    }
    final Offset p1 = _startAnchor!;
    final Offset p2 = _endAnchor!;
    if ((p1 - p2).distance < 1.0 && !_startOutsidePrev && !_endOutsideNext) {
      return null;
    }
    final List<_SelectableAtom> hitAtoms = _atomsInDragRange(p1, p2);
    if (hitAtoms.isEmpty) {
      return null;
    }
    SourceSpan? merged;
    for (final _SelectableAtom atom in hitAtoms) {
      final SourceSpan? span = atom.span;
      if (span == null || span.isEmpty) {
        continue;
      }
      if (span.start < 0 || span.end > _effectiveSource.length) {
        continue;
      }
      merged = merged == null ? span : merged.merge(span);
    }
    if (merged == null) {
      return SourceSpan(0, _effectiveSource.length);
    }
    return TexMathSelectionUtils.expandSpanToMinimalNode(
      _syntaxTree,
      merged,
      _effectiveSource,
    );
  }

  List<_SelectableAtom> _atomsInDragRange(Offset p1, Offset p2) {
    if (_atoms.isEmpty) {
      return const <_SelectableAtom>[];
    }
    final double minX = math.min(p1.dx, p2.dx);
    final double maxX = math.max(p1.dx, p2.dx);
    final double rawMinY = math.min(p1.dy, p2.dy);
    final double rawMaxY = math.max(p1.dy, p2.dy);
    final double padY = _fontSize * 0.35;
    final Rect searchRect = Rect.fromLTRB(
      minX - 1.0,
      rawMinY - padY,
      maxX + 1.0,
      rawMaxY + padY,
    );

    final double midY = (rawMinY + rawMaxY) * 0.5;
    final List<double> blockingBarsY = <double>[];
    for (final _SelectableAtom atom in _atoms) {
      if (!atom.isHorizontalRule) {
        continue;
      }
      final bool overlapsX = atom.rect.right >= minX && atom.rect.left <= maxX;
      final bool rawDragCrossesBar =
          rawMinY <= atom.rect.bottom && rawMaxY >= atom.rect.top;
      if (overlapsX && !rawDragCrossesBar) {
        blockingBarsY.add(atom.rect.center.dy);
      }
    }

    final List<_SelectableAtom> hits = <_SelectableAtom>[];
    for (final _SelectableAtom atom in _atoms) {
      if (!atom.rect.overlaps(searchRect)) {
        continue;
      }
      final double atomCenterY = atom.rect.center.dy;
      bool blockedByBar = false;
      for (final double barY in blockingBarsY) {
        if ((midY < barY && atomCenterY >= barY) ||
            (midY > barY && atomCenterY <= barY)) {
          blockedByBar = true;
          break;
        }
      }
      if (!blockedByBar) {
        hits.add(atom);
      }
    }
    return hits;
  }

  _SelectableAtom? _closestAtom(Offset localPos) {
    _SelectableAtom? best;
    double bestDist = double.infinity;
    for (final _SelectableAtom atom in _atoms) {
      if (atom.rect.contains(localPos)) {
        return atom;
      }
      final double dx = (localPos.dx - atom.rect.center.dx).abs();
      final double dy = (localPos.dy - atom.rect.center.dy).abs();
      final double dist = dx * dx + dy * dy;
      if (dist < bestDist) {
        bestDist = dist;
        best = atom;
      }
    }
    return best;
  }

  int _nearestSourceOffset(Offset localPos) {
    final _SelectableAtom? atom = _closestAtom(localPos);
    if (atom == null || atom.span == null) {
      return localPos.dx >= size.width * 0.5 ? _effectiveSource.length : 0;
    }
    final int clampedStart = atom.span!.start.clamp(0, _effectiveSource.length);
    final int clampedEnd = atom.span!.end.clamp(0, _effectiveSource.length);
    return localPos.dx >= atom.rect.center.dx ? clampedEnd : clampedStart;
  }

  Offset _globalToLocal(Offset globalPosition) {
    final Matrix4 transform = getTransformTo(null);
    transform.invert();
    return MatrixUtils.transformPoint(transform, globalPosition);
  }

  void _rebuildAtoms() {
    final DisplayMetrics metrics = _displayList.metrics;
    final double safeFontSize = _fontSize.isFinite && _fontSize > 0
        ? _fontSize
        : _theme.fontSize;
    final double unitsScale = safeFontSize / metrics.unitsPerEm;
    final List<_SelectableAtom> built = <_SelectableAtom>[];

    for (final DisplayItem item in _displayList.items) {
      switch (item) {
        case RuleItem(
          :final double xEm,
          :final double yEm,
          :final double widthEm,
          :final double heightEm,
          :final SourceSpan? span,
        ):
          final double left = xEm * safeFontSize;
          final double top =
              (metrics.baselineEm - (yEm + heightEm)) * safeFontSize;
          final double width = math.max(widthEm * safeFontSize, 1.0);
          final double height = math.max(heightEm * safeFontSize, 2.0);
          final bool isHorizontalRule =
              widthEm > heightEm * 2.0 && item.strokeWidthEm == null;
          built.add(
            _SelectableAtom(
              rect: Rect.fromLTWH(left, top, width, height),
              span: span,
              isHorizontalRule: isHorizontalRule,
            ),
          );

        case GlyphItem(
          :final int glyphId,
          :final double xEm,
          :final double yEm,
          :final double scaleX,
          :final double scaleY,
          :final double advanceEm,
          :final GlyphOutline? outline,
          :final SourceSpan? span,
        ):
          final double dx = xEm * safeFontSize;
          final double dy = (metrics.baselineEm - yEm) * safeFontSize;
          final Path? cachedPath = (outline != null || _font != null)
              ? _pathCache.resolvePath(
                  glyphId: glyphId,
                  font: _font,
                  outline: outline,
                )
              : null;
          late final Rect rect;
          if (cachedPath != null) {
            final Rect pathBounds = cachedPath.getBounds();
            final double left = math.min(
              dx,
              dx + pathBounds.left * unitsScale * scaleX,
            );
            final double right = math.max(
              dx + advanceEm * safeFontSize,
              dx + pathBounds.right * unitsScale * scaleX,
            );
            double top = dy - pathBounds.bottom * unitsScale * scaleY;
            double bottom = dy - pathBounds.top * unitsScale * scaleY;
            final double minHeight = safeFontSize * 0.25;
            if (bottom - top < minHeight) {
              final double mid = (top + bottom) * 0.5;
              top = mid - minHeight * 0.5;
              bottom = mid + minHeight * 0.5;
            }
            rect = Rect.fromLTRB(
              left,
              top,
              math.max(right, left + 1.0),
              math.max(bottom, top + 1.0),
            );
          } else {
            rect = Rect.fromLTWH(
              dx,
              dy - 0.7 * safeFontSize * scaleY,
              math.max(advanceEm * safeFontSize, 0.25 * safeFontSize),
              math.max(0.9 * safeFontSize * scaleY, 1.0),
            );
          }
          built.add(
            _SelectableAtom(rect: rect, span: span, isHorizontalRule: false),
          );

        case AnchorItem():
          break;
      }
    }
    _atoms = List<_SelectableAtom>.unmodifiable(built);
  }

  void _updateSelectionGeometry() {
    final SelectionGeometry next = _buildSelectionGeometry();
    if (_selectionGeometry == next) {
      return;
    }
    _selectionGeometry = next;
    _notifyListeners();
  }

  SelectionGeometry _buildSelectionGeometry() {
    final bool hasContent = _effectiveSource.isNotEmpty;
    if (!hasContent || !_hasActiveSelection) {
      return SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: hasContent,
      );
    }

    final Rect fullBox =
        Offset.zero & (hasSize ? size : Size(_naturalWidth, _naturalHeight));
    if (_isAllSelected) {
      return SelectionGeometry(
        startSelectionPoint: SelectionPoint(
          localPosition: fullBox.bottomLeft,
          lineHeight: fullBox.height,
          handleType: TextSelectionHandleType.left,
        ),
        endSelectionPoint: SelectionPoint(
          localPosition: fullBox.bottomRight,
          lineHeight: fullBox.height,
          handleType: TextSelectionHandleType.right,
        ),
        selectionRects: <Rect>[fullBox],
        status: SelectionStatus.uncollapsed,
        hasContent: true,
      );
    }

    final SourceSpan? resolved = _resolvedSelectedSpan();
    if (resolved == null || resolved.isEmpty) {
      final Offset cursor = _startAnchor ?? _endAnchor ?? fullBox.bottomLeft;
      final Offset handlePos = Offset(
        cursor.dx.clamp(fullBox.left, fullBox.right),
        fullBox.bottom,
      );
      return SelectionGeometry(
        startSelectionPoint: SelectionPoint(
          localPosition: handlePos,
          lineHeight: fullBox.height,
          handleType: TextSelectionHandleType.collapsed,
        ),
        endSelectionPoint: SelectionPoint(
          localPosition: handlePos,
          lineHeight: fullBox.height,
          handleType: TextSelectionHandleType.collapsed,
        ),
        status: SelectionStatus.collapsed,
        hasContent: true,
      );
    }

    Rect? unionRect;
    for (final _SelectableAtom atom in _atoms) {
      final SourceSpan? atomSpan = atom.span;
      if (atomSpan != null &&
          !atomSpan.isEmpty &&
          TexMathSelectionUtils._overlaps(atomSpan, resolved)) {
        unionRect = unionRect == null
            ? atom.rect
            : unionRect.expandToInclude(atom.rect);
      }
    }
    final Rect highlight = unionRect ?? fullBox;
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: highlight.bottomLeft,
        lineHeight: highlight.height,
        handleType: TextSelectionHandleType.left,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: highlight.bottomRight,
        lineHeight: highlight.height,
        handleType: TextSelectionHandleType.right,
      ),
      selectionRects: <Rect>[highlight],
      status: SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }
}
