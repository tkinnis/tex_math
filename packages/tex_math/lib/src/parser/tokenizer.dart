import 'package:meta/meta.dart';

import '../source_span.dart';

/// TeX character category codes assigned during tokenization.
enum TexCatCode {
  /// Escape character (`\`, catcode 0).
  escape,

  /// Begin group delimiter (`{`, catcode 1).
  beginGroup,

  /// End group delimiter (`}`, catcode 2).
  endGroup,

  /// Math shift delimiter (`$`, catcode 3).
  mathShift,

  /// Alignment tab (`&`, catcode 4).
  alignmentTab,

  /// End-of-line character (`\r` or `\n`, catcode 5).
  endOfLine,

  /// Macro parameter prefix (`#`, catcode 6).
  parameter,

  /// Superscript operator (`^`, catcode 7).
  superscript,

  /// Subscript operator (`_`, catcode 8).
  subscript,

  /// Whitespace separator (` ` or `\t`, catcode 10).
  space,

  /// ASCII alphabetic letter (`A`–`Z`, `a`–`z`, catcode 11).
  letter,

  /// Other character (digits, punctuation, operators, non-ASCII, catcode 12).
  other,

  /// Active character (`~`, catcode 13).
  active,

  /// Comment prefix (`%`, catcode 14).
  comment,
}

/// Token categories produced by [tokenizeTex].
enum TexTokenKind {
  /// Control word (`\frac`) or single-character control symbol (`\,`, `\\`).
  controlSequence,

  /// Opening brace `{`.
  beginGroup,

  /// Closing brace `}`.
  endGroup,

  /// Math shift `$`.
  mathShift,

  /// Alignment tab `&`.
  alignmentTab,

  /// Macro parameter prefix `#`.
  parameter,

  /// Superscript marker `^`.
  superscript,

  /// Subscript marker `_`.
  subscript,

  /// Active tie character `~`.
  active,

  /// Horizontal or line-break whitespace run.
  space,

  /// Single ASCII alphabetic letter.
  letter,

  /// Single non-letter character or surrogate-paired Unicode scalar.
  other,

  /// Line comment `%...` retained for source span continuity.
  comment,
}

/// Immutable token scanned from TeX source with an exact UTF-16 [span].
@immutable
final class TexToken {
  /// Creates a token with [kind], [text], [span], and [catCode].
  const TexToken({
    required this.kind,
    required this.text,
    required this.span,
    required this.catCode,
    this.isControlWord = false,
  });

  /// Syntactic token category.
  final TexTokenKind kind;

  /// Control sequence name (without leading `\`) or token character payload.
  final String text;

  /// Exact half-open UTF-16 code-unit range in the original TeX input.
  final SourceSpan span;

  /// Assigned TeX category code.
  final TexCatCode catCode;

  /// Whether a [TexTokenKind.controlSequence] is an alphabetic control word.
  final bool isControlWord;

  /// Whether this token is a space or comment token ignored in math mode.
  bool get isIgnorableInMath =>
      kind == TexTokenKind.space || kind == TexTokenKind.comment;

  /// Original TeX representation used when serializing or matching templates.
  String get rawText => kind == TexTokenKind.controlSequence ? '\\$text' : text;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexToken &&
          kind == other.kind &&
          text == other.text &&
          span == other.span &&
          catCode == other.catCode &&
          isControlWord == other.isControlWord;

  @override
  int get hashCode => Object.hash(kind, text, span, catCode, isControlWord);

  @override
  String toString() => 'TexToken($kind, "$text", $span)';
}

/// Scans [source] into catcode-annotated [TexToken] values using UTF-16
/// `codeUnitAt` indexing with zero regex backtracking.
List<TexToken> tokenizeTex(String source) {
  final int length = source.length;
  final List<TexToken> tokens = <TexToken>[];
  int i = 0;

  while (i < length) {
    final int unit = source.codeUnitAt(i);
    switch (unit) {
      case 0x5C: // \
        if (i + 1 >= length) {
          tokens.add(
            TexToken(
              kind: TexTokenKind.controlSequence,
              text: '',
              span: SourceSpan(i, length),
              catCode: TexCatCode.escape,
            ),
          );
          i = length;
          break;
        }
        final int next = source.codeUnitAt(i + 1);
        if (_isAsciiLetter(next)) {
          int end = i + 2;
          while (end < length && _isAsciiLetter(source.codeUnitAt(end))) {
            end++;
          }
          tokens.add(
            TexToken(
              kind: TexTokenKind.controlSequence,
              text: source.substring(i + 1, end),
              span: SourceSpan(i, end),
              catCode: TexCatCode.escape,
              isControlWord: true,
            ),
          );
          i = end;
        } else if (next < 128) {
          tokens.add(
            TexToken(
              kind: TexTokenKind.controlSequence,
              text: _asciiSingleChars[next],
              span: SourceSpan(i, i + 2),
              catCode: TexCatCode.escape,
            ),
          );
          i += 2;
        } else {
          final int end = _advanceOneCodePoint(source, i + 1, length);
          tokens.add(
            TexToken(
              kind: TexTokenKind.controlSequence,
              text: source.substring(i + 1, end),
              span: SourceSpan(i, end),
              catCode: TexCatCode.escape,
            ),
          );
          i = end;
        }
      case 0x7B: // {
        tokens.add(
          TexToken(
            kind: TexTokenKind.beginGroup,
            text: '{',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.beginGroup,
          ),
        );
        i++;
      case 0x7D: // }
        tokens.add(
          TexToken(
            kind: TexTokenKind.endGroup,
            text: '}',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.endGroup,
          ),
        );
        i++;
      case 0x24: // $
        tokens.add(
          TexToken(
            kind: TexTokenKind.mathShift,
            text: r'$',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.mathShift,
          ),
        );
        i++;
      case 0x26: // &
        tokens.add(
          TexToken(
            kind: TexTokenKind.alignmentTab,
            text: '&',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.alignmentTab,
          ),
        );
        i++;
      case 0x23: // #
        tokens.add(
          TexToken(
            kind: TexTokenKind.parameter,
            text: '#',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.parameter,
          ),
        );
        i++;
      case 0x5E: // ^
        tokens.add(
          TexToken(
            kind: TexTokenKind.superscript,
            text: '^',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.superscript,
          ),
        );
        i++;
      case 0x5F: // _
        tokens.add(
          TexToken(
            kind: TexTokenKind.subscript,
            text: '_',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.subscript,
          ),
        );
        i++;
      case 0x7E: // ~
        tokens.add(
          TexToken(
            kind: TexTokenKind.active,
            text: '~',
            span: SourceSpan(i, i + 1),
            catCode: TexCatCode.active,
          ),
        );
        i++;
      case 0x25: // %
        int end = i + 1;
        while (end < length) {
          final int cu = source.codeUnitAt(end);
          if (cu == 0x0A || cu == 0x0D) {
            end++;
            if (cu == 0x0D && end < length && source.codeUnitAt(end) == 0x0A) {
              end++;
            }
            break;
          }
          end++;
        }
        tokens.add(
          TexToken(
            kind: TexTokenKind.comment,
            text: source.substring(i, end),
            span: SourceSpan(i, end),
            catCode: TexCatCode.comment,
          ),
        );
        i = end;
      case 0x20: // space
      case 0x09: // tab
      case 0x0A: // LF
      case 0x0D: // CR
      case 0x00A0: // nbsp
        final int start = i;
        final TexCatCode cat = (unit == 0x0A || unit == 0x0D)
            ? TexCatCode.endOfLine
            : TexCatCode.space;
        i++;
        while (i < length && _isWhitespaceUnit(source.codeUnitAt(i))) {
          i++;
        }
        tokens.add(
          TexToken(
            kind: TexTokenKind.space,
            text: (i == start + 1 && unit < 128)
                ? _asciiSingleChars[unit]
                : source.substring(start, i),
            span: SourceSpan(start, i),
            catCode: cat,
          ),
        );
      default:
        if (_isAsciiLetter(unit)) {
          tokens.add(
            TexToken(
              kind: TexTokenKind.letter,
              text: _asciiSingleChars[unit],
              span: SourceSpan(i, i + 1),
              catCode: TexCatCode.letter,
            ),
          );
          i++;
        } else if (unit < 128) {
          tokens.add(
            TexToken(
              kind: TexTokenKind.other,
              text: _asciiSingleChars[unit],
              span: SourceSpan(i, i + 1),
              catCode: TexCatCode.other,
            ),
          );
          i++;
        } else {
          final int end = _advanceOneCodePoint(source, i, length);
          tokens.add(
            TexToken(
              kind: TexTokenKind.other,
              text: source.substring(i, end),
              span: SourceSpan(i, end),
              catCode: TexCatCode.other,
            ),
          );
          i = end;
        }
    }
  }

  return tokens;
}

final List<String> _asciiSingleChars = List<String>.generate(
  128,
  String.fromCharCode,
  growable: false,
);

bool _isAsciiLetter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

bool _isWhitespaceUnit(int unit) =>
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0A ||
    unit == 0x0D ||
    unit == 0x00A0;

int _advanceOneCodePoint(String source, int index, int length) {
  if (index >= length) {
    return length;
  }
  final int first = source.codeUnitAt(index);
  if (first >= 0xD800 && first <= 0xDBFF && index + 1 < length) {
    final int second = source.codeUnitAt(index + 1);
    if (second >= 0xDC00 && second <= 0xDFFF) {
      return index + 2;
    }
  }
  return index + 1;
}
