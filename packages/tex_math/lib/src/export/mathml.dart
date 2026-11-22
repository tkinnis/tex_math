import '../ast.dart';
import '../format_utils.dart';
import '../options.dart';
import '../shared/colors.dart';
import '../shared/math_symbols.dart';

/// Serializes [node] into a Presentation MathML XML string.
///
/// Traverses all 16 sealed [MathNode] subclasses exhaustively to produce clean,
/// accessible MathML suitable for screen readers and external interchange.
String mathNodeToMathMl(MathNode node, {bool includeXmlNamespace = true}) {
  final StringBuffer out = StringBuffer();
  if (node is MathRootNode) {
    _writeMathMlNode(out, node);
    return out.toString();
  }
  out.write(
    includeXmlNamespace
        ? '<math xmlns="http://www.w3.org/1998/Math/MathML">'
        : '<math>',
  );
  _writeMathMlNode(out, node);
  out.write('</math>');
  return out.toString();
}

void _writeMathMlNode(StringBuffer out, MathNode node) {
  switch (node) {
    case MathRootNode(
      :final List<MathNode> children,
      :final TexMathDisplayMode displayMode,
    ):
      final String display = displayMode == TexMathDisplayMode.display
          ? 'block'
          : 'inline';
      out.write('<math xmlns="http://www.w3.org/1998/Math/MathML" display="');
      out.write(display);
      out.write('">');
      _writeMathMlList(out, children);
      out.write('</math>');

    case MathGroupNode(
      :final List<MathNode> children,
      :final TexMathFontVariant? fontVariant,
      :final String? role,
      :final Map<String, String> attributes,
    ):
      if (role == 'phantom' || role == 'hphantom' || role == 'vphantom') {
        out.write('<mphantom>');
        _writeMathMlList(out, children);
        out.write('</mphantom>');
        return;
      }
      if (role == 'boxed') {
        out.write('<menclose notation="box">');
        _writeMathMlList(out, children);
        out.write('</menclose>');
        return;
      }
      if (role == 'cancel') {
        out.write('<menclose notation="updiagonalstrike">');
        _writeMathMlList(out, children);
        out.write('</menclose>');
        return;
      }
      if (role == 'bcancel') {
        out.write('<menclose notation="downdiagonalstrike">');
        _writeMathMlList(out, children);
        out.write('</menclose>');
        return;
      }
      if (role == 'xcancel') {
        out.write('<menclose notation="updiagonalstrike downdiagonalstrike">');
        _writeMathMlList(out, children);
        out.write('</menclose>');
        return;
      }
      if (role == 'cancelto' && children.length >= 2) {
        out.write('<msup><menclose notation="updiagonalstrike">');
        _writeMathMlNode(out, children[0]);
        out.write('</menclose>');
        _writeMathMlNode(out, children[1]);
        out.write('</msup>');
        return;
      }
      if (role == 'enclose') {
        final String notation = attributes['notation'] ?? 'box';
        out.write('<menclose notation="');
        writeEscapedXmlAttr(out, notation);
        out.write('">');
        _writeMathMlList(out, children);
        out.write('</menclose>');
        return;
      }
      if (role == 'toggle') {
        out.write('<maction actiontype="toggle">');
        _writeMathMlList(out, children);
        out.write('</maction>');
        return;
      }
      if ((role == 'mathtip' || role == 'texttip') && children.length >= 2) {
        out.write('<maction actiontype="tooltip">');
        _writeMathMlNode(out, children[0]);
        _writeMathMlNode(out, children[1]);
        out.write('</maction>');
        return;
      }
      if (role == 'href' && attributes.containsKey('href')) {
        final String hrefVal = attributes['href']!;
        if (isSafeHrefUri(hrefVal)) {
          out.write('<mrow href="');
          writeEscapedXmlAttr(out, hrefVal);
          out.write('">');
        } else {
          out.write('<mrow>');
        }
        _writeMathMlList(out, children);
        out.write('</mrow>');
        return;
      }
      if (role == 'bbox') {
        final String? bg = sanitizeMathMlColor(attributes['background']);
        if (bg == null) {
          out.write('<mpadded>');
        } else {
          out.write('<mpadded mathbackground="');
          writeEscapedXmlAttr(out, bg);
          out.write('">');
        }
        _writeMathMlList(out, children);
        out.write('</mpadded>');
        return;
      }
      final String? variantAttr = _mathVariantAttr(fontVariant);
      if (variantAttr != null) {
        out.write('<mstyle mathvariant="');
        out.write(variantAttr);
        out.write('">');
        _writeMathMlList(out, children);
        out.write('</mstyle>');
        return;
      }
      if (children.length == 1) {
        _writeMathMlNode(out, children.first);
        return;
      }
      out.write('<mrow>');
      _writeMathMlList(out, children);
      out.write('</mrow>');

    case SymbolNode(
      :final String value,
      :final TexMathAtomClass? atomClass,
      :final TexMathFontVariant? fontVariant,
    ):
      final String? rawVariant = _mathVariantAttr(fontVariant);
      final String tag;
      final String? effectiveVariant;
      if (_isDigitRun(value)) {
        tag = 'mn';
        effectiveVariant = rawVariant;
      } else if (atomClass == TexMathAtomClass.bin ||
          atomClass == TexMathAtomClass.rel ||
          atomClass == TexMathAtomClass.open ||
          atomClass == TexMathAtomClass.close ||
          atomClass == TexMathAtomClass.punct ||
          atomClass == TexMathAtomClass.op ||
          _isOperatorChar(value)) {
        tag = 'mo';
        effectiveVariant = rawVariant;
      } else {
        tag = 'mi';
        effectiveVariant = (rawVariant == 'italic' && value.runes.length == 1)
            ? null
            : rawVariant;
      }
      out.write('<');
      out.write(tag);
      if (effectiveVariant != null) {
        out.write(' mathvariant="');
        out.write(effectiveVariant);
        out.write('"');
      }
      out.write('>');
      writeEscapedXmlAttr(out, value);
      out.write('</');
      out.write(tag);
      out.write('>');

    case OperatorNode(:final String operatorName, :final bool isLarge):
      final String tag = (isLarge || _isSymbolOperator(operatorName))
          ? 'mo'
          : 'mi';
      out.write('<');
      out.write(tag);
      out.write('>');
      writeEscapedXmlAttr(out, operatorName);
      out.write('</');
      out.write(tag);
      out.write('>');

    case FractionNode(
      :final MathNode numerator,
      :final MathNode denominator,
      :final double? ruleThicknessEm,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
      :final bool isBevelled,
    ):
      final bool hasDelims = leftDelimiter != null || rightDelimiter != null;
      if (hasDelims) {
        out.write('<mrow>');
        if (leftDelimiter != null) {
          out.write('<mo stretchy="true">');
          writeEscapedXmlAttr(out, leftDelimiter);
          out.write('</mo>');
        }
      }
      out.write('<mfrac');
      if (ruleThicknessEm != null) {
        out.write(' linethickness="');
        if (ruleThicknessEm == 0) {
          out.write('0');
        } else {
          out.write(ruleThicknessEm);
          out.write('em');
        }
        out.write('"');
      }
      if (isBevelled) {
        out.write(' bevelled="true"');
      }
      out.write('>');
      _writeMathMlNode(out, numerator);
      _writeMathMlNode(out, denominator);
      out.write('</mfrac>');
      if (hasDelims) {
        if (rightDelimiter != null) {
          out.write('<mo stretchy="true">');
          writeEscapedXmlAttr(out, rightDelimiter);
          out.write('</mo>');
        }
        out.write('</mrow>');
      }

    case ScriptNode(
      :final MathNode base,
      :final MathNode? subscript,
      :final MathNode? superscript,
      :final bool limitsAboveBelow,
      :final MathNode? presubscript,
      :final MathNode? presuperscript,
    ):
      if (presubscript != null || presuperscript != null) {
        out.write('<mmultiscripts>');
        _writeMathMlNode(out, base);
        if (subscript != null || superscript != null) {
          if (subscript == null) {
            out.write('<none/>');
          } else {
            _writeMathMlNode(out, subscript);
          }
          if (superscript == null) {
            out.write('<none/>');
          } else {
            _writeMathMlNode(out, superscript);
          }
        }
        out.write('<mprescripts/>');
        if (presubscript == null) {
          out.write('<none/>');
        } else {
          _writeMathMlNode(out, presubscript);
        }
        if (presuperscript == null) {
          out.write('<none/>');
        } else {
          _writeMathMlNode(out, presuperscript);
        }
        out.write('</mmultiscripts>');
        return;
      }
      if (limitsAboveBelow) {
        if (subscript != null && superscript != null) {
          out.write('<munderover>');
          _writeMathMlNode(out, base);
          _writeMathMlNode(out, subscript);
          _writeMathMlNode(out, superscript);
          out.write('</munderover>');
          return;
        }
        if (subscript != null) {
          out.write('<munder>');
          _writeMathMlNode(out, base);
          _writeMathMlNode(out, subscript);
          out.write('</munder>');
          return;
        }
        if (superscript != null) {
          out.write('<mover>');
          _writeMathMlNode(out, base);
          _writeMathMlNode(out, superscript);
          out.write('</mover>');
          return;
        }
        _writeMathMlNode(out, base);
        return;
      }
      if (subscript != null && superscript != null) {
        out.write('<msubsup>');
        _writeMathMlNode(out, base);
        _writeMathMlNode(out, subscript);
        _writeMathMlNode(out, superscript);
        out.write('</msubsup>');
        return;
      }
      if (subscript != null) {
        out.write('<msub>');
        _writeMathMlNode(out, base);
        _writeMathMlNode(out, subscript);
        out.write('</msub>');
        return;
      }
      if (superscript != null) {
        out.write('<msup>');
        _writeMathMlNode(out, base);
        _writeMathMlNode(out, superscript);
        out.write('</msup>');
        return;
      }
      _writeMathMlNode(out, base);

    case RadicalNode(:final MathNode radicand, :final MathNode? index):
      if (index != null) {
        out.write('<mroot>');
        _writeMathMlNode(out, radicand);
        _writeMathMlNode(out, index);
        out.write('</mroot>');
        return;
      }
      out.write('<msqrt>');
      _writeMathMlNode(out, radicand);
      out.write('</msqrt>');

    case AccentNode(
      :final MathNode base,
      :final String accent,
      :final bool isWide,
      :final bool isUnder,
    ):
      out.write(
        isUnder ? '<munder accentunder="true">' : '<mover accent="true">',
      );
      _writeMathMlNode(out, base);
      out.write(
        isWide ? '<mo accent="true" stretchy="true">' : '<mo accent="true">',
      );
      writeEscapedXmlAttr(out, accent);
      out.write('</mo>');
      out.write(isUnder ? '</munder>' : '</mover>');

    case DelimiterNode(
      :final List<MathNode> children,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
      :final double? fixedSizeEm,
    ):
      final String stretchy = fixedSizeEm == 0.0 ? 'false' : 'true';
      out.write('<mrow>');
      if (leftDelimiter != null && leftDelimiter.isNotEmpty) {
        out.write('<mo stretchy="');
        out.write(stretchy);
        out.write('">');
        writeEscapedXmlAttr(out, leftDelimiter);
        out.write('</mo>');
      }
      _writeMathMlList(out, children);
      if (rightDelimiter != null && rightDelimiter.isNotEmpty) {
        out.write('<mo stretchy="');
        out.write(stretchy);
        out.write('">');
        writeEscapedXmlAttr(out, rightDelimiter);
        out.write('</mo>');
      }
      out.write('</mrow>');

    case MatrixNode(
      :final List<List<MathNode>> rows,
      :final String environment,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      final bool hasLeft = leftDelimiter != null && leftDelimiter.isNotEmpty;
      final bool hasRight = rightDelimiter != null && rightDelimiter.isNotEmpty;
      final bool wrapRow = leftDelimiter != null || rightDelimiter != null;
      final bool isMultlineEnv =
          environment == 'multline' ||
          environment == 'multline*' ||
          environment == 'multlined';
      if (wrapRow) {
        out.write('<mrow>');
        if (hasLeft) {
          out.write('<mo stretchy="true">');
          writeEscapedXmlAttr(out, leftDelimiter);
          out.write('</mo>');
        }
      }
      out.write('<mtable>');
      for (int r = 0; r < rows.length; r++) {
        final List<MathNode> row = rows[r];
        out.write('<mtr>');
        for (final MathNode cell in row) {
          String? colAlign;
          if (isMultlineEnv) {
            final String? shove = _extractMultlineShoveRole(cell);
            if (shove == 'shoveleft') {
              colAlign = 'left';
            } else if (shove == 'shoveright') {
              colAlign = 'right';
            } else if (r == 0) {
              colAlign = 'left';
            } else if (r == rows.length - 1 && rows.length > 1) {
              colAlign = 'right';
            }
          }
          if (colAlign != null) {
            out.write('<mtd columnalign="');
            out.write(colAlign);
            out.write('">');
          } else {
            out.write('<mtd>');
          }
          _writeMathMlNode(out, cell);
          out.write('</mtd>');
        }
        out.write('</mtr>');
      }
      out.write('</mtable>');
      if (wrapRow) {
        if (hasRight) {
          out.write('<mo stretchy="true">');
          writeEscapedXmlAttr(out, rightDelimiter);
          out.write('</mo>');
        }
        out.write('</mrow>');
      }

    case TextNode(
      :final String text,
      :final String? styleCommand,
      :final List<MathNode> children,
    ):
      if (children.isNotEmpty) {
        out.write('<mrow>');
        _writeMathMlList(out, children);
        out.write('</mrow>');
        return;
      }
      final String? mv = mathMlVariantForTextStyle(styleCommand);
      if (mv == null) {
        out.write('<mtext>');
      } else {
        out.write('<mtext mathvariant="');
        out.write(mv);
        out.write('">');
      }
      writeEscapedXmlAttr(out, text);
      out.write('</mtext>');

    case SpaceNode(:final double widthEm):
      out.write('<mspace width="');
      out.write(_formatNumber(widthEm));
      out.write('em"/>');

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
      out.write('<mstyle');
      if (disp != null) {
        out.write(' displaystyle="');
        out.write(disp);
        out.write('"');
      }
      if (style == TexMathStyle.script || style == TexMathStyle.crampedScript) {
        out.write(' scriptlevel="1"');
      } else if (style == TexMathStyle.scriptScript ||
          style == TexMathStyle.crampedScriptScript) {
        out.write(' scriptlevel="2"');
      }
      if (scaleEm != null) {
        out.write(' mathsize="');
        out.write(_formatNumber(scaleEm));
        out.write('em"');
      }
      out.write('>');
      _writeMathMlList(out, children);
      out.write('</mstyle>');

    case ColorNode(
      :final TexMathColorRole role,
      :final String? colorValue,
      :final String? backgroundColor,
      :final List<MathNode> children,
    ):
      final String? rawFg =
          colorValue ??
          (role == TexMathColorRole.error
              ? defaultRoleColorHex(TexMathColorRole.error)
              : null);
      final String? fg = sanitizeMathMlColor(rawFg);
      final String? bg = sanitizeMathMlColor(backgroundColor);
      out.write('<mstyle');
      if (fg != null) {
        out.write(' mathcolor="');
        writeEscapedXmlAttr(out, fg);
        out.write('"');
      }
      if (bg != null) {
        out.write(' mathbackground="');
        writeEscapedXmlAttr(out, bg);
        out.write('"');
      }
      out.write('>');
      _writeMathMlList(out, children);
      out.write('</mstyle>');

    case TagNode(
      :final String label,
      :final bool isStarred,
      :final MathNode? body,
      :final bool isReference,
      :final bool isLabelDefinition,
    ):
      if (isLabelDefinition) {
        out.write('<mspace id="');
        writeEscapedXmlAttr(out, label);
        out.write('"/>');
        return;
      }
      final String formatted = isStarred ? label : '($label)';
      if (isReference || body == null) {
        out.write('<mtext>');
        writeEscapedXmlAttr(out, formatted);
        out.write('</mtext>');
        return;
      }
      out.write('<mrow>');
      _writeMathMlNode(out, body);
      out.write('<mtext>');
      writeEscapedXmlAttr(out, formatted);
      out.write('</mtext></mrow>');

    case ErrorNode(:final String rawSource):
      out.write('<merror><mtext>');
      writeEscapedXmlAttr(out, rawSource);
      out.write('</mtext></merror>');
  }
}

void _writeMathMlList(StringBuffer out, List<MathNode> children) {
  if (children.isEmpty) {
    out.write('<mrow/>');
    return;
  }
  for (final MathNode child in children) {
    _writeMathMlNode(out, child);
  }
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

String? _extractMultlineShoveRole(MathNode node) {
  if (node is MathGroupNode) {
    if (node.role == 'shoveleft' || node.role == 'shoveright') {
      return node.role;
    }
    if (!node.isExplicitGroup) {
      for (final MathNode child in node.children) {
        if (child is TagNode && child.isLabelDefinition) {
          continue;
        }
        return _extractMultlineShoveRole(child);
      }
      return null;
    }
    if (node.children.length == 1) {
      return _extractMultlineShoveRole(node.children.first);
    }
  }
  return null;
}
