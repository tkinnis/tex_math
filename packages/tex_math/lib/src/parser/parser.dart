import '../ast.dart';
import '../error.dart';
import '../options.dart';
import '../shared/colors.dart';
import '../shared/math_symbols.dart';
import '../source_span.dart';
import 'environments.dart';
import 'macros.dart';
import 'mhchem_parser.dart';
import 'package_registry.dart';
import 'parser_host.dart';
import 'physics_parser.dart';
import 'symbol_map.dart';
import 'tokenizer.dart';

/// Parses [source] into a typed [MathNode] syntax tree using [options].
MathNode parseTexInternal(String source, {TexMathOptions? options}) {
  final TexMathOptions effective = options ?? const TexMathOptions();
  final int length = source.length;
  if (length > effective.budgets.maxInputLength) {
    throw TexMathBudgetError(
      'Input length $length exceeds maxInputLength '
      '(${effective.budgets.maxInputLength}).',
      budgetName: 'maxInputLength',
      limit: effective.budgets.maxInputLength,
      actual: length,
      span: SourceSpan(effective.budgets.maxInputLength, length),
    );
  }

  final SourceSpan fullSpan = SourceSpan(0, length);
  final TexActivePackages activePackages = TexActivePackages(effective);
  final bool suppressErrors =
      !effective.strictErrors || activePackages.has('noerrors');

  try {
    final List<TexToken> tokens = tokenizeTex(source);
    final TexTokenCursor cursor = TexTokenCursor(
      source: source,
      initialTokens: tokens,
      budgets: effective.budgets,
    );
    final Map<String, String> initialMacros =
        activePackages.has('configmacros') || effective.macros.isNotEmpty
        ? effective.macros
        : const <String, String>{};
    final TexMacroTable macroTable = TexMacroTable(
      preconfiguredMacros: initialMacros,
    );
    final _TexParser parser = _TexParser(
      source: source,
      cursor: cursor,
      macroTable: macroTable,
      activePackages: activePackages,
      options: effective,
    );
    return parser.parseDocument();
  } on TexMathBudgetError {
    rethrow;
  } on TexMathError catch (err) {
    if (!suppressErrors) {
      rethrow;
    }
    return MathRootNode(
      span: fullSpan,
      displayMode: effective.displayMode,
      children: <MathNode>[
        ErrorNode(span: err.span ?? fullSpan, error: err, rawSource: source),
      ],
    );
  }
}

final class _TexParser implements TexParserHost {
  _TexParser({
    required this.source,
    required this.cursor,
    required this.macroTable,
    required this.activePackages,
    required this.options,
    Map<String, String>? labels,
    _AutoTagCounter? tagCounter,
  }) : _labels = labels ?? <String, String>{},
       _tagCounter = tagCounter ?? _AutoTagCounter();

  final String source;

  @override
  final TexTokenCursor cursor;

  @override
  final TexMacroTable macroTable;

  @override
  final TexActivePackages activePackages;

  @override
  final TexMathOptions options;

  final Map<String, String> _labels;
  final _AutoTagCounter _tagCounter;
  final List<_OpenEnvFrame> _envStack = <_OpenEnvFrame>[];
  final List<_OpenEnvFrame> _openUserEnvs = <_OpenEnvFrame>[];
  int _nestingDepth = 0;
  TexMathFontVariant? _fontVariant;
  bool _inBoldSymbol = false;

  @override
  TexMathFontVariant? get currentFontVariant => _fontVariant;

  @override
  int nextAutoTag() => _tagCounter.next();

  @override
  void bindLabel(String labelName, String tag) {
    _labels[labelName] = tag;
  }

  TexMathFontVariant? _resolveSymbolVariant(
    TexMathFontVariant? baseVariant,
    String value,
  ) {
    if (!_inBoldSymbol) {
      return baseVariant;
    }
    return boldSymbolVariantFor(
      baseVariant,
      value.isEmpty ? null : value.runes.first,
    );
  }

  @override
  void enterNesting(SourceSpan span) {
    _nestingDepth++;
    if (_nestingDepth > options.budgets.maxNestingDepth) {
      throw TexMathBudgetError(
        'AST nesting depth $_nestingDepth exceeds maxNestingDepth '
        '(${options.budgets.maxNestingDepth}).',
        budgetName: 'maxNestingDepth',
        limit: options.budgets.maxNestingDepth,
        actual: _nestingDepth,
        span: span,
      );
    }
  }

  @override
  void exitNesting() {
    if (_nestingDepth > 0) {
      _nestingDepth--;
    }
  }

  MathRootNode parseDocument() {
    final SourceSpan fullSpan = SourceSpan(0, source.length);
    enterNesting(fullSpan);
    try {
      final _SeqResult result = _parseSequence(stopMode: _StopMode.eof);
      if (_envStack.isNotEmpty) {
        final _OpenEnvFrame unclosed = _envStack.last;
        throw TexMathSyntaxError(
          'Missing \\end{${unclosed.name}}.',
          errorClass: TexMathErrorClass.mismatchedEnvironment,
          span: unclosed.span,
        );
      }
      if (_openUserEnvs.isNotEmpty) {
        final _OpenEnvFrame unclosed = _openUserEnvs.last;
        throw TexMathSyntaxError(
          'Missing \\end{${unclosed.name}}.',
          errorClass: TexMathErrorClass.mismatchedEnvironment,
          span: unclosed.span,
        );
      }
      List<MathNode> finalNodes = result.nodes;
      if (result.rowTag != null) {
        final TagNode rt = result.rowTag!;
        if (result.rowLabel != null) {
          _labels[result.rowLabel!] = rt.label;
        }
        final MathNode bodyNode = finalNodes.length == 1
            ? finalNodes.first
            : MathGroupNode(
                span: _mergeSpanList(fullSpan, finalNodes),
                isExplicitGroup: false,
                children: _unmodifiableNodes(finalNodes),
              );
        finalNodes = <MathNode>[
          TagNode(
            span: fullSpan,
            label: rt.label,
            isStarred: rt.isStarred,
            body: bodyNode,
          ),
        ];
      } else if (options.tagMode == TexMathTagMode.all &&
          options.displayMode == TexMathDisplayMode.display &&
          !result.rowHasNoTag &&
          !_containsTaggableDisplayEnvironment(finalNodes)) {
        final String tagStr = '${nextAutoTag()}';
        if (result.rowLabel != null) {
          _labels[result.rowLabel!] = tagStr;
        }
        final MathNode bodyNode = finalNodes.length == 1
            ? finalNodes.first
            : MathGroupNode(
                span: _mergeSpanList(fullSpan, finalNodes),
                isExplicitGroup: false,
                children: _unmodifiableNodes(finalNodes),
              );
        finalNodes = <MathNode>[
          TagNode(span: fullSpan, label: tagStr, body: bodyNode),
        ];
      }
      return MathRootNode(
        span: fullSpan,
        displayMode: options.displayMode,
        children: _unmodifiableNodes(finalNodes),
        labels: Map<String, String>.unmodifiable(_labels),
      );
    } finally {
      exitNesting();
    }
  }

  _SeqResult _parseSequence({
    required _StopMode stopMode,
    String? activeEnvName,
    bool allowAlignTab = false,
  }) {
    final List<MathNode> nodes = <MathNode>[];
    int? infixSplitIndex;
    String? infixLeftDelim;
    String? infixRightDelim;
    double? infixThicknessEm;
    SourceSpan? infixSpan;
    bool rowHasNoTag = false;
    TagNode? rowTag;
    String? rowLabel;
    String? cellBackground;
    String? rowBackground;
    String? columnBackground;

    _SeqResult finish(String? stopReason, [_SeqResult? rest]) =>
        _buildSeqResult(
          nodes: nodes,
          infixSplitIndex: infixSplitIndex,
          infixLeftDelim: infixLeftDelim,
          infixRightDelim: infixRightDelim,
          infixThicknessEm: infixThicknessEm,
          infixSpan: infixSpan,
          stopReason: stopReason,
          rowHasNoTag: rowHasNoTag || (rest?.rowHasNoTag ?? false),
          rowTag: rowTag ?? rest?.rowTag,
          rowLabel: rest?.rowLabel ?? rowLabel,
          cellBackground: rest?.cellBackground ?? cellBackground,
          rowBackground: rest?.rowBackground ?? rowBackground,
          columnBackground: rest?.columnBackground ?? columnBackground,
        );

    void appendNode(MathNode node) {
      nodes.add(node);
    }

    while (true) {
      cursor.skipIgnorable();
      final TexToken? peeked = cursor.peek();
      if (peeked == null) {
        if (stopMode == _StopMode.closeBrace) {
          throw TexMathSyntaxError(
            'Missing closing brace "}".',
            errorClass: TexMathErrorClass.missingBrace,
            span: SourceSpan.empty(source.length),
          );
        }
        if (stopMode == _StopMode.rightDelim) {
          throw TexMathSyntaxError(
            'Missing \\right delimiter.',
            errorClass: TexMathErrorClass.missingDelimiter,
            span: SourceSpan.empty(source.length),
          );
        }
        if (stopMode == _StopMode.envCell) {
          throw TexMathSyntaxError(
            'Missing \\end{$activeEnvName}.',
            errorClass: TexMathErrorClass.mismatchedEnvironment,
            span: SourceSpan.empty(source.length),
          );
        }
        break;
      }

      if (peeked.kind == TexTokenKind.endGroup) {
        if (stopMode == _StopMode.closeBrace) {
          cursor.next();
          break;
        }
        if (stopMode == _StopMode.rightDelim) {
          throw TexMathSyntaxError(
            'Missing \\right delimiter before "}".',
            errorClass: TexMathErrorClass.missingDelimiter,
            span: peeked.span,
          );
        }
        throw TexMathSyntaxError(
          'Extra closing brace "}".',
          errorClass: TexMathErrorClass.extraBrace,
          span: peeked.span,
        );
      }

      if (peeked.kind == TexTokenKind.alignmentTab) {
        if (stopMode == _StopMode.envCell) {
          if (!allowAlignTab) {
            throw TexMathSyntaxError(
              'Misplaced alignment tab & inside \\begin{$activeEnvName}.',
              errorClass: TexMathErrorClass.misplacedAlignmentTab,
              span: peeked.span,
            );
          }
          cursor.next();
          return finish('amp');
        }
        throw TexMathSyntaxError(
          'Misplaced alignment tab character &.',
          errorClass: TexMathErrorClass.misplacedAlignmentTab,
          span: peeked.span,
        );
      }

      // Check control sequence stopping conditions BEFORE expanding user macros
      // or handling commands, EXCEPT expand user macros that might produce \end or \\.
      if (peeked.kind == TexTokenKind.controlSequence) {
        final String cs = peeked.text;
        if (cs == 'right' && stopMode == _StopMode.rightDelim) {
          cursor.next();
          break;
        }
        if (cs == 'end') {
          if (tryExpandUserEnvEnd()) {
            continue;
          }
          if (stopMode == _StopMode.envCell) {
            return finish('end');
          }
          if (stopMode == _StopMode.rightDelim) {
            throw TexMathSyntaxError(
              'Missing \\right delimiter before \\end.',
              errorClass: TexMathErrorClass.missingDelimiter,
              span: peeked.span,
            );
          }
          if (stopMode == _StopMode.closeBrace) {
            throw TexMathSyntaxError(
              'Missing closing brace "}" before \\end.',
              errorClass: TexMathErrorClass.missingBrace,
              span: peeked.span,
            );
          }
        }
        if ((cs == '\\' || cs == 'cr') && stopMode == _StopMode.envCell) {
          cursor.next();
          if (cs == '\\') {
            _consumeNewlineStarAndDimen(peeked.span);
          }
          return finish('cr');
        }
        if (cs == '\\') {
          cursor.next();
          _consumeNewlineStarAndDimen(peeked.span);
          appendNode(SpaceNode(span: peeked.span, widthEm: 0, command: r'\\'));
          continue;
        }
        if (cs == 'hline' || cs == 'hdashline') {
          throw TexMathSyntaxError(
            'Misplaced \\$cs.',
            errorClass: TexMathErrorClass.misplacedNewline,
            span: peeked.span,
          );
        }
        if (cs == 'cr') {
          throw TexMathSyntaxError(
            'Misplaced \\cr outside alignment environment.',
            errorClass: TexMathErrorClass.misplacedNewline,
            span: peeked.span,
          );
        }
      }

      final TexToken token = cursor.next()!;

      // Handle infix fraction commands (`\over`, `\choose`, `\brack`, `\brace`, `\atop`, `\above`).
      if (token.kind == TexTokenKind.controlSequence &&
          _isInfixFractionCommand(token.text)) {
        if (infixSplitIndex != null) {
          throw TexMathSyntaxError(
            'Ambiguous repeated \\${token.text} in the same group.',
            errorClass: TexMathErrorClass.syntaxError,
            span: token.span,
          );
        }
        final _InfixFractionInfo info = _parseInfixFractionCommand(
          token.text,
          token.span,
        );
        infixSplitIndex = nodes.length;
        infixLeftDelim = info.leftDelim;
        infixRightDelim = info.rightDelim;
        infixThicknessEm = info.thicknessEm;
        infixSpan = token.span;
        continue;
      }

      // Handle standalone script tokens attached to previous atom or empty base.
      if (token.kind == TexTokenKind.superscript ||
          token.kind == TexTokenKind.subscript ||
          (token.kind == TexTokenKind.other &&
              (token.text == "'" || token.text == '\u2019'))) {
        final MathNode base = nodes.isNotEmpty
            ? nodes.removeLast()
            : MathGroupNode(
                span: SourceSpan.empty(token.span.start),
                children: const <MathNode>[],
                isExplicitGroup: false,
              );
        nodes.add(_attachSingleScript(base, token));
        continue;
      }

      // Handle `\limits`, `\nolimits`, `\displaylimits`.
      if (token.kind == TexTokenKind.controlSequence &&
          (token.text == 'limits' ||
              token.text == 'nolimits' ||
              token.text == 'displaylimits')) {
        if (nodes.isEmpty) {
          throw TexMathSyntaxError(
            '\\${token.text} is allowed only on operators.',
            span: token.span,
          );
        }
        final bool? limits = switch (token.text) {
          'limits' => true,
          'nolimits' => false,
          _ => null,
        };
        nodes[nodes.length - 1] = _applyLimitsModifier(
          nodes.last,
          limits,
          token.span,
        );
        continue;
      }

      // Handle `\color` switch (when `color` package is active and NOT `colorv2`),
      // `\rm`/`\bf`/`\it`/`\sf`/`\tt`/`\cal`/`\mit`/`\oldstyle` switches,
      // `\displaystyle`/`\textstyle`/`\scriptstyle`/`\scriptscriptstyle`,
      // and `fontsizev3` `\tiny`..`\Huge` switches which apply to the REST of
      // the current group!
      if (token.kind == TexTokenKind.controlSequence) {
        final String cs = token.text;
        if (cs == 'color' &&
            activePackages.has('color') &&
            !activePackages.usesColorV2) {
          final String? model = readOptionalBracketText('color');
          final String colorArg = readArgumentText('color');
          final String resolved = resolveTexColor(
            colorArg,
            model: model ?? '',
            customColors: macroTable.visibleColors(),
            span: token.span,
          );
          final _SeqResult rest;
          enterNesting(token.span);
          try {
            rest = _parseSequence(
              stopMode: stopMode,
              activeEnvName: activeEnvName,
              allowAlignTab: allowAlignTab,
            );
          } finally {
            exitNesting();
          }
          appendNode(
            ColorNode(
              span: _mergeSpanList(token.span, rest.nodes),
              role: TexMathColorRole.custom,
              colorValue: resolved,
              children: _unmodifiableNodes(rest.nodes),
            ),
          );
          return finish(rest.stopReason, rest);
        }

        final TexMathStyle? styleSwitch = _styleSwitchForCommand(cs);
        if (styleSwitch != null) {
          final _SeqResult rest;
          enterNesting(token.span);
          try {
            rest = _parseSequence(
              stopMode: stopMode,
              activeEnvName: activeEnvName,
              allowAlignTab: allowAlignTab,
            );
          } finally {
            exitNesting();
          }
          appendNode(
            StyleNode(
              span: _mergeSpanList(token.span, rest.nodes),
              style: styleSwitch,
              children: _unmodifiableNodes(rest.nodes),
            ),
          );
          return finish(rest.stopReason, rest);
        }

        final double? fontSizeScale = fontSizeCommands[cs];
        if (fontSizeScale != null) {
          final _SeqResult rest;
          enterNesting(token.span);
          try {
            rest = _parseSequence(
              stopMode: stopMode,
              activeEnvName: activeEnvName,
              allowAlignTab: allowAlignTab,
            );
          } finally {
            exitNesting();
          }
          appendNode(
            StyleNode(
              span: _mergeSpanList(token.span, rest.nodes),
              style: options.displayMode == TexMathDisplayMode.display
                  ? TexMathStyle.display
                  : TexMathStyle.text,
              scaleEm: fontSizeScale,
              children: _unmodifiableNodes(rest.nodes),
            ),
          );
          return finish(rest.stopReason, rest);
        }

        final TexMathFontVariant? legacyFont = _legacyFontSwitchForCommand(cs);
        if (legacyFont != null) {
          final TexMathFontVariant? prevVariant = _fontVariant;
          final TexMathFontVariant effectiveLegacy = _inBoldSymbol
              ? boldSymbolVariantFor(legacyFont, null)
              : legacyFont;
          _fontVariant = effectiveLegacy;
          enterNesting(token.span);
          try {
            final _SeqResult rest = _parseSequence(
              stopMode: stopMode,
              activeEnvName: activeEnvName,
              allowAlignTab: allowAlignTab,
            );
            appendNode(
              MathGroupNode(
                span: _mergeSpanList(token.span, rest.nodes),
                isExplicitGroup: false,
                fontVariant: effectiveLegacy,
                children: _unmodifiableNodes(rest.nodes),
              ),
            );
            return finish(rest.stopReason, rest);
          } finally {
            exitNesting();
            _fontVariant = prevVariant;
          }
        }

        if ((cs == 'cellcolor' || cs == 'rowcolor' || cs == 'columncolor') &&
            activePackages.has('colortbl')) {
          if (stopMode != _StopMode.envCell) {
            throw TexMathSyntaxError(
              'Unsupported use of \\$cs outside a table cell.',
              span: token.span,
            );
          }
          if (cs == 'rowcolor' && nodes.isNotEmpty) {
            throw TexMathSyntaxError(
              '\\rowcolor must appear at the start of a row.',
              span: token.span,
            );
          }
          final String? model = readOptionalBracketText(cs);
          final String colorArg = readArgumentText(cs);
          if (cs == 'columncolor') {
            readOptionalBracketText(cs);
            readOptionalBracketText(cs);
          }
          final String resolved = resolveTexColor(
            colorArg,
            model: model ?? '',
            customColors: macroTable.visibleColors(),
            span: token.span,
          );
          if (cs == 'cellcolor') {
            cellBackground = resolved;
          } else if (cs == 'rowcolor') {
            rowBackground = resolved;
          } else {
            columnBackground = resolved;
          }
          continue;
        }

        // Tag / label commands within environment rows or expressions.
        if ((cs == 'notag' || cs == 'nonumber') &&
            (activePackages.has('ams') || cs == 'nonumber')) {
          rowHasNoTag = true;
          continue;
        }
        if (cs == 'tag' && activePackages.has('ams')) {
          final bool starred = consumeOptionalStar();
          final String tagText = readArgumentText('tag');
          rowTag = TagNode(
            span: token.span,
            label: tagText,
            isStarred: starred,
          );
          if (rowLabel != null) {
            _labels[rowLabel] = tagText;
          }
          continue;
        }
        if (cs == 'label') {
          final String labelName = readArgumentText('label').trim();
          rowLabel = labelName;
          if (rowTag != null) {
            _labels[labelName] = rowTag.label;
          }
          appendNode(
            TagNode(
              span: token.span,
              label: labelName,
              isLabelDefinition: true,
            ),
          );
          continue;
        }
      }

      final MathNode? parsedAtom = _parseAtom(token);
      if (parsedAtom != null) {
        appendNode(attachScripts(parsedAtom));
      }
    }

    return finish(null);
  }

  _SeqResult _buildSeqResult({
    required List<MathNode> nodes,
    required int? infixSplitIndex,
    required String? infixLeftDelim,
    required String? infixRightDelim,
    required double? infixThicknessEm,
    required SourceSpan? infixSpan,
    required String? stopReason,
    required bool rowHasNoTag,
    required TagNode? rowTag,
    String? rowLabel,
    String? cellBackground,
    String? rowBackground,
    String? columnBackground,
  }) {
    if (infixSplitIndex == null) {
      return _SeqResult(
        nodes: nodes,
        stopReason: stopReason,
        rowHasNoTag: rowHasNoTag,
        rowTag: rowTag,
        rowLabel: rowLabel,
        cellBackground: cellBackground,
        rowBackground: rowBackground,
        columnBackground: columnBackground,
      );
    }
    final List<MathNode> numNodes = nodes.sublist(0, infixSplitIndex);
    final List<MathNode> denNodes = nodes.sublist(infixSplitIndex);
    final MathNode num = numNodes.length == 1
        ? numNodes.first
        : MathGroupNode(
            span: _mergeSpanList(infixSpan!, numNodes),
            isExplicitGroup: false,
            children: numNodes,
          );
    final MathNode den = denNodes.length == 1
        ? denNodes.first
        : MathGroupNode(
            span: _mergeSpanList(infixSpan!, denNodes),
            isExplicitGroup: false,
            children: denNodes,
          );
    return _SeqResult(
      nodes: <MathNode>[
        FractionNode(
          span: num.span.merge(den.span).merge(infixSpan!),
          numerator: num,
          denominator: den,
          ruleThicknessEm: infixThicknessEm,
          leftDelimiter: infixLeftDelim,
          rightDelimiter: infixRightDelim,
        ),
      ],
      stopReason: stopReason,
      rowHasNoTag: rowHasNoTag,
      rowTag: rowTag,
      rowLabel: rowLabel,
      cellBackground: cellBackground,
      rowBackground: rowBackground,
      columnBackground: columnBackground,
    );
  }

  MathNode? _parseAtom(TexToken token) {
    switch (token.kind) {
      case TexTokenKind.space:
      case TexTokenKind.comment:
        return null;

      case TexTokenKind.beginGroup:
        return _parseBraceGroup(token);

      case TexTokenKind.endGroup:
        throw TexMathSyntaxError(
          'Extra closing brace "}".',
          errorClass: TexMathErrorClass.extraBrace,
          span: token.span,
        );

      case TexTokenKind.parameter:
        throw TexMathSyntaxError(
          'Macro parameter character "#" cannot appear in math mode.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: token.span,
        );

      case TexTokenKind.alignmentTab:
        throw TexMathSyntaxError(
          'Misplaced alignment tab character &.',
          errorClass: TexMathErrorClass.misplacedAlignmentTab,
          span: token.span,
        );

      case TexTokenKind.active:
        return SpaceNode(span: token.span, widthEm: 0.25, command: '~');

      case TexTokenKind.mathShift:
        throw TexMathSyntaxError(
          'Unexpected math shift "\$" inside math mode.',
          span: token.span,
        );

      case TexTokenKind.superscript:
      case TexTokenKind.subscript:
        return _attachSingleScript(
          MathGroupNode(
            span: SourceSpan.empty(token.span.start),
            children: const <MathNode>[],
            isExplicitGroup: false,
          ),
          token,
        );

      case TexTokenKind.letter:
        return SymbolNode(
          span: token.span,
          value: token.text,
          atomClass: TexMathAtomClass.ord,
          fontVariant: _resolveSymbolVariant(
            _fontVariant ?? TexMathFontVariant.italic,
            token.text,
          ),
        );

      case TexTokenKind.other:
        return _parseOtherChar(token);

      case TexTokenKind.controlSequence:
        return _parseControlSequence(token);
    }
  }

  MathNode _parseBraceGroup(TexToken openToken) {
    enterNesting(openToken.span);
    macroTable.pushBraceScope();
    final TexMathFontVariant? savedFont = _fontVariant;
    final bool savedBoldSymbol = _inBoldSymbol;
    try {
      final _SeqResult inner = _parseSequence(stopMode: _StopMode.closeBrace);
      final SourceSpan span = _mergeSpanList(openToken.span, inner.nodes);
      return MathGroupNode(
        span: span,
        children: inner.nodes,
        isExplicitGroup: true,
      );
    } finally {
      _fontVariant = savedFont;
      _inBoldSymbol = savedBoldSymbol;
      macroTable.popBraceScope();
      exitNesting();
    }
  }

  MathNode? _parseOtherChar(TexToken token) {
    final String ch = token.text;
    if (ch == '<' && activePackages.has('texhtml')) {
      final MathNode? texHtml = _tryParseTexHtml(token);
      if (texHtml != null) {
        return texHtml;
      }
    }
    if (activePackages.texDigits && _isDigitString(ch)) {
      final String? grouped = _tryReadGroupedNumber(token);
      if (grouped != null) {
        return SymbolNode(
          span: token.span,
          value: grouped,
          atomClass: TexMathAtomClass.ord,
          fontVariant: _resolveSymbolVariant(_fontVariant, grouped),
        );
      }
    }
    final TexMathAtomClass atomClass = switch (ch) {
      '+' || '-' || '*' => TexMathAtomClass.bin,
      '=' || '<' || '>' => TexMathAtomClass.rel,
      '(' || '[' => TexMathAtomClass.open,
      ')' || ']' => TexMathAtomClass.close,
      ',' || ';' || ':' => TexMathAtomClass.punct,
      _ => TexMathAtomClass.ord,
    };
    final TexMathFontVariant? variant = _isDigitString(ch)
        ? (_fontVariant ?? TexMathFontVariant.normal)
        : _fontVariant;
    return SymbolNode(
      span: token.span,
      value: ch,
      atomClass: atomClass,
      fontVariant: _resolveSymbolVariant(variant, ch),
    );
  }

  String? _tryReadGroupedNumber(TexToken firstDigit) {
    final StringBuffer digits = StringBuffer(firstDigit.text);
    while (true) {
      final TexToken? next = cursor.peek(skipSpaces: false);
      if (next == null) {
        break;
      }
      if (next.kind == TexTokenKind.other && _isDigitString(next.text)) {
        cursor.nextRaw();
        digits.write(next.text);
        continue;
      }
      if (next.kind == TexTokenKind.other && next.text == ',') {
        // Peek ahead in cursor to see if 3 digits follow.
        cursor.nextRaw();
        final List<TexToken> followingDigits = <TexToken>[];
        for (int k = 0; k < 3; k++) {
          final TexToken? d = cursor.peek(skipSpaces: false);
          if (d != null &&
              d.kind == TexTokenKind.other &&
              _isDigitString(d.text)) {
            followingDigits.add(cursor.nextRaw()!);
          } else {
            break;
          }
        }
        if (followingDigits.length == 3) {
          digits.write(',');
          for (final TexToken d in followingDigits) {
            digits.write(d.text);
          }
          continue;
        }
        cursor.pushTokens(<TexToken>[next, ...followingDigits]);
        break;
      }
      break;
    }
    final String result = digits.toString();
    return result.contains(',') ? result : null;
  }

  MathNode? _tryParseTexHtml(TexToken openToken) {
    final int start = openToken.span.start;
    if (start >= source.length || !source.startsWith('<tex-html>', start)) {
      return null;
    }
    const String closeTag = '</tex-html>';
    final int closeIdx = source.indexOf(closeTag, start + '<tex-html>'.length);
    if (closeIdx < 0) {
      throw TexMathSyntaxError(
        'Missing closing </tex-html> tag.',
        errorClass: TexMathErrorClass.missingArgument,
        span: openToken.span,
      );
    }
    final String rawHtml = source
        .substring(start + '<tex-html>'.length, closeIdx)
        .trim();
    final int endOffset = closeIdx + closeTag.length;
    cursor.discardRawUntilOffset(endOffset);
    final SourceSpan htmlSpan = SourceSpan(start, endOffset);
    return MathGroupNode(
      span: htmlSpan,
      isExplicitGroup: false,
      role: 'texhtml',
      attributes: <String, String>{'html': rawHtml},
      children: _parseTexHtmlRuns(rawHtml, htmlSpan),
    );
  }

  List<MathNode> _parseTexHtmlRuns(String rawHtml, SourceSpan htmlSpan) {
    final List<({String tag, String style})> styleStack =
        <({String tag, String style})>[];
    final List<MathNode> runs = <MathNode>[];
    final StringBuffer buffer = StringBuffer();

    String currentStyle() =>
        styleStack.isEmpty ? 'text' : styleStack.last.style;

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        runs.add(
          TextNode(
            span: htmlSpan,
            text: buffer.toString(),
            styleCommand: currentStyle(),
          ),
        );
        buffer.clear();
      }
    }

    int cursorPos = 0;
    for (final RegExpMatch match in _htmlTagPattern.allMatches(rawHtml)) {
      if (match.start > cursorPos) {
        buffer.write(rawHtml.substring(cursorPos, match.start));
      }
      cursorPos = match.end;
      final String? parsedTag = _parseHtmlTagName(match.group(0)!);
      if (parsedTag == null) {
        continue;
      }
      if (parsedTag.startsWith('/')) {
        final String closeName = parsedTag.substring(1);
        for (int i = styleStack.length - 1; i >= 0; i--) {
          if (styleStack[i].tag == closeName) {
            final String prevStyle = currentStyle();
            final String nextStyle = styleStack.length == 1
                ? 'text'
                : (i == styleStack.length - 1
                      ? styleStack[i - 1].style
                      : prevStyle);
            if (nextStyle != prevStyle) {
              flushBuffer();
            }
            styleStack.removeAt(i);
            break;
          }
        }
        continue;
      }
      final String? mappedStyle = _texHtmlTagStyle(parsedTag);
      if (mappedStyle == null) {
        continue;
      }
      if (mappedStyle != currentStyle()) {
        flushBuffer();
      }
      styleStack.add((tag: parsedTag, style: mappedStyle));
    }
    if (cursorPos < rawHtml.length) {
      buffer.write(rawHtml.substring(cursorPos));
    }
    flushBuffer();

    if (runs.isEmpty) {
      return <MathNode>[
        TextNode(span: htmlSpan, text: '', styleCommand: 'text'),
      ];
    }
    return _unmodifiableNodes(runs);
  }

  MathNode? _parseControlSequence(TexToken token) {
    final String cs = token.text;
    if (cs.isEmpty) {
      throw TexMathSyntaxError(
        'Trailing backslash at end of input.',
        errorClass: TexMathErrorClass.undefinedControlSequence,
        span: token.span,
      );
    }

    // 1. Check user-defined macros, \let aliases, declared operators, paired
    //    delimiters, and custom extensible arrows in scoped macro table.
    final TexMacroEntry? macroEntry = macroTable.lookupMacro(cs);
    if (macroEntry != null) {
      return _invokeMacroEntry(macroEntry, token);
    }

    // 2. Check package-specific commands and core syntax primitives.
    return _parseBuiltinCommand(cs, token.span);
  }

  MathNode? _invokeMacroEntry(TexMacroEntry entry, TexToken callToken) {
    switch (entry) {
      case TexUserMacroEntry():
        final List<List<TexToken>> args = _readMacroArguments(entry, callToken);
        final List<TexToken> substituted = substituteMacroParams(
          body: entry.body,
          args: args,
          fallbackSpan: callToken.span,
          budgets: options.budgets,
          budgetState: cursor.budgetState,
        );
        cursor.pushMacroExpansion(
          substituted,
          span: callToken.span,
          chargeTokens: false,
        );
        return null;

      case TexAliasEntry(
        :final String? targetCommand,
        :final TexToken? literalToken,
      ):
        if (targetCommand != null) {
          return _parseBuiltinCommand(targetCommand, callToken.span);
        }
        if (literalToken != null) {
          return _parseAtom(
            TexToken(
              kind: literalToken.kind,
              text: literalToken.text,
              span: callToken.span,
              catCode: literalToken.catCode,
              isControlWord: literalToken.isControlWord,
            ),
          );
        }
        return null;

      case TexDeclaredOperatorEntry(
        :final List<TexToken> body,
        :final bool hasLimits,
      ):
        final MathNode bodyNode = parseSubTokens(body, span: callToken.span);
        final String opText = _extractOperatorText(bodyNode);
        return OperatorNode(
          span: callToken.span,
          operatorName: opText,
          hasLimits: hasLimits,
          command: entry.name,
          isDeclared: true,
        );

      case TexPairedDelimiterEntry(
        :final String leftDelimiter,
        :final String rightDelimiter,
      ):
        final bool star = consumeOptionalStar();
        final String? sizeCmd = readOptionalBracketText(entry.name);
        final List<TexToken> arg = readArgumentTokens(entry.name);
        final MathNode inner = parseSubTokens(arg, span: callToken.span);
        double? fixedSizeEm;
        if (sizeCmd != null && sizeCmd.trim().isNotEmpty) {
          fixedSizeEm = sizeForBigCommand(
            sizeCmd.trim().replaceFirst('\\', ''),
          );
        } else if (!star) {
          fixedSizeEm = 0.0;
        }
        return DelimiterNode(
          span: callToken.span,
          leftDelimiter: leftDelimiter,
          rightDelimiter: rightDelimiter,
          fixedSizeEm: fixedSizeEm,
          children: <MathNode>[inner],
        );

      case TexExtArrowEntry(:final int codePoint):
        return _parseExtArrowWithCodePoint(
          entry.name,
          codePoint,
          callToken.span,
        );
    }
  }

  List<List<TexToken>> _readMacroArguments(
    TexUserMacroEntry entry,
    TexToken callToken,
  ) {
    if (entry.preDelimiter.isNotEmpty &&
        !_consumeExpectedTokenList(entry.preDelimiter)) {
      throw TexMathMacroError(
        'Use of \\${entry.name} does not match its definition.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: callToken.span,
      );
    }
    if (entry.paramCount == 0) {
      return const <List<TexToken>>[];
    }
    final List<List<TexToken>> args = <List<TexToken>>[];
    int startIndex = 0;
    if (entry.defaultArg != null) {
      final List<TexToken>? opt = readOptionalBracketTokens(entry.name);
      args.add(opt ?? entry.defaultArg!);
      startIndex = 1;
    }
    for (int i = startIndex; i < entry.paramCount; i++) {
      final List<TexToken>? delim = i < entry.paramDelimiters.length
          ? entry.paramDelimiters[i]
          : null;
      if (delim != null && delim.isNotEmpty) {
        args.add(
          _readDelimitedArgumentTokens(entry.name, delim, callToken.span),
        );
      } else {
        args.add(readArgumentTokens(entry.name));
      }
    }
    return args;
  }

  bool _consumeExpectedTokenList(List<TexToken> expected) {
    final List<TexToken> matched = <TexToken>[];
    for (final TexToken exp in expected) {
      if (exp.kind == TexTokenKind.space) {
        continue;
      }
      final TexToken? next = cursor.peek();
      if (next == null || next.kind != exp.kind || next.text != exp.text) {
        cursor.pushTokens(matched);
        return false;
      }
      matched.add(cursor.next()!);
    }
    return true;
  }

  List<TexToken> _readDelimitedArgumentTokens(
    String macroName,
    List<TexToken> delimiter,
    SourceSpan callSpan,
  ) {
    final List<TexToken> collected = <TexToken>[];
    int braceDepth = 0;
    while (true) {
      if (braceDepth == 0 && _matchesDelimiterAhead(delimiter)) {
        _consumeDelimiterAhead(delimiter);
        if (collected.length >= 2 &&
            collected.first.kind == TexTokenKind.beginGroup &&
            collected.last.kind == TexTokenKind.endGroup &&
            _isSingleOuterBracePair(collected)) {
          return collected.sublist(1, collected.length - 1);
        }
        return collected;
      }
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathMacroError(
          'Runaway delimited argument for \\$macroName.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: callSpan,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        braceDepth++;
      } else if (tok.kind == TexTokenKind.endGroup && braceDepth > 0) {
        braceDepth--;
      }
      collected.add(tok);
    }
  }

  bool _matchesDelimiterAhead(List<TexToken> delimiter) =>
      cursor.matchesDelimiterAhead(delimiter);

  void _consumeDelimiterAhead(List<TexToken> delimiter) =>
      cursor.consumeDelimiterAhead(delimiter);

  MathNode? _parseBuiltinCommand(String cs, SourceSpan span) {
    // Package activation / autoload check if unknown below.
    switch (cs) {
      case 'relax':
      case 'ignorespaces':
        return null;

      // Require
      case 'require':
        if (!activePackages.has('require')) {
          break;
        }
        String? optsArg;
        if (activePackages.has('setoptions')) {
          optsArg = readOptionalBracketText('require');
        }
        final String pkg = readArgumentText('require');
        activePackages.require(pkg, span: span);
        if (optsArg != null && optsArg.isNotEmpty) {
          activePackages.setOptions(pkg, _parseKeyValues(optsArg), span: span);
        }
        return null;

      // SetOptions
      case 'setOptions':
        if (!activePackages.has('setoptions')) {
          break;
        }
        final String pkg = readOptionalBracketText('setOptions') ?? 'tex';
        final String optsRaw = readArgumentText('setOptions');
        activePackages.setOptions(pkg, _parseKeyValues(optsRaw), span: span);
        return null;

      // Begingroup
      case 'begingroup':
        if (!activePackages.has('begingroup')) {
          break;
        }
        macroTable.pushBegingroup();
        return null;
      case 'endgroup':
        if (!activePackages.has('begingroup')) {
          break;
        }
        if (!macroTable.popBegingroup()) {
          throw TexMathSyntaxError(
            'Extra \\endgroup without matching \\begingroup.',
            errorClass: TexMathErrorClass.mismatchedEnvironment,
            span: span,
          );
        }
        return null;
      case 'begingroupSandbox':
        if (!activePackages.has('begingroup')) {
          break;
        }
        macroTable.pushSandbox();
        return null;
      case 'begingroupReset':
        if (!activePackages.has('begingroup')) {
          break;
        }
        if (!macroTable.resetSandbox()) {
          throw TexMathSyntaxError(
            'Extra \\begingroupReset without matching \\begingroupSandbox.',
            errorClass: TexMathErrorClass.mismatchedEnvironment,
            span: span,
          );
        }
        return null;
      case 'global':
        if (!activePackages.has('begingroup')) {
          break;
        }
        final TexToken? next = cursor.next();
        if (next == null || next.kind != TexTokenKind.controlSequence) {
          throw TexMathMacroError(
            '\\global must be followed by a definition command.',
            errorClass: TexMathErrorClass.invalidMacroDefinition,
            span: next?.span ?? span,
          );
        }
        if (next.text == 'def' ||
            next.text == 'edef' ||
            next.text == 'gdef' ||
            next.text == 'xdef') {
          _parseDefCommand(
            next.text,
            next.span,
            forceGlobal: true,
            expandBody: next.text == 'edef' || next.text == 'xdef',
          );
          return null;
        }
        if (next.text == 'let') {
          _parseLetCommand(next.span, forceGlobal: true);
          return null;
        }
        if (next.text == 'newcommand' || next.text == 'renewcommand') {
          _parseNewCommand(next.text, next.span, forceGlobal: true);
          return null;
        }
        throw TexMathMacroError(
          '\\global cannot precede \\${next.text}.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: next.span,
        );

      // Macro definition commands (`newcommand` / `begingroup`)
      case 'newcommand':
      case 'renewcommand':
      case 'providecommand':
        if (!activePackages.has('newcommand') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        _parseNewCommand(cs, span, forceGlobal: false);
        return null;

      case 'def':
      case 'gdef':
      case 'edef':
      case 'xdef':
        if (!activePackages.has('newcommand') &&
            !activePackages.has('begingroup') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        _parseDefCommand(
          cs,
          span,
          forceGlobal: cs == 'gdef' || cs == 'xdef',
          expandBody: cs == 'edef' || cs == 'xdef',
        );
        return null;

      case 'let':
        if (!activePackages.has('newcommand') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        _parseLetCommand(span, forceGlobal: false);
        return null;

      case 'newenvironment':
      case 'renewenvironment':
        if (!activePackages.has('newcommand') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        _parseNewEnvironment(cs, span);
        return null;

      // AMS declarations
      case 'DeclareMathOperator':
        if (!activePackages.has('ams')) {
          break;
        }
        _parseDeclareMathOperator(span);
        return null;

      // Mathtools declarations
      case 'DeclarePairedDelimiter':
      case 'DeclarePairedDelimiterX':
      case 'DeclarePairedDelimiterXPP':
        if (!activePackages.has('mathtools')) {
          break;
        }
        _parseDeclarePairedDelimiter(cs, span);
        return null;
      case 'mathtoolsset':
      case 'newtagform':
      case 'renewtagform':
      case 'usetagform':
        if (!activePackages.has('mathtools')) {
          break;
        }
        if (cs == 'newtagform' || cs == 'renewtagform') {
          readArgumentText(cs);
          readOptionalBracketText(cs);
          readArgumentText(cs);
          readArgumentText(cs);
        } else {
          readArgumentText(cs);
        }
        return null;

      // Extpfeil declaration
      case 'Newextarrow':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        _parseNewExtArrow(span);
        return null;

      // Fractions & Binomials
      case 'frac':
      case 'dfrac':
      case 'tfrac':
      case 'cfrac':
        if (cs != 'frac' && !activePackages.has('ams')) {
          break;
        }
        if (cs == 'cfrac') {
          readOptionalBracketText('cfrac');
        }
        final MathNode num = _parseRequiredArgNode(cs);
        final MathNode den = _parseRequiredArgNode(cs);
        final TexMathStyle? styleOverride = switch (cs) {
          'dfrac' || 'cfrac' => TexMathStyle.display,
          'tfrac' => TexMathStyle.text,
          _ => null,
        };
        return FractionNode(
          span: num.span.merge(den.span).merge(span),
          numerator: num,
          denominator: den,
          styleOverride: styleOverride,
        );

      case 'binom':
      case 'dbinom':
      case 'tbinom':
        if (!activePackages.has('ams')) {
          break;
        }
        final MathNode num = _parseRequiredArgNode(cs);
        final MathNode den = _parseRequiredArgNode(cs);
        final TexMathStyle? styleOverride = switch (cs) {
          'dbinom' => TexMathStyle.display,
          'tbinom' => TexMathStyle.text,
          _ => null,
        };
        return FractionNode(
          span: num.span.merge(den.span).merge(span),
          numerator: num,
          denominator: den,
          ruleThicknessEm: 0.0,
          leftDelimiter: '(',
          rightDelimiter: ')',
          styleOverride: styleOverride,
        );

      case 'genfrac':
        if (!activePackages.has('ams')) {
          break;
        }
        final String leftRaw = readArgumentText(cs).trim();
        final String rightRaw = readArgumentText(cs).trim();
        final String thickRaw = readArgumentText(cs).trim();
        final String styleRaw = readArgumentText(cs).trim();
        final MathNode num = _parseRequiredArgNode(cs);
        final MathNode den = _parseRequiredArgNode(cs);
        final double? thickness = thickRaw.isEmpty
            ? null
            : parseTexDimensionToEm(thickRaw);
        final TexMathStyle? style = switch (styleRaw) {
          '0' => TexMathStyle.display,
          '1' => TexMathStyle.text,
          '2' => TexMathStyle.script,
          '3' => TexMathStyle.scriptScript,
          _ => null,
        };
        return FractionNode(
          span: span.merge(den.span),
          numerator: num,
          denominator: den,
          ruleThicknessEm: thickness,
          leftDelimiter: leftRaw.isEmpty ? null : leftRaw,
          rightDelimiter: rightRaw.isEmpty ? null : rightRaw,
          styleOverride: style,
        );

      // Roots
      case 'sqrt':
        final List<TexToken>? indexTokens = readOptionalBracketTokens('sqrt');
        final MathNode? index = indexTokens == null
            ? null
            : parseSubTokens(indexTokens, span: span);
        final MathNode radicand = _parseRequiredArgNode('sqrt');
        return RadicalNode(
          span: span.merge(radicand.span),
          radicand: radicand,
          index: index,
        );
      case 'root':
        final List<TexToken> degTokens = _readTokensUntilCommand('of', span);
        final MathNode radicand = _parseRequiredArgNode('root');
        return RadicalNode(
          span: span.merge(radicand.span),
          radicand: radicand,
          index: parseSubTokens(degTokens, span: span),
        );
      case 'uproot':
      case 'leftroot':
        readArgumentText(cs);
        return null;

      // Overset / Underset / Stackrel / Overunderset
      case 'overset':
      case 'stackrel':
      case 'stackbin':
        final MathNode top = _parseRequiredArgNode(cs);
        final MathNode base = _parseRequiredArgNode(cs);
        return ScriptNode(
          span: span.merge(base.span),
          base: base,
          superscript: top,
          limitsAboveBelow: true,
        );
      case 'underset':
        final MathNode bot = _parseRequiredArgNode(cs);
        final MathNode base = _parseRequiredArgNode(cs);
        return ScriptNode(
          span: span.merge(base.span),
          base: base,
          subscript: bot,
          limitsAboveBelow: true,
        );
      case 'overunderset':
        final MathNode top = _parseRequiredArgNode(cs);
        final MathNode bot = _parseRequiredArgNode(cs);
        final MathNode base = _parseRequiredArgNode(cs);
        return ScriptNode(
          span: span.merge(base.span),
          base: base,
          superscript: top,
          subscript: bot,
          limitsAboveBelow: true,
        );

      // Delimiters
      case 'left':
        return _parseLeftRightGroup(span);
      case 'right':
        throw TexMathSyntaxError(
          'Extra \\right delimiter without matching \\left.',
          errorClass: TexMathErrorClass.extraDelimiter,
          span: span,
        );
      case 'middle':
        throw TexMathSyntaxError(
          'Extra \\middle delimiter outside \\left...\\right.',
          errorClass: TexMathErrorClass.extraDelimiter,
          span: span,
        );
      case 'big':
      case 'Big':
      case 'bigg':
      case 'Bigg':
      case 'bigl':
      case 'Bigl':
      case 'biggl':
      case 'Biggl':
      case 'bigr':
      case 'Bigr':
      case 'biggr':
      case 'Biggr':
      case 'bigm':
      case 'Bigm':
      case 'biggm':
      case 'Biggm':
        final String delim = readDelimiterToken(cs, allowPeriod: false);
        final double sizeEm = sizeForBigCommand(cs)!;
        final bool isRight = cs.endsWith('r');
        return DelimiterNode(
          span: span,
          leftDelimiter: isRight ? null : delim,
          rightDelimiter: isRight ? delim : null,
          fixedSizeEm: sizeEm,
          children: const <MathNode>[],
        );

      // Environments
      case 'begin':
        return _parseBeginEnvironment(span);
      case 'end':
        final String endEnv = readArgumentText('end').trim();
        throw TexMathSyntaxError(
          'Extra \\end{$endEnv} without matching \\begin{$endEnv}.',
          errorClass: TexMathErrorClass.mismatchedEnvironment,
          span: span,
        );

      // Operators
      case 'operatorname':
        final bool star = consumeOptionalStar();
        final String opName = readArgumentText('operatorname');
        return OperatorNode(
          span: span,
          operatorName: opName,
          hasLimits: star,
          command: 'operatorname',
          isDeclared: true,
        );
      case 'pmod':
        final MathNode arg = _parseRequiredArgNode('pmod');
        return MathGroupNode(
          span: span.merge(arg.span),
          isExplicitGroup: false,
          role: 'pmod',
          children: <MathNode>[
            SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
            DelimiterNode(
              span: span.merge(arg.span),
              leftDelimiter: '(',
              rightDelimiter: ')',
              children: <MathNode>[
                OperatorNode(span: span, operatorName: 'mod'),
                SpaceNode(span: span, widthEm: 6.0 / 18.0, command: 'kern'),
                arg,
              ],
            ),
          ],
        );
      case 'pod':
        final MathNode arg = _parseRequiredArgNode('pod');
        return MathGroupNode(
          span: span.merge(arg.span),
          isExplicitGroup: false,
          role: 'pod',
          children: <MathNode>[
            SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
            DelimiterNode(
              span: span.merge(arg.span),
              leftDelimiter: '(',
              rightDelimiter: ')',
              children: <MathNode>[arg],
            ),
          ],
        );
      case 'bmod':
        return OperatorNode(span: span, operatorName: 'mod', command: 'bmod');
      case 'mod':
        final MathNode arg = _parseRequiredArgNode('mod');
        return MathGroupNode(
          span: span.merge(arg.span),
          isExplicitGroup: false,
          role: 'mod',
          children: <MathNode>[
            SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
            OperatorNode(span: span, operatorName: 'mod'),
            SpaceNode(span: span, widthEm: 6.0 / 18.0),
            arg,
          ],
        );

      // Negation
      case 'not':
        return _parseNotCommand(span);
      case 'centernot':
        if (!activePackages.has('centernot')) {
          break;
        }
        final MathNode arg = _parseRequiredArgNode('centernot');
        if (arg is SymbolNode) {
          return SymbolNode(
            span: span.merge(arg.span),
            value: notRemap[arg.value] ?? arg.value,
            command: arg.command,
            atomClass: arg.atomClass,
            fontVariant: arg.fontVariant,
            isNegated: !notRemap.containsKey(arg.value),
          );
        }
        return MathGroupNode(
          span: span.merge(arg.span),
          role: 'centernot',
          children: <MathNode>[arg],
        );

      // Atom class modifiers
      case 'mathord':
      case 'mathop':
      case 'mathbin':
      case 'mathrel':
      case 'mathopen':
      case 'mathclose':
      case 'mathpunct':
      case 'mathinner':
        final TexMathAtomClass atomClass = switch (cs) {
          'mathord' => TexMathAtomClass.ord,
          'mathop' => TexMathAtomClass.op,
          'mathbin' => TexMathAtomClass.bin,
          'mathrel' => TexMathAtomClass.rel,
          'mathopen' => TexMathAtomClass.open,
          'mathclose' => TexMathAtomClass.close,
          'mathpunct' => TexMathAtomClass.punct,
          _ => TexMathAtomClass.inner,
        };
        final MathNode inner = _parseRequiredArgNode(cs);
        if (inner is SymbolNode) {
          return SymbolNode(
            span: span.merge(inner.span),
            value: inner.value,
            command: inner.command,
            atomClass: atomClass,
            fontVariant: inner.fontVariant,
            isNegated: inner.isNegated,
            isStretchy: inner.isStretchy,
          );
        }
        return MathGroupNode(
          span: span.merge(inner.span),
          atomClass: atomClass,
          isExplicitGroup: false,
          children: <MathNode>[inner],
        );

      // Math font commands
      case 'mathrm':
      case 'mathup':
      case 'mathbf':
      case 'mathbfup':
      case 'mathit':
      case 'mathbfit':
      case 'mathbb':
      case 'Bbb':
      case 'mathfrak':
      case 'frak':
      case 'mathbffrak':
      case 'mathscr':
      case 'mathcal':
      case 'mathbfcal':
      case 'mathbfscr':
      case 'mathsf':
      case 'mathsfup':
      case 'mathbfsf':
      case 'mathbfsfup':
      case 'mathsfit':
      case 'mathbfsfit':
      case 'mathtt':
      case 'mathnormal':
        final TexMathFontVariant variant = _mathAlphabetVariant(cs);
        final List<TexToken> tokens = readArgumentTokens(cs);
        return parseSubTokens(tokens, span: span, fontVariant: variant);

      case 'boldsymbol':
        if (!activePackages.has('boldsymbol') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final List<TexToken> tokens = readArgumentTokens(cs);
        return parseSubTokens(tokens, span: span, inBoldSymbol: true);

      case 'pmb':
        final MathNode arg = _parseRequiredArgNode('pmb');
        return MathGroupNode(
          span: span.merge(arg.span),
          role: 'pmb',
          children: _unmodifiableNodes(<MathNode>[arg]),
        );

      case 'mathbbm':
      case 'mathbbmss':
      case 'mathbbmtt':
        if (!activePackages.has('bbm')) {
          break;
        }
        final TexMathFontVariant bbmVariant = switch (cs) {
          'mathbbmss' => TexMathFontVariant.doubleStruckSans,
          'mathbbmtt' => TexMathFontVariant.doubleStruckMonospace,
          _ =>
            activePackages.bbmBold
                ? TexMathFontVariant.doubleStruckBold
                : TexMathFontVariant.doubleStruck,
        };
        return parseSubTokens(
          readArgumentTokens(cs),
          span: span,
          fontVariant: bbmVariant,
        );
      case 'mathversion':
        if (!activePackages.has('bbm')) {
          break;
        }
        final String version = readArgumentText('mathversion').trim();
        activePackages.bbmBold = version == 'bold';
        return null;

      case 'mathds':
        if (!activePackages.has('dsfont')) {
          break;
        }
        return parseSubTokens(
          readArgumentTokens(cs),
          span: span,
          fontVariant: activePackages.dsfontSans
              ? TexMathFontVariant.doubleStruckSans
              : TexMathFontVariant.doubleStruck,
        );

      case 'mathbfbb':
        if (!activePackages.has('bboldx')) {
          break;
        }
        return parseSubTokens(
          readArgumentTokens(cs),
          span: span,
          fontVariant: TexMathFontVariant.doubleStruckBold,
        );

      // Text-mode containers
      case 'text':
      case 'textrm':
      case 'textbf':
      case 'textit':
      case 'textsf':
      case 'texttt':
      case 'textup':
      case 'textnormal':
      case 'mbox':
      case 'hbox':
        if (cs == 'text' &&
            !activePackages.has('ams') &&
            !activePackages.has('textmacros')) {
          break;
        }
        final List<TexToken> tokens = readArgumentTokens(cs);
        return parseTextTokens(tokens, span: span, styleCommand: cs);

      case 'intertext':
      case 'shortintertext':
        if (!activePackages.has('ams')) {
          break;
        }
        return parseTextTokens(
          readArgumentTokens(cs),
          span: span,
          styleCommand: 'text',
        );

      // Math accents
      case 'hat':
      case 'tilde':
      case 'bar':
      case 'vec':
      case 'dot':
      case 'ddot':
      case 'dddot':
      case 'ddddot':
      case 'check':
      case 'breve':
      case 'acute':
      case 'grave':
      case 'mathring':
      case 'widehat':
      case 'widetilde':
      case 'overline':
      case 'underline':
      case 'overbrace':
      case 'underbrace':
      case 'overparen':
      case 'underparen':
      case 'overbracket':
      case 'underbracket':
      case 'overrightarrow':
      case 'underrightarrow':
      case 'overleftarrow':
      case 'underleftarrow':
      case 'overleftrightarrow':
      case 'underleftrightarrow':
        final ({String unicode, bool isWide, bool isUnder}) info =
            mathAccentCommands[cs]!;
        final MathNode base = _parseRequiredArgNode(cs);
        return AccentNode(
          span: span.merge(base.span),
          base: base,
          accent: info.unicode,
          isWide: info.isWide,
          isUnder: info.isUnder,
        );

      // Spacing, phantom, smash, lap
      case 'kern':
      case 'mkern':
      case 'hskip':
      case 'mskip':
      case 'hspace':
        final bool star = cs == 'hspace' ? consumeOptionalStar() : false;
        final String dim = cs == 'hspace'
            ? readArgumentText(cs)
            : _readUnbracedDimen(cs);
        return SpaceNode(
          span: span,
          widthEm: parseTexDimensionToEm(dim),
          command: star ? '$cs*' : cs,
        );

      case 'phantom':
      case 'vphantom':
      case 'hphantom':
      case 'smash':
      case 'rlap':
      case 'llap':
      case 'clap':
      case 'mathrlap':
      case 'mathllap':
      case 'mathclap':
      case 'cramped':
      case 'crampedrlap':
      case 'crampedllap':
      case 'crampedclap':
        String? smashOpt;
        if (cs == 'smash') {
          smashOpt = readOptionalBracketText('smash');
        }
        final MathNode inner = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(inner.span),
          isExplicitGroup: false,
          role: smashOpt != null ? 'smash_$smashOpt' : cs,
          children: <MathNode>[inner],
        );

      case 'boxed':
      case 'fbox':
        final MathNode inner = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(inner.span),
          isExplicitGroup: false,
          role: 'boxed',
          children: <MathNode>[inner],
        );

      case 'mathchoice':
        final MathNode d = _parseRequiredArgNode(cs);
        final MathNode t = _parseRequiredArgNode(cs);
        final MathNode s = _parseRequiredArgNode(cs);
        final MathNode ss = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(ss.span),
          isExplicitGroup: false,
          role: 'mathchoice',
          children: <MathNode>[d, t, s, ss],
        );

      // AMS / Mathtools / Extpfeil extensible arrows
      case 'xrightarrow':
        return _parseExtArrowWithCodePoint(cs, 0x2192, span);
      case 'xleftarrow':
        return _parseExtArrowWithCodePoint(cs, 0x2190, span);
      case 'xleftrightarrow':
        return _parseExtArrowWithCodePoint(cs, 0x2194, span);
      case 'xLeftarrow':
        return _parseExtArrowWithCodePoint(cs, 0x21D0, span);
      case 'xRightarrow':
        return _parseExtArrowWithCodePoint(cs, 0x21D2, span);
      case 'xLeftrightarrow':
        return _parseExtArrowWithCodePoint(cs, 0x21D4, span);
      case 'xhookleftarrow':
        return _parseExtArrowWithCodePoint(cs, 0x21A9, span);
      case 'xhookrightarrow':
        return _parseExtArrowWithCodePoint(cs, 0x21AA, span);
      case 'xleftharpoonup':
        return _parseExtArrowWithCodePoint(cs, 0x21BC, span);
      case 'xleftharpoondown':
        return _parseExtArrowWithCodePoint(cs, 0x21BD, span);
      case 'xrightharpoonup':
        return _parseExtArrowWithCodePoint(cs, 0x21C0, span);
      case 'xrightharpoondown':
        return _parseExtArrowWithCodePoint(cs, 0x21C1, span);
      case 'xrightleftharpoons':
        return _parseExtArrowWithCodePoint(cs, 0x21CC, span);
      case 'xleftrightharpoons':
        return _parseExtArrowWithCodePoint(cs, 0x21CB, span);
      case 'xtwoheadrightarrow':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseExtArrowWithCodePoint(cs, 0x21A0, span);
      case 'xtwoheadleftarrow':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseExtArrowWithCodePoint(cs, 0x219E, span);
      case 'xmapsto':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseExtArrowWithCodePoint(cs, 0x21A6, span);
      case 'xlongequal':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseExtArrowWithCodePoint(cs, 0x003D, span);
      case 'xtofrom':
        if (!activePackages.has('extpfeil') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseExtArrowWithCodePoint(cs, 0x21C4, span);

      case 'sideset':
        if (!activePackages.has('ams')) {
          break;
        }
        final List<TexToken> leftSide = readArgumentTokens('sideset');
        final List<TexToken> rightSide = readArgumentTokens('sideset');
        final MathNode op = _parseRequiredArgNode('sideset');
        return MathGroupNode(
          span: span.merge(op.span),
          isExplicitGroup: false,
          role: 'sideset',
          children: <MathNode>[
            parseSubTokens(leftSide, span: span),
            op,
            parseSubTokens(rightSide, span: span),
          ],
        );

      case 'substack':
        if (!activePackages.has('ams')) {
          break;
        }
        final List<TexToken> subTokens = readArgumentTokens('substack');
        final List<List<TexToken>> lines = _splitTokensOnNewline(subTokens);
        final List<List<MathNode>> rows = lines
            .map(
              (List<TexToken> line) => <MathNode>[
                parseSubTokens(line, span: span),
              ],
            )
            .toList();
        return MatrixNode(
          span: span,
          rows: rows,
          environment: 'subarray',
          columnAlignments: const <String>['c'],
        );

      case 'shoveleft':
      case 'shoveright':
        if (!activePackages.has('ams')) {
          break;
        }
        final String? rawShift = activePackages.has('mathtools')
            ? readOptionalBracketText(cs)
            : null;
        final double shiftEm = rawShift != null && rawShift.trim().isNotEmpty
            ? parseTexDimensionToEm(rawShift)
            : 0.0;
        final MathNode arg = _parseRequiredArgNode(cs);
        final List<MathNode> children;
        if (shiftEm != 0.0) {
          final SpaceNode spacer = SpaceNode(span: span, widthEm: shiftEm);
          children = cs == 'shoveleft'
              ? <MathNode>[spacer, arg]
              : <MathNode>[arg, spacer];
        } else {
          children = <MathNode>[arg];
        }
        return MathGroupNode(
          span: span.merge(arg.span),
          isExplicitGroup: false,
          role: cs,
          children: children,
        );

      case 'ref':
      case 'eqref':
        final String labelName = readArgumentText(cs).trim();
        final String resolvedTag = _labels[labelName] ?? '???';
        return TagNode(
          span: span,
          label: resolvedTag,
          targetId: labelName,
          isStarred: cs == 'ref',
          isReference: true,
        );

      // Color package & ColorV2
      case 'color':
        if (activePackages.usesColorV2) {
          final String colorArg = readArgumentText('color');
          final MathNode body = _parseRequiredArgNode('color');
          final String resolved = resolveTexColor(
            colorArg,
            customColors: macroTable.visibleColors(),
            span: span,
          );
          return ColorNode(
            span: span.merge(body.span),
            role: TexMathColorRole.custom,
            colorValue: resolved,
            children: <MathNode>[body],
          );
        }
        break;

      case 'textcolor':
        if (!activePackages.has('color') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String? model = readOptionalBracketText('textcolor');
        final String colorArg = readArgumentText('textcolor');
        final MathNode body = _parseRequiredArgNode('textcolor');
        return ColorNode(
          span: span.merge(body.span),
          role: TexMathColorRole.custom,
          colorValue: resolveTexColor(
            colorArg,
            model: model ?? '',
            customColors: macroTable.visibleColors(),
            span: span,
          ),
          children: <MathNode>[body],
        );

      case 'colorbox':
        if (!activePackages.has('color') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String? model = readOptionalBracketText('colorbox');
        final String colorArg = readArgumentText('colorbox');
        final MathNode body = _parseRequiredArgNode('colorbox');
        return ColorNode(
          span: span.merge(body.span),
          role: TexMathColorRole.custom,
          backgroundColor: resolveTexColor(
            colorArg,
            model: model ?? '',
            customColors: macroTable.visibleColors(),
            span: span,
          ),
          children: <MathNode>[body],
        );

      case 'fcolorbox':
        if (!activePackages.has('color') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String? fModel = readOptionalBracketText('fcolorbox');
        final String fArg = readArgumentText('fcolorbox');
        final String? cModel = readOptionalBracketText('fcolorbox');
        final String cArg = readArgumentText('fcolorbox');
        final MathNode body = _parseRequiredArgNode('fcolorbox');
        return ColorNode(
          span: span.merge(body.span),
          role: TexMathColorRole.custom,
          borderColor: resolveTexColor(
            fArg,
            model: fModel ?? '',
            customColors: macroTable.visibleColors(),
            span: span,
          ),
          backgroundColor: resolveTexColor(
            cArg,
            model: cModel ?? fModel ?? '',
            customColors: macroTable.visibleColors(),
            span: span,
          ),
          children: <MathNode>[body],
        );

      case 'definecolor':
        if (!activePackages.has('color') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String name = readArgumentText('definecolor').trim();
        final String model = readArgumentText('definecolor').trim();
        final String spec = readArgumentText('definecolor').trim();
        macroTable.defineColor(
          name,
          resolveTexColor(
            spec,
            model: model,
            customColors: macroTable.visibleColors(),
            span: span,
          ),
        );
        return null;

      // Bbox, Cancel, Enclose
      case 'bbox':
        if (!activePackages.has('bbox') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String? optsRaw = readOptionalBracketText('bbox');
        final MathNode body = _parseRequiredArgNode('bbox');
        final Map<String, String> attrs = <String, String>{};
        if (optsRaw != null && optsRaw.isNotEmpty) {
          for (final String part in optsRaw.split(',')) {
            final String p = part.trim();
            if (p.startsWith('border:')) {
              attrs['border'] = p.substring('border:'.length).trim();
            } else if (p.isNotEmpty && _isAsciiDigitUnit(p.codeUnitAt(0))) {
              attrs['padding'] = p;
            } else if (p.isNotEmpty) {
              attrs['background'] = resolveTexColor(
                p,
                customColors: macroTable.visibleColors(),
                span: span,
              );
            }
          }
        }
        return MathGroupNode(
          span: span.merge(body.span),
          role: 'bbox',
          attributes: attrs,
          children: <MathNode>[body],
        );

      case 'cancel':
      case 'bcancel':
      case 'xcancel':
        if (!activePackages.has('cancel') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final MathNode body = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(body.span),
          role: cs,
          children: <MathNode>[body],
        );
      case 'cancelto':
        if (!activePackages.has('cancel') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final MathNode target = _parseRequiredArgNode(cs);
        final MathNode body = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(body.span),
          role: 'cancelto',
          children: <MathNode>[body, target],
        );

      case 'enclose':
        if (!activePackages.has('enclose') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String notation = readArgumentText('enclose').trim();
        final String? attr = readOptionalBracketText('enclose');
        final MathNode body = _parseRequiredArgNode('enclose');
        return MathGroupNode(
          span: span.merge(body.span),
          role: 'enclose',
          attributes: <String, String>{
            'notation': notation,
            if (attr != null && attr.isNotEmpty) 'style': attr,
          },
          children: <MathNode>[body],
        );

      // Action
      case 'toggle':
        if (!activePackages.has('action') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final List<MathNode> choices = <MathNode>[];
        while (true) {
          final TexToken? next = cursor.peek();
          if (next == null) {
            throw TexMathSyntaxError(
              'Missing \\endtoggle.',
              errorClass: TexMathErrorClass.missingArgument,
              span: span,
            );
          }
          if (next.kind == TexTokenKind.controlSequence &&
              next.text == 'endtoggle') {
            cursor.next();
            break;
          }
          choices.add(_parseRequiredArgNode('toggle'));
        }
        return MathGroupNode(span: span, role: 'toggle', children: choices);
      case 'mathtip':
      case 'texttip':
        if (!activePackages.has('action') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final MathNode base = _parseRequiredArgNode(cs);
        final List<TexToken> tipTokens = readArgumentTokens(cs);
        final MathNode tip = cs == 'texttip'
            ? parseTextTokens(tipTokens, span: span, styleCommand: 'text')
            : parseSubTokens(tipTokens, span: span);
        return MathGroupNode(
          span: span.merge(base.span),
          role: cs,
          children: <MathNode>[base, tip],
        );

      // HTML attributes
      case 'href':
      case 'class':
      case 'cssId':
      case 'style':
      case 'data':
        if (!activePackages.has('html') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String attrVal = readArgumentText(cs);
        if (cs == 'href' && !isSafeHrefUri(attrVal)) {
          throw TexMathSyntaxError(
            'Unsafe or disallowed URI scheme in \\href.',
            span: span,
          );
        }
        final MathNode body = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(body.span),
          role: cs,
          attributes: Map<String, String>.unmodifiable(<String, String>{
            cs: attrVal,
          }),
          children: _unmodifiableNodes(<MathNode>[body]),
        );

      // Mathtools prescript & splitfrac
      case 'prescript':
        if (!activePackages.has('mathtools')) {
          break;
        }
        final List<TexToken> supTokens = readArgumentTokens('prescript');
        final List<TexToken> subTokens = readArgumentTokens('prescript');
        final MathNode base = _parseRequiredArgNode('prescript');
        final MathNode? preSup = supTokens.isEmpty
            ? null
            : parseSubTokens(supTokens, span: span);
        final MathNode? preSub = subTokens.isEmpty
            ? null
            : parseSubTokens(subTokens, span: span);
        return ScriptNode(
          span: span.merge(base.span),
          base: base,
          presubscript: preSub,
          presuperscript: preSup,
        );
      case 'splitfrac':
      case 'splitdfrac':
        if (!activePackages.has('mathtools')) {
          break;
        }
        final MathNode num = _parseRequiredArgNode(cs);
        final MathNode den = _parseRequiredArgNode(cs);
        return FractionNode(
          span: span.merge(den.span),
          numerator: num,
          denominator: den,
          ruleThicknessEm: 0.0,
          styleOverride: cs == 'splitdfrac' ? TexMathStyle.display : null,
        );
      case 'Aboxed':
        if (!activePackages.has('mathtools')) {
          break;
        }
        final MathNode body = _parseRequiredArgNode(cs);
        return MathGroupNode(
          span: span.merge(body.span),
          role: 'boxed',
          children: <MathNode>[body],
        );
      case 'xmathstrut':
        if (!activePackages.has('mathtools')) {
          break;
        }
        readOptionalBracketText(cs);
        readArgumentText(cs);
        return SpaceNode(span: span, widthEm: 0.0, command: cs);

      // Unicode
      case 'unicode':
      case 'U':
        if (!activePackages.has('unicode') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        if (cs == 'unicode') {
          readOptionalBracketText('unicode');
        }
        final String codeStr = readArgumentText(cs).trim();
        final int cp = _parseCodePoint(codeStr, span);
        final String val = String.fromCharCode(cp);
        return SymbolNode(
          span: span,
          value: val,
          command: cs,
          fontVariant: _resolveSymbolVariant(
            _fontVariant ?? TexMathFontVariant.normal,
            val,
          ),
        );
      case 'char':
        if (!activePackages.has('unicode') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final int cp = _readTexCharCodePoint(span);
        final String val = String.fromCharCode(cp);
        return SymbolNode(
          span: span,
          value: val,
          command: 'char',
          fontVariant: _resolveSymbolVariant(
            _fontVariant ?? TexMathFontVariant.normal,
            val,
          ),
        );

      // Verb
      case 'verb':
        if (!activePackages.has('verb') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        return _parseVerbCommand(span);

      // Mhchem
      case 'ce':
      case 'pu':
        if (!activePackages.has('mhchem') &&
            !activePackages.tryAutoloadCommand(cs)) {
          break;
        }
        final String chemArg = readArgumentText(cs);
        final String tex = translateMhchemToTex(
          chemArg,
          isPhysicalUnits: cs == 'pu',
          maxNestingDepth: options.budgets.maxNestingDepth,
        );
        return parseSyntheticTex(
          tex,
          span: span,
          fontVariant: TexMathFontVariant.normal,
        );

      // Units
      case 'units':
        if (!activePackages.has('units')) {
          break;
        }
        final String? val = readOptionalBracketText('units');
        final String dim = readArgumentText('units');
        final MathNode unitBody = parseSyntheticTex(
          '\\mathrm{$dim}',
          span: span,
        );
        if (val == null || val.isEmpty) {
          return unitBody;
        }
        final MathNode valNode = parseSyntheticTex(val, span: span);
        return MathGroupNode(
          span: span,
          isExplicitGroup: false,
          children: _unmodifiableNodes(<MathNode>[
            valNode,
            SpaceNode(
              span: span,
              widthEm: activePackages.unitsLoose ? 0.25 : thinMuSkipEm,
              command: activePackages.unitsLoose ? '~' : ',',
            ),
            unitBody,
          ]),
        );
      case 'unitfrac':
        if (!activePackages.has('units')) {
          break;
        }
        final String? val = readOptionalBracketText('unitfrac');
        final String num = readArgumentText('unitfrac');
        final String den = readArgumentText('unitfrac');
        final FractionNode fracNode = FractionNode(
          span: span,
          numerator: parseSyntheticTex('\\mathrm{$num}', span: span),
          denominator: parseSyntheticTex('\\mathrm{$den}', span: span),
          isBevelled: !activePackages.unitsUgly,
        );
        if (val == null || val.isEmpty) {
          return fracNode;
        }
        final MathNode valNode = parseSyntheticTex(val, span: span);
        return MathGroupNode(
          span: span,
          isExplicitGroup: false,
          children: _unmodifiableNodes(<MathNode>[
            valNode,
            SpaceNode(
              span: span,
              widthEm: activePackages.unitsLoose ? 0.25 : thinMuSkipEm,
              command: activePackages.unitsLoose ? '~' : ',',
            ),
            fracNode,
          ]),
        );
      case 'nicefrac':
        if (!activePackages.has('units')) {
          break;
        }
        final String fontCmd =
            readOptionalBracketText('nicefrac') ?? r'\mathrm';
        final String num = readArgumentText('nicefrac');
        final String den = readArgumentText('nicefrac');
        return FractionNode(
          span: span,
          numerator: parseSyntheticTex('$fontCmd{$num}', span: span),
          denominator: parseSyntheticTex('$fontCmd{$den}', span: span),
          isBevelled: !activePackages.unitsUgly,
        );

      // Braket package (when physics doesn't override)
      case 'bra':
      case 'ket':
      case 'braket':
      case 'set':
      case 'Bra':
      case 'Ket':
      case 'Braket':
      case 'Set':
      case 'ketbra':
      case 'Ketbra':
        if (activePackages.has('physics')) {
          final MathNode? phys = PhysicsParser.tryParseCommand(this, cs, span);
          if (phys != null) {
            return phys;
          }
        }
        if (activePackages.has('braket') ||
            activePackages.tryAutoloadCommand(cs)) {
          return _parseBraketPackageCommand(cs, span);
        }
        break;
    }

    // 3. Check `physics` commands when `physics` package is active.
    if (activePackages.has('physics')) {
      final MathNode? physNode = PhysicsParser.tryParseCommand(this, cs, span);
      if (physNode != null) {
        return physNode;
      }
    }

    // 4. Check spacing commands (`\,`, `\:`, `\;`, `\!`, `\quad`, etc.).
    final double? spaceWidth = mathSpacingCommands[cs];
    if (spaceWidth != null) {
      return SpaceNode(span: span, widthEm: spaceWidth, command: cs);
    }

    // 5. Check symbol maps gated by active packages.
    final TexSymbolSpec? spec = _lookupPackageSymbol(cs);
    if (spec != null) {
      if (spec.isOperator) {
        return OperatorNode(
          span: span,
          operatorName: spec.unicode,
          hasLimits: spec.hasLimits,
          isLarge: spec.isLarge,
          command: cs,
        );
      }
      return SymbolNode(
        span: span,
        value: spec.unicode,
        command: cs,
        atomClass: spec.atomClass,
        fontVariant: _resolveSymbolVariant(
          _fontVariant ?? spec.fontVariant,
          spec.unicode,
        ),
        isStretchy: spec.isStretchy,
      );
    }

    // 6. Autoload retry if `autoload` is enabled.
    if (activePackages.tryAutoloadCommand(cs)) {
      return _parseBuiltinCommand(cs, span);
    }

    // 7. Fallback (`noundefined`) or strict error (`undefinedControlSequence`).
    if (activePackages.has('noundefined')) {
      return ColorNode(
        span: span,
        role: TexMathColorRole.error,
        colorValue: '#FF0000',
        children: <MathNode>[
          TextNode(span: span, text: '\\$cs', styleCommand: 'text'),
        ],
      );
    }

    throw TexMathSyntaxError(
      'Undefined control sequence \\$cs.',
      errorClass: TexMathErrorClass.undefinedControlSequence,
      span: span,
    );
  }

  TexSymbolSpec? _lookupPackageSymbol(String cs) {
    final TexSymbolSpec? base = baseSymbolMap[cs];
    if (base != null) {
      return base;
    }
    if (activePackages.has('ams')) {
      final TexSymbolSpec? ams = amsSymbolMap[cs];
      if (ams != null) {
        return ams;
      }
    }
    if (activePackages.has('upgreek')) {
      final TexSymbolSpec? up = upgreekSymbolMap[cs];
      if (up != null) {
        return up;
      }
    }
    if (activePackages.has('gensymb')) {
      final TexSymbolSpec? gen = gensymbSymbolMap[cs];
      if (gen != null) {
        return gen;
      }
    }
    if (activePackages.has('textcomp')) {
      final TexSymbolSpec? tc = textcompSymbolMap[cs];
      if (tc != null) {
        return tc;
      }
    }
    if (activePackages.has('mathtools')) {
      final TexSymbolSpec? mt = mathtoolsSymbolMap[cs];
      if (mt != null) {
        return mt;
      }
    }
    if (activePackages.has('bboldx')) {
      final TexSymbolSpec? bb = bboldxSymbolMap[cs];
      if (bb != null) {
        return bb;
      }
    }
    return null;
  }

  MathNode _parseExtArrowWithCodePoint(
    String cs,
    int codePoint,
    SourceSpan span,
  ) {
    final List<TexToken>? underTokens = readOptionalBracketTokens(cs);
    final List<TexToken> overTokens = readArgumentTokens(cs);
    final MathNode? under = underTokens == null
        ? null
        : parseSubTokens(underTokens, span: span);
    final MathNode? over = overTokens.isEmpty
        ? null
        : parseSubTokens(overTokens, span: span);
    final OperatorNode arrow = OperatorNode(
      span: span,
      operatorName: String.fromCharCode(codePoint),
      hasLimits: true,
      command: cs,
      isExtensible: true,
    );
    if (over == null && under == null) {
      return arrow;
    }
    return ScriptNode(
      span: span,
      base: arrow,
      superscript: over,
      subscript: under,
      limitsAboveBelow: true,
    );
  }

  MathNode _parseBraketPackageCommand(String cs, SourceSpan span) {
    final bool isBig =
        cs == 'Bra' ||
        cs == 'Ket' ||
        cs == 'Braket' ||
        cs == 'Set' ||
        cs == 'Ketbra';
    final double? fixedSize = isBig ? null : 0.0;
    final (String left, String right) = switch (cs) {
      'bra' || 'Bra' => ('\u27E8', '|'),
      'ket' || 'Ket' => ('|', '\u27E9'),
      'braket' || 'Braket' => ('\u27E8', '\u27E9'),
      'set' || 'Set' => ('{', '}'),
      _ => ('|', '|'),
    };

    if (cs == 'ketbra' || cs == 'Ketbra') {
      final MathNode a = parseSubTokens(readArgumentTokens(cs), span: span);
      final MathNode b = parseSubTokens(readArgumentTokens(cs), span: span);
      return MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: <MathNode>[
          DelimiterNode(
            span: span,
            leftDelimiter: '|',
            rightDelimiter: '\u27E9',
            fixedSizeEm: fixedSize,
            children: <MathNode>[a],
          ),
          DelimiterNode(
            span: span,
            leftDelimiter: '\u27E8',
            rightDelimiter: '|',
            fixedSizeEm: fixedSize,
            children: <MathNode>[b],
          ),
        ],
      );
    }

    final List<TexToken> tokens = readArgumentTokens(cs);
    final List<List<TexToken>> segments = _splitTopLevelBars(tokens);
    final List<MathNode> children = <MathNode>[];
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) {
        children.add(
          SymbolNode(
            span: span,
            value: '|',
            command: 'middle',
            atomClass: TexMathAtomClass.ord,
            isStretchy: isBig,
          ),
        );
      }
      children.add(parseSubTokens(segments[i], span: span));
    }
    return DelimiterNode(
      span: span,
      leftDelimiter: left,
      rightDelimiter: right,
      fixedSizeEm: fixedSize,
      children: children,
    );
  }

  List<List<TexToken>> _splitTopLevelBars(List<TexToken> tokens) {
    final List<List<TexToken>> parts = <List<TexToken>>[];
    List<TexToken> current = <TexToken>[];
    int depth = 0;
    for (final TexToken t in tokens) {
      if (t.kind == TexTokenKind.beginGroup) {
        depth++;
      } else if (t.kind == TexTokenKind.endGroup && depth > 0) {
        depth--;
      } else if (depth == 0 &&
          ((t.kind == TexTokenKind.other && t.text == '|') ||
              (t.kind == TexTokenKind.controlSequence && t.text == 'vert'))) {
        parts.add(current);
        current = <TexToken>[];
        continue;
      }
      current.add(t);
    }
    parts.add(current);
    return parts;
  }

  MathNode _parseVerbCommand(SourceSpan verbSpan) {
    final bool hasStar = consumeOptionalStar();
    cursor.skipSpaces();
    final TexToken? delimTok = cursor.peekRaw();
    if (delimTok == null || delimTok.span.start >= source.length) {
      throw TexMathSyntaxError(
        'Missing argument for \\verb.',
        errorClass: TexMathErrorClass.missingArgument,
        span: verbSpan,
      );
    }
    final int delimStart = delimTok.span.start;
    final String delimChar = source.substring(delimStart, delimStart + 1);
    final int closeIdx = source.indexOf(delimChar, delimStart + 1);
    if (closeIdx < 0) {
      throw TexMathSyntaxError(
        'Can\'t find closing delimiter for \\verb.',
        errorClass: TexMathErrorClass.missingArgument,
        span: SourceSpan(verbSpan.start, source.length),
      );
    }
    String text = source.substring(delimStart + 1, closeIdx);
    if (hasStar) {
      text = text.replaceAll(' ', '\u2423');
    }
    cursor.discardRawUntilOffset(closeIdx + 1);
    return TextNode(
      span: SourceSpan(verbSpan.start, closeIdx + 1),
      text: text,
      styleCommand: 'texttt',
    );
  }

  MathNode _parseNotCommand(SourceSpan span) {
    final TexToken? next = cursor.peek();
    if (next == null) {
      throw TexMathSyntaxError(
        'Missing argument for \\not.',
        errorClass: TexMathErrorClass.missingArgument,
        span: span,
      );
    }
    final MathNode? target;
    enterNesting(span);
    try {
      target = _parseAtom(cursor.next()!);
    } finally {
      exitNesting();
    }
    if (target is SymbolNode) {
      final String? mapped = notRemap[target.value];
      return SymbolNode(
        span: span.merge(target.span),
        value: mapped ?? target.value,
        command: target.command,
        atomClass: target.atomClass,
        fontVariant: target.fontVariant,
        isNegated: mapped == null,
      );
    }
    if (target == null) {
      return SymbolNode(span: span, value: '\u29F8', command: 'not');
    }
    return MathGroupNode(
      span: span.merge(target.span),
      role: 'not',
      children: _unmodifiableNodes(<MathNode>[target]),
    );
  }

  MathNode _parseLeftRightGroup(SourceSpan leftSpan) {
    final String leftDelim = readDelimiterToken('left');
    final String? leftNormalized = leftDelim.isEmpty ? null : leftDelim;
    enterNesting(leftSpan);
    try {
      final List<MathNode> children = <MathNode>[];
      while (true) {
        cursor.skipIgnorable();
        final TexToken? next = cursor.peek();
        if (next == null) {
          throw TexMathSyntaxError(
            'Missing \\right delimiter.',
            errorClass: TexMathErrorClass.missingDelimiter,
            span: leftSpan,
          );
        }
        if (next.kind == TexTokenKind.endGroup) {
          throw TexMathSyntaxError(
            'Missing \\right delimiter before "}".',
            errorClass: TexMathErrorClass.missingDelimiter,
            span: next.span,
          );
        }
        if (next.kind == TexTokenKind.controlSequence && next.text == 'end') {
          if (tryExpandUserEnvEnd()) {
            continue;
          }
          throw TexMathSyntaxError(
            'Missing \\right delimiter before \\end.',
            errorClass: TexMathErrorClass.missingDelimiter,
            span: next.span,
          );
        }
        if (next.kind == TexTokenKind.controlSequence && next.text == 'right') {
          cursor.next();
          final String rightDelim = readDelimiterToken('right');
          final String? rightNormalized = rightDelim.isEmpty
              ? null
              : rightDelim;
          return DelimiterNode(
            span: leftSpan.merge(next.span),
            leftDelimiter: leftNormalized,
            rightDelimiter: rightNormalized,
            children: children,
          );
        }
        if (next.kind == TexTokenKind.controlSequence &&
            next.text == 'middle') {
          cursor.next();
          final String midDelim = readDelimiterToken('middle');
          children.add(
            SymbolNode(
              span: next.span,
              value: midDelim.isEmpty ? '|' : midDelim,
              command: 'middle',
              atomClass: TexMathAtomClass.ord,
              isStretchy: true,
            ),
          );
          continue;
        }
        final TexToken tok = cursor.next()!;
        if (tok.kind == TexTokenKind.superscript ||
            tok.kind == TexTokenKind.subscript ||
            (tok.kind == TexTokenKind.other &&
                (tok.text == "'" || tok.text == '\u2019'))) {
          final MathNode base = children.isNotEmpty
              ? children.removeLast()
              : MathGroupNode(
                  span: SourceSpan.empty(tok.span.start),
                  children: const <MathNode>[],
                  isExplicitGroup: false,
                );
          children.add(_attachSingleScript(base, tok));
          continue;
        }
        final MathNode? atom = _parseAtom(tok);
        if (atom != null) {
          children.add(attachScripts(atom));
        }
      }
    } finally {
      exitNesting();
    }
  }

  MathNode? _parseBeginEnvironment(SourceSpan beginSpan) {
    final String envName = readArgumentText('begin').trim();
    if (envName.isEmpty || envName.contains('\\')) {
      throw TexMathSyntaxError(
        'Invalid environment name "$envName".',
        errorClass: TexMathErrorClass.unknownEnvironment,
        span: beginSpan,
      );
    }

    // Check user-defined environments first (`\newenvironment`).
    final TexUserEnvDef? userEnv = macroTable.lookupEnvironment(envName);
    if (userEnv != null) {
      final List<List<TexToken>> args = <List<TexToken>>[];
      int startIndex = 0;
      if (userEnv.defaultArg != null) {
        final List<TexToken>? opt = readOptionalBracketTokens(
          'begin{$envName}',
        );
        args.add(opt ?? userEnv.defaultArg!);
        startIndex = 1;
      }
      for (int i = startIndex; i < userEnv.paramCount; i++) {
        args.add(readArgumentTokens('begin{$envName}'));
      }
      final List<TexToken> expandedBegin = substituteMacroParams(
        body: userEnv.beginBody,
        args: args,
        fallbackSpan: beginSpan,
        budgets: options.budgets,
        budgetState: cursor.budgetState,
      );
      _openUserEnvs.add(
        _OpenEnvFrame(name: envName, span: beginSpan, userEnvDef: userEnv),
      );
      cursor.pushMacroExpansion(
        expandedBegin,
        span: beginSpan,
        chargeTokens: false,
      );
      return null;
    }

    // Check autoload for environments like CD or prooftree.
    if (!builtinEnvironments.containsKey(envName) ||
        !activePackages.has(builtinEnvironments[envName]!.packageName)) {
      activePackages.tryAutoloadEnvironment(envName);
    }

    final TexEnvironmentSpec? spec = builtinEnvironments[envName];
    if (spec == null || !activePackages.has(spec.packageName)) {
      throw TexMathSyntaxError(
        'Unknown environment "$envName".',
        errorClass: TexMathErrorClass.unknownEnvironment,
        span: beginSpan,
      );
    }

    _envStack.add(_OpenEnvFrame(name: envName, span: beginSpan));
    enterNesting(beginSpan);
    macroTable.pushBraceScope();
    try {
      return parseEnvironment(
        host: this,
        envName: envName,
        beginSpan: beginSpan,
      );
    } finally {
      macroTable.popBraceScope();
      exitNesting();
    }
  }

  @override
  bool tryExpandUserEnvEnd() {
    if (_openUserEnvs.isEmpty) {
      return false;
    }
    final TexToken? tok = cursor.peek();
    if (tok == null ||
        tok.kind != TexTokenKind.controlSequence ||
        tok.text != 'end') {
      return false;
    }
    final TexToken endTok = cursor.next()!;
    final List<TexToken> argTokens = readArgumentTokens('end');
    final String actualEnd = argTokens
        .map((TexToken t) => t.rawText)
        .join()
        .trim();
    if (_openUserEnvs.last.name == actualEnd) {
      final _OpenEnvFrame frame = _openUserEnvs.removeLast();
      final List<TexToken> endBody = frame.userEnvDef?.endBody ?? <TexToken>[];
      cursor.pushMacroExpansion(endBody, span: endTok.span);
      return true;
    }
    // Restore `\end{actualEnd}` when it targets an inner built-in environment.
    cursor.pushTokens(<TexToken>[
      endTok,
      TexToken(
        kind: TexTokenKind.beginGroup,
        text: '{',
        span: endTok.span,
        catCode: TexCatCode.beginGroup,
      ),
      ...argTokens,
      TexToken(
        kind: TexTokenKind.endGroup,
        text: '}',
        span: endTok.span,
        catCode: TexCatCode.endGroup,
      ),
    ]);
    return false;
  }

  @override
  SourceSpan consumeEndEnvironment(String envName, SourceSpan beginSpan) {
    final TexToken? tok = cursor.next();
    if (tok == null ||
        tok.kind != TexTokenKind.controlSequence ||
        tok.text != 'end') {
      throw TexMathSyntaxError(
        'Missing \\end{$envName}.',
        errorClass: TexMathErrorClass.mismatchedEnvironment,
        span: beginSpan,
      );
    }
    final String actualEnd = readArgumentText('end').trim();
    if (actualEnd != envName) {
      throw TexMathSyntaxError(
        '\\begin{$envName} ended by \\end{$actualEnd}.',
        errorClass: TexMathErrorClass.mismatchedEnvironment,
        span: tok.span,
      );
    }
    if (_envStack.isEmpty || _envStack.last.name != envName) {
      throw TexMathSyntaxError(
        'Mismatched \\end{$actualEnd}.',
        errorClass: TexMathErrorClass.mismatchedEnvironment,
        span: tok.span,
      );
    }
    _envStack.removeLast();
    return tok.span;
  }

  // --- Macro Definition Parsers ---

  void _parseNewCommand(
    String cmd,
    SourceSpan span, {
    required bool forceGlobal,
  }) {
    consumeOptionalStar();
    final String name = _readDefinedCommandName(cmd, span);
    final int arity = _readOptionalParamCount(cmd, span);
    final List<TexToken>? defaultArg = arity > 0
        ? readOptionalBracketTokens(cmd)
        : null;
    final List<TexToken> body = _readRequiredDefBody(cmd, span);
    validateMacroBody(
      body: body,
      paramCount: arity,
      commandName: name,
      span: span,
    );
    if (cmd == 'providecommand' && macroTable.lookupMacro(name) != null) {
      return;
    }
    macroTable.defineMacro(
      name,
      TexUserMacroEntry(
        name: name,
        paramCount: arity,
        defaultArg: defaultArg,
        body: body,
      ),
      global: forceGlobal,
    );
  }

  void _parseNewEnvironment(String cmd, SourceSpan span) {
    consumeOptionalStar();
    final String envName = readArgumentText(cmd).trim();
    if (envName.isEmpty) {
      throw TexMathMacroError(
        'Empty environment name in \\$cmd.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    final int arity = _readOptionalParamCount(cmd, span);
    final List<TexToken>? defaultArg = arity > 0
        ? readOptionalBracketTokens(cmd)
        : null;
    final List<TexToken> beginBody = _readRequiredDefBody(cmd, span);
    final List<TexToken> endBody = _readRequiredDefBody(cmd, span);
    validateMacroBody(
      body: beginBody,
      paramCount: arity,
      commandName: envName,
      span: span,
    );
    validateMacroBody(
      body: endBody,
      paramCount: 0,
      commandName: envName,
      span: span,
    );
    macroTable.defineEnvironment(
      envName,
      TexUserEnvDef(
        name: envName,
        paramCount: arity,
        defaultArg: defaultArg,
        beginBody: beginBody,
        endBody: endBody,
      ),
    );
  }

  void _parseDefCommand(
    String cmd,
    SourceSpan span, {
    required bool forceGlobal,
    required bool expandBody,
  }) {
    cursor.skipIgnorable();
    final TexToken? csTok = cursor.next();
    if (csTok == null ||
        csTok.kind != TexTokenKind.controlSequence ||
        csTok.text.isEmpty) {
      throw TexMathMacroError(
        '\\$cmd must be followed by a control sequence.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: csTok?.span ?? span,
      );
    }
    final String name = csTok.text;

    // Parse parameter template up to `{`.
    final List<TexToken> preDelimiter = <TexToken>[];
    final List<List<TexToken>> paramDelimiters = <List<TexToken>>[];
    int paramCount = 0;
    List<TexToken> currentDelim = <TexToken>[];

    while (true) {
      final TexToken? tok = cursor.peek(skipSpaces: false);
      if (tok == null) {
        throw TexMathMacroError(
          'Missing replacement text for definition of \\$name.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: span,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        break;
      }
      cursor.nextRaw();
      if (tok.kind == TexTokenKind.comment || tok.kind == TexTokenKind.space) {
        continue;
      }
      if (tok.kind == TexTokenKind.parameter) {
        final TexToken? numTok = cursor.nextRaw();
        if (numTok == null ||
            numTok.kind != TexTokenKind.other ||
            numTok.text.length != 1) {
          throw TexMathMacroError(
            'Illegal parameter marker in \\$cmd \\$name.',
            errorClass: TexMathErrorClass.invalidMacroDefinition,
            span: numTok?.span ?? tok.span,
          );
        }
        final int code = numTok.text.codeUnitAt(0);
        if (code < 0x31 || code > 0x39 || (code - 0x30) != paramCount + 1) {
          throw TexMathMacroError(
            'Parameters in \\$cmd \\$name must be numbered sequentially #1..#9.',
            errorClass: TexMathErrorClass.invalidMacroDefinition,
            span: numTok.span,
          );
        }
        if (paramCount == 0) {
          preDelimiter.addAll(currentDelim);
        } else {
          paramDelimiters.add(currentDelim);
        }
        currentDelim = <TexToken>[];
        paramCount++;
        continue;
      }
      currentDelim.add(tok);
    }
    if (paramCount > 0) {
      paramDelimiters.add(currentDelim);
    } else if (currentDelim.isNotEmpty) {
      preDelimiter.addAll(currentDelim);
    }

    final List<TexToken> rawBody = _readRequiredDefBody(cmd, span);
    validateMacroBody(
      body: rawBody,
      paramCount: paramCount,
      commandName: name,
      span: span,
    );
    final List<TexToken> finalBody = expandBody
        ? _expandEdefTokens(rawBody, span)
        : rawBody;

    macroTable.defineMacro(
      name,
      TexUserMacroEntry(
        name: name,
        paramCount: paramCount,
        preDelimiter: preDelimiter,
        paramDelimiters: paramDelimiters,
        body: finalBody,
      ),
      global: forceGlobal,
    );
  }

  List<TexToken> _expandEdefTokens(List<TexToken> tokens, SourceSpan span) {
    final List<TexToken> expanded = <TexToken>[];
    final TexTokenCursor subCursor = TexTokenCursor(
      source: source,
      initialTokens: tokens,
      budgets: options.budgets,
      budgetState: cursor.budgetState,
      initialMacroDepth: cursor.macroDepth,
    );
    while (!subCursor.isAtEnd) {
      final TexToken? t = subCursor.next(skipSpaces: false);
      if (t == null) {
        break;
      }
      if (t.kind == TexTokenKind.controlSequence) {
        final TexMacroEntry? entry = macroTable.lookupMacro(t.text);
        if (entry is TexUserMacroEntry && entry.paramCount == 0) {
          subCursor.pushMacroExpansion(entry.body, span: t.span);
          continue;
        }
      }
      cursor.budgetState.chargeTokens(
        1,
        budgets: options.budgets,
        span: t.span,
      );
      expanded.add(t);
    }
    return expanded;
  }

  void _parseLetCommand(SourceSpan span, {required bool forceGlobal}) {
    cursor.skipIgnorable();
    final TexToken? csTok = cursor.next();
    if (csTok == null ||
        csTok.kind != TexTokenKind.controlSequence ||
        csTok.text.isEmpty) {
      throw TexMathMacroError(
        '\\let must be followed by a control sequence.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: csTok?.span ?? span,
      );
    }
    final String name = csTok.text;
    final TexToken? maybeEq = cursor.peek();
    if (maybeEq != null &&
        maybeEq.kind == TexTokenKind.other &&
        maybeEq.text == '=') {
      cursor.next();
    }
    final TexToken? target = cursor.next();
    if (target == null) {
      throw TexMathMacroError(
        'Missing target token for \\let\\$name.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    if (target.kind == TexTokenKind.controlSequence) {
      if (target.text == name) {
        return;
      }
      final TexMacroEntry? existing = macroTable.lookupMacro(target.text);
      if (existing != null) {
        macroTable.defineMacro(name, existing, global: forceGlobal);
      } else {
        macroTable.defineMacro(
          name,
          TexAliasEntry(targetCommand: target.text),
          global: forceGlobal,
        );
      }
    } else {
      macroTable.defineMacro(
        name,
        TexAliasEntry(literalToken: target),
        global: forceGlobal,
      );
    }
  }

  void _parseDeclareMathOperator(SourceSpan span) {
    final bool hasLimits = consumeOptionalStar();
    final String name = _readDefinedCommandName('DeclareMathOperator', span);
    final List<TexToken> body = _readRequiredDefBody(
      'DeclareMathOperator',
      span,
    );
    macroTable.defineMacro(
      name,
      TexDeclaredOperatorEntry(name: name, body: body, hasLimits: hasLimits),
    );
  }

  void _parseDeclarePairedDelimiter(String cmd, SourceSpan span) {
    final String name = _readDefinedCommandName(cmd, span);
    if (cmd == 'DeclarePairedDelimiterX' ||
        cmd == 'DeclarePairedDelimiterXPP') {
      _readOptionalParamCount(cmd, span);
    }
    if (cmd == 'DeclarePairedDelimiterXPP') {
      readArgumentTokens(cmd);
    }
    final String leftDelim = readArgumentText(cmd).trim();
    final String rightDelim = readArgumentText(cmd).trim();
    if (cmd == 'DeclarePairedDelimiterX' ||
        cmd == 'DeclarePairedDelimiterXPP') {
      readArgumentTokens(cmd);
    }
    if (cmd == 'DeclarePairedDelimiterXPP') {
      readArgumentTokens(cmd);
    }
    macroTable.defineMacro(
      name,
      TexPairedDelimiterEntry(
        name: name,
        leftDelimiter: normalizeDelimiterString(leftDelim),
        rightDelimiter: normalizeDelimiterString(rightDelim),
      ),
    );
  }

  void _parseNewExtArrow(SourceSpan span) {
    final String rawCs = readArgumentText('Newextarrow').trim();
    final String spaceSpec = readArgumentText('Newextarrow').trim();
    final String charSpec = readArgumentText('Newextarrow').trim();
    if (!_newExtArrowCsPattern.hasMatch(rawCs)) {
      throw TexMathMacroError(
        'First argument to \\Newextarrow must be a control sequence.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    if (!_newExtArrowSpacePattern.hasMatch(spaceSpec)) {
      throw TexMathMacroError(
        'Second argument to \\Newextarrow must be two integers.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    final int? codePoint =
        charSpec.startsWith('0x') || charSpec.startsWith('0X')
        ? int.tryParse(charSpec.substring(2), radix: 16)
        : int.tryParse(charSpec);
    if (codePoint == null) {
      throw TexMathMacroError(
        'Third argument to \\Newextarrow must be a Unicode code point.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    final String csName = rawCs.substring(1);
    macroTable.defineMacro(
      csName,
      TexExtArrowEntry(name: csName, codePoint: codePoint),
    );
  }

  String _readDefinedCommandName(String cmd, SourceSpan span) {
    final List<TexToken> tokens = _readRequiredDefBody(cmd, span);
    final List<TexToken> filtered = tokens
        .where((TexToken t) => !t.isIgnorableInMath)
        .toList();
    if (filtered.length != 1 ||
        filtered.first.kind != TexTokenKind.controlSequence ||
        filtered.first.text.isEmpty) {
      throw TexMathMacroError(
        'Illegal control sequence name in \\$cmd.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    return filtered.first.text;
  }

  int _readOptionalParamCount(String cmd, SourceSpan span) {
    final String? raw = readOptionalBracketText(cmd);
    if (raw == null) {
      return 0;
    }
    final String trimmed = raw.trim();
    final int? count = int.tryParse(trimmed);
    if (count == null || count < 0 || count > 9) {
      throw TexMathMacroError(
        'Illegal parameter count "$trimmed" in \\$cmd.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    return count;
  }

  List<TexToken> _readRequiredDefBody(String cmd, SourceSpan span) {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek(skipSpaces: false);
    if (next == null) {
      throw TexMathMacroError(
        'Missing replacement body for \\$cmd.',
        errorClass: TexMathErrorClass.invalidMacroDefinition,
        span: span,
      );
    }
    if (next.kind != TexTokenKind.beginGroup) {
      return <TexToken>[cursor.nextRaw()!];
    }
    cursor.nextRaw(); // consume `{`
    final List<TexToken> body = <TexToken>[];
    int depth = 1;
    while (true) {
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathSyntaxError(
          'Missing closing brace "}" in \\$cmd.',
          errorClass: TexMathErrorClass.missingBrace,
          span: next.span,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        depth++;
        body.add(tok);
      } else if (tok.kind == TexTokenKind.endGroup) {
        depth--;
        if (depth == 0) {
          return body;
        }
        body.add(tok);
      } else {
        body.add(tok);
      }
    }
  }

  // --- Host Helper Implementations ---

  @override
  bool consumeOptionalStar() {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek();
    if (next != null && next.kind == TexTokenKind.other && next.text == '*') {
      cursor.next();
      return true;
    }
    return false;
  }

  @override
  List<TexToken>? readOptionalBracketTokens(String commandName) {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek();
    if (next == null || next.kind != TexTokenKind.other || next.text != '[') {
      return null;
    }
    cursor.next(); // consume `[`
    final List<TexToken> out = <TexToken>[];
    int braceDepth = 0;
    while (true) {
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathSyntaxError(
          'Missing closing bracket "]" for \\$commandName.',
          errorClass: TexMathErrorClass.missingBrace,
          span: next.span,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        braceDepth++;
        out.add(tok);
      } else if (tok.kind == TexTokenKind.endGroup) {
        if (braceDepth == 0) {
          throw TexMathSyntaxError(
            'Extra closing brace "}" inside optional argument.',
            errorClass: TexMathErrorClass.extraBrace,
            span: tok.span,
          );
        }
        braceDepth--;
        out.add(tok);
      } else if (braceDepth == 0 &&
          tok.kind == TexTokenKind.other &&
          tok.text == ']') {
        return out;
      } else if (tok.kind != TexTokenKind.comment) {
        out.add(tok);
      }
    }
  }

  @override
  String? readOptionalBracketText(String commandName) {
    final List<TexToken>? tokens = readOptionalBracketTokens(commandName);
    if (tokens == null) {
      return null;
    }
    return tokens.map((TexToken t) => t.rawText).join();
  }

  @override
  List<TexToken> readArgumentTokens(
    String commandName, {
    bool allowSingleToken = true,
  }) {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek(skipSpaces: false);
    if (next == null) {
      throw TexMathSyntaxError(
        'Missing argument for \\$commandName.',
        errorClass: TexMathErrorClass.missingArgument,
        span: cursor.currentSpan(),
      );
    }
    if (next.kind == TexTokenKind.endGroup ||
        next.kind == TexTokenKind.alignmentTab) {
      throw TexMathSyntaxError(
        'Missing argument for \\$commandName.',
        errorClass: TexMathErrorClass.missingArgument,
        span: next.span,
      );
    }
    if (next.kind != TexTokenKind.beginGroup) {
      if (!allowSingleToken) {
        throw TexMathSyntaxError(
          'Expected braced argument for \\$commandName.',
          errorClass: TexMathErrorClass.missingArgument,
          span: next.span,
        );
      }
      final TexToken single = cursor.nextRaw()!;
      if (single.kind == TexTokenKind.controlSequence &&
          single.text == 'frac') {
        final List<TexToken> a1;
        final List<TexToken> a2;
        enterNesting(single.span);
        try {
          a1 = readArgumentTokens('frac');
          a2 = readArgumentTokens('frac');
        } finally {
          exitNesting();
        }
        return <TexToken>[
          single,
          TexToken(
            kind: TexTokenKind.beginGroup,
            text: '{',
            span: single.span,
            catCode: TexCatCode.beginGroup,
          ),
          ...a1,
          TexToken(
            kind: TexTokenKind.endGroup,
            text: '}',
            span: single.span,
            catCode: TexCatCode.endGroup,
          ),
          TexToken(
            kind: TexTokenKind.beginGroup,
            text: '{',
            span: single.span,
            catCode: TexCatCode.beginGroup,
          ),
          ...a2,
          TexToken(
            kind: TexTokenKind.endGroup,
            text: '}',
            span: single.span,
            catCode: TexCatCode.endGroup,
          ),
        ];
      }
      return <TexToken>[single];
    }

    cursor.nextRaw(); // consume `{`
    final List<TexToken> out = <TexToken>[];
    int depth = 1;
    while (true) {
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathSyntaxError(
          'Missing closing brace "}" in argument for \\$commandName.',
          errorClass: TexMathErrorClass.missingBrace,
          span: next.span,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        depth++;
        out.add(tok);
      } else if (tok.kind == TexTokenKind.endGroup) {
        depth--;
        if (depth == 0) {
          return out;
        }
        out.add(tok);
      } else if (tok.kind != TexTokenKind.comment) {
        out.add(tok);
      }
    }
  }

  @override
  String readArgumentText(String commandName, {bool allowSingleToken = true}) {
    final List<TexToken> tokens = readArgumentTokens(
      commandName,
      allowSingleToken: allowSingleToken,
    );
    return tokens.map((TexToken t) => t.rawText).join();
  }

  @override
  List<TexToken> readBalancedDelimiterTokens(
    String commandName,
    String openChar,
    String closeChar,
  ) {
    cursor.skipIgnorable();
    final TexToken? open = cursor.next();
    if (open == null || open.text != openChar) {
      throw TexMathSyntaxError(
        'Expected "$openChar" for \\$commandName.',
        errorClass: TexMathErrorClass.missingArgument,
        span: open?.span ?? cursor.currentSpan(),
      );
    }
    final List<TexToken> out = <TexToken>[];
    int braceDepth = 0;
    int delimDepth = 1;
    while (true) {
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathSyntaxError(
          'Missing closing "$closeChar" for \\$commandName.',
          errorClass: TexMathErrorClass.missingDelimiter,
          span: open.span,
        );
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        braceDepth++;
        out.add(tok);
        continue;
      }
      if (tok.kind == TexTokenKind.endGroup) {
        if (braceDepth > 0) {
          braceDepth--;
        }
        out.add(tok);
        continue;
      }
      if (braceDepth == 0) {
        if (openChar != closeChar && tok.text == openChar) {
          delimDepth++;
        } else if (tok.text == closeChar) {
          delimDepth--;
          if (delimDepth == 0) {
            return out;
          }
        }
      }
      if (tok.kind != TexTokenKind.comment) {
        out.add(tok);
      }
    }
  }

  MathNode _parseRequiredArgNode(String commandName) {
    final List<TexToken> tokens = readArgumentTokens(commandName);
    final SourceSpan argSpan = tokens.isEmpty
        ? cursor.currentSpan()
        : tokens.first.span.merge(tokens.last.span);
    return parseSubTokens(tokens, span: argSpan);
  }

  @override
  MathNode parseSubTokens(
    List<TexToken> tokens, {
    required SourceSpan span,
    TexMathDisplayMode? displayMode,
    TexMathFontVariant? fontVariant,
    bool isExplicitGroup = false,
    bool inBoldSymbol = false,
  }) {
    enterNesting(span);
    final bool effectiveBoldSymbol = inBoldSymbol || _inBoldSymbol;
    final TexMathFontVariant? effectiveFontVariant =
        fontVariant != null && effectiveBoldSymbol
        ? boldSymbolVariantFor(fontVariant, null)
        : fontVariant;
    final TexTokenCursor subCursor = TexTokenCursor(
      source: source,
      initialTokens: tokens,
      budgets: options.budgets,
      budgetState: cursor.budgetState,
      initialMacroDepth: cursor.macroDepth,
    );
    final _TexParser subParser =
        _TexParser(
            source: source,
            cursor: subCursor,
            macroTable: macroTable,
            activePackages: activePackages,
            options: displayMode == null
                ? options
                : options.copyWith(displayMode: displayMode),
            labels: _labels,
            tagCounter: _tagCounter,
          )
          .._nestingDepth = _nestingDepth
          .._fontVariant = effectiveFontVariant ?? _fontVariant
          .._inBoldSymbol = effectiveBoldSymbol;
    macroTable.pushBraceScope();
    try {
      final _SeqResult res = subParser._parseSequence(stopMode: _StopMode.eof);
      if (res.nodes.length == 1 &&
          effectiveFontVariant == null &&
          !isExplicitGroup) {
        return res.nodes.first;
      }
      return MathGroupNode(
        span: _mergeSpanList(span, res.nodes),
        children: _unmodifiableNodes(res.nodes),
        isExplicitGroup: isExplicitGroup,
        fontVariant: effectiveFontVariant,
      );
    } finally {
      macroTable.popBraceScope();
      exitNesting();
    }
  }

  @override
  MathNode parseSyntheticTex(
    String tex, {
    required SourceSpan span,
    TexMathDisplayMode? displayMode,
    TexMathFontVariant? fontVariant,
  }) {
    if (tex.length > options.budgets.maxInputLength) {
      throw TexMathBudgetError(
        'Synthetic TeX length ${tex.length} exceeds maxInputLength '
        '(${options.budgets.maxInputLength}).',
        budgetName: 'maxInputLength',
        limit: options.budgets.maxInputLength,
        actual: tex.length,
        span: span,
      );
    }
    final List<TexToken> tokens = tokenizeTex(tex)
        .map(
          (TexToken t) => TexToken(
            kind: t.kind,
            text: t.text,
            span: span,
            catCode: t.catCode,
            isControlWord: t.isControlWord,
          ),
        )
        .toList();
    cursor.budgetState.chargeTokens(
      tokens.length,
      budgets: options.budgets,
      span: span,
    );
    return parseSubTokens(
      tokens,
      span: span,
      displayMode: displayMode,
      fontVariant: fontVariant,
    );
  }

  @override
  TextNode parseTextTokens(
    List<TexToken> tokens, {
    required SourceSpan span,
    String? styleCommand,
  }) {
    enterNesting(span);
    try {
      final _TextModeParser textParser = _TextModeParser(
        host: this,
        tokens: tokens,
        span: span,
        styleCommand: styleCommand ?? 'text',
      );
      return textParser.parse();
    } finally {
      exitNesting();
    }
  }

  @override
  ({
    MathNode node,
    String? stopReason,
    SourceSpan span,
    bool rowHasNoTag,
    TagNode? rowTag,
    String? rowLabel,
    String? cellBackground,
    String? rowBackground,
    String? columnBackground,
  })
  parseEnvironmentCell({
    required String envName,
    required bool allowAlignTab,
    bool textMode = false,
  }) {
    if (textMode) {
      return _parseTextModeEnvCell(envName: envName);
    }
    final SourceSpan startSpan = cursor.currentSpan();
    final _SeqResult result = _parseSequence(
      stopMode: _StopMode.envCell,
      activeEnvName: envName,
      allowAlignTab: allowAlignTab,
    );
    final SourceSpan cellSpan = _mergeSpanList(startSpan, result.nodes);
    final MathNode node = result.nodes.length == 1
        ? result.nodes.first
        : MathGroupNode(
            span: cellSpan,
            isExplicitGroup: false,
            children: result.nodes,
          );
    return (
      node: node,
      stopReason: result.stopReason,
      span: cellSpan,
      rowHasNoTag: result.rowHasNoTag,
      rowTag: result.rowTag,
      rowLabel: result.rowLabel,
      cellBackground: result.cellBackground,
      rowBackground: result.rowBackground,
      columnBackground: result.columnBackground,
    );
  }

  ({
    MathNode node,
    String? stopReason,
    SourceSpan span,
    bool rowHasNoTag,
    TagNode? rowTag,
    String? rowLabel,
    String? cellBackground,
    String? rowBackground,
    String? columnBackground,
  })
  _parseTextModeEnvCell({required String envName}) {
    final SourceSpan startSpan = cursor.currentSpan();
    final List<TexToken> cellTokens = <TexToken>[];
    String? stopReason;
    int braceDepth = 0;

    while (true) {
      final TexToken? peeked = cursor.peek(skipSpaces: false);
      if (peeked == null) {
        throw TexMathSyntaxError(
          'Missing \\end{$envName}.',
          errorClass: TexMathErrorClass.mismatchedEnvironment,
          span: startSpan,
        );
      }
      if (braceDepth == 0) {
        if (peeked.kind == TexTokenKind.alignmentTab) {
          throw TexMathSyntaxError(
            'Extra alignment tab & in text column of $envName.',
            errorClass: TexMathErrorClass.misplacedAlignmentTab,
            span: peeked.span,
          );
        }
        if (peeked.kind == TexTokenKind.controlSequence &&
            (peeked.text == '\\' || peeked.text == 'cr')) {
          cursor.nextRaw();
          if (peeked.text == '\\') {
            _consumeNewlineStarAndDimen(peeked.span);
          }
          stopReason = 'cr';
          break;
        }
        if (peeked.kind == TexTokenKind.controlSequence &&
            peeked.text == 'end') {
          stopReason = 'end';
          break;
        }
      }
      final TexToken tok = cursor.nextRaw()!;
      if (tok.kind == TexTokenKind.beginGroup) {
        braceDepth++;
      } else if (tok.kind == TexTokenKind.endGroup && braceDepth > 0) {
        braceDepth--;
      }
      cellTokens.add(tok);
    }

    final SourceSpan cellSpan = cellTokens.isEmpty
        ? startSpan
        : cellTokens.first.span.merge(cellTokens.last.span);
    final TextNode node = parseTextTokens(
      cellTokens,
      span: cellSpan,
      styleCommand: 'text',
    );
    return (
      node: node,
      stopReason: stopReason,
      span: cellSpan,
      rowHasNoTag: false,
      rowTag: null,
      rowLabel: null,
      cellBackground: null,
      rowBackground: null,
      columnBackground: null,
    );
  }

  @override
  String? tryConsumeRowRule() {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek();
    if (next == null || next.kind != TexTokenKind.controlSequence) {
      return null;
    }
    if (next.text == 'hline') {
      cursor.next();
      return 'solid';
    }
    if (next.text == 'hdashline') {
      cursor.next();
      return 'dashed';
    }
    return null;
  }

  @override
  String readDelimiterToken(String commandName, {bool allowPeriod = true}) {
    cursor.skipIgnorable();
    final TexToken? tok = cursor.next();
    if (tok == null) {
      throw TexMathSyntaxError(
        'Missing delimiter after \\$commandName.',
        errorClass: TexMathErrorClass.missingDelimiter,
        span: cursor.currentSpan(),
      );
    }
    if (tok.kind == TexTokenKind.other) {
      if (tok.text == '.' && !allowPeriod) {
        throw TexMathSyntaxError(
          'Unrecognized delimiter "." for \\$commandName.',
          errorClass: TexMathErrorClass.missingDelimiter,
          span: tok.span,
        );
      }
      final String? literal = literalDelimiterMap[tok.text];
      if (literal != null) {
        return literal;
      }
      throw TexMathSyntaxError(
        'Unrecognized delimiter "${tok.text}" for \\$commandName.',
        errorClass: TexMathErrorClass.missingDelimiter,
        span: tok.span,
      );
    }
    if (tok.kind == TexTokenKind.controlSequence) {
      final TexMacroEntry? macro = macroTable.lookupMacro(tok.text);
      if (macro is TexAliasEntry && macro.targetCommand != null) {
        final TexSymbolSpec? aliased = _lookupPackageSymbol(
          macro.targetCommand!,
        );
        if (aliased != null && aliased.isDelimiter) {
          return aliased.unicode;
        }
      }
      final TexSymbolSpec? spec = _lookupPackageSymbol(tok.text);
      if (spec != null && spec.isDelimiter) {
        return spec.unicode;
      }
    }
    throw TexMathSyntaxError(
      'Unrecognized delimiter "${tok.rawText}" for \\$commandName.',
      errorClass: TexMathErrorClass.missingDelimiter,
      span: tok.span,
    );
  }

  @override
  MathNode attachScripts(MathNode base) {
    MathNode current = base;
    while (true) {
      cursor.skipIgnorable();
      final TexToken? next = cursor.peek();
      if (next == null) {
        break;
      }
      if (next.kind == TexTokenKind.superscript ||
          next.kind == TexTokenKind.subscript ||
          (next.kind == TexTokenKind.other &&
              (next.text == "'" || next.text == '\u2019'))) {
        cursor.next();
        current = _attachSingleScript(current, next);
        continue;
      }
      break;
    }
    return current;
  }

  MathNode _attachSingleScript(MathNode current, TexToken scriptTok) {
    final bool isPrime =
        scriptTok.kind == TexTokenKind.other &&
        (scriptTok.text == "'" || scriptTok.text == '\u2019');
    if (isPrime) {
      final String primeStr = _consumePrimeRun(scriptTok);
      final SymbolNode primeNode = SymbolNode(
        span: scriptTok.span,
        value: primeStr,
        command: 'prime_char',
      );
      if (current is ScriptNode) {
        if (current.superscript != null) {
          throw TexMathSyntaxError(
            'Prime causes double exponent.',
            errorClass: TexMathErrorClass.doubleScript,
            span: scriptTok.span,
          );
        }
        return ScriptNode(
          span: current.span.merge(scriptTok.span),
          base: current.base,
          subscript: current.subscript,
          superscript: primeNode,
          limitsAboveBelow: current.limitsAboveBelow,
          presubscript: current.presubscript,
          presuperscript: current.presuperscript,
        );
      }
      final bool useLimits = current is OperatorNode && current.hasLimits;
      return ScriptNode(
        span: current.span.merge(scriptTok.span),
        base: current,
        superscript: primeNode,
        limitsAboveBelow: useLimits,
      );
    }

    final bool isSup = scriptTok.kind == TexTokenKind.superscript;
    final MathNode scriptArg = _parseSingleScriptArgument(
      isSup ? '^' : '_',
      scriptTok.span,
    );

    if (current is ScriptNode) {
      if (isSup) {
        final bool existingIsPrimeOnly = _isPrimeOnlyNode(current.superscript);
        if (current.superscript != null && !existingIsPrimeOnly) {
          throw TexMathSyntaxError(
            'Double superscript.',
            errorClass: TexMathErrorClass.doubleScript,
            span: scriptTok.span,
          );
        }
        final MathNode mergedSup = existingIsPrimeOnly
            ? MathGroupNode(
                span: current.superscript!.span.merge(scriptArg.span),
                isExplicitGroup: false,
                children: <MathNode>[current.superscript!, scriptArg],
              )
            : scriptArg;
        return ScriptNode(
          span: current.span.merge(scriptArg.span),
          base: current.base,
          subscript: current.subscript,
          superscript: mergedSup,
          limitsAboveBelow: current.limitsAboveBelow,
          presubscript: current.presubscript,
          presuperscript: current.presuperscript,
        );
      } else {
        if (current.subscript != null) {
          throw TexMathSyntaxError(
            'Double subscript.',
            errorClass: TexMathErrorClass.doubleScript,
            span: scriptTok.span,
          );
        }
        return ScriptNode(
          span: current.span.merge(scriptArg.span),
          base: current.base,
          subscript: scriptArg,
          superscript: current.superscript,
          limitsAboveBelow: current.limitsAboveBelow,
          presubscript: current.presubscript,
          presuperscript: current.presuperscript,
        );
      }
    }

    final bool useLimits = current is OperatorNode && current.hasLimits;
    return ScriptNode(
      span: current.span.merge(scriptArg.span),
      base: current,
      subscript: isSup ? null : scriptArg,
      superscript: isSup ? scriptArg : null,
      limitsAboveBelow: useLimits,
    );
  }

  bool _isPrimeOnlyNode(MathNode? node) {
    return node is SymbolNode && node.command == 'prime_char';
  }

  String _consumePrimeRun(TexToken first) {
    int count = 1;
    while (true) {
      final TexToken? next = cursor.peek(skipSpaces: false);
      if (next != null &&
          next.kind == TexTokenKind.other &&
          (next.text == "'" || next.text == '\u2019')) {
        cursor.nextRaw();
        count++;
        continue;
      }
      break;
    }
    return switch (count) {
      1 => '\u2032',
      2 => '\u2033',
      3 => '\u2034',
      4 => '\u2057',
      _ => '\u2032' * count,
    };
  }

  MathNode _parseSingleScriptArgument(String marker, SourceSpan markerSpan) {
    cursor.skipIgnorable();
    final TexToken? next = cursor.peek();
    if (next == null) {
      throw TexMathSyntaxError(
        'Missing script argument after "$marker".',
        errorClass: TexMathErrorClass.missingArgument,
        span: markerSpan,
      );
    }
    if (next.kind == TexTokenKind.beginGroup) {
      return _parseRequiredArgNode(marker);
    }
    // Single-token script (`x^2`, `x^\alpha`, `x^\infty`).
    final TexToken tok = cursor.next()!;
    final MathNode? node = _parseAtom(tok);
    return node ?? MathGroupNode(span: tok.span, children: const <MathNode>[]);
  }

  MathNode _applyLimitsModifier(
    MathNode target,
    bool? limits,
    SourceSpan span,
  ) {
    if (target is OperatorNode) {
      return OperatorNode(
        span: target.span.merge(span),
        operatorName: target.operatorName,
        hasLimits: limits ?? target.isLarge,
        isLarge: target.isLarge,
        command: target.command,
        isDeclared: target.isDeclared,
        isExtensible: target.isExtensible,
      );
    }
    if (target is ScriptNode) {
      final MathNode modBase = target.base is OperatorNode
          ? _applyLimitsModifier(target.base, limits, span)
          : target.base;
      return ScriptNode(
        span: target.span.merge(span),
        base: modBase,
        subscript: target.subscript,
        superscript: target.superscript,
        limitsAboveBelow: limits ?? target.limitsAboveBelow,
        presubscript: target.presubscript,
        presuperscript: target.presuperscript,
      );
    }
    return target;
  }

  void _consumeNewlineStarAndDimen(SourceSpan nlSpan) {
    consumeOptionalStar();
    final TexToken? next = cursor.peek(skipSpaces: false);
    if (next != null && next.kind == TexTokenKind.other && next.text == '[') {
      final String rawDim = (readOptionalBracketText('\\') ?? '').trim();
      if (rawDim.isNotEmpty && !isValidTexDimension(rawDim)) {
        throw TexMathSyntaxError(
          'Bracket argument to \\\\ must be a valid TeX dimension: "$rawDim".',
          errorClass: TexMathErrorClass.misplacedNewline,
          span: next.span,
        );
      }
    }
  }

  bool _isInfixFractionCommand(String cs) {
    return cs == 'over' ||
        cs == 'atop' ||
        cs == 'choose' ||
        cs == 'brace' ||
        cs == 'brack' ||
        cs == 'above' ||
        cs == 'overwithdelims' ||
        cs == 'atopwithdelims' ||
        cs == 'abovewithdelims';
  }

  _InfixFractionInfo _parseInfixFractionCommand(String cs, SourceSpan span) {
    String? leftDelim;
    String? rightDelim;
    double? thicknessEm;
    if (cs == 'choose') {
      leftDelim = '(';
      rightDelim = ')';
      thicknessEm = 0.0;
    } else if (cs == 'brack') {
      leftDelim = '[';
      rightDelim = ']';
      thicknessEm = 0.0;
    } else if (cs == 'brace') {
      leftDelim = '{';
      rightDelim = '}';
      thicknessEm = 0.0;
    } else if (cs == 'atop') {
      thicknessEm = 0.0;
    } else if (cs.endsWith('withdelims')) {
      leftDelim = readDelimiterToken(cs);
      rightDelim = readDelimiterToken(cs);
      if (cs == 'atopwithdelims') {
        thicknessEm = 0.0;
      }
    }
    if (cs == 'above' || cs == 'abovewithdelims') {
      thicknessEm = parseTexDimensionToEm(_readUnbracedDimen(cs));
    }
    return _InfixFractionInfo(
      leftDelim: leftDelim,
      rightDelim: rightDelim,
      thicknessEm: thicknessEm,
    );
  }

  String _readUnbracedDimen(String cs) {
    cursor.skipIgnorable();
    final StringBuffer buf = StringBuffer();
    while (true) {
      final TexToken? next = cursor.peek(skipSpaces: false);
      if (next == null || next.kind == TexTokenKind.space) {
        break;
      }
      if (next.kind == TexTokenKind.other && _isDimenScalarText(next.text)) {
        buf.write(cursor.nextRaw()!.text);
        continue;
      }
      if (next.kind == TexTokenKind.letter) {
        buf.write(cursor.nextRaw()!.text);
        if (buf.length >= 2 && _dimenSuffixPattern.hasMatch(buf.toString())) {
          break;
        }
        continue;
      }
      break;
    }
    final String dim = buf.toString().trim();
    if (dim.isEmpty) {
      throw TexMathSyntaxError(
        'Missing dimension for \\$cs.',
        errorClass: TexMathErrorClass.missingArgument,
        span: cursor.currentSpan(),
      );
    }
    return dim;
  }

  List<TexToken> _readTokensUntilCommand(
    String stopCommand,
    SourceSpan startSpan,
  ) {
    final List<TexToken> out = <TexToken>[];
    while (true) {
      final TexToken? tok = cursor.nextRaw();
      if (tok == null) {
        throw TexMathSyntaxError(
          'Missing \\$stopCommand in \\root expression.',
          errorClass: TexMathErrorClass.missingArgument,
          span: startSpan,
        );
      }
      if (tok.kind == TexTokenKind.controlSequence && tok.text == stopCommand) {
        return out;
      }
      out.add(tok);
    }
  }

  List<List<TexToken>> _splitTokensOnNewline(List<TexToken> tokens) {
    final List<List<TexToken>> lines = <List<TexToken>>[];
    List<TexToken> current = <TexToken>[];
    int depth = 0;
    for (final TexToken t in tokens) {
      if (t.kind == TexTokenKind.beginGroup) {
        depth++;
      } else if (t.kind == TexTokenKind.endGroup && depth > 0) {
        depth--;
      } else if (depth == 0 &&
          t.kind == TexTokenKind.controlSequence &&
          (t.text == '\\' || t.text == 'cr')) {
        lines.add(current);
        current = <TexToken>[];
        continue;
      }
      current.add(t);
    }
    lines.add(current);
    return lines;
  }

  int _parseCodePoint(String raw, SourceSpan span) {
    final String cleaned = raw.trim();
    int? parsed;
    if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) {
      parsed = int.tryParse(cleaned.substring(2), radix: 16);
    } else if (cleaned.startsWith('x') || cleaned.startsWith('X')) {
      parsed = int.tryParse(cleaned.substring(1), radix: 16);
    } else if (_isAllAsciiDigits(cleaned)) {
      parsed = int.tryParse(cleaned);
    } else if (_isAllHexDigits(cleaned)) {
      parsed = int.tryParse(cleaned, radix: 16);
    }
    if (parsed == null || !_isValidXmlScalar(parsed)) {
      throw TexMathSyntaxError(
        'Invalid Unicode code point "$raw".',
        span: span,
      );
    }
    return parsed;
  }

  int _readTexCharCharCode(String raw, int radix, SourceSpan span) {
    final int? parsed = int.tryParse(raw, radix: radix);
    if (parsed == null || !_isValidXmlScalar(parsed)) {
      throw TexMathSyntaxError('Invalid character code "$raw".', span: span);
    }
    return parsed;
  }

  static bool _isValidXmlScalar(int cp) {
    if (cp < 0 || cp > 0x10FFFF) {
      return false;
    }
    if (cp < 0x20) {
      return cp == 0x09 || cp == 0x0A || cp == 0x0D;
    }
    if (cp == 0x7F || cp == 0xFFFE || cp == 0xFFFF) {
      return false;
    }
    return cp < 0xD800 || cp > 0xDFFF;
  }

  int _readTexCharCodePoint(SourceSpan span) {
    cursor.skipIgnorable();
    final TexToken? first = cursor.peek(skipSpaces: false);
    if (first == null) {
      throw TexMathSyntaxError(
        'Missing character code after \\char.',
        errorClass: TexMathErrorClass.missingArgument,
        span: span,
      );
    }
    int radix = 10;
    if (first.kind == TexTokenKind.other && first.text == '"') {
      cursor.nextRaw();
      radix = 16;
    } else if (first.kind == TexTokenKind.other && first.text == "'") {
      cursor.nextRaw();
      radix = 8;
    }
    final StringBuffer digits = StringBuffer();
    while (true) {
      final TexToken? tok = cursor.peek(skipSpaces: false);
      if (tok == null) {
        break;
      }
      final String ch = tok.text;
      final bool matches = _isDigitInRadix(ch, radix);
      if (!matches) {
        break;
      }
      digits.write(cursor.nextRaw()!.text);
    }
    if (digits.isEmpty) {
      throw TexMathSyntaxError(
        'Invalid character constant after \\char.',
        span: span,
      );
    }
    return _readTexCharCharCode(digits.toString(), radix, span);
  }
}

/// Text-mode parser handling `\text{...}`, `\textbf{...}`, `\emph{...}`,
/// text accents, ligatures, `$...$` inline math, and `textcomp` symbols.
final class _TextModeParser {
  _TextModeParser({
    required this.host,
    required this.tokens,
    required this.span,
    required this.styleCommand,
  });

  final _TexParser host;
  final List<TexToken> tokens;
  final SourceSpan span;
  final String styleCommand;

  int _index = 0;

  TextNode parse() {
    final List<MathNode> children = _parseRange(
      stopAtCloseBrace: false,
      activeStyle: styleCommand,
    );
    if (children.length == 1 && children.first is TextNode) {
      final TextNode single = children.first as TextNode;
      if (single.styleCommand == styleCommand && single.children.isEmpty) {
        return TextNode(
          span: span,
          text: single.text,
          styleCommand: styleCommand,
        );
      }
    }
    final StringBuffer plain = StringBuffer();
    for (final MathNode child in children) {
      if (child is TextNode) {
        plain.write(child.text);
      }
    }
    return TextNode(
      span: span,
      text: plain.toString(),
      styleCommand: styleCommand,
      children: children,
    );
  }

  List<MathNode> _parseRange({
    required bool stopAtCloseBrace,
    required String activeStyle,
  }) {
    final List<MathNode> items = <MathNode>[];
    final StringBuffer textBuf = StringBuffer();

    void flushText() {
      if (textBuf.isNotEmpty) {
        items.add(
          TextNode(
            span: span,
            text: textBuf.toString(),
            styleCommand: activeStyle,
          ),
        );
        textBuf.clear();
      }
    }

    while (_index < tokens.length) {
      final TexToken tok = tokens[_index++];
      if (tok.kind == TexTokenKind.comment) {
        continue;
      }
      if (tok.kind == TexTokenKind.beginGroup) {
        flushText();
        final List<MathNode> nested;
        host.enterNesting(tok.span);
        try {
          nested = _parseRange(
            stopAtCloseBrace: true,
            activeStyle: activeStyle,
          );
        } finally {
          host.exitNesting();
        }
        items.addAll(nested);
        continue;
      }
      if (tok.kind == TexTokenKind.endGroup) {
        if (stopAtCloseBrace) {
          flushText();
          return items;
        }
        throw TexMathSyntaxError(
          'Extra closing brace "}" in text mode.',
          errorClass: TexMathErrorClass.extraBrace,
          span: tok.span,
        );
      }
      if (tok.kind == TexTokenKind.mathShift) {
        flushText();
        final List<TexToken> mathTokens = <TexToken>[];
        int braceDepth = 0;
        bool closed = false;
        while (_index < tokens.length) {
          final TexToken mt = tokens[_index++];
          if (mt.kind == TexTokenKind.beginGroup) {
            braceDepth++;
          } else if (mt.kind == TexTokenKind.endGroup && braceDepth > 0) {
            braceDepth--;
          } else if (mt.kind == TexTokenKind.mathShift && braceDepth == 0) {
            closed = true;
            break;
          }
          mathTokens.add(mt);
        }
        if (!closed) {
          throw TexMathSyntaxError(
            'Unterminated inline math \$...\$ inside text.',
            span: tok.span,
          );
        }
        items.add(
          host.parseSubTokens(
            mathTokens,
            span: tok.span,
            displayMode: TexMathDisplayMode.inline,
          ),
        );
        continue;
      }
      if (tok.kind == TexTokenKind.active) {
        textBuf.write('\u00A0');
        continue;
      }
      if (tok.kind == TexTokenKind.space) {
        textBuf.write(' ');
        continue;
      }
      if (tok.kind == TexTokenKind.superscript ||
          tok.kind == TexTokenKind.subscript) {
        throw TexMathSyntaxError(
          '"${tok.text}" is allowed only in math mode.',
          span: tok.span,
        );
      }
      if (tok.kind == TexTokenKind.alignmentTab) {
        throw TexMathSyntaxError(
          'Misplaced "&" in text mode.',
          errorClass: TexMathErrorClass.misplacedAlignmentTab,
          span: tok.span,
        );
      }
      if (tok.kind == TexTokenKind.other) {
        // Handle TeX text ligatures (`---`, `--`, `` `` ``, `''`, `` ` ``, `'`).
        if (tok.text == '-' &&
            _index < tokens.length &&
            tokens[_index].text == '-') {
          _index++;
          if (_index < tokens.length && tokens[_index].text == '-') {
            _index++;
            textBuf.write('\u2014');
          } else {
            textBuf.write('\u2013');
          }
          continue;
        }
        if (tok.text == '`' &&
            _index < tokens.length &&
            tokens[_index].text == '`') {
          _index++;
          textBuf.write('\u201C');
          continue;
        }
        if (tok.text == "'" &&
            _index < tokens.length &&
            tokens[_index].text == "'") {
          _index++;
          textBuf.write('\u201D');
          continue;
        }
        if (tok.text == '`') {
          textBuf.write('\u2018');
          continue;
        }
        if (tok.text == "'") {
          textBuf.write('\u2019');
          continue;
        }
        textBuf.write(tok.text);
        continue;
      }
      if (tok.kind == TexTokenKind.letter) {
        textBuf.write(tok.text);
        continue;
      }

      // Control sequence inside text mode.
      if (tok.kind == TexTokenKind.controlSequence) {
        if (tok.isControlWord) {
          while (_index < tokens.length &&
              tokens[_index].kind == TexTokenKind.space) {
            _index++;
          }
        }
        final String cs = tok.text;
        // Text accents (`\'`, `\"`, `\^`, etc.)
        final String? combining = _textAccentCombining[cs];
        if (combining != null) {
          final String arg = _readTextArgString();
          if (arg.isNotEmpty) {
            textBuf.write(_composeAccent(arg[0], combining));
            if (arg.length > 1) {
              textBuf.write(arg.substring(1));
            }
          }
          continue;
        }
        // Font wrappers inside text (`\textbf`, `\textit`, `\emph`, `\textsf`, `\texttt`, `\textrm`, `\textbb`, `\textbfbb`)
        if (cs == 'textbf' ||
            cs == 'textit' ||
            cs == 'textsf' ||
            cs == 'texttt' ||
            cs == 'textrm' ||
            cs == 'textup' ||
            cs == 'textnormal' ||
            cs == 'emph' ||
            (host.activePackages.has('bboldx') &&
                (cs == 'textbb' || cs == 'textbfbb'))) {
          flushText();
          final List<TexToken> innerTokens = _readTextArgTokens();
          final String nextStyle = cs == 'emph'
              ? (activeStyle == 'textit' ? 'textrm' : 'textit')
              : cs;
          final TextNode nested;
          host.enterNesting(tok.span);
          try {
            nested = _TextModeParser(
              host: host,
              tokens: innerTokens,
              span: tok.span,
              styleCommand: nextStyle,
            ).parse();
          } finally {
            host.exitNesting();
          }
          items.add(nested);
          continue;
        }

        // Literal escaped punctuation in text mode
        if (cs == ' ' ||
            cs == r'$' ||
            cs == '%' ||
            cs == '&' ||
            cs == '#' ||
            cs == '_' ||
            cs == '{' ||
            cs == '}') {
          textBuf.write(cs);
          continue;
        }
        final String? textSym = _textLiteralCommands[cs];
        if (textSym != null) {
          textBuf.write(textSym);
          continue;
        }
        if (host.activePackages.has('textcomp')) {
          final TexSymbolSpec? tc = textcompSymbolMap[cs];
          if (tc != null) {
            textBuf.write(tc.unicode);
            continue;
          }
        }
        if (host.activePackages.has('gensymb')) {
          final TexSymbolSpec? gen = gensymbSymbolMap[cs];
          if (gen != null) {
            textBuf.write(gen.unicode);
            continue;
          }
        }
        if (cs == 'ref' || cs == 'eqref') {
          flushText();
          final String lbl = _readTextArgString().trim();
          items.add(
            TagNode(
              span: tok.span,
              label: host._labels[lbl] ?? '???',
              targetId: lbl,
              isStarred: cs == 'ref',
              isReference: true,
            ),
          );
          continue;
        }
        if (host.activePackages.has('noundefined')) {
          flushText();
          items.add(
            ColorNode(
              span: tok.span,
              role: TexMathColorRole.error,
              colorValue: '#FF0000',
              children: <MathNode>[
                TextNode(span: tok.span, text: '\\$cs', styleCommand: 'text'),
              ],
            ),
          );
          continue;
        }
        throw TexMathSyntaxError(
          'Undefined control sequence \\$cs inside text mode.',
          errorClass: TexMathErrorClass.undefinedControlSequence,
          span: tok.span,
        );
      }
    }

    if (stopAtCloseBrace) {
      throw TexMathSyntaxError(
        'Missing closing brace "}" in text mode.',
        errorClass: TexMathErrorClass.missingBrace,
        span: span,
      );
    }
    flushText();
    return items;
  }

  List<TexToken> _readTextArgTokens() {
    while (_index < tokens.length &&
        tokens[_index].kind == TexTokenKind.space) {
      _index++;
    }
    if (_index >= tokens.length) {
      throw TexMathSyntaxError(
        'Missing argument in text mode.',
        errorClass: TexMathErrorClass.missingArgument,
        span: span,
      );
    }
    final TexToken first = tokens[_index++];
    if (first.kind != TexTokenKind.beginGroup) {
      return <TexToken>[first];
    }
    final List<TexToken> out = <TexToken>[];
    int depth = 1;
    while (_index < tokens.length) {
      final TexToken tok = tokens[_index++];
      if (tok.kind == TexTokenKind.beginGroup) {
        depth++;
        out.add(tok);
      } else if (tok.kind == TexTokenKind.endGroup) {
        depth--;
        if (depth == 0) {
          return out;
        }
        out.add(tok);
      } else {
        out.add(tok);
      }
    }
    throw TexMathSyntaxError(
      'Missing closing brace "}" in text mode.',
      errorClass: TexMathErrorClass.missingBrace,
      span: first.span,
    );
  }

  String _readTextArgString() {
    final List<TexToken> argTokens = _readTextArgTokens();
    return argTokens.map((TexToken t) => t.text).join();
  }
}

enum _StopMode { eof, closeBrace, rightDelim, envCell }

final class _AutoTagCounter {
  int value = 0;

  int next() => ++value;
}

final class _SeqResult {
  const _SeqResult({
    required this.nodes,
    required this.stopReason,
    required this.rowHasNoTag,
    required this.rowTag,
    this.rowLabel,
    this.cellBackground,
    this.rowBackground,
    this.columnBackground,
  });

  final List<MathNode> nodes;
  final String? stopReason;
  final bool rowHasNoTag;
  final TagNode? rowTag;
  final String? rowLabel;
  final String? cellBackground;
  final String? rowBackground;
  final String? columnBackground;
}

const Set<String> _taggableDisplayEnvironments = <String>{
  'equation',
  'equation*',
  'align',
  'align*',
  'gather',
  'gather*',
  'multline',
  'multline*',
  'flalign',
  'flalign*',
  'alignat',
  'alignat*',
  'xalignat',
  'xalignat*',
  'xxalignat',
  'eqnarray',
  'eqnarray*',
  'eqalignno',
  'leqalignno',
  'numcases',
  'subnumcases',
};

bool _containsTaggableDisplayEnvironment(List<MathNode> nodes) {
  for (final MathNode node in nodes) {
    if (_nodeContainsTaggableDisplayEnvironment(node)) {
      return true;
    }
  }
  return false;
}

bool _nodeContainsTaggableDisplayEnvironment(MathNode node) {
  switch (node) {
    case MatrixNode(:final String environment):
      return _taggableDisplayEnvironments.contains(environment);
    case MathGroupNode(:final String? role, :final List<MathNode> children):
      if (role != null && _taggableDisplayEnvironments.contains(role)) {
        return true;
      }
      return _containsTaggableDisplayEnvironment(children);
    case TagNode(
      :final bool isLabelDefinition,
      :final bool isReference,
      :final MathNode? body,
    ):
      if (!isLabelDefinition && !isReference) {
        return true;
      }
      return body != null && _nodeContainsTaggableDisplayEnvironment(body);
    case MathRootNode(:final List<MathNode> children):
    case DelimiterNode(:final List<MathNode> children):
    case StyleNode(:final List<MathNode> children):
    case ColorNode(:final List<MathNode> children):
      return _containsTaggableDisplayEnvironment(children);
    default:
      return false;
  }
}

final class _OpenEnvFrame {
  const _OpenEnvFrame({
    required this.name,
    required this.span,
    this.userEnvDef,
  });

  final String name;
  final SourceSpan span;
  final TexUserEnvDef? userEnvDef;
}

final class _InfixFractionInfo {
  const _InfixFractionInfo({this.leftDelim, this.rightDelim, this.thicknessEm});

  final String? leftDelim;
  final String? rightDelim;
  final double? thicknessEm;
}

bool _isSingleOuterBracePair(List<TexToken> tokens) {
  int depth = 0;
  for (int i = 0; i < tokens.length; i++) {
    if (tokens[i].kind == TexTokenKind.beginGroup) {
      depth++;
    } else if (tokens[i].kind == TexTokenKind.endGroup) {
      depth--;
      if (depth == 0 && i < tokens.length - 1) {
        return false;
      }
    }
  }
  return depth == 0;
}

SourceSpan _mergeSpanList(SourceSpan fallback, List<MathNode> nodes) {
  if (nodes.isEmpty) {
    return fallback;
  }
  SourceSpan merged = nodes.first.span;
  for (int i = 1; i < nodes.length; i++) {
    merged = merged.merge(nodes[i].span);
  }
  return merged;
}

TexMathStyle? _styleSwitchForCommand(String cs) {
  switch (cs) {
    case 'displaystyle':
      return TexMathStyle.display;
    case 'textstyle':
      return TexMathStyle.text;
    case 'scriptstyle':
      return TexMathStyle.script;
    case 'scriptscriptstyle':
      return TexMathStyle.scriptScript;
    default:
      return null;
  }
}

TexMathFontVariant? _legacyFontSwitchForCommand(String cs) {
  switch (cs) {
    case 'rm':
      return TexMathFontVariant.normal;
    case 'bf':
      return TexMathFontVariant.bold;
    case 'it':
      return TexMathFontVariant.italic;
    case 'mit':
      return TexMathFontVariant.italic;
    case 'sf':
      return TexMathFontVariant.sansSerif;
    case 'tt':
      return TexMathFontVariant.monospace;
    case 'cal':
      return TexMathFontVariant.script;
    default:
      return null;
  }
}

TexMathFontVariant _mathAlphabetVariant(String cs) {
  switch (cs) {
    case 'mathrm':
    case 'mathup':
      return TexMathFontVariant.normal;
    case 'mathbf':
    case 'mathbfup':
      return TexMathFontVariant.bold;
    case 'mathit':
      return TexMathFontVariant.italic;
    case 'mathbfit':
      return TexMathFontVariant.boldItalic;
    case 'mathbb':
    case 'Bbb':
      return TexMathFontVariant.doubleStruck;
    case 'mathfrak':
    case 'frak':
      return TexMathFontVariant.fraktur;
    case 'mathbffrak':
      return TexMathFontVariant.boldFraktur;
    case 'mathscr':
    case 'mathcal':
      return TexMathFontVariant.script;
    case 'mathbfcal':
    case 'mathbfscr':
      return TexMathFontVariant.boldScript;
    case 'mathsf':
    case 'mathsfup':
      return TexMathFontVariant.sansSerif;
    case 'mathbfsf':
    case 'mathbfsfup':
      return TexMathFontVariant.boldSansSerif;
    case 'mathsfit':
      return TexMathFontVariant.sansSerifItalic;
    case 'mathbfsfit':
      return TexMathFontVariant.sansSerifBoldItalic;
    case 'mathtt':
      return TexMathFontVariant.monospace;
    default:
      return TexMathFontVariant.italic;
  }
}

bool _isDigitString(String text) =>
    text.length == 1 &&
    text.codeUnitAt(0) >= 0x30 &&
    text.codeUnitAt(0) <= 0x39;

Map<String, String> _parseKeyValues(String raw) {
  final Map<String, String> result = <String, String>{};
  for (final String part in raw.split(',')) {
    final int eq = part.indexOf('=');
    if (eq < 0) {
      continue;
    }
    result[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }
  return result;
}

String _extractOperatorText(MathNode node) {
  switch (node) {
    case SymbolNode(:final String value):
      return value;
    case TextNode(:final String text):
      return text;
    case SpaceNode():
      return '\u2006';
    case MathGroupNode(:final List<MathNode> children):
    case MathRootNode(:final List<MathNode> children):
    case StyleNode(:final List<MathNode> children):
    case ColorNode(:final List<MathNode> children):
      return children.map(_extractOperatorText).join();
    case OperatorNode(:final String operatorName):
      return operatorName;
    case FractionNode():
    case ScriptNode():
    case RadicalNode():
    case AccentNode():
    case DelimiterNode():
    case MatrixNode():
    case TagNode():
    case ErrorNode():
      return '';
  }
}

List<MathNode> _unmodifiableNodes(List<MathNode> nodes) =>
    nodes.isEmpty ? const <MathNode>[] : List<MathNode>.unmodifiable(nodes);

const Map<String, String> _textAccentCombining = <String, String>{
  "'": '\u0301',
  '`': '\u0300',
  '^': '\u0302',
  '"': '\u0308',
  '~': '\u0303',
  '=': '\u0304',
  '.': '\u0307',
  'u': '\u0306',
  'v': '\u030C',
  'H': '\u030B',
  'c': '\u0327',
  'd': '\u0323',
  'r': '\u030A',
};

const Map<String, String> _textLiteralCommands = <String, String>{
  'S': '\u00A7',
  'P': '\u00B6',
  'dag': '\u2020',
  'dagger': '\u2020',
  'ddag': '\u2021',
  'ddagger': '\u2021',
  'AA': '\u212B',
  'aa': '\u00E5',
  'AE': '\u00C6',
  'ae': '\u00E6',
  'OE': '\u0152',
  'oe': '\u0153',
  'O': '\u00D8',
  'o': '\u00F8',
  'L': '\u0141',
  'l': '\u0142',
  'ss': '\u00DF',
  'i': '\u0131',
  'j': '\u0237',
  'ldots': '\u2026',
  'dots': '\u2026',
  'copyright': '\u00A9',
  'pounds': '\u00A3',
  ',': '\u2006',
  'quad': '\u2003',
  'qquad': '\u2003\u2003',
  'enspace': '\u2002',
};

String _composeAccent(String ch, String combining) {
  const Map<(String, String), String> precomposed = <(String, String), String>{
    ('e', '\u0301'): '\u00E9',
    ('E', '\u0301'): '\u00C9',
    ('a', '\u0301'): '\u00E1',
    ('a', '\u0300'): '\u00E0',
    ('e', '\u0300'): '\u00E8',
    ('i', '\u0308'): '\u00EF',
    ('o', '\u0308'): '\u00F6',
    ('u', '\u0308'): '\u00FC',
    ('a', '\u0308'): '\u00E4',
    ('o', '\u0302'): '\u00F4',
    ('e', '\u0302'): '\u00EA',
    ('a', '\u0302'): '\u00E2',
    ('n', '\u0303'): '\u00F1',
    ('c', '\u0327'): '\u00E7',
  };
  return precomposed[(ch, combining)] ?? '$ch$combining';
}

final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');
final RegExp _htmlTagNamePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9]*)');

String? _parseHtmlTagName(String tag) {
  if (tag.length < 3) {
    return null;
  }
  final String inner = tag.substring(1, tag.length - 1).trim();
  if (inner.isEmpty || inner.startsWith('!') || inner.startsWith('?')) {
    return null;
  }
  final bool isClosing = inner.startsWith('/');
  final String body = (isClosing ? inner.substring(1) : inner).trimLeft();
  if (!isClosing && body.endsWith('/')) {
    return null;
  }
  final RegExpMatch? m = _htmlTagNamePattern.firstMatch(body);
  if (m == null) {
    return null;
  }
  return '${isClosing ? '/' : ''}${m.group(1)!.toLowerCase()}';
}

String? _texHtmlTagStyle(String tagName) {
  switch (tagName) {
    case 'em':
    case 'i':
      return 'textit';
    case 'strong':
    case 'b':
      return 'textbf';
    case 'code':
    case 'tt':
      return 'texttt';
    default:
      return null;
  }
}

final RegExp _newExtArrowCsPattern = RegExp(r'^\\([a-zA-Z]+|.)$');
final RegExp _newExtArrowSpacePattern = RegExp(r'^\d+,\d+$');
final RegExp _dimenSuffixPattern = RegExp(
  r'(pt|pc|in|bp|cm|mm|dd|cc|sp|em|ex|mu|px)$',
);

bool _isAsciiDigitUnit(int c) => c >= 0x30 && c <= 0x39;

bool _isHexDigitUnit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x46) ||
    (c >= 0x61 && c <= 0x66);

bool _isDimenScalarText(String text) {
  if (text.length != 1) {
    return false;
  }
  final int c = text.codeUnitAt(0);
  return _isAsciiDigitUnit(c) || c == 0x2E || c == 0x2B || c == 0x2D;
}

bool _isAllAsciiDigits(String text) {
  if (text.isEmpty) {
    return false;
  }
  for (int i = 0; i < text.length; i++) {
    if (!_isAsciiDigitUnit(text.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

bool _isAllHexDigits(String text) {
  if (text.isEmpty) {
    return false;
  }
  for (int i = 0; i < text.length; i++) {
    if (!_isHexDigitUnit(text.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

bool _isDigitInRadix(String ch, int radix) {
  if (ch.length != 1) {
    return false;
  }
  final int c = ch.codeUnitAt(0);
  return switch (radix) {
    16 => _isHexDigitUnit(c),
    8 => c >= 0x30 && c <= 0x37,
    _ => _isAsciiDigitUnit(c),
  };
}
