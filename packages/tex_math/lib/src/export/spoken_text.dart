import '../ast.dart';

/// Generates plain natural-language spoken math text from a parsed [MathNode]
/// syntax tree for screen readers and accessibility labels.
String mathNodeToSpokenText(MathNode node) {
  return _normalizeSpaces(_speakNode(node));
}

String _speakNode(MathNode node) {
  switch (node) {
    case MathRootNode(:final List<MathNode> children):
      return _speakList(children);

    case MathGroupNode(:final List<MathNode> children, :final String? role):
      final String inner = _speakList(children);
      switch (role) {
        case 'cancel':
        case 'bcancel':
        case 'xcancel':
          return 'cancelled $inner';
        case 'cancelto':
          if (children.length >= 2) {
            return '${_speakNode(children[0])} cancelled to ${_speakNode(children[1])}';
          }
          return inner;
        case 'boxed':
          return 'boxed $inner';
        case 'phantom':
        case 'hphantom':
        case 'vphantom':
          return '';
        default:
          return inner;
      }

    case SymbolNode(:final String value, :final String? command):
      return _speakSymbol(value, command);

    case OperatorNode(:final String operatorName):
      return _speakOperator(operatorName);

    case FractionNode(
      :final MathNode numerator,
      :final MathNode denominator,
      :final double? ruleThicknessEm,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      final String numText = _speakNode(numerator);
      final String denText = _speakNode(denominator);
      if (leftDelimiter == '(' &&
          rightDelimiter == ')' &&
          ruleThicknessEm == 0.0) {
        return '$numText choose $denText';
      }
      if (ruleThicknessEm == 0.0) {
        return '$numText atop $denText';
      }
      return '$numText over $denText';

    case ScriptNode(
      :final MathNode base,
      :final MathNode? subscript,
      :final MathNode? superscript,
      :final bool limitsAboveBelow,
      :final MathNode? presubscript,
      :final MathNode? presuperscript,
    ):
      final StringBuffer out = StringBuffer();
      if (presubscript != null) {
        out.write('pre-subscript ${_speakNode(presubscript)} ');
      }
      if (presuperscript != null) {
        out.write('pre-superscript ${_speakNode(presuperscript)} ');
      }
      out.write(_speakNode(base));
      if (subscript != null) {
        final String subText = _speakNode(subscript);
        out.write(limitsAboveBelow ? ' from $subText' : ' sub $subText');
      }
      if (superscript != null) {
        final String supText = _speakNode(superscript);
        if (limitsAboveBelow) {
          out.write(' to $supText');
        } else if (supText == '2') {
          out.write(' squared');
        } else if (supText == '3') {
          out.write(' cubed');
        } else if (supText == 'prime') {
          out.write(' prime');
        } else {
          out.write(' to the $supText');
        }
      }
      return out.toString();

    case RadicalNode(:final MathNode radicand, :final MathNode? index):
      final String rad = _speakNode(radicand);
      if (index == null) {
        return 'square root of $rad';
      }
      final String idx = _speakNode(index);
      if (idx == '3') {
        return 'cube root of $rad';
      }
      return 'root $idx of $rad';

    case AccentNode(
      :final MathNode base,
      :final String accent,
      :final bool isUnder,
    ):
      final String baseText = _speakNode(base);
      final String accentName = _speakAccent(accent, isUnder: isUnder);
      return '$baseText $accentName';

    case DelimiterNode(
      :final List<MathNode> children,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      final String inner = _speakList(children);
      final String leftName = _speakDelimiter(leftDelimiter, isLeft: true);
      final String rightName = _speakDelimiter(rightDelimiter, isLeft: false);
      return '$leftName $inner $rightName';

    case MatrixNode(
      :final List<List<MathNode>> rows,
      :final String environment,
    ):
      final int rowCount = rows.length;
      final int colCount = rows.isEmpty ? 0 : rows.first.length;
      final StringBuffer out = StringBuffer();
      if (environment == 'cases' || environment == 'dcases') {
        out.write('cases ');
      } else if (colCount > 1) {
        out.write('$rowCount by $colCount matrix ');
      }
      for (int r = 0; r < rows.length; r++) {
        if (r > 0) {
          out.write(', row ${r + 1}: ');
        } else if (rows.length > 1) {
          out.write('row 1: ');
        }
        out.write(rows[r].map(_speakNode).join(', '));
      }
      return out.toString();

    case TextNode(:final String text, :final List<MathNode> children):
      if (children.isNotEmpty) {
        return children.map(_speakNode).join(' ');
      }
      return text;

    case SpaceNode():
      return '';

    case StyleNode(:final List<MathNode> children):
      return _speakList(children);

    case ColorNode(:final List<MathNode> children):
      return _speakList(children);

    case TagNode(
      :final String label,
      :final MathNode? body,
      :final bool isLabelDefinition,
    ):
      if (isLabelDefinition) {
        return '';
      }
      if (body == null) {
        return 'tag $label';
      }
      return '${_speakNode(body)} tag $label';

    case ErrorNode(:final String rawSource):
      return 'error in $rawSource';
  }
}

String _speakList(List<MathNode> nodes) {
  final List<String> parts = <String>[];
  for (final MathNode node in nodes) {
    final String text = _speakNode(node);
    if (text.isNotEmpty) {
      parts.add(text);
    }
  }
  return parts.join(' ');
}

String _speakSymbol(String value, String? command) {
  final String? mapped = _spokenSymbols[value];
  if (mapped != null) {
    return mapped;
  }
  if (command != null && _spokenCommands.containsKey(command)) {
    return _spokenCommands[command]!;
  }
  return value;
}

String _speakOperator(String op) {
  return _spokenSymbols[op] ?? op;
}

String _speakAccent(String accent, {required bool isUnder}) {
  switch (accent) {
    case '\u005E':
      return 'hat';
    case '\u007E':
      return 'tilde';
    case '\u00AF':
    case '\u2015':
      return isUnder ? 'underline' : 'bar';
    case '\u2192':
      return 'vector';
    case '\u02D9':
      return 'dot';
    case '\u00A8':
      return 'double dot';
    case '\u20DB':
      return 'triple dot';
    case '\u23DE':
      return 'overbrace';
    case '\u23DF':
      return 'underbrace';
    default:
      return isUnder ? 'under accent' : 'accent';
  }
}

String _speakDelimiter(String? delim, {required bool isLeft}) {
  if (delim == null || delim.isEmpty) {
    return '';
  }
  switch (delim) {
    case '(':
      return 'left parenthesis';
    case ')':
      return 'right parenthesis';
    case '[':
      return 'left bracket';
    case ']':
      return 'right bracket';
    case '{':
      return 'left brace';
    case '}':
      return 'right brace';
    case '|':
      return isLeft ? 'left vertical bar' : 'right vertical bar';
    case '\u2016':
      return isLeft ? 'left norm' : 'right norm';
    case '\u27E8':
      return 'left angle';
    case '\u27E9':
      return 'right angle';
    case '\u230A':
      return 'left floor';
    case '\u230B':
      return 'right floor';
    case '\u2308':
      return 'left ceiling';
    case '\u2309':
      return 'right ceiling';
    default:
      return delim;
  }
}

String _normalizeSpaces(String input) =>
    input.replaceAll(RegExp(r'\s+'), ' ').trim();

const Map<String, String> _spokenCommands = <String, String>{
  'prime': 'prime',
  'prime_char': 'prime',
  'ldots': 'dot dot dot',
  'cdots': 'dot dot dot',
  'dots': 'dot dot dot',
};

const Map<String, String> _spokenSymbols = <String, String>{
  '+': 'plus',
  '-': 'minus',
  '=': 'equals',
  '<': 'less than',
  '>': 'greater than',
  '\u00D7': 'times',
  '\u00F7': 'divided by',
  '\u00B1': 'plus or minus',
  '\u2213': 'minus or plus',
  '\u22C5': 'dot',
  '\u2260': 'not equal to',
  '\u2264': 'less than or equal to',
  '\u2265': 'greater than or equal to',
  '\u2248': 'approximately equal to',
  '\u2261': 'equivalent to',
  '\u221E': 'infinity',
  '\u2211': 'sum',
  '\u220F': 'product',
  '\u222B': 'integral',
  '\u222C': 'double integral',
  '\u222D': 'triple integral',
  '\u222E': 'contour integral',
  '\u2202': 'partial',
  '\u2207': 'nabla',
  '\u2208': 'in',
  '\u2209': 'not in',
  '\u2282': 'subset of',
  '\u2286': 'subset of or equal to',
  '\u222A': 'union',
  '\u2229': 'intersection',
  '\u2200': 'for all',
  '\u2203': 'there exists',
  '\u00AC': 'not',
  '\u2192': 'to',
  '\u2190': 'left arrow',
  '\u2194': 'left right arrow',
  '\u21D2': 'implies',
  '\u21D4': 'if and only if',
  '\u27F6': 'maps to',
  '\u21A6': 'maps to',
  '\u2032': 'prime',
  '\u2033': 'double prime',
  '\u2034': 'triple prime',
  '\u03B1': 'alpha',
  '\u03B2': 'beta',
  '\u03B3': 'gamma',
  '\u03B4': 'delta',
  '\u03B5': 'epsilon',
  '\u03F5': 'epsilon',
  '\u03B6': 'zeta',
  '\u03B7': 'eta',
  '\u03B8': 'theta',
  '\u03D1': 'theta',
  '\u03B9': 'iota',
  '\u03BA': 'kappa',
  '\u03BB': 'lambda',
  '\u03BC': 'mu',
  '\u03BD': 'nu',
  '\u03BE': 'xi',
  '\u03C0': 'pi',
  '\u03C1': 'rho',
  '\u03C3': 'sigma',
  '\u03C4': 'tau',
  '\u03C5': 'upsilon',
  '\u03C6': 'phi',
  '\u03D5': 'phi',
  '\u03C7': 'chi',
  '\u03C8': 'psi',
  '\u03C9': 'omega',
  '\u0393': 'Gamma',
  '\u0394': 'Delta',
  '\u0398': 'Theta',
  '\u039B': 'Lambda',
  '\u039E': 'Xi',
  '\u03A0': 'Pi',
  '\u03A3': 'Sigma',
  '\u03A5': 'Upsilon',
  '\u03A6': 'Phi',
  '\u03A8': 'Psi',
  '\u03A9': 'Omega',
};
