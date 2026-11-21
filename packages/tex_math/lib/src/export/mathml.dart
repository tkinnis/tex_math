import '../ast.dart';
import '../format_utils.dart';
import '../options.dart';

/// Serializes [node] into a Presentation MathML XML string.
///
/// Traverses all 16 sealed [MathNode] subclasses exhaustively to produce clean,
/// accessible MathML suitable for screen readers and external interchange.
String mathNodeToMathMl(MathNode node, {bool includeXmlNamespace = true}) {
  final String body = _emitMathMlNode(node);
  if (node is MathRootNode) {
    return body;
  }
  final String nsAttr = includeXmlNamespace
      ? ' xmlns="http://www.w3.org/1998/Math/MathML"'
      : '';
  return '<math$nsAttr>$body</math>';
}

String _emitMathMlNode(MathNode node) {
  switch (node) {
    case MathRootNode(
      :final List<MathNode> children,
      :final TexMathDisplayMode displayMode,
    ):
      final String display = displayMode == TexMathDisplayMode.display
          ? 'block'
          : 'inline';
      final String inner = _emitMathMlList(children);
      return '<math xmlns="http://www.w3.org/1998/Math/MathML" display="$display">$inner</math>';

    case MathGroupNode(
      :final List<MathNode> children,
      :final TexMathFontVariant? fontVariant,
      :final String? role,
      :final Map<String, String> attributes,
    ):
      final String inner = _emitMathMlList(children);
      if (role == 'phantom' || role == 'hphantom' || role == 'vphantom') {
        return '<mphantom>$inner</mphantom>';
      }
      if (role == 'boxed') {
        return '<menclose notation="box">$inner</menclose>';
      }
      if (role == 'cancel') {
        return '<menclose notation="updiagonalstrike">$inner</menclose>';
      }
      if (role == 'bcancel') {
        return '<menclose notation="downdiagonalstrike">$inner</menclose>';
      }
      if (role == 'xcancel') {
        return '<menclose notation="updiagonalstrike downdiagonalstrike">$inner</menclose>';
      }
      if (role == 'cancelto' && children.length >= 2) {
        return '<msup><menclose notation="updiagonalstrike">${_emitMathMlNode(children[0])}</menclose>${_emitMathMlNode(children[1])}</msup>';
      }
      if (role == 'enclose') {
        final String notation = attributes['notation'] ?? 'box';
        return '<menclose notation="${_escapeXml(notation)}">$inner</menclose>';
      }
      if (role == 'toggle') {
        return '<maction actiontype="toggle">$inner</maction>';
      }
      if ((role == 'mathtip' || role == 'texttip') && children.length >= 2) {
        return '<maction actiontype="tooltip">${_emitMathMlNode(children[0])}${_emitMathMlNode(children[1])}</maction>';
      }
      if (role == 'href' && attributes.containsKey('href')) {
        return '<mrow href="${_escapeXml(attributes['href']!)}">$inner</mrow>';
      }
      if (role == 'bbox') {
        final String bg = attributes['background'] ?? '';
        final String attr = bg.isEmpty
            ? ''
            : ' mathbackground="${_escapeXml(bg)}"';
        return '<mpadded$attr>$inner</mpadded>';
      }
      final String? variantAttr = _mathVariantAttr(fontVariant);
      if (variantAttr != null) {
        return '<mstyle mathvariant="$variantAttr">$inner</mstyle>';
      }
      if (children.length == 1) {
        return _emitMathMlNode(children.first);
      }
      return '<mrow>$inner</mrow>';

    case SymbolNode(
      :final String value,
      :final TexMathAtomClass? atomClass,
      :final TexMathFontVariant? fontVariant,
    ):
      final String escaped = _escapeXml(value);
      final String? rawVariant = _mathVariantAttr(fontVariant);
      final String mv = rawVariant == null ? '' : ' mathvariant="$rawVariant"';
      if (_isDigitRun(value)) {
        return '<mn$mv>$escaped</mn>';
      }
      if (atomClass == TexMathAtomClass.bin ||
          atomClass == TexMathAtomClass.rel ||
          atomClass == TexMathAtomClass.open ||
          atomClass == TexMathAtomClass.close ||
          atomClass == TexMathAtomClass.punct ||
          atomClass == TexMathAtomClass.op ||
          _isOperatorChar(value)) {
        return '<mo$mv>$escaped</mo>';
      }
      final String miVariant =
          (rawVariant == 'italic' && value.runes.length == 1) ? '' : mv;
      return '<mi$miVariant>$escaped</mi>';

    case OperatorNode(:final String operatorName, :final bool isLarge):
      final String escaped = _escapeXml(operatorName);
      if (isLarge || _isSymbolOperator(operatorName)) {
        return '<mo>$escaped</mo>';
      }
      return '<mi>$escaped</mi>';

    case FractionNode(
      :final MathNode numerator,
      :final MathNode denominator,
      :final double? ruleThicknessEm,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
      :final bool isBevelled,
    ):
      final String num = _emitMathMlNode(numerator);
      final String den = _emitMathMlNode(denominator);
      final StringBuffer attrs = StringBuffer();
      if (ruleThicknessEm != null) {
        attrs.write(
          ' linethickness="${ruleThicknessEm == 0 ? '0' : '${ruleThicknessEm}em'}"',
        );
      }
      if (isBevelled) {
        attrs.write(' bevelled="true"');
      }
      final String frac = '<mfrac$attrs>$num$den</mfrac>';
      if (leftDelimiter != null || rightDelimiter != null) {
        final String open = leftDelimiter == null
            ? ''
            : '<mo stretchy="true">${_escapeXml(leftDelimiter)}</mo>';
        final String close = rightDelimiter == null
            ? ''
            : '<mo stretchy="true">${_escapeXml(rightDelimiter)}</mo>';
        return '<mrow>$open$frac$close</mrow>';
      }
      return frac;

    case ScriptNode(
      :final MathNode base,
      :final MathNode? subscript,
      :final MathNode? superscript,
      :final bool limitsAboveBelow,
      :final MathNode? presubscript,
      :final MathNode? presuperscript,
    ):
      final String baseMl = _emitMathMlNode(base);
      if (presubscript != null || presuperscript != null) {
        final String sub = subscript == null
            ? '<none/>'
            : _emitMathMlNode(subscript);
        final String sup = superscript == null
            ? '<none/>'
            : _emitMathMlNode(superscript);
        final String preSub = presubscript == null
            ? '<none/>'
            : _emitMathMlNode(presubscript);
        final String preSup = presuperscript == null
            ? '<none/>'
            : _emitMathMlNode(presuperscript);
        final String post = (subscript != null || superscript != null)
            ? '$sub$sup'
            : '';
        return '<mmultiscripts>$baseMl$post<mprescripts/>$preSub$preSup</mmultiscripts>';
      }
      if (limitsAboveBelow) {
        if (subscript != null && superscript != null) {
          return '<munderover>$baseMl${_emitMathMlNode(subscript)}${_emitMathMlNode(superscript)}</munderover>';
        }
        if (subscript != null) {
          return '<munder>$baseMl${_emitMathMlNode(subscript)}</munder>';
        }
        if (superscript != null) {
          return '<mover>$baseMl${_emitMathMlNode(superscript)}</mover>';
        }
        return baseMl;
      }
      if (subscript != null && superscript != null) {
        return '<msubsup>$baseMl${_emitMathMlNode(subscript)}${_emitMathMlNode(superscript)}</msubsup>';
      }
      if (subscript != null) {
        return '<msub>$baseMl${_emitMathMlNode(subscript)}</msub>';
      }
      if (superscript != null) {
        return '<msup>$baseMl${_emitMathMlNode(superscript)}</msup>';
      }
      return baseMl;

    case RadicalNode(:final MathNode radicand, :final MathNode? index):
      final String radMl = _emitMathMlNode(radicand);
      if (index != null) {
        return '<mroot>$radMl${_emitMathMlNode(index)}</mroot>';
      }
      return '<msqrt>$radMl</msqrt>';

    case AccentNode(
      :final MathNode base,
      :final String accent,
      :final bool isWide,
      :final bool isUnder,
    ):
      final String baseMl = _emitMathMlNode(base);
      final String stretchyAttr = isWide ? ' stretchy="true"' : '';
      final String accentOp =
          '<mo accent="true"$stretchyAttr>${_escapeXml(accent)}</mo>';
      return isUnder
          ? '<munder accentunder="true">$baseMl$accentOp</munder>'
          : '<mover accent="true">$baseMl$accentOp</mover>';

    case DelimiterNode(
      :final List<MathNode> children,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
      :final double? fixedSizeEm,
    ):
      final String stretchy = fixedSizeEm == 0.0 ? 'false' : 'true';
      final String open = leftDelimiter == null || leftDelimiter.isEmpty
          ? ''
          : '<mo stretchy="$stretchy">${_escapeXml(leftDelimiter)}</mo>';
      final String close = rightDelimiter == null || rightDelimiter.isEmpty
          ? ''
          : '<mo stretchy="$stretchy">${_escapeXml(rightDelimiter)}</mo>';
      return '<mrow>$open${_emitMathMlList(children)}$close</mrow>';

    case MatrixNode(
      :final List<List<MathNode>> rows,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      final StringBuffer table = StringBuffer('<mtable>');
      for (final List<MathNode> row in rows) {
        table.write('<mtr>');
        for (final MathNode cell in row) {
          table.write('<mtd>${_emitMathMlNode(cell)}</mtd>');
        }
        table.write('</mtr>');
      }
      table.write('</mtable>');
      if (leftDelimiter != null || rightDelimiter != null) {
        final String open = leftDelimiter == null || leftDelimiter.isEmpty
            ? ''
            : '<mo stretchy="true">${_escapeXml(leftDelimiter)}</mo>';
        final String close = rightDelimiter == null || rightDelimiter.isEmpty
            ? ''
            : '<mo stretchy="true">${_escapeXml(rightDelimiter)}</mo>';
        return '<mrow>$open$table$close</mrow>';
      }
      return table.toString();

    case TextNode(
      :final String text,
      :final String? styleCommand,
      :final List<MathNode> children,
    ):
      if (children.isNotEmpty) {
        return '<mrow>${_emitMathMlList(children)}</mrow>';
      }
      final String? mv = switch (styleCommand) {
        'textbf' || 'textbfbb' => 'bold',
        'textit' || 'emph' => 'italic',
        'textsf' => 'sans-serif',
        'texttt' => 'monospace',
        _ => null,
      };
      final String attr = mv == null ? '' : ' mathvariant="$mv"';
      return '<mtext$attr>${_escapeXml(text)}</mtext>';

    case SpaceNode(:final double widthEm):
      return '<mspace width="${_formatNumber(widthEm)}em"/>';

    case StyleNode(
      :final TexMathStyle style,
      :final List<MathNode> children,
      :final double? scaleEm,
    ):
      final bool? disp = switch (style) {
        TexMathStyle.display || TexMathStyle.crampedDisplay => true,
        TexMathStyle.text || TexMathStyle.crampedText => false,
        _ => null,
      };
      final StringBuffer attrs = StringBuffer();
      if (disp != null) {
        attrs.write(' displaystyle="$disp"');
      }
      if (style == TexMathStyle.script || style == TexMathStyle.crampedScript) {
        attrs.write(' scriptlevel="1"');
      } else if (style == TexMathStyle.scriptScript ||
          style == TexMathStyle.crampedScriptScript) {
        attrs.write(' scriptlevel="2"');
      }
      if (scaleEm != null) {
        attrs.write(' mathsize="${_formatNumber(scaleEm)}em"');
      }
      return '<mstyle$attrs>${_emitMathMlList(children)}</mstyle>';

    case ColorNode(
      :final TexMathColorRole role,
      :final String? colorValue,
      :final String? backgroundColor,
      :final List<MathNode> children,
    ):
      final String? fg =
          colorValue ?? (role == TexMathColorRole.error ? '#DC2626' : null);
      final StringBuffer attrs = StringBuffer();
      if (fg != null && fg.isNotEmpty) {
        attrs.write(' mathcolor="${_escapeXml(fg)}"');
      }
      if (backgroundColor != null && backgroundColor.isNotEmpty) {
        attrs.write(' mathbackground="${_escapeXml(backgroundColor)}"');
      }
      return '<mstyle$attrs>${_emitMathMlList(children)}</mstyle>';

    case TagNode(
      :final String label,
      :final bool isStarred,
      :final MathNode? body,
      :final bool isReference,
      :final bool isLabelDefinition,
    ):
      if (isLabelDefinition) {
        return '<mspace id="${_escapeXml(label)}"/>';
      }
      final String formatted = isStarred ? label : '($label)';
      final String tagMl = '<mtext>${_escapeXml(formatted)}</mtext>';
      if (isReference || body == null) {
        return tagMl;
      }
      return '<mrow>${_emitMathMlNode(body)}$tagMl</mrow>';

    case ErrorNode(:final String rawSource):
      return '<merror><mtext>${_escapeXml(rawSource)}</mtext></merror>';
  }
}

String _emitMathMlList(List<MathNode> children) {
  if (children.isEmpty) {
    return '<mrow/>';
  }
  final StringBuffer buffer = StringBuffer();
  for (final MathNode child in children) {
    buffer.write(_emitMathMlNode(child));
  }
  return buffer.toString();
}

String? _mathVariantAttr(TexMathFontVariant? variant) {
  if (variant == null) {
    return null;
  }
  switch (variant) {
    case TexMathFontVariant.normal:
      return 'normal';
    case TexMathFontVariant.bold:
      return 'bold';
    case TexMathFontVariant.italic:
      return 'italic';
    case TexMathFontVariant.boldItalic:
      return 'bold-italic';
    case TexMathFontVariant.script:
      return 'script';
    case TexMathFontVariant.boldScript:
      return 'bold-script';
    case TexMathFontVariant.fraktur:
      return 'fraktur';
    case TexMathFontVariant.boldFraktur:
      return 'bold-fraktur';
    case TexMathFontVariant.sansSerif:
      return 'sans-serif';
    case TexMathFontVariant.boldSansSerif:
      return 'bold-sans-serif';
    case TexMathFontVariant.sansSerifItalic:
      return 'sans-serif-italic';
    case TexMathFontVariant.sansSerifBoldItalic:
      return 'sans-serif-bold-italic';
    case TexMathFontVariant.monospace:
      return 'monospace';
    case TexMathFontVariant.doubleStruck:
    case TexMathFontVariant.doubleStruckBold:
    case TexMathFontVariant.doubleStruckSans:
    case TexMathFontVariant.doubleStruckMonospace:
      return 'double-struck';
  }
}

bool _isDigitRun(String value) {
  if (value.isEmpty) {
    return false;
  }
  for (int i = 0; i < value.length; i++) {
    final int cu = value.codeUnitAt(i);
    if ((cu < 0x30 || cu > 0x39) && cu != 0x2E && cu != 0x2C) {
      return false;
    }
  }
  return true;
}

bool _isOperatorChar(String value) {
  const Set<String> ops = <String>{
    '+',
    '-',
    '=',
    '<',
    '>',
    ',',
    ';',
    ':',
    '!',
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '|',
    '/',
  };
  return ops.contains(value);
}

bool _isSymbolOperator(String value) =>
    value.length == 1 && value.codeUnitAt(0) > 0x7F;

String _formatNumber(double value) => formatTrimmedNumber(value);

String _escapeXml(String text) => escapeXmlAttr(text);
