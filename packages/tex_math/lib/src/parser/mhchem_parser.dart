/// Pure-Dart translator for `mhchem` `\ce{...}` chemical equations and
/// `\pu{...}` physical unit expressions into standard TeX math syntax.
library;

import '../error.dart';
import '../options.dart';

/// Converts the body of `\ce{...}` or `\pu{...}` into TeX math source while
/// enforcing [maxNestingDepth].
String translateMhchemToTex(
  String input, {
  required bool isPhysicalUnits,
  int maxNestingDepth = TexMathBudgets.defaultMaxNestingDepth,
}) {
  final String normalized = _normalizeMhchemInput(input);
  if (isPhysicalUnits) {
    return _translatePu(normalized);
  }
  return _translateCe(normalized, depth: 0, maxDepth: maxNestingDepth);
}

String _normalizeMhchemInput(String input) {
  final int len = input.length;
  int firstReplace = -1;
  for (int i = 0; i < len; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x0A || cu == 0x2212 || cu == 0x2013 || cu == 0x2014) {
      firstReplace = i;
      break;
    }
  }
  if (firstReplace < 0) {
    return input;
  }
  final StringBuffer sb = StringBuffer()
    ..write(input.substring(0, firstReplace));
  for (int i = firstReplace; i < len; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x0A) {
      sb.writeCharCode(0x20);
    } else if (cu == 0x2212 || cu == 0x2013 || cu == 0x2014) {
      sb.writeCharCode(0x2D);
    } else {
      sb.writeCharCode(cu);
    }
  }
  return sb.toString();
}

String _translateCe(String input, {required int depth, required int maxDepth}) {
  if (depth > maxDepth) {
    throw TexMathBudgetError(
      'mhchem group nesting depth $depth exceeds maxNestingDepth ($maxDepth).',
      budgetName: 'maxNestingDepth',
      limit: maxDepth,
      actual: depth,
    );
  }
  final StringBuffer out = StringBuffer();
  int i = 0;
  final int len = input.length;
  bool atTermStart = true;

  while (i < len) {
    final int ch = input.codeUnitAt(i);

    // Whitespace
    if (_isSpace(ch)) {
      while (i < len && _isSpace(input.codeUnitAt(i))) {
        i++;
      }
      if (out.isNotEmpty) {
        out.writeCharCode(0x20);
      }
      atTermStart = true;
      continue;
    }

    // Inline math escape $...$
    if (ch == 0x24) {
      final int close = _findClosingDollar(input, i + 1);
      out.write(input.substring(i + 1, close));
      i = close < len ? close + 1 : len;
      atTermStart = false;
      continue;
    }

    // Braced group {...}
    if (ch == 0x7B) {
      final int end = _findMatchingBrace(input, i);
      final String inner = input.substring(i + 1, end);
      out.writeCharCode(0x7B);
      out.write(_translateCe(inner, depth: depth + 1, maxDepth: maxDepth));
      out.writeCharCode(0x7D);
      i = end < len ? end + 1 : len;
      atTermStart = false;
      continue;
    }

    // Control sequence (e.g. \text{...}, \alpha, \bond{...})
    if (ch == 0x5C) {
      final int csEnd = _scanControlSequenceEnd(input, i);
      final String cs = input.substring(i + 1, csEnd);
      if (cs == 'bond' && csEnd < len && input.codeUnitAt(csEnd) == 0x7B) {
        final int braceEnd = _findMatchingBrace(input, csEnd);
        final String bondSpec = input.substring(csEnd + 1, braceEnd).trim();
        out.write(_translateBond(bondSpec));
        i = braceEnd < len ? braceEnd + 1 : len;
        atTermStart = false;
        continue;
      }
      if ((cs == 'text' || cs == 'mathrm' || cs == 'ce') &&
          csEnd < len &&
          input.codeUnitAt(csEnd) == 0x7B) {
        final int braceEnd = _findMatchingBrace(input, csEnd);
        out.write(input.substring(i, braceEnd < len ? braceEnd + 1 : len));
        i = braceEnd < len ? braceEnd + 1 : len;
        atTermStart = false;
        continue;
      }
      out.write(input.substring(i, csEnd));
      i = csEnd;
      atTermStart = false;
      continue;
    }

    // Reaction arrows: <=>>, <<=>, <--> , <->, <=>, ->, <-
    if (ch == 0x3C || ch == 0x2D) {
      final ({String tex, int length})? arrow = _matchReactionArrow(input, i);
      if (arrow != null) {
        i += arrow.length;
        String? above;
        String? below;
        if (i < len && input.codeUnitAt(i) == 0x5B) {
          final int end1 = _findMatchingBracket(input, i);
          above = input.substring(i + 1, end1).trim();
          i = end1 < len ? end1 + 1 : len;
          if (i < len && input.codeUnitAt(i) == 0x5B) {
            final int end2 = _findMatchingBracket(input, i);
            below = input.substring(i + 1, end2).trim();
            i = end2 < len ? end2 + 1 : len;
          }
        }
        out.writeCharCode(0x20);
        out.write(_formatArrowTex(arrow.tex, above: above, below: below));
        out.writeCharCode(0x20);
        atTermStart = true;
        continue;
      }
    }

    // Gas (^) and precipitate (v) tokens when standalone.
    if ((ch == 0x5E || ch == 0x76) &&
        atTermStart &&
        (i + 1 >= len || _isDelimiterOrSpace(input.codeUnitAt(i + 1)))) {
      out.write(ch == 0x5E ? r'\uparrow ' : r'\downarrow ');
      i++;
      atTermStart = true;
      continue;
    }

    // Leading isotope prescripts: ^{238}_{92}U or _{92}^{238}U
    if (atTermStart && (ch == 0x5E || ch == 0x5F)) {
      String? sup;
      String? sub;
      while (i < len &&
          (input.codeUnitAt(i) == 0x5E || input.codeUnitAt(i) == 0x5F)) {
        final bool isSup = input.codeUnitAt(i) == 0x5E;
        i++;
        final ({String content, int next}) parsed = _readScriptArg(input, i);
        if (isSup) {
          sup = parsed.content;
        } else {
          sub = parsed.content;
        }
        i = parsed.next;
      }
      out.write('{}');
      if (sub != null) {
        out.write('_{$sub}');
      }
      if (sup != null) {
        out.write('^{$sup}');
      }
      atTermStart = false;
      continue;
    }

    // Explicit superscript/subscript charges like ^{2+}, ^2+, _{2}
    if (ch == 0x5E || ch == 0x5F) {
      final bool isSup = ch == 0x5E;
      i++;
      if (i < len && input.codeUnitAt(i) == 0x7B) {
        final int end = _findMatchingBrace(input, i);
        final String inner = input.substring(i + 1, end);
        out.write(isSup ? '^{\\mathrm{$inner}}' : '_{\\mathrm{$inner}}');
        i = end < len ? end + 1 : len;
      } else {
        final int start = i;
        while (i < len &&
            (_isDigit(input.codeUnitAt(i)) ||
                input.codeUnitAt(i) == 0x2B ||
                input.codeUnitAt(i) == 0x2D)) {
          i++;
        }
        final String raw = input.substring(start, i);
        if (raw.isNotEmpty) {
          out.write(isSup ? '^{$raw}' : '_{$raw}');
        }
      }
      atTermStart = false;
      continue;
    }

    // Standalone + operator between species vs trailing ionic charge
    if (ch == 0x2B) {
      final bool hasPreceding = out.isNotEmpty && !atTermStart;
      final bool endsSpecies =
          i + 1 >= len ||
          _isSpace(input.codeUnitAt(i + 1)) ||
          input.codeUnitAt(i + 1) == 0x5D ||
          input.codeUnitAt(i + 1) == 0x29 ||
          input.codeUnitAt(i + 1) == 0x7D;
      if (hasPreceding && endsSpecies) {
        out.write('^{+}');
      } else {
        out.write(' + ');
      }
      i++;
      atTermStart = !hasPreceding || !endsSpecies;
      continue;
    }

    // Minus: trailing ionic charge vs single bond vs operator
    if (ch == 0x2D) {
      final bool hasPreceding = out.isNotEmpty && !atTermStart;
      final bool followedBySpace =
          i + 1 < len && _isSpace(input.codeUnitAt(i + 1));
      final bool endsSpecies =
          i + 1 >= len ||
          _isSpace(input.codeUnitAt(i + 1)) ||
          input.codeUnitAt(i + 1) == 0x5D ||
          input.codeUnitAt(i + 1) == 0x29 ||
          input.codeUnitAt(i + 1) == 0x7D ||
          input.codeUnitAt(i + 1) == 0x2C;
      if (!hasPreceding && followedBySpace) {
        out.write(' - ');
        atTermStart = true;
      } else if (hasPreceding && endsSpecies) {
        out.write('^{-}');
        atTermStart = false;
      } else {
        out.write('-');
        atTermStart = false;
      }
      i++;
      continue;
    }

    // Double bond `=` and triple bond `#`
    if (ch == 0x3D) {
      out.write('=');
      i++;
      atTermStart = false;
      continue;
    }
    if (ch == 0x23) {
      out.write(r'\equiv ');
      i++;
      atTermStart = false;
      continue;
    }

    // Numbers: stoichiometric coefficient at term start vs subscript inside formula
    if (_isDigit(ch)) {
      final int start = i;
      while (i < len && _isDigit(input.codeUnitAt(i))) {
        i++;
      }
      final String digits = input.substring(start, i);
      if (atTermStart) {
        out.write(digits);
        if (i < len && _isAsciiAlpha(input.codeUnitAt(i))) {
          out.write(r'\,');
        }
        atTermStart = false;
      } else {
        // Check if trailing charge like Zn2+
        if (i < len &&
            (input.codeUnitAt(i) == 0x2B || input.codeUnitAt(i) == 0x2D) &&
            (i + 1 >= len || _isDelimiterOrSpace(input.codeUnitAt(i + 1)))) {
          final String sign = input.substring(i, i + 1);
          i++;
          out.write('^{$digits$sign}');
        } else {
          out.write('_{$digits}');
        }
      }
      continue;
    }

    // Letters -> upright roman chemical element/group symbols
    if (_isAsciiAlpha(ch)) {
      final int start = i;
      while (i < len && _isAsciiAlpha(input.codeUnitAt(i))) {
        i++;
      }
      final String letters = input.substring(start, i);
      out.write('\\mathrm{$letters}');
      atTermStart = false;
      continue;
    }

    // Parentheses/brackets/punctuation
    out.writeCharCode(ch);
    i++;
    atTermStart = ch == 0x28 || ch == 0x5B || ch == 0x2C;
  }

  return out.toString().trim();
}

final RegExp _puWhitespacePattern = RegExp(r'\s+');
final RegExp _puSciPattern = RegExp(r'^([+-]?\d+(?:\.\d+)?)[eE]([+-]?\d+)$');
final RegExp _looksLikeNumberPattern = RegExp(
  r'^[+-]?\d+(?:[.,]\d+)?(?:[eE][+-]?\d+)?$',
);

String _translatePu(String input) {
  final List<String> tokens = input.trim().split(_puWhitespacePattern);
  if (tokens.isEmpty) {
    return '';
  }
  final StringBuffer out = StringBuffer();
  for (int idx = 0; idx < tokens.length; idx++) {
    final String part = tokens[idx];
    if (part.isEmpty) {
      continue;
    }
    if (idx > 0) {
      out.write(idx == 1 && _looksLikeNumber(tokens[0]) ? r'\,' : r'\,');
    }
    out.write(_translatePuToken(part));
  }
  return out.toString();
}

String _translatePuToken(String token) {
  // Handle scientific notation e.g. 6.022e23 or 6.022e-5
  final RegExpMatch? sciMatch = _puSciPattern.firstMatch(token);
  if (sciMatch != null) {
    return '${sciMatch.group(1)} \\cdot 10^{${sciMatch.group(2)}}';
  }
  if (_looksLikeNumber(token)) {
    return token;
  }

  // Handle unit combinations with `/` and `^` like `m/s^2` or `mol^-1`.
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < token.length) {
    final int ch = token.codeUnitAt(i);
    if (ch == 0x5E) {
      i++;
      if (i < token.length && token.codeUnitAt(i) == 0x7B) {
        final int end = _findMatchingBrace(token, i);
        out.write('^{${token.substring(i + 1, end)}}');
        i = end < token.length ? end + 1 : token.length;
      } else {
        final int start = i;
        while (i < token.length &&
            (_isDigit(token.codeUnitAt(i)) ||
                token.codeUnitAt(i) == 0x2D ||
                token.codeUnitAt(i) == 0x2B)) {
          i++;
        }
        out.write('^{${token.substring(start, i)}}');
      }
      continue;
    }
    if (_isAsciiAlpha(ch)) {
      final int start = i;
      while (i < token.length && _isAsciiAlpha(token.codeUnitAt(i))) {
        i++;
      }
      out.write('\\mathrm{${token.substring(start, i)}}');
      continue;
    }
    if (ch == 0x2A) {
      out.write(r'\cdot ');
      i++;
      continue;
    }
    out.writeCharCode(ch);
    i++;
  }
  return out.toString();
}

bool _looksLikeNumber(String s) => _looksLikeNumberPattern.hasMatch(s);

({String tex, int length})? _matchReactionArrow(String input, int index) {
  const List<(String, String)> arrows = <(String, String)>[
    ('<=>>', r'\rightleftharpoons'),
    ('<<=>', r'\rightleftharpoons'),
    ('<-->', r'\longleftrightarrow'),
    ('<->', r'\leftrightarrow'),
    ('<=>', r'\rightleftharpoons'),
    ('->', r'\longrightarrow'),
    ('<-', r'\longleftarrow'),
  ];
  for (final (String pattern, String tex) in arrows) {
    if (input.startsWith(pattern, index)) {
      return (tex: tex, length: pattern.length);
    }
  }
  return null;
}

String _formatArrowTex(String baseArrow, {String? above, String? below}) {
  final String? extCmd = switch (baseArrow) {
    r'\longrightarrow' => r'\xrightarrow',
    r'\longleftarrow' => r'\xleftarrow',
    r'\longleftrightarrow' => r'\xleftrightarrow',
    r'\leftrightarrow' => r'\xleftrightarrow',
    r'\rightleftharpoons' => r'\xrightleftharpoons',
    _ => null,
  };
  if ((above == null || above.isEmpty) && (below == null || below.isEmpty)) {
    return baseArrow;
  }
  final String topArg = above == null || above.isEmpty ? '' : above;
  if (extCmd != null) {
    if (below != null && below.isNotEmpty) {
      return '$extCmd[$below]{$topArg}';
    }
    return '$extCmd{$topArg}';
  }
  if (below != null && below.isNotEmpty) {
    return '\\underset{$below}{\\overset{$topArg}{$baseArrow}}';
  }
  return '\\overset{$topArg}{$baseArrow}';
}

String _translateBond(String spec) {
  switch (spec) {
    case '-':
    case '1':
    case 'single':
      return '-';
    case '=':
    case '2':
    case 'double':
      return '=';
    case '#':
    case '3':
    case 'triple':
      return r'\equiv ';
    case '~':
      return r'\sim ';
    case '->':
      return r'\rightarrow ';
    case '<-':
      return r'\leftarrow ';
    default:
      return spec;
  }
}

({String content, int next}) _readScriptArg(String input, int index) {
  if (index >= input.length) {
    return (content: '', next: index);
  }
  if (input.codeUnitAt(index) == 0x7B) {
    final int end = _findMatchingBrace(input, index);
    return (
      content: input.substring(index + 1, end),
      next: end < input.length ? end + 1 : input.length,
    );
  }
  return (content: input.substring(index, index + 1), next: index + 1);
}

int _findMatchingBrace(String input, int openIndex) {
  int depth = 0;
  for (int i = openIndex; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x5C) {
      i++;
      continue;
    }
    if (cu == 0x7B) {
      depth++;
    } else if (cu == 0x7D) {
      depth--;
      if (depth == 0) {
        return i;
      }
    }
  }
  return input.length;
}

int _findMatchingBracket(String input, int openIndex) {
  int braceDepth = 0;
  for (int i = openIndex + 1; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x5C) {
      i++;
      continue;
    }
    if (cu == 0x7B) {
      braceDepth++;
    } else if (cu == 0x7D) {
      if (braceDepth > 0) {
        braceDepth--;
      }
    } else if (cu == 0x5D && braceDepth == 0) {
      return i;
    }
  }
  return input.length;
}

int _findClosingDollar(String input, int start) {
  for (int i = start; i < input.length; i++) {
    final int cu = input.codeUnitAt(i);
    if (cu == 0x5C) {
      i++;
      continue;
    }
    if (cu == 0x24) {
      return i;
    }
  }
  return input.length;
}

int _scanControlSequenceEnd(String input, int backslashIndex) {
  if (backslashIndex + 1 >= input.length) {
    return input.length;
  }
  int i = backslashIndex + 1;
  if (_isAsciiAlpha(input.codeUnitAt(i))) {
    while (i < input.length && _isAsciiAlpha(input.codeUnitAt(i))) {
      i++;
    }
    return i;
  }
  return i + 1;
}

bool _isSpace(int cu) => cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

bool _isDigit(int cu) => cu >= 0x30 && cu <= 0x39;

bool _isAsciiAlpha(int cu) =>
    (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A);

bool _isDelimiterOrSpace(int cu) =>
    _isSpace(cu) || cu == 0x29 || cu == 0x5D || cu == 0x7D || cu == 0x2C;
