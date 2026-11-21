import 'dart:math' as math;

import '../ast.dart';
import '../display_list.dart';
import '../error.dart';
import '../font.dart';
import '../options.dart';
import '../source_span.dart';
import 'box.dart';
import 'glyph_resolve.dart';
import 'matrix_layout.dart';
import 'stretchy.dart';
import 'style_spacing.dart';

/// Lays out a parsed [MathNode] syntax tree into a coordinate-resolved
/// [DisplayList] strictly driven by [font]'s OpenType `MATH` table.
DisplayList layoutMathTree(
  MathNode syntaxTree, {
  required MathFont font,
  required TexMathOptions options,
  String? source,
}) {
  if (font.mathTable == null) {
    throw TexMathFontError(
      'MathFont is missing an OpenType MATH table required for layout.',
      errorClass: TexMathErrorClass.invalidFont,
      span: syntaxTree.span,
    );
  }

  final TexMathDisplayMode rootDisplayMode = syntaxTree is MathRootNode
      ? syntaxTree.displayMode
      : options.displayMode;
  final TexMathStyle initialStyle =
      rootDisplayMode == TexMathDisplayMode.display
      ? TexMathStyle.display
      : TexMathStyle.text;
  final Map<String, String> labels = syntaxTree is MathRootNode
      ? syntaxTree.labels
      : const <String, String>{};

  final _AppendixGLayoutEngine engine = _AppendixGLayoutEngine(
    font: font,
    mathTable: font.mathTable!,
    options: options,
    labels: labels,
  );
  final MathBox rootBox = engine._layoutNode(
    syntaxTree,
    _LayoutState(style: initialStyle, isTopLevel: true),
  );
  return rootBox.toDisplayList(
    unitsPerEm: font.unitsPerEm,
    source: source,
    maxOutputItems: options.budgets.maxOutputItems,
  );
}

class _LayoutState {
  const _LayoutState({
    required this.style,
    this.fontVariant,
    this.isTextMode = false,
    this.fontScale = 1.0,
    this.isTopLevel = false,
  });

  final TexMathStyle style;
  final TexMathFontVariant? fontVariant;
  final bool isTextMode;
  final double fontScale;
  final bool isTopLevel;

  _LayoutState copyWith({
    TexMathStyle? style,
    TexMathFontVariant? fontVariant,
    bool clearFontVariant = false,
    bool? isTextMode,
    double? fontScale,
    bool? isTopLevel,
  }) {
    return _LayoutState(
      style: style ?? this.style,
      fontVariant: clearFontVariant ? null : (fontVariant ?? this.fontVariant),
      isTextMode: isTextMode ?? this.isTextMode,
      fontScale: fontScale ?? this.fontScale,
      isTopLevel: isTopLevel ?? this.isTopLevel,
    );
  }

  _LayoutState nested({
    TexMathStyle? style,
    TexMathFontVariant? fontVariant,
    bool clearFontVariant = false,
    bool? isTextMode,
    double? fontScale,
  }) {
    return copyWith(
      style: style,
      fontVariant: fontVariant,
      clearFontVariant: clearFontVariant,
      isTextMode: isTextMode,
      fontScale: fontScale,
      isTopLevel: false,
    );
  }
}

class _RowAtom {
  const _RowAtom({
    required this.box,
    required this.scriptLevel,
    required this.isTransparent,
  });

  final MathBox box;
  final int scriptLevel;
  final bool isTransparent;
}

class _AppendixGLayoutEngine {
  _AppendixGLayoutEngine({
    required this.font,
    required this.mathTable,
    required this.options,
    required this.labels,
  }) : constants = mathTable.constants,
       upem = font.unitsPerEm.toDouble();

  final MathFont font;
  final MathTableData mathTable;
  final MathConstants constants;
  final TexMathOptions options;
  final Map<String, String> labels;
  final double upem;

  double _scale(_LayoutState state) =>
      scaleForStyle(state.style, constants) * state.fontScale;

  MathBox _layoutNode(
    MathNode node,
    _LayoutState state, {
    TexMathAtomClass? leadingImplicitClass,
  }) {
    switch (node) {
      case MathRootNode(:final List<MathNode> children):
        return _layoutSequence(
          children,
          state,
          span: node.span,
          leadingImplicitClass: leadingImplicitClass,
        );

      case MathGroupNode():
        return _layoutGroupNode(
          node,
          state,
          leadingImplicitClass: leadingImplicitClass,
        );

      case SymbolNode():
        return _layoutSymbolNode(node, state);

      case OperatorNode():
        return _layoutOperatorNode(node, state);

      case FractionNode():
        return _layoutFractionNode(node, state);

      case ScriptNode():
        return _layoutScriptNode(node, state);

      case RadicalNode():
        return _layoutRadicalNode(node, state);

      case AccentNode():
        return _layoutAccentNode(node, state);

      case DelimiterNode():
        return _layoutDelimiterNode(node, state);

      case MatrixNode():
        return layoutMatrixNode(
          node: node,
          font: font,
          currentStyle: state.style,
          fontScale: state.fontScale,
          layoutCell:
              (
                MathNode cell, {
                required TexMathStyle style,
                TexMathAtomClass? leadingImplicitClass,
              }) {
                return _layoutNode(
                  cell,
                  state.nested(style: style),
                  leadingImplicitClass: leadingImplicitClass,
                );
              },
        );

      case TextNode():
        return _layoutTextNode(node, state.nested());

      case SpaceNode():
        final double scale = _scale(state);
        final BreakPoint bp = (state.isTopLevel && node.command == r'\\')
            ? const BreakPoint(
                kind: MathBreakKind.explicit,
                isExplicit: true,
                isGood: true,
              )
            : BreakPoint.none;
        return KernBox(
          widthEm: node.widthEm * scale,
          atomClass: TexMathAtomClass.ord,
          span: node.span,
          breakPoint: bp,
        );

      case StyleNode():
        return _layoutSequence(
          node.children,
          state.copyWith(
            style: node.style,
            fontScale: node.scaleEm ?? state.fontScale,
          ),
          span: node.span,
          leadingImplicitClass: leadingImplicitClass,
        );

      case ColorNode():
        return _layoutColorNode(node, state);

      case TagNode():
        return _layoutTagNode(node, state.nested());

      case ErrorNode():
        final String display = node.rawSource.isNotEmpty
            ? node.rawSource
            : node.error.message;
        final MathBox errBox = _layoutTextNode(
          TextNode(span: node.span, text: display, styleCommand: 'texttt'),
          state.nested(isTextMode: true),
        );
        return errBox.withMetadata(
          atomClass: TexMathAtomClass.ord,
          colorRole: TexMathColorRole.error,
          inheritColor: false,
        );
    }
  }

  MathBox _layoutSequence(
    List<MathNode> nodes,
    _LayoutState state, {
    SourceSpan? span,
    TexMathAtomClass outerClass = TexMathAtomClass.ord,
    TexMathAtomClass? leadingImplicitClass,
    bool preserveInnerBoundaryClass = false,
  }) {
    if (nodes.isEmpty) {
      return KernBox(widthEm: 0.0, atomClass: outerClass, span: span);
    }

    final double scale = _scale(state);
    final int curLevel = scriptLevelForStyle(state.style);
    final List<_RowAtom> rawAtoms = <_RowAtom>[];

    for (int i = 0; i < nodes.length; i++) {
      final MathNode child = nodes[i];
      _appendNodeAtoms(
        node: child,
        state: state,
        nextSibling: i + 1 < nodes.length ? nodes[i + 1] : null,
        out: rawAtoms,
        defaultLevel: curLevel,
      );
    }

    if (rawAtoms.isEmpty) {
      return KernBox(widthEm: 0.0, atomClass: outerClass, span: span);
    }

    if (rawAtoms.length == 1 &&
        !rawAtoms[0].isTransparent &&
        leadingImplicitClass == null) {
      final _RowAtom entry = rawAtoms[0];
      if (entry.box is! KernBox) {
        final TexMathAtomClass promotedClass = promoteAtomClass(
          atomClass: entry.box.atomClass,
          prevClass: null,
          nextClass: null,
        );
        final BreakPoint breakHint = state.isTopLevel
            ? _breakPointForClass(promotedClass, existing: entry.box.breakPoint)
            : BreakPoint.none;
        final TexMathAtomClass finalOuterClass = preserveInnerBoundaryClass
            ? promotedClass
            : outerClass;
        if (entry.box.atomClass == finalOuterClass &&
            entry.box.breakPoint == breakHint) {
          return entry.box;
        }
        return entry.box.withMetadata(
          atomClass: finalOuterClass,
          breakPoint: breakHint,
        );
      }
    }

    // Collect indices of non-transparent atoms for unary/binary resolution.
    final int rawCount = rawAtoms.length;
    final List<int> atomIndices = <int>[];
    final List<TexMathAtomClass> promoted = List<TexMathAtomClass>.filled(
      rawCount,
      TexMathAtomClass.ord,
    );
    for (int i = 0; i < rawCount; i++) {
      final _RowAtom raw = rawAtoms[i];
      promoted[i] = raw.box.atomClass;
      if (!raw.isTransparent) {
        atomIndices.add(i);
      }
    }

    // Resolve unary/binary `+`, `-`, `\pm`, `\mp` promotions.
    for (int k = 0; k < atomIndices.length; k++) {
      final int idx = atomIndices[k];
      final TexMathAtomClass? prevClass = k > 0
          ? promoted[atomIndices[k - 1]]
          : leadingImplicitClass;
      final TexMathAtomClass? nextClass = k + 1 < atomIndices.length
          ? rawAtoms[atomIndices[k + 1]].box.atomClass
          : null;
      promoted[idx] = promoteAtomClass(
        atomClass: promoted[idx],
        prevClass: prevClass,
        nextClass: nextClass,
      );
    }

    // Insert TeX inter-atom spacing and BreakPoint hints.
    final List<MathBox> laidChildren = <MathBox>[];
    int? prevAtomIdx;
    TexMathAtomClass? prevAtomClass = leadingImplicitClass;
    int prevAtomLevel = curLevel;

    for (int i = 0; i < rawAtoms.length; i++) {
      final _RowAtom entry = rawAtoms[i];
      if (entry.isTransparent) {
        laidChildren.add(entry.box);
        continue;
      }

      final TexMathAtomClass resolvedClass = promoted[i];
      if (prevAtomClass != null &&
          (prevAtomIdx != null || leadingImplicitClass != null)) {
        final double spaceEm = interAtomSpaceEm(
          left: prevAtomClass,
          right: resolvedClass,
          leftLevel: prevAtomLevel,
          rightLevel: entry.scriptLevel,
          styleScale: scale,
        );
        if (spaceEm > 0.0) {
          laidChildren.add(KernBox(widthEm: spaceEm));
        }
      }

      final BreakPoint breakHint = state.isTopLevel
          ? _breakPointForClass(resolvedClass, existing: entry.box.breakPoint)
          : BreakPoint.none;
      final MathBox updated =
          (resolvedClass != entry.box.atomClass ||
              breakHint != entry.box.breakPoint)
          ? entry.box.withMetadata(
              atomClass: resolvedClass,
              breakPoint: breakHint,
            )
          : entry.box;
      laidChildren.add(updated);

      prevAtomIdx = i;
      prevAtomClass = resolvedClass;
      prevAtomLevel = entry.scriptLevel;
    }

    final TexMathAtomClass finalOuterClass =
        preserveInnerBoundaryClass && atomIndices.length == 1
        ? promoted[atomIndices.first]
        : outerClass;

    if (laidChildren.length == 1 && laidChildren.first is! KernBox) {
      final MathBox single = laidChildren.first;
      return single.atomClass == finalOuterClass
          ? single
          : single.withMetadata(atomClass: finalOuterClass);
    }
    return HBox(children: laidChildren, atomClass: finalOuterClass, span: span);
  }

  void _appendNodeAtoms({
    required MathNode node,
    required _LayoutState state,
    required MathNode? nextSibling,
    required List<_RowAtom> out,
    required int defaultLevel,
  }) {
    if (node is StyleNode) {
      final _LayoutState subState = state.copyWith(
        style: node.style,
        fontScale: node.scaleEm ?? state.fontScale,
      );
      final int subLevel = scriptLevelForStyle(subState.style);
      for (int i = 0; i < node.children.length; i++) {
        _appendNodeAtoms(
          node: node.children[i],
          state: subState,
          nextSibling: i + 1 < node.children.length
              ? node.children[i + 1]
              : nextSibling,
          out: out,
          defaultLevel: subLevel,
        );
      }
      return;
    }

    if (node is MathGroupNode &&
        node.role == null &&
        !node.isExplicitGroup &&
        node.atomClass == null) {
      final _LayoutState subState = node.fontVariant != null
          ? state.copyWith(fontVariant: node.fontVariant)
          : state;
      for (int i = 0; i < node.children.length; i++) {
        _appendNodeAtoms(
          node: node.children[i],
          state: subState,
          nextSibling: i + 1 < node.children.length
              ? node.children[i + 1]
              : nextSibling,
          out: out,
          defaultLevel: defaultLevel,
        );
      }
      return;
    }

    final MathBox box = _layoutNode(node, state);
    if (node is OperatorNode && node.command == 'bmod') {
      final double pad = thickMuSkipEm * _scale(state);
      out.add(
        _RowAtom(
          box: HBox(
            children: <MathBox>[
              KernBox(widthEm: pad),
              box,
              KernBox(widthEm: pad),
            ],
            atomClass: TexMathAtomClass.ord,
            span: node.span,
          ),
          scriptLevel: defaultLevel,
          isTransparent: false,
        ),
      );
      return;
    }
    final bool isTransparent =
        node is SpaceNode || (node is TagNode && node.isLabelDefinition);
    out.add(
      _RowAtom(
        box: box,
        scriptLevel: defaultLevel,
        isTransparent: isTransparent,
      ),
    );

    if (_isNamedFunctionAtom(node) && _shouldInsertApplyFunction(nextSibling)) {
      out.add(
        _RowAtom(
          box: buildApplyFunctionBox(span: node.span),
          scriptLevel: defaultLevel,
          isTransparent: true,
        ),
      );
    }
  }

  BreakPoint _breakPointForClass(
    TexMathAtomClass atomClass, {
    required BreakPoint existing,
  }) {
    if (existing != BreakPoint.none) {
      return existing;
    }
    switch (atomClass) {
      case TexMathAtomClass.bin:
        return const BreakPoint(kind: MathBreakKind.afterBinary, penalty: 700);
      case TexMathAtomClass.rel:
        return const BreakPoint(
          kind: MathBreakKind.afterRelation,
          penalty: 500,
        );
      case TexMathAtomClass.ord:
      case TexMathAtomClass.op:
      case TexMathAtomClass.open:
      case TexMathAtomClass.close:
      case TexMathAtomClass.punct:
      case TexMathAtomClass.inner:
        return BreakPoint.none;
    }
  }

  bool _isNamedFunctionAtom(MathNode node) {
    if (node is OperatorNode) {
      if (node.isLarge || node.isExtensible) {
        return false;
      }
      if (node.isDeclared || node.command == 'operatorname') {
        return true;
      }
      final String? cmd = node.command;
      if (cmd != null && namedLimitOperators.contains(cmd)) {
        return false;
      }
      return (cmd != null && namedFunctionOperators.contains(cmd)) ||
          namedFunctionOperators.contains(node.operatorName);
    }
    if (node is ScriptNode) {
      return _isNamedFunctionAtom(node.base);
    }
    if (node is MathGroupNode &&
        node.role == null &&
        !node.isExplicitGroup &&
        node.children.length == 1) {
      return _isNamedFunctionAtom(node.children.first);
    }
    return false;
  }

  bool _shouldInsertApplyFunction(MathNode? next) {
    if (next == null || next is SpaceNode) {
      return false;
    }
    if (next is TagNode && next.isLabelDefinition) {
      return false;
    }
    if (next is MathGroupNode && next.children.isEmpty) {
      return false;
    }
    final TexMathAtomClass? nextClass = _leadingAtomClass(next);
    if (nextClass == TexMathAtomClass.bin ||
        nextClass == TexMathAtomClass.rel ||
        nextClass == TexMathAtomClass.close ||
        nextClass == TexMathAtomClass.punct) {
      return false;
    }
    return true;
  }

  TexMathAtomClass? _leadingAtomClass(MathNode node) {
    switch (node) {
      case SymbolNode(:final TexMathAtomClass? atomClass):
        return atomClass ?? TexMathAtomClass.ord;
      case OperatorNode():
        return TexMathAtomClass.op;
      case DelimiterNode():
        return node.leftDelimiter != null
            ? TexMathAtomClass.open
            : TexMathAtomClass.close;
      case MathGroupNode(:final TexMathAtomClass? atomClass):
        if (atomClass != null) {
          return atomClass;
        }
        if (node.isExplicitGroup) {
          return TexMathAtomClass.ord;
        }
        if (node.children.isNotEmpty) {
          return _leadingAtomClass(node.children.first);
        }
        return TexMathAtomClass.ord;
      case ScriptNode(:final MathNode base):
        return _leadingAtomClass(base);
      case FractionNode():
        return TexMathAtomClass.inner;
      case StyleNode(:final List<MathNode> children):
        return children.isNotEmpty ? _leadingAtomClass(children.first) : null;
      default:
        return TexMathAtomClass.ord;
    }
  }

  MathBox _layoutGroupNode(
    MathGroupNode node,
    _LayoutState state, {
    TexMathAtomClass? leadingImplicitClass,
  }) {
    final String? role = node.role;
    if (role != null) {
      final _LayoutState innerState = state.nested();
      switch (role) {
        case 'boxed':
          return _layoutBoxedGroup(node, innerState);
        case 'bbox':
          return _layoutBboxGroup(node, innerState);
        case 'cancel':
        case 'bcancel':
        case 'xcancel':
        case 'cancelto':
          return _layoutCancelGroup(node, innerState, role);
        case 'enclose':
          return _layoutEncloseGroup(node, innerState);
        case 'prooftree':
        case 'prooftree_rule':
          return layoutProoftreeGroup(
            node: node,
            font: font,
            currentStyle: state.style,
            fontScale: state.fontScale,
            layoutCell:
                (
                  MathNode cell, {
                  required TexMathStyle style,
                  TexMathAtomClass? leadingImplicitClass,
                }) {
                  return _layoutNode(
                    cell,
                    innerState.copyWith(style: style),
                    leadingImplicitClass: leadingImplicitClass,
                  );
                },
          );
        case 'numcases':
        case 'subnumcases':
          return _layoutSequence(
            node.children,
            innerState,
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
            preserveInnerBoundaryClass: true,
          );
        case 'smash':
        case 'smash_t':
        case 'smash_b':
        case 'smash_tb':
          final MathBox inner = _layoutSequence(
            node.children,
            innerState,
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
          );
          final bool smashTop = role != 'smash_b';
          final bool smashBottom = role != 'smash_t';
          return VBox.positioned(
            children: <VBoxChild>[VBoxChild(box: inner)],
            widthEm: inner.widthEm,
            heightEm: smashTop ? 0.0 : inner.heightEm,
            depthEm: smashBottom ? 0.0 : inner.depthEm,
            atomClass: node.atomClass ?? TexMathAtomClass.ord,
            span: node.span,
          );
        case 'phantom':
        case 'vphantom':
        case 'hphantom':
          final MathBox inner = _layoutSequence(
            node.children,
            innerState,
            span: node.span,
          );
          return KernBox(
            widthEm: role == 'vphantom' ? 0.0 : inner.widthEm,
            heightEm: role == 'hphantom' ? 0.0 : inner.heightEm,
            depthEm: role == 'hphantom' ? 0.0 : inner.depthEm,
            atomClass: node.atomClass ?? TexMathAtomClass.ord,
            span: node.span,
          );
        case 'rlap':
        case 'llap':
        case 'clap':
        case 'mathrlap':
        case 'mathllap':
        case 'mathclap':
        case 'crampedrlap':
        case 'crampedllap':
        case 'crampedclap':
          final _LayoutState lapState = role.startsWith('cramped')
              ? innerState.copyWith(style: toCrampedStyle(state.style))
              : innerState;
          final MathBox inner = _layoutSequence(
            node.children,
            lapState,
            span: node.span,
          );
          final double xOffset;
          if (role.endsWith('llap')) {
            xOffset = -inner.widthEm;
          } else if (role.endsWith('clap')) {
            xOffset = -inner.widthEm / 2.0;
          } else {
            xOffset = 0.0;
          }
          return VBox.positioned(
            children: <VBoxChild>[VBoxChild(box: inner, xEm: xOffset)],
            widthEm: 0.0,
            heightEm: inner.heightEm,
            depthEm: inner.depthEm,
            atomClass: TexMathAtomClass.ord,
            span: node.span,
          );
        case 'mathchoice':
          if (node.children.length == 4) {
            final int idx;
            switch (scriptLevelForStyle(state.style)) {
              case 0:
                idx = isDisplayStyle(state.style) ? 0 : 1;
              case 1:
                idx = 2;
              default:
                idx = 3;
            }
            return _layoutNode(node.children[idx], innerState);
          }
          return KernBox(widthEm: 0.0, span: node.span);
        case 'sideset':
          return _layoutSidesetNode(node, innerState);
        case 'not':
        case 'centernot':
          return _layoutNegatedGroup(
            node,
            innerState,
            centered: role == 'centernot',
          );
        case 'cramped':
          return _layoutSequence(
            node.children,
            innerState.copyWith(style: toCrampedStyle(state.style)),
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
          );
        case 'pmod':
        case 'pod':
        case 'mod':
          final double scale = _scale(state);
          final List<MathNode> kids = List<MathNode>.from(node.children);
          if (!isDisplayStyle(state.style) &&
              kids.isNotEmpty &&
              kids.first is SpaceNode) {
            // TeX uses 8mu in text/script styles vs \quad in display style.
            kids[0] = SpaceNode(span: kids.first.span, widthEm: 8.0 / 18.0);
          }
          final MathBox box = _layoutSequence(
            kids,
            innerState,
            span: node.span,
          );
          return box.withMetadata(
            atomClass: TexMathAtomClass.ord,
            shiftYEm: 0.0 * scale,
          );
        case 'shoveleft':
        case 'shoveright':
        case 'spreadlines':
        case 'texhtml':
          return _layoutSequence(
            node.children,
            innerState,
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
          );
        case 'toggle':
          if (node.children.isEmpty) {
            return KernBox(widthEm: 0.0, span: node.span);
          }
          final MathBox active = _layoutNode(node.children.first, innerState);
          return HBox(
            children: <MathBox>[
              AnchorBox(id: 'toggle', span: node.span),
              active,
            ],
            atomClass: active.atomClass,
            span: node.span,
          );
        case 'mathtip':
        case 'texttip':
          if (node.children.isEmpty) {
            return KernBox(widthEm: 0.0, span: node.span);
          }
          final MathBox base = _layoutNode(node.children.first, innerState);
          return HBox(
            children: <MathBox>[
              AnchorBox(id: role, span: node.span),
              base,
            ],
            atomClass: base.atomClass,
            span: node.span,
          );
        case 'href':
        case 'class':
        case 'cssId':
        case 'style':
        case 'data':
          final String? attrVal = node.attributes[role];
          final MathBox body = _layoutSequence(
            node.children,
            innerState,
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
            preserveInnerBoundaryClass: true,
          );
          final String anchorId = role == 'cssId' && attrVal != null
              ? attrVal
              : '$role:${attrVal ?? ''}';
          return HBox(
            children: <MathBox>[
              AnchorBox(id: anchorId, label: attrVal, span: node.span),
              body,
            ],
            atomClass: body.atomClass,
            span: node.span,
          );
        default:
          final TexMathStyle envStyle = role == 'math'
              ? TexMathStyle.text
              : (role == 'equation' ||
                        role == 'equation*' ||
                        role == 'displaymath'
                    ? TexMathStyle.display
                    : state.style);
          return _layoutSequence(
            node.children,
            state.copyWith(
              style: envStyle,
              isTopLevel:
                  state.isTopLevel &&
                  (role == 'equation' ||
                      role == 'equation*' ||
                      role == 'math' ||
                      role == 'displaymath'),
            ),
            span: node.span,
            outerClass: node.atomClass ?? TexMathAtomClass.ord,
            leadingImplicitClass: leadingImplicitClass,
          );
      }
    }

    final _LayoutState groupState = state.copyWith(
      fontVariant: node.fontVariant,
      isTopLevel:
          state.isTopLevel && !node.isExplicitGroup && node.atomClass == null,
    );
    return _layoutSequence(
      node.children,
      groupState,
      span: node.span,
      outerClass: node.atomClass ?? TexMathAtomClass.ord,
      leadingImplicitClass: leadingImplicitClass,
      preserveInnerBoundaryClass:
          !node.isExplicitGroup && node.atomClass == null,
    );
  }

  MathBox _layoutBoxedGroup(MathGroupNode node, _LayoutState state) {
    final MathBox inner = _layoutSequence(
      node.children,
      state,
      span: node.span,
    );
    final double scale = _scale(state);
    final double padEm = 0.20 * scale;
    final double strokeEm =
        (constants.fractionRuleThickness / upem) * 1.675 * scale;
    return _wrapBoxWithFrame(
      inner: inner,
      padEm: padEm,
      borderStrokeEm: strokeEm,
      borderRole: TexMathColorRole.foreground,
      span: node.span,
    );
  }

  MathBox _wrapBoxWithFrame({
    required MathBox inner,
    required double padEm,
    int? backgroundArgb,
    double borderStrokeEm = 0.0,
    TexMathColorRole borderRole = TexMathColorRole.foreground,
    int? borderArgb,
    SourceSpan? span,
  }) {
    final double effectiveStroke = borderStrokeEm > 0.0 ? borderStrokeEm : 0.0;
    final double halfStroke = effectiveStroke / 2.0;
    final double totalPad = padEm + effectiveStroke;
    final double outerW = inner.widthEm + 2.0 * totalPad;
    final double outerH = inner.heightEm + totalPad;
    final double outerD = inner.depthEm + totalPad;
    final List<VBoxChild> layers = <VBoxChild>[];

    if (backgroundArgb != null) {
      final double fillPad = effectiveStroke > 0.0 ? halfStroke : 0.0;
      layers.add(
        VBoxChild(
          box: RuleBox(
            widthEm: math.max(0.0, outerW - 2.0 * fillPad),
            heightEm: math.max(0.0, outerH + outerD - 2.0 * fillPad),
            colorRole: TexMathColorRole.custom,
            customColor: backgroundArgb,
            inheritColor: false,
            span: span,
          ),
          xEm: fillPad,
          yEm: -outerD + fillPad,
        ),
      );
    }

    if (effectiveStroke > 0.0) {
      layers.add(
        VBoxChild(
          box: RuleBox(
            widthEm: inner.widthEm + 2.0 * padEm + effectiveStroke,
            heightEm:
                inner.heightEm + inner.depthEm + 2.0 * padEm + effectiveStroke,
            strokeWidthEm: effectiveStroke,
            colorRole: borderRole,
            customColor: borderArgb,
            inheritColor:
                borderRole != TexMathColorRole.custom && borderArgb == null,
            span: span,
          ),
          xEm: halfStroke,
          yEm: -inner.depthEm - padEm - halfStroke,
        ),
      );
    }

    layers.add(VBoxChild(box: inner, xEm: totalPad, yEm: 0.0));
    return VBox.positioned(
      children: layers,
      widthEm: outerW,
      heightEm: outerH,
      depthEm: outerD,
      atomClass: TexMathAtomClass.ord,
      span: span,
    );
  }

  MathBox _layoutSidesetNode(MathGroupNode node, _LayoutState state) {
    if (node.children.length != 3) {
      return _layoutSequence(node.children, state, span: node.span);
    }
    final MathBox centerBox = _layoutNode(node.children[1], state);
    final MathNode? coreOpNode = _extractCoreOperator(node.children[1]);
    final MathBox? coreOpBox = coreOpNode != null
        ? _layoutNode(coreOpNode, state)
        : null;
    final double refH = coreOpBox?.heightEm ?? centerBox.heightEm;
    final double refD = coreOpBox?.depthEm ?? centerBox.depthEm;

    MathBox layoutSide(MathNode sideNode) {
      if (sideNode is ScriptNode && _isEmptyNode(sideNode.base)) {
        return _layoutSideScriptsWithRef(
          subscript: sideNode.subscript,
          superscript: sideNode.superscript,
          refHeightEm: refH,
          refDepthEm: refD,
          state: state,
          span: sideNode.span,
        );
      }
      if (sideNode is MathGroupNode && sideNode.children.isNotEmpty) {
        final List<MathBox> parts = <MathBox>[];
        for (final MathNode child in sideNode.children) {
          if (child is ScriptNode && _isEmptyNode(child.base)) {
            parts.add(
              _layoutSideScriptsWithRef(
                subscript: child.subscript,
                superscript: child.superscript,
                refHeightEm: refH,
                refDepthEm: refD,
                state: state,
                span: child.span,
              ),
            );
          } else {
            parts.add(_layoutNode(child, state));
          }
        }
        return HBox(children: parts, span: sideNode.span);
      }
      return _layoutNode(sideNode, state);
    }

    final MathBox leftBox = layoutSide(node.children[0]);
    final MathBox rightBox = layoutSide(node.children[2]);
    return HBox(
      children: <MathBox>[leftBox, centerBox, rightBox],
      atomClass: TexMathAtomClass.op,
      span: node.span,
    );
  }

  MathBox _layoutSideScriptsWithRef({
    required MathNode? subscript,
    required MathNode? superscript,
    required double refHeightEm,
    required double refDepthEm,
    required _LayoutState state,
    required SourceSpan span,
  }) {
    final MathBox phantomBase = KernBox(
      widthEm: 0.0,
      heightEm: refHeightEm,
      depthEm: refDepthEm,
      span: span,
    );
    return _assembleSideScripts(
      baseBox: phantomBase,
      isLargeOp: false,
      subscriptNode: subscript,
      superscriptNode: superscript,
      state: state,
      span: span,
    );
  }

  MathBox _layoutNegatedGroup(
    MathGroupNode node,
    _LayoutState state, {
    bool centered = false,
  }) {
    if (!centered &&
        node.children.length == 1 &&
        node.children.first is SymbolNode) {
      final SymbolNode sym = node.children.first as SymbolNode;
      final String? negated = _negatedUnicode[sym.value];
      if (negated != null) {
        return _layoutSymbolNode(
          SymbolNode(
            span: sym.span,
            value: negated,
            atomClass: sym.atomClass ?? TexMathAtomClass.rel,
            fontVariant: sym.fontVariant,
          ),
          state,
        );
      }
    }
    final List<MathNode> baseNodes =
        centered &&
            node.children.length == 1 &&
            node.children.first is SymbolNode &&
            ((node.children.first as SymbolNode).command == 'implies' ||
                (node.children.first as SymbolNode).command == 'iff')
        ? <MathNode>[
            SymbolNode(
              span: node.children.first.span,
              value: (node.children.first as SymbolNode).value,
              atomClass:
                  (node.children.first as SymbolNode).atomClass ??
                  TexMathAtomClass.rel,
              fontVariant: (node.children.first as SymbolNode).fontVariant,
            ),
          ]
        : node.children;
    final MathBox base = _layoutSequence(baseNodes, state, span: node.span);
    return _overlayNegationSlash(
      base: base,
      state: state,
      centered: centered,
      span: node.span,
    );
  }

  MathBox _overlayNegationSlash({
    required MathBox base,
    required _LayoutState state,
    required bool centered,
    required SourceSpan? span,
  }) {
    final double scale = _scale(state);
    final int slashCp =
        (centered || base.widthEm >= 1.0 * scale) &&
            font.glyphIdForCodePoint(0x29F8) != 0
        ? 0x29F8
        : 0x2F;
    final GlyphBox slash = buildGlyphBoxFromId(
      font: font,
      glyphId: font.glyphIdForCodePoint(slashCp),
      codePoint: slashCp,
      scale: scale,
      span: span,
    );
    final double slashX = (base.widthEm - slash.widthEm) / 2.0;
    final (double baseMinY, double baseMaxY) = boxVerticalInkBoundsEm(
      base,
      font,
    );
    final (double slashMinY, double slashMaxY) = boxVerticalInkBoundsEm(
      slash,
      font,
    );
    final double slashY = centered
        ? ((baseMinY + baseMaxY) / 2.0) - ((slashMinY + slashMaxY) / 2.0)
        : 0.0;
    return VBox.positioned(
      children: <VBoxChild>[
        VBoxChild(box: base),
        VBoxChild(box: slash, xEm: slashX, yEm: slashY),
      ],
      widthEm: math.max(base.widthEm, slash.widthEm),
      atomClass: TexMathAtomClass.rel,
      span: span,
    );
  }

  MathBox _layoutSymbolNode(SymbolNode node, _LayoutState state) {
    final TexMathAtomClass atomClass = node.atomClass ?? TexMathAtomClass.ord;
    final TexMathFontVariant? variant = node.fontVariant ?? state.fontVariant;
    final double scale = _scale(state);
    final int scriptLevel = scriptLevelForStyle(state.style);

    String value = node.value;
    bool needsSlashOverlay = false;
    if (node.isNegated) {
      if (_negatedUnicode.containsKey(value)) {
        value = _negatedUnicode[value]!;
      } else {
        needsSlashOverlay = true;
      }
    }

    if (value.isEmpty) {
      return KernBox(widthEm: 0.0, atomClass: atomClass, span: node.span);
    }

    final int? singleCp = singleCodePointOrNull(value);
    final MathBox symbolBox;
    if (singleCp != null) {
      final (int cp, int gid) = resolveMathGlyphCodePointAndId(
        baseCodePoint: singleCp,
        font: font,
        variant: variant,
        isTextMode: state.isTextMode,
      );
      final GlyphBox glyph = buildGlyphBoxFromId(
        font: font,
        glyphId: gid,
        codePoint: cp,
        scale: scale,
        atomClass: atomClass,
        scriptLevel: scriptLevel,
        useOpticalScriptVariants: options.useOpticalScriptVariants,
        span: node.span,
      );
      if (!node.isNegated &&
          (node.command == 'implies' || node.command == 'iff')) {
        final double pad = thickMuSkipEm * scale;
        symbolBox = HBox(
          children: <MathBox>[
            KernBox(widthEm: pad),
            glyph,
            KernBox(widthEm: pad),
          ],
          atomClass: atomClass,
          span: node.span,
        );
      } else {
        symbolBox = glyph;
      }
    } else {
      final List<MathBox> chars = <MathBox>[];
      for (final int r in value.runes) {
        final (int cp, int gid) = resolveMathGlyphCodePointAndId(
          baseCodePoint: r,
          font: font,
          variant: variant,
          isTextMode: state.isTextMode,
        );
        chars.add(
          buildGlyphBoxFromId(
            font: font,
            glyphId: gid,
            codePoint: cp,
            scale: scale,
            scriptLevel: scriptLevel,
            useOpticalScriptVariants: options.useOpticalScriptVariants,
            span: node.span,
          ),
        );
      }
      symbolBox = HBox(children: chars, atomClass: atomClass, span: node.span);
    }

    if (needsSlashOverlay) {
      return _overlayNegationSlash(
        base: symbolBox,
        state: state,
        centered: false,
        span: node.span,
      );
    }
    return symbolBox;
  }

  MathBox _layoutOperatorNode(OperatorNode node, _LayoutState state) {
    final double scale = _scale(state);
    final int scriptLevel = scriptLevelForStyle(state.style);
    final String name = node.operatorName;

    if (node.isExtensible) {
      final int cp = firstCodePointOr(name, 0x2192);
      return buildHorizontalStretchyBox(
        font: font,
        codePoint: cp,
        targetWidthEm: 1.0 * scale,
        scale: scale,
        atomClass: TexMathAtomClass.rel,
        span: node.span,
      );
    }

    if (node.isLarge) {
      final int? singleLargeCp = singleCodePointOrNull(name);
      if (singleLargeCp != null) {
        return buildLargeOperatorBox(
          font: font,
          codePoint: singleLargeCp,
          style: state.style,
          scale: scale,
          span: node.span,
        );
      }
      final List<MathBox> parts = <MathBox>[];
      for (final int r in name.runes) {
        if (r == 0x222B || r == 0x222E || r == 0x222F) {
          parts.add(
            buildLargeOperatorBox(
              font: font,
              codePoint: r,
              style: state.style,
              scale: scale,
              span: node.span,
            ),
          );
        } else {
          parts.add(
            buildGlyphBoxFromId(
              font: font,
              glyphId: font.glyphIdForCodePoint(r),
              codePoint: r,
              scale: scale,
              scriptLevel: scriptLevel,
              useOpticalScriptVariants: options.useOpticalScriptVariants,
              span: node.span,
            ),
          );
        }
      }
      return HBox(
        children: parts,
        atomClass: TexMathAtomClass.op,
        span: node.span,
      );
    }

    final TexMathFontVariant opVariant =
        (state.fontVariant == TexMathFontVariant.bold ||
            state.fontVariant == TexMathFontVariant.boldItalic)
        ? TexMathFontVariant.bold
        : (state.fontVariant == TexMathFontVariant.sansSerif ||
                  state.fontVariant == TexMathFontVariant.boldSansSerif ||
                  state.fontVariant == TexMathFontVariant.monospace
              ? state.fontVariant!
              : TexMathFontVariant.normal);
    final List<MathBox> glyphs = <MathBox>[];
    for (final int r in name.runes) {
      if (r == 0x2006 || r == 0x2009) {
        glyphs.add(KernBox(widthEm: thinMuSkipEm * scale));
        continue;
      }
      final int cp = resolveMathGlyphCodePoint(
        baseCodePoint: r,
        font: font,
        variant: opVariant,
        isTextMode: true,
      );
      glyphs.add(
        buildGlyphBoxFromId(
          font: font,
          glyphId: font.glyphIdForCodePoint(cp),
          codePoint: cp,
          scale: scale,
          scriptLevel: scriptLevel,
          useOpticalScriptVariants: options.useOpticalScriptVariants,
          span: node.span,
        ),
      );
    }
    if (glyphs.isEmpty) {
      return KernBox(
        widthEm: 0.0,
        atomClass: TexMathAtomClass.op,
        span: node.span,
      );
    }
    return HBox(
      children: glyphs,
      atomClass: TexMathAtomClass.op,
      span: node.span,
    );
  }

  MathBox _layoutFractionNode(FractionNode node, _LayoutState state) {
    final TexMathStyle fracStyle = node.styleOverride ?? state.style;
    final bool isDisplay = isDisplayStyle(fracStyle);
    final double scale = scaleForStyle(fracStyle, constants) * state.fontScale;

    final MathBox num = _layoutNode(
      node.numerator,
      state.nested(style: numeratorStyle(fracStyle)),
    );
    final MathBox den = _layoutNode(
      node.denominator,
      state.nested(style: denominatorStyle(fracStyle)),
    );

    final double axis = (constants.axisHeight / upem) * scale;
    final VBox core;

    if (node.isBevelled) {
      final double horizGap =
          (constants.skewedFractionHorizontalGap / upem) * scale;
      final double vertGap =
          (constants.skewedFractionVerticalGap / upem) * scale;
      final double targetSlashSpan = math.max(
        1.0 * scale,
        (num.heightEm + den.depthEm) * 0.9,
      );
      final MathBox slash = buildVerticalDelimiterBox(
        font: font,
        delimiter: '/',
        targetSpanEm: targetSlashSpan,
        atomClass: TexMathAtomClass.ord,
        scale: scale,
        exactSize: false,
        span: node.span,
      );
      final double slashShiftY = axis - (slash.heightEm - slash.depthEm) / 2.0;
      final double numY = axis + vertGap / 2.0 + num.depthEm;
      final double denY = axis - vertGap / 2.0 - den.heightEm;
      final double slashX = num.widthEm + horizGap / 2.0 - slash.widthEm / 2.0;
      final double denX = num.widthEm + horizGap;
      final double coreW = math.max(denX + den.widthEm, slashX + slash.widthEm);
      core = VBox.positioned(
        children: <VBoxChild>[
          VBoxChild(box: num, xEm: 0.0, yEm: numY),
          VBoxChild(box: slash, xEm: slashX, yEm: slashShiftY),
          VBoxChild(box: den, xEm: denX, yEm: denY),
        ],
        widthEm: coreW,
        atomClass: TexMathAtomClass.inner,
        span: node.span,
      );
    } else {
      final double baseTheta =
          node.ruleThicknessEm ?? (constants.fractionRuleThickness / upem);
      final double theta = baseTheta * scale;
      final double contentW = math.max(num.widthEm, den.widthEm);

      double shiftUp;
      double shiftDown;
      final List<VBoxChild> items = <VBoxChild>[];
      final double barPad = theta > 0.0
          ? (2.5 * constants.fractionRuleThickness / upem) * scale
          : 0.0;
      final double barW = contentW + 2.0 * barPad;

      if (theta > 0.0) {
        shiftUp =
            (isDisplay
                ? constants.fractionNumeratorDisplayStyleShiftUp
                : constants.fractionNumeratorShiftUp) /
            upem *
            scale;
        shiftDown =
            (isDisplay
                ? constants.fractionDenominatorDisplayStyleShiftDown
                : constants.fractionDenominatorShiftDown) /
            upem *
            scale;
        final double numGapMin =
            (isDisplay
                ? constants.fractionNumDisplayStyleGapMin
                : constants.fractionNumeratorGapMin) /
            upem *
            scale;
        final double denGapMin =
            (isDisplay
                ? constants.fractionDenomDisplayStyleGapMin
                : constants.fractionDenominatorGapMin) /
            upem *
            scale;

        final double ruleTop = axis + theta / 2.0;
        final double ruleBottom = axis - theta / 2.0;

        final double actualNumGap = (shiftUp - num.depthEm) - ruleTop;
        if (actualNumGap < numGapMin) {
          shiftUp += numGapMin - actualNumGap;
        }

        final double actualDenGap = ruleBottom - (den.heightEm - shiftDown);
        if (actualDenGap < denGapMin) {
          shiftDown += denGapMin - actualDenGap;
        }
      } else {
        shiftUp =
            (isDisplay
                ? constants.stackTopDisplayStyleShiftUp
                : constants.stackTopShiftUp) /
            upem *
            scale;
        shiftDown =
            (isDisplay
                ? constants.stackBottomDisplayStyleShiftDown
                : constants.stackBottomShiftDown) /
            upem *
            scale;
        final double gapMin =
            (isDisplay
                ? constants.stackDisplayStyleGapMin
                : constants.stackGapMin) /
            upem *
            scale;

        final double actualGap =
            (shiftUp - num.depthEm) - (den.heightEm - shiftDown);
        if (actualGap < gapMin) {
          final double deficit = (gapMin - actualGap) / 2.0;
          shiftUp += deficit;
          shiftDown += deficit;
        }
      }

      items.add(
        VBoxChild(box: num, xEm: (barW - num.widthEm) / 2.0, yEm: shiftUp),
      );
      items.add(
        VBoxChild(box: den, xEm: (barW - den.widthEm) / 2.0, yEm: -shiftDown),
      );
      if (theta > 0.0) {
        items.add(
          VBoxChild(
            box: RuleBox(widthEm: barW, heightEm: theta, span: node.span),
            xEm: 0.0,
            yEm: axis - theta / 2.0,
          ),
        );
      }

      core = VBox.positioned(
        children: items,
        widthEm: barW,
        atomClass: TexMathAtomClass.inner,
        span: node.span,
      );
    }

    final double halfSpan = math.max(core.heightEm - axis, core.depthEm + axis);
    final double delimSpan = math.max(
      2.0 * halfSpan,
      (constants.delimitedSubFormulaMinHeight / upem) * scale,
    );

    final MathBox leftDelim = buildVerticalDelimiterBox(
      font: font,
      delimiter: node.leftDelimiter,
      targetSpanEm: delimSpan,
      atomClass: TexMathAtomClass.open,
      scale: scale,
      exactSize: true,
      span: node.span,
    );
    final MathBox rightDelim = buildVerticalDelimiterBox(
      font: font,
      delimiter: node.rightDelimiter,
      targetSpanEm: delimSpan,
      atomClass: TexMathAtomClass.close,
      scale: scale,
      exactSize: true,
      span: node.span,
    );

    return HBox(
      children: <MathBox>[leftDelim, core, rightDelim],
      atomClass: TexMathAtomClass.inner,
      span: node.span,
    );
  }

  MathBox _layoutScriptNode(ScriptNode node, _LayoutState state) {
    final _LayoutState innerState = state.nested();
    final OperatorNode? baseOp = _extractCoreOperator(node.base);
    if (baseOp != null && baseOp.isExtensible) {
      return _layoutExtensibleArrowNode(node, baseOp, innerState);
    }

    final bool hasHorizAccent = _isHorizontalLimiterAccent(node.base);
    final bool useLimits;
    if (hasHorizAccent) {
      useLimits = true;
    } else if (baseOp != null) {
      if (!node.limitsAboveBelow || !baseOp.hasLimits) {
        useLimits = false;
      } else if (isDisplayStyle(state.style)) {
        useLimits = true;
      } else {
        // Integrals default to side scripts, so hasLimits here indicates an
        // explicit \limits modifier.
        useLimits = _isIntegralOperator(baseOp);
      }
    } else {
      useLimits = node.limitsAboveBelow;
    }

    final MathBox baseBox = _layoutNode(node.base, innerState);
    if (useLimits && node.presubscript == null && node.presuperscript == null) {
      return _assembleLimitsBox(
        baseBox: baseBox,
        underNode: node.subscript,
        overNode: node.superscript,
        addBigOpPadding: baseOp != null,
        state: innerState,
        span: node.span,
      );
    }

    MathBox coreBox = baseBox;
    if (useLimits) {
      coreBox = _assembleLimitsBox(
        baseBox: baseBox,
        underNode: node.subscript,
        overNode: node.superscript,
        addBigOpPadding: baseOp != null,
        state: innerState,
        span: node.span,
      );
    }

    return _assembleSideScripts(
      baseBox: coreBox,
      isLargeOp: !useLimits && baseOp != null && baseOp.isLarge,
      subscriptNode: useLimits ? null : node.subscript,
      superscriptNode: useLimits ? null : node.superscript,
      presubscriptNode: node.presubscript,
      presuperscriptNode: node.presuperscript,
      state: innerState,
      span: node.span,
    );
  }

  MathBox _layoutExtensibleArrowNode(
    ScriptNode node,
    OperatorNode arrowOp,
    _LayoutState state,
  ) {
    final double scale = _scale(state);
    final MathBox? overBox = node.superscript != null
        ? _layoutNode(
            node.superscript!,
            state.nested(style: superscriptStyle(state.style)),
          )
        : null;
    final MathBox? underBox = node.subscript != null
        ? _layoutNode(
            node.subscript!,
            state.nested(style: subscriptStyle(state.style)),
          )
        : null;

    final double labelWidth = math.max(
      overBox?.widthEm ?? 0.0,
      underBox?.widthEm ?? 0.0,
    );
    final double targetWidth = math.max(1.0 * scale, labelWidth + 0.55 * scale);
    final int cp = firstCodePointOr(arrowOp.operatorName, 0x2192);
    final MathBox arrowBox = buildHorizontalStretchyBox(
      font: font,
      codePoint: cp,
      targetWidthEm: targetWidth,
      scale: scale,
      atomClass: TexMathAtomClass.rel,
      span: node.span,
    );

    final double totalW = math.max(arrowBox.widthEm, labelWidth);
    final double gapAbove = (constants.stretchStackGapAboveMin / upem) * scale;
    final double gapBelow = (constants.stretchStackGapBelowMin / upem) * scale;
    final double shiftTopMin =
        (constants.stretchStackTopShiftUp / upem) * scale;
    final double shiftBotMin =
        (constants.stretchStackBottomShiftDown / upem) * scale;
    final (double _, double arrowInkMax) = boxVerticalInkBoundsEm(
      arrowBox,
      font,
    );
    final (double arrowInkMin, double _) = boxVerticalInkBoundsEm(
      arrowBox,
      font,
    );

    final List<VBoxChild> placed = <VBoxChild>[
      VBoxChild(
        box: arrowBox,
        xEm: (totalW - arrowBox.widthEm) / 2.0,
        yEm: 0.0,
      ),
    ];

    if (overBox != null) {
      final double minBaseTop = arrowInkMax + gapAbove + overBox.depthEm;
      final double overY = math.max(minBaseTop, shiftTopMin);
      placed.add(
        VBoxChild(
          box: overBox,
          xEm: (totalW - overBox.widthEm) / 2.0,
          yEm: overY,
        ),
      );
    }

    if (underBox != null) {
      final double maxBaseBot = arrowInkMin - gapBelow - underBox.heightEm;
      final double underY = math.min(maxBaseBot, -shiftBotMin);
      placed.add(
        VBoxChild(
          box: underBox,
          xEm: (totalW - underBox.widthEm) / 2.0,
          yEm: underY,
        ),
      );
    }

    return VBox.positioned(
      children: placed,
      widthEm: totalW,
      atomClass: TexMathAtomClass.rel,
      span: node.span,
    );
  }

  MathBox _assembleLimitsBox({
    required MathBox baseBox,
    required MathNode? underNode,
    required MathNode? overNode,
    required bool addBigOpPadding,
    required _LayoutState state,
    required SourceSpan span,
  }) {
    final double scale = _scale(state);
    final MathBox? overBox = overNode != null
        ? _layoutNode(
            overNode,
            state.nested(style: superscriptStyle(state.style)),
          )
        : null;
    final MathBox? underBox = underNode != null
        ? _layoutNode(
            underNode,
            state.nested(style: subscriptStyle(state.style)),
          )
        : null;

    final double ic = baseBox.italicsCorrectionEm;
    final double halfIc = ic / 2.0;

    final double minLeft = math.min(
      0.0,
      math.min(
        overBox != null
            ? (baseBox.widthEm - overBox.widthEm) / 2.0 + halfIc
            : 0.0,
        underBox != null
            ? (baseBox.widthEm - underBox.widthEm) / 2.0 - halfIc
            : 0.0,
      ),
    );
    final double shiftRight = -minLeft;

    final List<VBoxChild> placed = <VBoxChild>[
      VBoxChild(box: baseBox, xEm: shiftRight, yEm: 0.0),
    ];
    double maxRight = shiftRight + baseBox.widthEm;
    double maxTop = baseBox.heightEm;
    double maxBottom = baseBox.depthEm;
    final double opPadding = addBigOpPadding ? 0.10 * scale : 0.0;

    if (underBox != null) {
      final double underGapMin = (constants.lowerLimitGapMin / upem) * scale;
      final double underDropMin =
          (constants.lowerLimitBaselineDropMin / upem) * scale;
      final double underY = -math.max(
        baseBox.depthEm + underGapMin + underBox.heightEm,
        baseBox.depthEm + underDropMin,
      );
      final double underX =
          shiftRight + (baseBox.widthEm - underBox.widthEm) / 2.0 - halfIc;
      placed.add(VBoxChild(box: underBox, xEm: underX, yEm: underY));
      maxRight = math.max(maxRight, underX + underBox.widthEm);
      maxBottom = math.max(maxBottom, -underY + underBox.depthEm + opPadding);
    }

    if (overBox != null) {
      final double overGapMin = (constants.upperLimitGapMin / upem) * scale;
      final double overRiseMin =
          (constants.upperLimitBaselineRiseMin / upem) * scale;
      final double overY = math.max(
        baseBox.heightEm + overGapMin + overBox.depthEm,
        baseBox.heightEm + overRiseMin,
      );
      final double overX =
          shiftRight + (baseBox.widthEm - overBox.widthEm) / 2.0 + halfIc;
      placed.add(VBoxChild(box: overBox, xEm: overX, yEm: overY));
      maxRight = math.max(maxRight, overX + overBox.widthEm);
      maxTop = math.max(maxTop, overY + overBox.heightEm + opPadding);
    }

    return VBox.positioned(
      children: placed,
      widthEm: maxRight,
      heightEm: maxTop,
      depthEm: maxBottom,
      atomClass: baseBox.atomClass,
      span: span,
    );
  }

  (double u, double v) _computeSideScriptOffsets({
    required double baseHeightEm,
    required double baseDepthEm,
    required MathBox? supBox,
    required MathBox? subBox,
    required _LayoutState state,
  }) {
    final double scale = _scale(state);
    final double supMin =
        (isCrampedStyle(state.style)
            ? constants.superscriptShiftUpCramped
            : constants.superscriptShiftUp) /
        upem *
        scale;
    final double supDropMax =
        (constants.superscriptBaselineDropMax / upem) * scale;
    final double supBottomMin = (constants.superscriptBottomMin / upem) * scale;

    final double subMin = (constants.subscriptShiftDown / upem) * scale;
    final double subTopMax = (constants.subscriptTopMax / upem) * scale;
    final double subDropMin =
        (constants.subscriptBaselineDropMin / upem) * scale;

    final double subSupGapMin = (constants.subSuperscriptGapMin / upem) * scale;
    final double supBottomMaxWithSub =
        (constants.superscriptBottomMaxWithSubscript / upem) * scale;

    double u = supBox != null
        ? math.max(
            math.max(supMin, baseHeightEm - supDropMax),
            supBox.depthEm + supBottomMin,
          )
        : 0.0;
    double v = subBox != null
        ? math.max(
            math.max(subMin, baseDepthEm + subDropMin),
            subBox.heightEm - subTopMax,
          )
        : 0.0;

    if (supBox != null && subBox != null) {
      final double gap = (u - supBox.depthEm) - (subBox.heightEm - v);
      if (gap < subSupGapMin) {
        final double deficit = subSupGapMin - gap;
        final double raise = math.max(
          0.0,
          math.min(deficit, supBottomMaxWithSub - (u - supBox.depthEm)),
        );
        u += raise;
        v += deficit - raise;
      }
    }
    return (u, v);
  }

  MathBox _assembleSideScripts({
    required MathBox baseBox,
    required bool isLargeOp,
    required MathNode? subscriptNode,
    required MathNode? superscriptNode,
    MathNode? presubscriptNode,
    MathNode? presuperscriptNode,
    required _LayoutState state,
    required SourceSpan span,
  }) {
    final double scale = _scale(state);
    final MathBox? supBox = superscriptNode != null
        ? _layoutNode(
            superscriptNode,
            state.nested(style: superscriptStyle(state.style)),
          )
        : null;
    final MathBox? subBox = subscriptNode != null
        ? _layoutNode(
            subscriptNode,
            state.nested(style: subscriptStyle(state.style)),
          )
        : null;
    final MathBox? preSupBox = presuperscriptNode != null
        ? _layoutNode(
            presuperscriptNode,
            state.nested(style: superscriptStyle(state.style)),
          )
        : null;
    final MathBox? preSubBox = presubscriptNode != null
        ? _layoutNode(
            presubscriptNode,
            state.nested(style: subscriptStyle(state.style)),
          )
        : null;

    if (supBox == null &&
        subBox == null &&
        preSupBox == null &&
        preSubBox == null) {
      return baseBox;
    }

    final (double u, double v) = _computeSideScriptOffsets(
      baseHeightEm: baseBox.heightEm,
      baseDepthEm: baseBox.depthEm,
      supBox: supBox,
      subBox: subBox,
      state: state,
    );
    final (double preU, double preV) = _computeSideScriptOffsets(
      baseHeightEm: baseBox.heightEm,
      baseDepthEm: baseBox.depthEm,
      supBox: preSupBox,
      subBox: preSubBox,
      state: state,
    );
    final double spaceAfter = (constants.spaceAfterScript / upem) * scale;

    final GlyphBox? baseLead = _leadingGlyph(baseBox);
    double preSupW = preSupBox?.widthEm ?? 0.0;
    double preSubW = preSubBox?.widthEm ?? 0.0;
    if (baseLead != null && baseLead.glyphId != 0) {
      if (preSupBox != null) {
        final GlyphBox? preSupTrail = _trailingGlyph(preSupBox);
        if (preSupTrail != null && preSupTrail.glyphId != 0) {
          preSupW -= _evaluatePairKern(
            base: baseLead,
            baseCorner: MathKernCorner.topLeft,
            script: preSupTrail,
            scriptCorner: MathKernCorner.bottomRight,
            scriptBaselineYEm: preU,
          );
        }
      }
      if (preSubBox != null) {
        final GlyphBox? preSubTrail = _trailingGlyph(preSubBox);
        if (preSubTrail != null && preSubTrail.glyphId != 0) {
          preSubW -= _evaluatePairKern(
            base: baseLead,
            baseCorner: MathKernCorner.bottomLeft,
            script: preSubTrail,
            scriptCorner: MathKernCorner.topRight,
            scriptBaselineYEm: -preV,
          );
        }
      }
    }
    final double preWidth = math.max(0.0, math.max(preSupW, preSubW));
    final double baseX = preWidth + (preWidth > 0.0 ? spaceAfter : 0.0);

    // OpenType MATH italics correction and 4-corner math kerns.
    double supX = isLargeOp
        ? baseX + baseBox.widthEm
        : baseX + baseBox.widthEm + baseBox.italicsCorrectionEm;
    double subX = isLargeOp
        ? baseX + math.max(0.0, baseBox.widthEm - baseBox.italicsCorrectionEm)
        : baseX + baseBox.widthEm;

    final GlyphBox? baseGlyph = _trailingGlyph(baseBox);
    if (baseGlyph != null && baseGlyph.glyphId != 0) {
      if (supBox != null) {
        final GlyphBox? supLead = _leadingGlyph(supBox);
        if (supLead != null && supLead.glyphId != 0) {
          supX += _evaluatePairKern(
            base: baseGlyph,
            baseCorner: MathKernCorner.topRight,
            script: supLead,
            scriptCorner: MathKernCorner.bottomLeft,
            scriptBaselineYEm: u,
          );
        }
      }
      if (subBox != null) {
        final GlyphBox? subLead = _leadingGlyph(subBox);
        if (subLead != null && subLead.glyphId != 0) {
          subX += _evaluatePairKern(
            base: baseGlyph,
            baseCorner: MathKernCorner.bottomRight,
            script: subLead,
            scriptCorner: MathKernCorner.topLeft,
            scriptBaselineYEm: -v,
          );
        }
      }
    }

    final List<VBoxChild> placed = <VBoxChild>[];
    if (preSupBox != null) {
      placed.add(
        VBoxChild(
          box: preSupBox,
          xEm: math.max(0.0, baseX - preSupW - spaceAfter),
          yEm: preU,
        ),
      );
    }
    if (preSubBox != null) {
      placed.add(
        VBoxChild(
          box: preSubBox,
          xEm: math.max(0.0, baseX - preSubW - spaceAfter),
          yEm: -preV,
        ),
      );
    }
    placed.add(VBoxChild(box: baseBox, xEm: baseX, yEm: 0.0));
    double maxRight = baseX + baseBox.widthEm;
    if (supBox != null) {
      placed.add(VBoxChild(box: supBox, xEm: supX, yEm: u));
      maxRight = math.max(maxRight, supX + supBox.widthEm);
    }
    if (subBox != null) {
      placed.add(VBoxChild(box: subBox, xEm: subX, yEm: -v));
      maxRight = math.max(maxRight, subX + subBox.widthEm);
    }
    final double trailingSpace = (supBox != null || subBox != null)
        ? spaceAfter
        : 0.0;

    return VBox.positioned(
      children: placed,
      widthEm: maxRight + trailingSpace,
      atomClass: baseBox.atomClass,
      span: span,
    );
  }

  double _evaluatePairKern({
    required GlyphBox base,
    required MathKernCorner baseCorner,
    required GlyphBox script,
    required MathKernCorner scriptCorner,
    required double scriptBaselineYEm,
  }) {
    final double cornerYEm;
    if (baseCorner == MathKernCorner.topRight) {
      cornerYEm = math.min(base.heightEm, scriptBaselineYEm - script.depthEm);
    } else {
      cornerYEm = math.max(-base.depthEm, scriptBaselineYEm + script.heightEm);
    }
    final double baseHeightUnits = (cornerYEm / base.scaleY) * upem;
    final double scriptHeightUnits =
        ((cornerYEm - scriptBaselineYEm) / script.scaleY) * upem;
    final double baseK =
        mathTable.glyphInfo.mathKern(
          base.glyphId,
          baseCorner,
          baseHeightUnits,
        ) /
        upem *
        base.scaleX;
    final double scriptK =
        mathTable.glyphInfo.mathKern(
          script.glyphId,
          scriptCorner,
          scriptHeightUnits,
        ) /
        upem *
        script.scaleX;
    return baseK + scriptK;
  }

  MathBox _layoutRadicalNode(RadicalNode node, _LayoutState state) {
    final bool isDisplay = isDisplayStyle(state.style);
    final double scale = _scale(state);
    final MathBox radicand = _layoutNode(
      node.radicand,
      state.nested(style: toCrampedStyle(state.style)),
    );
    final MathBox? degree = node.index != null
        ? _layoutNode(
            node.index!,
            state.nested(style: TexMathStyle.scriptScript),
          )
        : null;

    double gap =
        (isDisplay
            ? constants.radicalDisplayStyleVerticalGap
            : constants.radicalVerticalGap) /
        upem *
        scale;
    final double theta = (constants.radicalRuleThickness / upem) * scale;
    final double extraAsc = (constants.radicalExtraAscender / upem) * scale;
    final double clearance = gap + (isDisplay ? theta / 4.0 : 0.0);

    final double reqSpan =
        radicand.heightEm + radicand.depthEm + clearance + theta;
    final MathBox surd = buildVerticalSurdBox(
      font: font,
      targetSpanEm: reqSpan,
      scale: scale,
      span: node.span,
    );

    final double actualSurdSpan = surd.heightEm + surd.depthEm;
    if (actualSurdSpan > reqSpan) {
      gap += (actualSurdSpan - reqSpan) * 0.5;
    }

    final double vinculumTop = radicand.heightEm + gap + theta;
    final double vinculumBottom = vinculumTop - theta;
    final double surdShiftY = vinculumTop - surd.heightEm;
    final double surdBottom = surdShiftY - surd.depthEm;

    double degreeX = 0.0;
    double surdX = 0.0;
    double degreeY = 0.0;

    if (degree != null) {
      final double kernBefore =
          (constants.radicalKernBeforeDegree / upem) * scale;
      final double kernAfter =
          (constants.radicalKernAfterDegree / upem) * scale;
      final double raisePct = constants.radicalDegreeBottomRaisePercent / 100.0;
      degreeY = surdBottom + (vinculumTop - surdBottom) * raisePct;

      final double rawSurdX = kernBefore + degree.widthEm + kernAfter;
      if (rawSurdX < 0.0) {
        degreeX = -rawSurdX + kernBefore;
        surdX = 0.0;
      } else {
        degreeX = kernBefore;
        surdX = rawSurdX;
      }
    }

    final double radicandX = surdX + surd.widthEm;
    final double totalW = radicandX + radicand.widthEm;
    final List<VBoxChild> placed = <VBoxChild>[
      VBoxChild(box: surd, xEm: surdX, yEm: surdShiftY),
    ];
    if (degree != null) {
      placed.add(VBoxChild(box: degree, xEm: degreeX, yEm: degreeY));
    }
    placed.add(VBoxChild(box: radicand, xEm: radicandX, yEm: 0.0));
    placed.add(
      VBoxChild(
        box: RuleBox(
          widthEm: radicand.widthEm,
          heightEm: theta,
          span: node.span,
        ),
        xEm: radicandX,
        yEm: vinculumBottom,
      ),
    );

    return VBox.positioned(
      children: placed,
      widthEm: totalW,
      heightEm: math.max(
        vinculumTop + extraAsc,
        degree != null ? degreeY + degree.heightEm : 0.0,
      ),
      depthEm: math.max(radicand.depthEm, -surdBottom),
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }

  MathBox _layoutAccentNode(AccentNode node, _LayoutState state) {
    final _LayoutState innerState = state.nested();
    final double scale = _scale(state);

    // Overline and underline (`U+2015` marker from parser) follow Appendix G
    // Rule 9 via OpenType `overbar*` / `underbar*` rule constants.
    if (node.accent == '\u2015' ||
        node.accent == '\u203E' ||
        node.accent == 'overline' ||
        node.accent == 'underline') {
      final MathBox base = _layoutNode(
        node.base,
        node.isUnder
            ? innerState
            : innerState.copyWith(style: toCrampedStyle(state.style)),
      );
      if (node.isUnder) {
        final double gap = (constants.underbarVerticalGap / upem) * scale;
        final double thick = (constants.underbarRuleThickness / upem) * scale;
        final double extra = (constants.underbarExtraDescender / upem) * scale;
        final double ruleY = -base.depthEm - gap - thick;
        return VBox.positioned(
          children: <VBoxChild>[
            VBoxChild(box: base),
            VBoxChild(
              box: RuleBox(
                widthEm: base.widthEm,
                heightEm: thick,
                span: node.span,
              ),
              xEm: 0.0,
              yEm: ruleY,
            ),
          ],
          widthEm: base.widthEm,
          heightEm: base.heightEm,
          depthEm: base.depthEm + gap + thick + extra,
          atomClass: TexMathAtomClass.ord,
          span: node.span,
        );
      } else {
        final double gap = (constants.overbarVerticalGap / upem) * scale;
        final double thick = (constants.overbarRuleThickness / upem) * scale;
        final double extra = (constants.overbarExtraAscender / upem) * scale;
        final double ruleY = base.heightEm + gap;
        return VBox.positioned(
          children: <VBoxChild>[
            VBoxChild(box: base),
            VBoxChild(
              box: RuleBox(
                widthEm: base.widthEm,
                heightEm: thick,
                span: node.span,
              ),
              xEm: 0.0,
              yEm: ruleY,
            ),
          ],
          widthEm: base.widthEm,
          heightEm: base.heightEm + gap + thick + extra,
          depthEm: base.depthEm,
          atomClass: TexMathAtomClass.ord,
          span: node.span,
        );
      }
    }

    final MathBox base = _layoutNode(
      node.base,
      node.isUnder
          ? innerState
          : innerState.copyWith(style: toCrampedStyle(state.style)),
    );
    final int accentCp = _resolveAccentCodePoint(node);
    final MathBox accentBox = node.isWide
        ? buildHorizontalStretchyBox(
            font: font,
            codePoint: accentCp,
            targetWidthEm: base.widthEm,
            scale: scale,
            span: node.span,
          )
        : buildGlyphBoxFromId(
            font: font,
            glyphId: font.glyphIdForCodePoint(accentCp),
            codePoint: accentCp,
            scale: scale,
            span: node.span,
          );

    final double baseAnchor = node.isWide
        ? base.widthEm / 2.0
        : boxTopAccentAnchorEm(base, font);
    final double accentAnchor = node.isWide
        ? accentBox.widthEm / 2.0
        : boxTopAccentAnchorEm(accentBox, font);
    final double accentX = baseAnchor - accentAnchor;

    final (double accInkMin, double accInkMax) = boxVerticalInkBoundsEm(
      accentBox,
      font,
    );
    final double gap =
        ((node.isUnder
                ? constants.underbarVerticalGap
                : constants.overbarVerticalGap) /
            upem) *
        scale;
    final double accentY = node.isUnder
        ? -base.depthEm - gap - accInkMax
        : base.heightEm + gap - accInkMin;

    return VBox.positioned(
      children: <VBoxChild>[
        VBoxChild(box: base, xEm: 0.0, yEm: 0.0),
        VBoxChild(box: accentBox, xEm: accentX, yEm: accentY),
      ],
      widthEm: node.isWide
          ? math.max(base.widthEm, accentX + accentBox.widthEm)
          : base.widthEm,
      atomClass: base.atomClass,
      span: node.span,
    );
  }

  int _resolveAccentCodePoint(AccentNode node) {
    final int rawCp = firstCodePointOr(node.accent, 0x02C6);
    if (node.isWide) {
      switch (rawCp) {
        case 0x005E:
        case 0x02C6:
          return 0x0302;
        case 0x007E:
        case 0x02DC:
          return 0x0303;
        default:
          return rawCp;
      }
    }
    switch (rawCp) {
      case 0x005E:
        return 0x02C6;
      case 0x007E:
        return 0x02DC;
      case 0x2192:
        return 0x20D7;
      default:
        return rawCp;
    }
  }

  MathBox _layoutDelimiterNode(DelimiterNode node, _LayoutState state) {
    final _LayoutState innerState = state.nested();
    final double scale = _scale(state);
    final double axis = (constants.axisHeight / upem) * scale;

    // Standalone manual delimiter commands (`\bigl(`, `\bigr)`, `\bigm|`).
    if (node.children.isEmpty && node.fixedSizeEm != null) {
      final bool hasLeft = node.leftDelimiter != null;
      final bool hasRight = node.rightDelimiter != null;
      final String? delim = hasLeft ? node.leftDelimiter : node.rightDelimiter;
      final TexMathAtomClass atomClass = hasLeft && !hasRight
          ? TexMathAtomClass.open
          : (!hasLeft && hasRight
                ? TexMathAtomClass.close
                : TexMathAtomClass.ord);
      return buildVerticalDelimiterBox(
        font: font,
        delimiter: delim,
        targetSpanEm: 0.0,
        atomClass: atomClass,
        scale: scale,
        fixedSizeEm: node.fixedSizeEm,
        isNullDelimiterSpace: false,
        span: node.span,
      );
    }

    // Split direct children around any `\middle` stretchy markers so we measure
    // non-delimiter content first and stretch `\left`, `\middle`, `\right`.
    final List<MathNode> segmentNodes = <MathNode>[];
    final List<({int segmentIndex, SymbolNode symbol})> middleMarkers =
        <({int segmentIndex, SymbolNode symbol})>[];
    final List<List<MathNode>> segments = <List<MathNode>>[<MathNode>[]];

    for (final MathNode child in node.children) {
      if (child is SymbolNode &&
          (child.command == 'middle' || child.isStretchy)) {
        middleMarkers.add((segmentIndex: segments.length - 1, symbol: child));
        segments.add(<MathNode>[]);
      } else {
        segments.last.add(child);
      }
    }

    final List<MathBox> segmentBoxes = <MathBox>[];
    double maxHeight = 0.0;
    double maxDepth = 0.0;
    for (final List<MathNode> seg in segments) {
      final MathBox segBox = seg.isEmpty
          ? const KernBox(widthEm: 0.0)
          : _layoutSequence(
              seg,
              innerState,
              span: node.span,
              preserveInnerBoundaryClass: true,
            );
      segmentBoxes.add(segBox);
      if (segBox.heightEm > maxHeight) {
        maxHeight = segBox.heightEm;
      }
      if (segBox.depthEm > maxDepth) {
        maxDepth = segBox.depthEm;
      }
      segmentNodes.addAll(seg);
    }

    final double halfSpan = math.max(maxHeight - axis, maxDepth + axis);
    final double targetSpan = math.max(
      2.0 * halfSpan,
      (constants.delimitedSubFormulaMinHeight / upem) * scale * 0.77,
    );

    final List<MathBox> assembled = <MathBox>[];
    if (node.leftDelimiter != null || node.fixedSizeEm == null) {
      assembled.add(
        buildVerticalDelimiterBox(
          font: font,
          delimiter: node.leftDelimiter,
          targetSpanEm: targetSpan,
          atomClass: TexMathAtomClass.open,
          scale: scale,
          fixedSizeEm: node.fixedSizeEm,
          span: node.span,
        ),
      );
    }

    for (int i = 0; i < segmentBoxes.length; i++) {
      if (segmentBoxes[i].widthEm > 0.0 ||
          segmentBoxes[i].heightEm > 0.0 ||
          segmentBoxes[i].depthEm > 0.0) {
        assembled.add(segmentBoxes[i]);
      }
      if (i < middleMarkers.length) {
        final SymbolNode midSym = middleMarkers[i].symbol;
        assembled.add(
          buildVerticalDelimiterBox(
            font: font,
            delimiter: midSym.value,
            targetSpanEm: targetSpan,
            atomClass: midSym.atomClass ?? TexMathAtomClass.rel,
            scale: scale,
            fixedSizeEm: node.fixedSizeEm,
            isNullDelimiterSpace: false,
            span: midSym.span,
          ),
        );
      }
    }

    if (node.rightDelimiter != null || node.fixedSizeEm == null) {
      assembled.add(
        buildVerticalDelimiterBox(
          font: font,
          delimiter: node.rightDelimiter,
          targetSpanEm: targetSpan,
          atomClass: TexMathAtomClass.close,
          scale: scale,
          fixedSizeEm: node.fixedSizeEm,
          span: node.span,
        ),
      );
    }

    return HBox(
      children: assembled,
      atomClass: TexMathAtomClass.inner,
      span: node.span,
    );
  }

  MathBox _layoutTextNode(TextNode node, _LayoutState state) {
    final TexMathFontVariant? textVariant = _variantForTextStyle(
      node.styleCommand,
    );
    final _LayoutState textState = state.copyWith(
      fontVariant: textVariant,
      clearFontVariant: textVariant == null,
      isTextMode: true,
    );

    if (node.children.isNotEmpty) {
      final List<MathBox> boxes = <MathBox>[];
      for (final MathNode child in node.children) {
        if (child is TextNode) {
          boxes.add(_layoutTextNode(child, textState));
        } else {
          // Embedded `$...$` inline math drops back to math mode.
          boxes.add(
            _layoutNode(
              child,
              state.copyWith(isTextMode: false, clearFontVariant: true),
            ),
          );
        }
      }
      return HBox(
        children: boxes,
        atomClass: TexMathAtomClass.ord,
        span: node.span,
      );
    }

    final double scale = _scale(state);
    final int level = scriptLevelForStyle(state.style);
    final List<MathBox> glyphs = <MathBox>[];
    for (final int r in node.text.runes) {
      final int baseCp;
      if (r == 0x20) {
        baseCp =
            (node.styleCommand != 'texttt' &&
                font.glyphIdForCodePoint(0x00A0) != 0)
            ? 0x00A0
            : (font.glyphIdForCodePoint(0x20) != 0 ? 0x20 : 0x00A0);
      } else {
        baseCp = r;
      }
      final int cp = resolveMathGlyphCodePoint(
        baseCodePoint: baseCp,
        font: font,
        variant: textVariant,
        isTextMode: true,
      );
      glyphs.add(
        buildGlyphBoxFromId(
          font: font,
          glyphId: font.glyphIdForCodePoint(cp),
          codePoint: cp,
          scale: scale,
          scriptLevel: level,
          useOpticalScriptVariants: options.useOpticalScriptVariants,
          span: node.span,
        ),
      );
    }
    if (glyphs.isEmpty) {
      return KernBox(
        widthEm: 0.0,
        atomClass: TexMathAtomClass.ord,
        span: node.span,
      );
    }
    return HBox(
      children: glyphs,
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }

  MathBox _layoutColorNode(ColorNode node, _LayoutState state) {
    final int? customArgb = resolveColorSpecArgb(node.colorValue);
    final int? bgArgb = resolveColorSpecArgb(node.backgroundColor);
    final int? borderArgb = resolveColorSpecArgb(node.borderColor);
    final bool hasBox = bgArgb != null || borderArgb != null;

    final MathBox inner = _layoutSequence(
      node.children,
      hasBox ? state.nested() : state,
      span: node.span,
      preserveInnerBoundaryClass: !hasBox,
    );

    final bool hasForeground =
        node.colorValue != null || node.role != TexMathColorRole.custom;
    final TexMathColorRole effectiveRole = customArgb != null
        ? TexMathColorRole.custom
        : node.role;
    final MathBox coloredInner = hasForeground
        ? inner.withMetadata(
            colorRole: effectiveRole,
            customColor: customArgb,
            inheritColor: false,
          )
        : inner;

    if (!hasBox) {
      return coloredInner;
    }

    final double scale = _scale(state);
    final double padEm = 0.30 * scale;
    final double strokeEm = borderArgb != null
        ? (constants.fractionRuleThickness / upem) * 1.675 * scale
        : 0.0;
    return _wrapBoxWithFrame(
      inner: coloredInner,
      padEm: padEm,
      backgroundArgb: bgArgb,
      borderStrokeEm: strokeEm,
      borderRole: borderArgb != null
          ? TexMathColorRole.custom
          : TexMathColorRole.foreground,
      borderArgb: borderArgb,
      span: node.span,
    );
  }

  MathBox _layoutBboxGroup(MathGroupNode node, _LayoutState state) {
    final MathBox inner = _layoutSequence(
      node.children,
      state,
      span: node.span,
    );
    final double scale = _scale(state);
    final int? bgArgb = resolveColorSpecArgb(node.attributes['background']);
    final double padEm = _parseCssLengthEm(node.attributes['padding'], scale);

    double strokeEm = 0.0;
    int? borderArgb;
    final String? rawBorder = node.attributes['border'];
    if (rawBorder != null && rawBorder.isNotEmpty) {
      final double defaultStroke =
          (constants.fractionRuleThickness / upem) * 1.675 * scale;
      strokeEm = defaultStroke;
      bool sawNone = false;
      for (final String token in rawBorder.split(_whitespacePattern)) {
        final String lower = token.trim().toLowerCase();
        if (lower.isEmpty ||
            lower == 'solid' ||
            lower == 'dashed' ||
            lower == 'dotted') {
          continue;
        }
        if (lower == 'none' || lower == 'hidden') {
          sawNone = true;
          continue;
        }
        if (_startsWithAsciiDigit(lower)) {
          strokeEm = _parseCssLengthEm(lower, scale);
          continue;
        }
        final int? parsedColor = resolveColorSpecArgb(token);
        if (parsedColor != null) {
          borderArgb = parsedColor;
        }
      }
      if (sawNone) {
        strokeEm = 0.0;
      }
    }

    if (bgArgb == null && strokeEm <= 0.0 && padEm <= 0.0) {
      return inner;
    }

    return _wrapBoxWithFrame(
      inner: inner,
      padEm: padEm,
      backgroundArgb: bgArgb,
      borderStrokeEm: strokeEm,
      borderRole: borderArgb != null
          ? TexMathColorRole.custom
          : TexMathColorRole.foreground,
      borderArgb: borderArgb,
      span: node.span,
    );
  }

  MathBox _layoutCancelGroup(
    MathGroupNode node,
    _LayoutState state,
    String role,
  ) {
    if (node.children.isEmpty) {
      return KernBox(widthEm: 0.0, span: node.span);
    }
    final MathBox body = _layoutNode(node.children.first, state);
    final double scale = _scale(state);
    final double strokeEm =
        (constants.fractionRuleThickness / upem) * 1.5 * scale;
    final double padY = 0.05 * scale;
    final double x0 = 0.0;
    final double x1 = math.max(body.widthEm, 0.25 * scale);
    final double y0 = -body.depthEm - padY;
    final double y1 = body.heightEm + padY;

    final List<VBoxChild> placed = <VBoxChild>[
      VBoxChild(box: body, xEm: 0.0, yEm: 0.0),
    ];

    if (role == 'cancel' || role == 'xcancel' || role == 'cancelto') {
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: x0,
            y0: y0,
            x1: x1,
            y1: y1,
            thicknessEm: strokeEm,
            span: node.span,
          ),
        ),
      );
    }
    if (role == 'bcancel' || role == 'xcancel') {
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: x0,
            y0: y1,
            x1: x1,
            y1: y0,
            thicknessEm: strokeEm,
            span: node.span,
          ),
        ),
      );
    }

    double totalW = math.max(body.widthEm, x1);
    double totalH = math.max(body.heightEm, y1);
    double totalD = math.max(body.depthEm, -y0);

    if (role == 'cancelto') {
      placed.add(
        VBoxChild(
          box: _arrowHeadGlyphBox(
            x0: x0,
            y0: y0,
            x1: x1,
            y1: y1,
            sizeEm: 0.20 * scale,
            span: node.span,
          ),
        ),
      );
      if (node.children.length >= 2) {
        final MathBox target = _layoutNode(
          node.children[1],
          state.copyWith(style: superscriptStyle(state.style)),
        );
        final double tx = x1 + 0.06 * scale;
        final double ty = y1 - target.depthEm * 0.25;
        placed.add(VBoxChild(box: target, xEm: tx, yEm: ty));
        totalW = math.max(totalW, tx + target.widthEm);
        totalH = math.max(totalH, ty + target.heightEm);
        totalD = math.max(totalD, -ty + target.depthEm);
      }
    }

    return VBox.positioned(
      children: placed,
      widthEm: totalW,
      heightEm: totalH,
      depthEm: totalD,
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }

  MathBox _layoutEncloseGroup(MathGroupNode node, _LayoutState state) {
    final MathBox inner = _layoutSequence(
      node.children,
      state,
      span: node.span,
    );
    final double scale = _scale(state);
    final double strokeEm =
        (constants.fractionRuleThickness / upem) * 1.5 * scale;
    final String rawNotation = node.attributes['notation'] ?? '';
    final Set<String> notations = rawNotation
        .split(_notationSeparatorPattern)
        .where((String s) => s.isNotEmpty)
        .toSet();

    if (notations.isEmpty) {
      return inner;
    }

    final int? customStrokeArgb = _extractEncloseColorArgb(
      node.attributes['style'],
    );
    final TexMathColorRole strokeRole = customStrokeArgb != null
        ? TexMathColorRole.custom
        : TexMathColorRole.foreground;
    final bool inheritStroke = customStrokeArgb == null;

    final bool needsPad = notations.any(
      (String n) =>
          n == 'box' ||
          n == 'roundedbox' ||
          n == 'circle' ||
          n == 'left' ||
          n == 'right' ||
          n == 'top' ||
          n == 'bottom' ||
          n == 'actuarial' ||
          n == 'madruwb' ||
          n == 'longdiv' ||
          n == 'radical' ||
          n == 'phasorangle',
    );
    final bool hasCircle = notations.contains('circle');
    final double padX = hasCircle
        ? 0.24 * scale
        : (needsPad ? 0.16 * scale : 0.0);
    final double padY = hasCircle
        ? 0.20 * scale
        : (needsPad ? 0.14 * scale : 0.0);
    final double leftExtra =
        (notations.contains('phasorangle') ||
            notations.contains('longdiv') ||
            notations.contains('radical'))
        ? 0.22 * scale
        : 0.0;

    final double xOffset = padX + leftExtra;
    final double totalW = xOffset + inner.widthEm + padX;
    final double totalH = inner.heightEm + padY;
    final double totalD = inner.depthEm + padY;
    final double fullH = totalH + totalD;
    final double leftEdge = 0.0;
    final double rightEdge = totalW;
    final double bottomY = -totalD;
    final double topY = totalH;

    final List<VBoxChild> placed = <VBoxChild>[
      VBoxChild(box: inner, xEm: xOffset, yEm: 0.0),
    ];

    void addRule(double x, double y, double w, double h) {
      placed.add(
        VBoxChild(
          box: RuleBox(
            widthEm: w,
            heightEm: h,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
          xEm: x,
          yEm: y,
        ),
      );
    }

    if (notations.contains('box')) {
      placed.add(
        VBoxChild(
          box: RuleBox(
            widthEm: math.max(0.0, totalW - strokeEm),
            heightEm: math.max(0.0, fullH - strokeEm),
            strokeWidthEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
          xEm: strokeEm / 2.0,
          yEm: bottomY + strokeEm / 2.0,
        ),
      );
    }
    if (notations.contains('roundedbox')) {
      placed.add(
        VBoxChild(
          box: _roundedRectStrokeGlyphBox(
            widthEm: totalW,
            bottomYEm: bottomY,
            topYEm: topY,
            radiusEm: math.min(0.22 * scale, math.min(totalW, fullH) * 0.35),
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
    }
    if (hasCircle) {
      placed.add(
        VBoxChild(
          box: _ellipseStrokeGlyphBox(
            cxEm: totalW / 2.0,
            cyEm: (bottomY + topY) / 2.0,
            rxEm: totalW / 2.0,
            ryEm: fullH / 2.0,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
    }
    if (notations.contains('top') || notations.contains('actuarial')) {
      addRule(leftEdge, topY - strokeEm, totalW, strokeEm);
    }
    if (notations.contains('bottom') || notations.contains('madruwb')) {
      addRule(leftEdge, bottomY, totalW, strokeEm);
    }
    if (notations.contains('left')) {
      addRule(leftEdge, bottomY, strokeEm, fullH);
    }
    if (notations.contains('right') ||
        notations.contains('actuarial') ||
        notations.contains('madruwb')) {
      addRule(rightEdge - strokeEm, bottomY, strokeEm, fullH);
    }
    if (notations.contains('horizontalstrike')) {
      addRule(
        leftEdge,
        (bottomY + topY) / 2.0 - strokeEm / 2.0,
        totalW,
        strokeEm,
      );
    }
    if (notations.contains('verticalstrike')) {
      addRule(totalW / 2.0 - strokeEm / 2.0, bottomY, strokeEm, fullH);
    }
    if (notations.contains('updiagonalstrike') ||
        notations.contains('updiagonalarrow') ||
        notations.contains('northeastarrow')) {
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: leftEdge,
            y0: bottomY,
            x1: rightEdge,
            y1: topY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
      if (notations.contains('updiagonalarrow') ||
          notations.contains('northeastarrow')) {
        placed.add(
          VBoxChild(
            box: _arrowHeadGlyphBox(
              x0: leftEdge,
              y0: bottomY,
              x1: rightEdge,
              y1: topY,
              sizeEm: 0.20 * scale,
              colorRole: strokeRole,
              customColor: customStrokeArgb,
              inheritColor: inheritStroke,
              span: node.span,
            ),
          ),
        );
      }
    }
    if (notations.contains('downdiagonalstrike')) {
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: leftEdge,
            y0: topY,
            x1: rightEdge,
            y1: bottomY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
    }
    if (notations.contains('phasorangle')) {
      final double legX = math.max(leftExtra, 0.25 * scale);
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: leftEdge,
            y0: bottomY,
            x1: legX,
            y1: topY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
      addRule(leftEdge, bottomY, totalW, strokeEm);
    }
    if (notations.contains('longdiv')) {
      final double barX = math.max(leftExtra * 0.6, 0.14 * scale);
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: leftEdge,
            y0: bottomY,
            x1: barX,
            y1: topY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
      addRule(barX, topY - strokeEm, totalW - barX, strokeEm);
    }
    if (notations.contains('radical')) {
      final double midX = leftExtra * 0.35;
      final double topX = leftExtra;
      final double midY = (bottomY + topY) * 0.5;
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: leftEdge,
            y0: midY,
            x1: midX,
            y1: bottomY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
      placed.add(
        VBoxChild(
          box: _lineStrokeGlyphBox(
            x0: midX,
            y0: bottomY,
            x1: topX,
            y1: topY,
            thicknessEm: strokeEm,
            colorRole: strokeRole,
            customColor: customStrokeArgb,
            inheritColor: inheritStroke,
            span: node.span,
          ),
        ),
      );
      addRule(topX, topY - strokeEm, totalW - topX, strokeEm);
    }

    return VBox.positioned(
      children: placed,
      widthEm: totalW,
      heightEm: totalH,
      depthEm: totalD,
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }

  GlyphBox _lineStrokeGlyphBox({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double thicknessEm,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    SourceSpan? span,
  }) {
    final double dx = x1 - x0;
    final double dy = y1 - y0;
    final double len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      return GlyphBox(
        glyphId: 0,
        codePoint: 0,
        widthEm: 0.0,
        heightEm: 0.0,
        depthEm: 0.0,
        advanceEm: 0.0,
        outline: const GlyphOutline(glyphId: 0, commands: <PathCommand>[]),
        span: span,
      );
    }
    final double nx = (-dy / len) * (thicknessEm / 2.0);
    final double ny = (dx / len) * (thicknessEm / 2.0);
    final GlyphOutline outline = GlyphOutline(
      glyphId: 0,
      commands: <PathCommand>[
        MoveTo((x0 + nx) * upem, (y0 + ny) * upem),
        LineTo((x1 + nx) * upem, (y1 + ny) * upem),
        LineTo((x1 - nx) * upem, (y1 - ny) * upem),
        LineTo((x0 - nx) * upem, (y0 - ny) * upem),
        const ClosePath(),
      ],
    );
    return GlyphBox(
      glyphId: 0,
      codePoint: 0,
      widthEm: 0.0,
      heightEm: 0.0,
      depthEm: 0.0,
      advanceEm: 0.0,
      outline: outline,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      span: span,
    );
  }

  GlyphBox _arrowHeadGlyphBox({
    required double x0,
    required double y0,
    required double x1,
    required double y1,
    required double sizeEm,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    SourceSpan? span,
  }) {
    final double dx = x1 - x0;
    final double dy = y1 - y0;
    final double len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) {
      return GlyphBox(
        glyphId: 0,
        codePoint: 0,
        widthEm: 0.0,
        heightEm: 0.0,
        depthEm: 0.0,
        advanceEm: 0.0,
        outline: const GlyphOutline(glyphId: 0, commands: <PathCommand>[]),
        span: span,
      );
    }
    final double ux = dx / len;
    final double uy = dy / len;
    final double px = -uy;
    final double py = ux;
    final double backX = x1 - ux * sizeEm;
    final double backY = y1 - uy * sizeEm;
    final double wing = sizeEm * 0.48;
    final GlyphOutline outline = GlyphOutline(
      glyphId: 0,
      commands: <PathCommand>[
        MoveTo(x1 * upem, y1 * upem),
        LineTo((backX + px * wing) * upem, (backY + py * wing) * upem),
        LineTo(
          (backX - ux * sizeEm * 0.15) * upem,
          (backY - uy * sizeEm * 0.15) * upem,
        ),
        LineTo((backX - px * wing) * upem, (backY - py * wing) * upem),
        const ClosePath(),
      ],
    );
    return GlyphBox(
      glyphId: 0,
      codePoint: 0,
      widthEm: 0.0,
      heightEm: 0.0,
      depthEm: 0.0,
      advanceEm: 0.0,
      outline: outline,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      span: span,
    );
  }

  GlyphBox _ellipseStrokeGlyphBox({
    required double cxEm,
    required double cyEm,
    required double rxEm,
    required double ryEm,
    required double thicknessEm,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    SourceSpan? span,
  }) {
    const double k = 0.5522847498;
    final double halfT = thicknessEm / 2.0;
    final double orx = (rxEm + halfT) * upem;
    final double ory = (ryEm + halfT) * upem;
    final double irx = math.max(0.0, rxEm - halfT) * upem;
    final double iry = math.max(0.0, ryEm - halfT) * upem;
    final double cx = cxEm * upem;
    final double cy = cyEm * upem;

    final GlyphOutline outline = GlyphOutline(
      glyphId: 0,
      commands: <PathCommand>[
        // Outer ellipse counter-clockwise
        MoveTo(cx + orx, cy),
        CubicTo(cx + orx, cy + k * ory, cx + k * orx, cy + ory, cx, cy + ory),
        CubicTo(cx - k * orx, cy + ory, cx - orx, cy + k * ory, cx - orx, cy),
        CubicTo(cx - orx, cy - k * ory, cx - k * orx, cy - ory, cx, cy - ory),
        CubicTo(cx + k * orx, cy - ory, cx + orx, cy - k * ory, cx + orx, cy),
        const ClosePath(),
        // Inner ellipse clockwise
        MoveTo(cx + irx, cy),
        CubicTo(cx + irx, cy - k * iry, cx + k * irx, cy - iry, cx, cy - iry),
        CubicTo(cx - k * irx, cy - iry, cx - irx, cy - k * iry, cx - irx, cy),
        CubicTo(cx - irx, cy + k * iry, cx - k * irx, cy + iry, cx, cy + iry),
        CubicTo(cx + k * irx, cy + iry, cx + irx, cy + k * iry, cx + irx, cy),
        const ClosePath(),
      ],
    );
    return GlyphBox(
      glyphId: 0,
      codePoint: 0,
      widthEm: 0.0,
      heightEm: 0.0,
      depthEm: 0.0,
      advanceEm: 0.0,
      outline: outline,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      span: span,
    );
  }

  GlyphBox _roundedRectStrokeGlyphBox({
    required double widthEm,
    required double bottomYEm,
    required double topYEm,
    required double radiusEm,
    required double thicknessEm,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    SourceSpan? span,
  }) {
    const double k = 0.5522847498;
    final double halfT = thicknessEm / 2.0;
    final double ox0 = (0.0 - halfT) * upem;
    final double ox1 = (widthEm + halfT) * upem;
    final double oy0 = (bottomYEm - halfT) * upem;
    final double oy1 = (topYEm + halfT) * upem;
    final double or = (radiusEm + halfT) * upem;

    final double ix0 = (0.0 + halfT) * upem;
    final double ix1 = (widthEm - halfT) * upem;
    final double iy0 = (bottomYEm + halfT) * upem;
    final double iy1 = (topYEm - halfT) * upem;
    final double ir = math.max(0.0, radiusEm - halfT) * upem;

    final GlyphOutline outline = GlyphOutline(
      glyphId: 0,
      commands: <PathCommand>[
        // Outer rounded rect counter-clockwise
        MoveTo(ox0 + or, oy0),
        LineTo(ox1 - or, oy0),
        CubicTo(
          ox1 - or * (1.0 - k),
          oy0,
          ox1,
          oy0 + or * (1.0 - k),
          ox1,
          oy0 + or,
        ),
        LineTo(ox1, oy1 - or),
        CubicTo(
          ox1,
          oy1 - or * (1.0 - k),
          ox1 - or * (1.0 - k),
          oy1,
          ox1 - or,
          oy1,
        ),
        LineTo(ox0 + or, oy1),
        CubicTo(
          ox0 + or * (1.0 - k),
          oy1,
          ox0,
          oy1 - or * (1.0 - k),
          ox0,
          oy1 - or,
        ),
        LineTo(ox0, oy0 + or),
        CubicTo(
          ox0,
          oy0 + or * (1.0 - k),
          ox0 + or * (1.0 - k),
          oy0,
          ox0 + or,
          oy0,
        ),
        const ClosePath(),
        // Inner rounded rect clockwise
        MoveTo(ix0 + ir, iy0),
        CubicTo(
          ix0 + ir * (1.0 - k),
          iy0,
          ix0,
          iy0 + ir * (1.0 - k),
          ix0,
          iy0 + ir,
        ),
        LineTo(ix0, iy1 - ir),
        CubicTo(
          ix0,
          iy1 - ir * (1.0 - k),
          ix0 + ir * (1.0 - k),
          iy1,
          ix0 + ir,
          iy1,
        ),
        LineTo(ix1 - ir, iy1),
        CubicTo(
          ix1 - ir * (1.0 - k),
          iy1,
          ix1,
          iy1 - ir * (1.0 - k),
          ix1,
          iy1 - ir,
        ),
        LineTo(ix1, iy0 + ir),
        CubicTo(
          ix1,
          iy0 + ir * (1.0 - k),
          ix1 - ir * (1.0 - k),
          iy0,
          ix1 - ir,
          iy0,
        ),
        LineTo(ix0 + ir, iy0),
        const ClosePath(),
      ],
    );
    return GlyphBox(
      glyphId: 0,
      codePoint: 0,
      widthEm: 0.0,
      heightEm: 0.0,
      depthEm: 0.0,
      advanceEm: 0.0,
      outline: outline,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      span: span,
    );
  }

  MathBox _layoutTagNode(TagNode node, _LayoutState state) {
    if (node.isLabelDefinition) {
      return AnchorBox(
        id: node.label,
        label: labels[node.label],
        span: node.span,
      );
    }

    if (node.isReference) {
      final String text = node.isStarred ? node.label : '(${node.label})';
      final MathBox textBox = _layoutTextNode(
        TextNode(span: node.span, text: text, styleCommand: 'textrm'),
        state,
      );
      return HBox(
        children: <MathBox>[
          AnchorBox(
            id: 'ref:${node.label}',
            label: node.label,
            span: node.span,
          ),
          textBox,
        ],
        atomClass: TexMathAtomClass.ord,
        span: node.span,
      );
    }

    final MathBox bodyBox = node.body != null
        ? _layoutNode(node.body!, state)
        : KernBox(widthEm: 0.0, span: node.span);
    final String tagText = node.isStarred ? node.label : '(${node.label})';
    final MathBox tagBox = _layoutTextNode(
      TextNode(span: node.span, text: tagText, styleCommand: 'textrm'),
      state,
    );
    return HBox(
      children: <MathBox>[
        bodyBox,
        KernBox(widthEm: 1.0 * scaleForStyle(state.style, constants)),
        AnchorBox(id: 'tag:${node.label}', label: node.label, span: node.span),
        tagBox,
      ],
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }

  bool _isHorizontalLimiterAccent(MathNode node) {
    if (node is AccentNode && node.accent.isNotEmpty) {
      final int cp = firstCodePointOr(node.accent, 0);
      return cp == 0x23DE ||
          cp == 0x23DF ||
          cp == 0x23B4 ||
          cp == 0x23B5 ||
          cp == 0x23DC ||
          cp == 0x23DD;
    }
    if (node is MathGroupNode &&
        node.role == null &&
        !node.isExplicitGroup &&
        node.children.length == 1) {
      return _isHorizontalLimiterAccent(node.children.first);
    }
    return false;
  }

  OperatorNode? _extractCoreOperator(MathNode node) {
    if (node is OperatorNode) {
      return node;
    }
    if (node is MathGroupNode &&
        node.role == null &&
        !node.isExplicitGroup &&
        node.children.length == 1) {
      return _extractCoreOperator(node.children.first);
    }
    return null;
  }

  bool _isIntegralOperator(OperatorNode op) {
    if (op.operatorName.isEmpty) {
      return false;
    }
    final int cp = firstCodePointOr(op.operatorName, 0);
    return (cp >= 0x222B && cp <= 0x2233) || cp == 0x2A0C;
  }

  bool _isEmptyNode(MathNode node) {
    return node is MathGroupNode && node.children.isEmpty;
  }

  GlyphBox? _trailingGlyph(MathBox box) {
    switch (box) {
      case GlyphBox():
        return box;
      case HBox(:final List<MathBox> children):
        for (int i = children.length - 1; i >= 0; i--) {
          final GlyphBox? g = _trailingGlyph(children[i]);
          if (g != null) {
            return g;
          }
        }
        return null;
      case VBox(:final List<VBoxChild> placements):
        return placements.isNotEmpty
            ? _trailingGlyph(placements.first.box)
            : null;
      case RuleBox():
      case KernBox():
      case AnchorBox():
        return null;
    }
  }

  GlyphBox? _leadingGlyph(MathBox box) {
    switch (box) {
      case GlyphBox():
        return box;
      case HBox(:final List<MathBox> children):
        for (final MathBox c in children) {
          final GlyphBox? g = _leadingGlyph(c);
          if (g != null) {
            return g;
          }
        }
        return null;
      case VBox(:final List<VBoxChild> placements):
        return placements.isNotEmpty
            ? _leadingGlyph(placements.first.box)
            : null;
      case RuleBox():
      case KernBox():
      case AnchorBox():
        return null;
    }
  }

  TexMathFontVariant? _variantForTextStyle(String? cmd) {
    switch (cmd) {
      case 'textbf':
        return TexMathFontVariant.bold;
      case 'texttt':
        return TexMathFontVariant.monospace;
      case 'textsf':
        return TexMathFontVariant.sansSerif;
      case 'textit':
      case 'emph':
        return TexMathFontVariant.italic;
      default:
        return null;
    }
  }

  double _parseCssLengthEm(String? raw, double scale) {
    if (raw == null || raw.isEmpty) {
      return 0.0;
    }
    final RegExpMatch? m = _cssLengthPattern.firstMatch(raw.trim());
    if (m == null) {
      return 0.0;
    }
    final double val = double.tryParse(m.group(1)!) ?? 0.0;
    final String unit = (m.group(2) ?? '').toLowerCase();
    switch (unit) {
      case 'em':
        return val * scale;
      case 'ex':
        return val * 0.43 * scale;
      case 'pt':
        return (val / 10.0) * scale;
      case 'px':
      default:
        return (val / 16.0) * scale;
    }
  }

  int? _extractEncloseColorArgb(String? styleAttr) {
    if (styleAttr == null || styleAttr.isEmpty) {
      return null;
    }
    final RegExpMatch? m = _encloseColorPattern.firstMatch(styleAttr);
    if (m == null) {
      return null;
    }
    return resolveColorSpecArgb(m.group(1));
  }
}

const Map<String, String> _negatedUnicode = <String, String>{
  '=': '\u2260',
  '<': '\u226E',
  '>': '\u226F',
  '\u2261': '\u2262',
  '\u2208': '\u2209',
  '\u220B': '\u220C',
  '\u2282': '\u2284',
  '\u2283': '\u2285',
  '\u2286': '\u2288',
  '\u2287': '\u2289',
  '\u223C': '\u2241',
  '\u2243': '\u2244',
  '\u2245': '\u2247',
  '\u2248': '\u2249',
  '\u224D': '\u226D',
  '\u2264': '\u2270',
  '\u2265': '\u2271',
  '\u227A': '\u2280',
  '\u227B': '\u2281',
  '\u227C': '\u22E0',
  '\u227D': '\u22E1',
  '\u2291': '\u22E2',
  '\u2292': '\u22E3',
  '\u2223': '\u2224',
  '\u2225': '\u2226',
  '\u22A2': '\u22AC',
  '\u22A8': '\u22AD',
  '\u22A9': '\u22AE',
  '\u22AB': '\u22AF',
  '\u2203': '\u2204',
};

final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _notationSeparatorPattern = RegExp(r'[\s,]+');
final RegExp _cssLengthPattern = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]*)$');
final RegExp _encloseColorPattern = RegExp(
  r'(?:mathcolor|color)\s*[:=]\s*"?([^";\s]+)"?',
  caseSensitive: false,
);

bool _startsWithAsciiDigit(String s) {
  if (s.isEmpty) {
    return false;
  }
  final int c = s.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}
