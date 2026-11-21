import '../ast.dart';

/// Generates plain natural-language spoken math text from a parsed [MathNode]
/// syntax tree for screen readers and accessibility labels.
String mathNodeToSpokenText(MathNode node) {
  final StringBuffer out = StringBuffer();
  _writeSpokenNode(out, node);
  return _normalizeSpaces(out.toString());
}

void _writeSpokenNode(StringBuffer out, MathNode node) {
  switch (node) {
    case MathRootNode(:final List<MathNode> children):
      _writeSpokenList(out, children);

    case MathGroupNode(:final List<MathNode> children, :final String? role):
      switch (role) {
        case 'cancel':
        case 'bcancel':
        case 'xcancel':
          out.write('cancelled ');
          _writeSpokenList(out, children);
        case 'cancelto':
          if (children.length >= 2) {
            _writeSpokenNode(out, children[0]);
            out.write(' cancelled to ');
            _writeSpokenNode(out, children[1]);
          } else {
            _writeSpokenList(out, children);
          }
        case 'boxed':
          out.write('boxed ');
          _writeSpokenList(out, children);
        case 'phantom':
        case 'hphantom':
        case 'vphantom':
          return;
        default:
          _writeSpokenList(out, children);
      }

    case SymbolNode(:final String value, :final String? command):
      out.write(_speakSymbol(value, command));

    case OperatorNode(:final String operatorName):
      out.write(_speakOperator(operatorName));

    case FractionNode(
      :final MathNode numerator,
      :final MathNode denominator,
      :final double? ruleThicknessEm,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      _writeSpokenNode(out, numerator);
      if (leftDelimiter == '(' &&
          rightDelimiter == ')' &&
          ruleThicknessEm == 0.0) {
        out.write(' choose ');
      } else if (ruleThicknessEm == 0.0) {
        out.write(' atop ');
      } else {
        out.write(' over ');
      }
      _writeSpokenNode(out, denominator);

    case ScriptNode(
      :final MathNode base,
      :final MathNode? subscript,
      :final MathNode? superscript,
      :final bool limitsAboveBelow,
      :final MathNode? presubscript,
      :final MathNode? presuperscript,
    ):
      if (presubscript != null) {
        out.write('pre-subscript ');
        _writeSpokenNode(out, presubscript);
        out.write(' ');
      }
      if (presuperscript != null) {
        out.write('pre-superscript ');
        _writeSpokenNode(out, presuperscript);
        out.write(' ');
      }
      _writeSpokenNode(out, base);
      if (subscript != null) {
        out.write(limitsAboveBelow ? ' from ' : ' sub ');
        _writeSpokenNode(out, subscript);
      }
      if (superscript != null) {
        if (limitsAboveBelow) {
          out.write(' to ');
          _writeSpokenNode(out, superscript);
        } else {
          final String? simpleSup = _singleSignificantAtom(superscript);
          if (simpleSup == '2') {
            out.write(' squared');
          } else if (simpleSup == '3') {
            out.write(' cubed');
          } else if (simpleSup == 'prime') {
            out.write(' prime');
          } else {
            out.write(' to the ');
            _writeSpokenNode(out, superscript);
          }
        }
      }

    case RadicalNode(:final MathNode radicand, :final MathNode? index):
      if (index == null) {
        out.write('square root of ');
        _writeSpokenNode(out, radicand);
        return;
      }
      final String? simpleIdx = _singleSignificantAtom(index);
      if (simpleIdx == '3') {
        out.write('cube root of ');
      } else {
        out.write('root ');
        _writeSpokenNode(out, index);
        out.write(' of ');
      }
      _writeSpokenNode(out, radicand);

    case AccentNode(
      :final MathNode base,
      :final String accent,
      :final bool isUnder,
    ):
      _writeSpokenNode(out, base);
      out.write(' ');
      out.write(_speakAccent(accent, isUnder: isUnder));

    case DelimiterNode(
      :final List<MathNode> children,
      :final String? leftDelimiter,
      :final String? rightDelimiter,
    ):
      final String leftName = _speakDelimiter(leftDelimiter, isLeft: true);
      final String rightName = _speakDelimiter(rightDelimiter, isLeft: false);
      if (leftName.isNotEmpty) {
        out.write(leftName);
        out.write(' ');
      }
      _writeSpokenList(out, children);
      if (rightName.isNotEmpty) {
        out.write(' ');
        out.write(rightName);
      }

    case MatrixNode(
      :final List<List<MathNode>> rows,
      :final String environment,
    ):
      final int rowCount = rows.length;
      final int colCount = rows.isEmpty ? 0 : rows.first.length;
      if (environment == 'cases' || environment == 'dcases') {
        out.write('cases ');
      } else if (colCount > 1) {
        out.write(rowCount);
        out.write(' by ');
        out.write(colCount);
        out.write(' matrix ');
      }
      for (int r = 0; r < rows.length; r++) {
        if (r > 0) {
          out.write(', row ');
          out.write(r + 1);
          out.write(': ');
        } else if (rows.length > 1) {
          out.write('row 1: ');
        }
        final List<MathNode> row = rows[r];
        for (int c = 0; c < row.length; c++) {
          if (c > 0) {
            out.write(', ');
          }
          _writeSpokenNode(out, row[c]);
        }
      }

    case TextNode(:final String text, :final List<MathNode> children):
      if (children.isNotEmpty) {
        _writeSpokenList(out, children);
      } else {
        out.write(text);
      }

    case SpaceNode():
      return;

    case StyleNode(:final List<MathNode> children):
      _writeSpokenList(out, children);

    case ColorNode(:final List<MathNode> children):
      _writeSpokenList(out, children);

    case TagNode(
      :final String label,
      :final MathNode? body,
      :final bool isLabelDefinition,
    ):
      if (isLabelDefinition) {
        return;
      }
      if (body == null) {
        out.write('tag ');
        out.write(label);
        return;
      }
      _writeSpokenNode(out, body);
      out.write(' tag ');
      out.write(label);

    case ErrorNode(:final String rawSource):
      out.write('error in ');
      out.write(rawSource);
  }
}

void _writeSpokenList(StringBuffer out, List<MathNode> nodes) {
  bool wrotePrevious = false;
  for (int i = 0; i < nodes.length; i++) {
    if (wrotePrevious) {
      out.write(' ');
    }
    final int beforeChild = out.length;
    _writeSpokenNode(out, nodes[i]);
    if (out.length > beforeChild) {
      wrotePrevious = true;
    }
  }
}

String? _singleSignificantAtom(MathNode node) {
  switch (node) {
    case SymbolNode(:final String value, :final String? command):
      return _speakSymbol(value, command);
    case OperatorNode(:final String operatorName):
      return _speakOperator(operatorName);
    case TextNode(:final String text, :final List<MathNode> children):
      if (children.isEmpty) {
        final String trimmed = text.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      return _singleSignificantFromList(children);
    case MathGroupNode(:final List<MathNode> children, :final String? role):
      if (role != null) {
        return null;
      }
      return _singleSignificantFromList(children);
    case MathRootNode(:final List<MathNode> children):
    case StyleNode(:final List<MathNode> children):
    case ColorNode(:final List<MathNode> children):
      return _singleSignificantFromList(children);
    case SpaceNode():
    case FractionNode():
    case ScriptNode():
    case RadicalNode():
    case AccentNode():
    case DelimiterNode():
    case MatrixNode():
    case TagNode():
    case ErrorNode():
      return null;
  }
}

String? _singleSignificantFromList(List<MathNode> children) {
  String? single;
  for (final MathNode child in children) {
    if (_isSpokenEmptyNode(child)) {
      continue;
    }
    final String? atom = _singleSignificantAtom(child);
    if (atom == null || single != null) {
      return null;
    }
    single = atom;
  }
  return single;
}

bool _isSpokenEmptyNode(MathNode node) {
  switch (node) {
    case SpaceNode():
      return true;
    case TagNode(:final bool isLabelDefinition):
      return isLabelDefinition;
    case TextNode(:final String text, :final List<MathNode> children):
      return children.isEmpty && text.trim().isEmpty;
    case MathGroupNode(:final List<MathNode> children, :final String? role):
      if (role == 'phantom' || role == 'hphantom' || role == 'vphantom') {
        return true;
      }
      return children.every(_isSpokenEmptyNode);
    default:
      return false;
  }
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

final RegExp _whitespacePattern = RegExp(r'\s+');

String _normalizeSpaces(String input) =>
    input.replaceAll(_whitespacePattern, ' ').trim();

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
