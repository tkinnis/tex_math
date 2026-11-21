import 'package:meta/meta.dart';

import '../error.dart';
import '../options.dart';
import '../source_span.dart';
import 'tokenizer.dart';

/// Base sealed entry stored in the scoped TeX macro and definition table.
@immutable
sealed class TexMacroEntry {
  /// Creates a macro table entry.
  const TexMacroEntry();
}

/// User-defined macro (`\newcommand`, `\renewcommand`, `\def`, `\edef`, etc.).
@immutable
final class TexUserMacroEntry extends TexMacroEntry {
  /// Creates a user-defined macro specification.
  const TexUserMacroEntry({
    required this.name,
    required this.paramCount,
    required this.body,
    this.defaultArg,
    this.preDelimiter = const <TexToken>[],
    this.paramDelimiters = const <List<TexToken>>[],
  });

  /// Control sequence name without leading backslash.
  final String name;

  /// Number of parameters (`0`..`9`).
  final int paramCount;

  /// Optional default token list for `#1` (`\newcommand{\f}[n][default]{...}`).
  final List<TexToken>? defaultArg;

  /// Literal tokens required immediately before `#1` for `\def` templates.
  final List<TexToken> preDelimiter;

  /// Delimiter token sequences expected after each parameter `#1`..`#n`.
  final List<List<TexToken>> paramDelimiters;

  /// Unexpanded replacement token sequence containing `#1`..`#9` placeholders.
  final List<TexToken> body;
}

/// `\let` alias binding a control sequence to an existing built-in command or
/// character token.
@immutable
final class TexAliasEntry extends TexMacroEntry {
  /// Creates an alias targeting [targetCommand] or a literal [literalToken].
  const TexAliasEntry({this.targetCommand, this.literalToken});

  /// Target control sequence name (without `\`).
  final String? targetCommand;

  /// Literal non-escape token bound via `\let\cs=<char>`.
  final TexToken? literalToken;
}

/// User-declared math operator (`\DeclareMathOperator` / `*`).
@immutable
final class TexDeclaredOperatorEntry extends TexMacroEntry {
  /// Creates a declared operator definition.
  const TexDeclaredOperatorEntry({
    required this.name,
    required this.body,
    required this.hasLimits,
  });

  /// Control sequence name without leading `\`.
  final String name;

  /// Operator body tokens (e.g. `Tr` or `arg\,max`).
  final List<TexToken> body;

  /// Whether `\DeclareMathOperator*` enables display limits above/below.
  final bool hasLimits;
}

/// User-declared paired delimiter (`\DeclarePairedDelimiter`).
@immutable
final class TexPairedDelimiterEntry extends TexMacroEntry {
  /// Creates a paired delimiter definition.
  const TexPairedDelimiterEntry({
    required this.name,
    required this.leftDelimiter,
    required this.rightDelimiter,
  });

  /// Control sequence name without leading `\`.
  final String name;

  /// Left delimiter string.
  final String leftDelimiter;

  /// Right delimiter string.
  final String rightDelimiter;
}

/// User-declared extensible arrow (`\Newextarrow`).
@immutable
final class TexExtArrowEntry extends TexMacroEntry {
  /// Creates an extensible arrow definition for [codePoint].
  const TexExtArrowEntry({required this.name, required this.codePoint});

  /// Control sequence name without leading `\`.
  final String name;

  /// Unicode scalar code point of the extensible arrow character.
  final int codePoint;
}

/// User-defined environment (`\newenvironment` / `\renewenvironment`).
@immutable
final class TexUserEnvDef {
  /// Creates a user-defined environment specification.
  const TexUserEnvDef({
    required this.name,
    required this.paramCount,
    required this.beginBody,
    required this.endBody,
    this.defaultArg,
  });

  /// Environment name.
  final String name;

  /// Number of arguments (`0`..`9`).
  final int paramCount;

  /// Optional default token list for `#1`.
  final List<TexToken>? defaultArg;

  /// Replacement tokens expanded at `\begin{name}`.
  final List<TexToken> beginBody;

  /// Replacement tokens expanded at `\end{name}`.
  final List<TexToken> endBody;
}

/// Scoped symbol/macro/environment/color frame managed during parsing.
final class TexScopeFrame {
  /// Creates a scope frame.
  TexScopeFrame({this.isBegingroup = false, this.isSandbox = false});

  /// Whether this frame was opened by `\begingroup`.
  final bool isBegingroup;

  /// Whether this frame was opened by `\begingroupSandbox`.
  final bool isSandbox;

  /// Macro entries defined in this scope.
  final Map<String, TexMacroEntry> macros = <String, TexMacroEntry>{};

  /// User environment definitions in this scope.
  final Map<String, TexUserEnvDef> environments = <String, TexUserEnvDef>{};

  /// Custom colors defined via `\definecolor` in this scope.
  final Map<String, String> colors = <String, String>{};
}

/// Scoped immutable-lookup table storing macros, user environments, and colors.
final class TexMacroTable {
  /// Initializes the root scope with [preconfiguredMacros].
  TexMacroTable({Map<String, String> preconfiguredMacros = const {}}) {
    _scopes.add(TexScopeFrame());
    for (final MapEntry<String, String> entry in preconfiguredMacros.entries) {
      final String name = entry.key.startsWith('\\')
          ? entry.key.substring(1)
          : entry.key;
      final List<TexToken> body = tokenizeTex(entry.value)
          .map(
            (TexToken t) => TexToken(
              kind: t.kind,
              text: t.text,
              span: SourceSpan.zero,
              catCode: t.catCode,
              isControlWord: t.isControlWord,
            ),
          )
          .toList();
      final int arity = _inferArityFromTokens(body);
      _scopes.first.macros[name] = TexUserMacroEntry(
        name: name,
        paramCount: arity,
        body: body,
      );
    }
  }

  final List<TexScopeFrame> _scopes = <TexScopeFrame>[];

  /// Opens a brace-local scope (`{`).
  void pushBraceScope() => _scopes.add(TexScopeFrame());

  /// Closes a brace-local scope (`}`).
  void popBraceScope() {
    if (_scopes.length > 1 &&
        !_scopes.last.isBegingroup &&
        !_scopes.last.isSandbox) {
      _scopes.removeLast();
    }
  }

  /// Opens a `\begingroup` scope.
  void pushBegingroup() => _scopes.add(TexScopeFrame(isBegingroup: true));

  /// Closes scopes back through the nearest matching `\begingroup`.
  bool popBegingroup() {
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isBegingroup) {
        _scopes.removeRange(i, _scopes.length);
        return true;
      }
      if (_scopes[i].isSandbox) {
        return false;
      }
    }
    return false;
  }

  /// Opens a `\begingroupSandbox` boundary.
  void pushSandbox() => _scopes.add(TexScopeFrame(isSandbox: true));

  /// Resets scopes back to and removing the nearest `\begingroupSandbox`.
  bool resetSandbox() {
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isSandbox) {
        _scopes.removeRange(i, _scopes.length);
        return true;
      }
    }
    return false;
  }

  /// Looks up a macro entry by [name] (without leading `\`).
  TexMacroEntry? lookupMacro(String name) {
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final TexMacroEntry? entry = _scopes[i].macros[name];
      if (entry != null) {
        return entry;
      }
    }
    return null;
  }

  /// Looks up a user environment definition by [name].
  TexUserEnvDef? lookupEnvironment(String name) {
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final TexUserEnvDef? env = _scopes[i].environments[name];
      if (env != null) {
        return env;
      }
    }
    return null;
  }

  /// Looks up a `\definecolor` binding by [name].
  String? lookupColor(String name) {
    final String lower = name.toLowerCase();
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final String? value = _scopes[i].colors[lower];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Collects all visible custom colors into a lookup map.
  Map<String, String> visibleColors() {
    final Map<String, String> merged = <String, String>{};
    for (final TexScopeFrame frame in _scopes) {
      merged.addAll(frame.colors);
    }
    return merged;
  }

  /// Registers a macro in the current scope or root/sandbox scope when [global].
  void defineMacro(String name, TexMacroEntry entry, {bool global = false}) {
    _targetScope(global: global).macros[name] = entry;
  }

  /// Registers a user environment in the current scope or global scope.
  void defineEnvironment(
    String name,
    TexUserEnvDef def, {
    bool global = false,
  }) {
    _targetScope(global: global).environments[name] = def;
  }

  /// Registers a custom color in the current or global scope.
  void defineColor(String name, String resolvedHex, {bool global = false}) {
    _targetScope(global: global).colors[name.toLowerCase()] = resolvedHex;
  }

  TexScopeFrame _targetScope({required bool global}) {
    if (!global) {
      return _scopes.last;
    }
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isSandbox) {
        return _scopes[i];
      }
    }
    return _scopes.first;
  }
}

int _inferArityFromTokens(List<TexToken> tokens) {
  int maxParam = 0;
  for (int i = 0; i < tokens.length - 1; i++) {
    if (tokens[i].kind == TexTokenKind.parameter) {
      final TexToken next = tokens[i + 1];
      if (next.kind == TexTokenKind.parameter) {
        i++;
        continue;
      }
      if (next.kind == TexTokenKind.other && next.text.length == 1) {
        final int code = next.text.codeUnitAt(0);
        if (code >= 0x31 && code <= 0x39) {
          final int n = code - 0x30;
          if (n > maxParam) {
            maxParam = n;
          }
        }
      }
    }
  }
  return maxParam;
}

/// Validates parameter references `#1`..`#9` inside a macro body and returns
/// normalized replacement tokens.
List<TexToken> validateMacroBody({
  required List<TexToken> body,
  required int paramCount,
  required String commandName,
  required SourceSpan? span,
}) {
  for (int i = 0; i < body.length; i++) {
    if (body[i].kind == TexTokenKind.parameter) {
      if (i + 1 >= body.length) {
        throw TexMathMacroError(
          'Trailing # parameter marker in definition of \\$commandName.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: body[i].span,
        );
      }
      final TexToken next = body[i + 1];
      if (next.kind == TexTokenKind.parameter) {
        i++;
        continue;
      }
      if (next.kind != TexTokenKind.other || next.text.length != 1) {
        throw TexMathMacroError(
          'Illegal parameter reference in definition of \\$commandName.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: next.span,
        );
      }
      final int code = next.text.codeUnitAt(0);
      if (code < 0x31 || code > 0x39) {
        throw TexMathMacroError(
          'Illegal parameter number #${next.text} in \\$commandName.',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: next.span,
        );
      }
      final int index = code - 0x30;
      if (index > paramCount) {
        throw TexMathMacroError(
          'Illegal parameter #$index in \\$commandName expecting $paramCount '
          'parameter(s).',
          errorClass: TexMathErrorClass.invalidMacroDefinition,
          span: span ?? next.span,
        );
      }
      i++;
    }
  }
  return body;
}

/// Substitutes `#1`..`#9` placeholders in [body] with [args], preserving valid
/// [SourceSpan] coordinates on every emitted token.
List<TexToken> substituteMacroParams({
  required List<TexToken> body,
  required List<List<TexToken>> args,
  required SourceSpan fallbackSpan,
}) {
  final List<TexToken> result = <TexToken>[];
  for (int i = 0; i < body.length; i++) {
    final TexToken token = body[i];
    if (token.kind == TexTokenKind.parameter && i + 1 < body.length) {
      final TexToken next = body[i + 1];
      if (next.kind == TexTokenKind.parameter) {
        result.add(
          TexToken(
            kind: TexTokenKind.parameter,
            text: '#',
            span: token.span,
            catCode: TexCatCode.parameter,
          ),
        );
        i++;
        continue;
      }
      if (next.kind == TexTokenKind.other && next.text.length == 1) {
        final int code = next.text.codeUnitAt(0);
        if (code >= 0x31 && code <= 0x39) {
          final int argIndex = code - 0x31;
          if (argIndex < args.length) {
            result.addAll(args[argIndex]);
          }
          i++;
          continue;
        }
      }
    }
    result.add(
      TexToken(
        kind: token.kind,
        text: token.text,
        span: token.span.end <= fallbackSpan.end ? token.span : fallbackSpan,
        catCode: token.catCode,
        isControlWord: token.isControlWord,
      ),
    );
  }
  return result;
}

/// Queue-backed expandable TeX token cursor enforcing macro depth and total
/// expansion budgets.
final class TexTokenCursor {
  /// Creates a token cursor over [source] and its scanned [initialTokens].
  TexTokenCursor({
    required this.source,
    required List<TexToken> initialTokens,
    required this.budgets,
  }) : _pending = List<Object>.of(initialTokens.reversed);

  /// Raw UTF-16 input string (used for verbatim slicing and span validation).
  final String source;

  /// Safety budgets enforced during expansion.
  final TexMathBudgets budgets;

  /// Reversed stack of queued tokens and frame markers (top is at `last`).
  final List<Object> _pending;

  int _macroDepth = 0;
  int _expansionCount = 0;

  /// Total macro/environment expansions executed so far.
  int get expansionCount => _expansionCount;

  /// Current active macro expansion depth.
  int get macroDepth => _macroDepth;

  /// Whether no further non-marker tokens remain in the stream.
  bool get isAtEnd => peekRaw() == null;

  /// Removes leading macro-frame sentinel markers and returns the next raw
  /// token without skipping spaces or comments.
  TexToken? peekRaw() {
    _popFinishedFrames();
    if (_pending.isEmpty) {
      return null;
    }
    return _pending.last as TexToken;
  }

  /// Peeks the next token skipping comments (and optionally spaces).
  TexToken? peek({bool skipSpaces = true}) {
    _popFinishedFrames();
    for (int i = _pending.length - 1; i >= 0; i--) {
      final Object item = _pending[i];
      if (item is _EndMacroFrame) {
        continue;
      }
      final TexToken token = item as TexToken;
      if (token.kind == TexTokenKind.comment) {
        continue;
      }
      if (skipSpaces && token.kind == TexTokenKind.space) {
        continue;
      }
      return token;
    }
    return null;
  }

  /// Consumes and returns the next raw token (skipping frame markers only).
  TexToken? nextRaw() {
    _popFinishedFrames();
    if (_pending.isEmpty) {
      return null;
    }
    return _pending.removeLast() as TexToken;
  }

  /// Consumes comments (and optionally spaces), then returns and removes the
  /// next token.
  TexToken? next({bool skipSpaces = true}) {
    while (true) {
      final TexToken? token = peekRaw();
      if (token == null) {
        return null;
      }
      if (token.kind == TexTokenKind.comment ||
          (skipSpaces && token.kind == TexTokenKind.space)) {
        _pending.removeLast();
        continue;
      }
      _pending.removeLast();
      return token;
    }
  }

  /// Skips any leading spaces and comments.
  void skipIgnorable() {
    while (true) {
      final TexToken? token = peekRaw();
      if (token == null || !token.isIgnorableInMath) {
        return;
      }
      _pending.removeLast();
    }
  }

  /// Skips horizontal/newline space tokens and comments immediately after a
  /// control word in text mode.
  void skipSpaces() => skipIgnorable();

  /// Pushes [tokens] back onto the front of the token stream without counting a
  /// macro expansion.
  void pushTokens(List<TexToken> tokens) {
    for (int i = tokens.length - 1; i >= 0; i--) {
      _pending.add(tokens[i]);
    }
  }

  /// Pushes a macro expansion [tokens] onto the stream while enforcing
  /// [TexMathBudgets.maxMacroDepth] and [TexMathBudgets.maxMacroExpansions].
  void pushMacroExpansion(List<TexToken> tokens, {SourceSpan? span}) {
    _expansionCount++;
    if (_expansionCount > budgets.maxMacroExpansions) {
      throw TexMathBudgetError(
        'Macro expansions ($_expansionCount) exceeded maxMacroExpansions '
        '(${budgets.maxMacroExpansions}).',
        budgetName: 'maxMacroExpansions',
        limit: budgets.maxMacroExpansions,
        actual: _expansionCount,
        span: span,
      );
    }
    _macroDepth++;
    if (_macroDepth > budgets.maxMacroDepth) {
      throw TexMathBudgetError(
        'Macro nesting depth ($_macroDepth) exceeded maxMacroDepth '
        '(${budgets.maxMacroDepth}).',
        budgetName: 'maxMacroDepth',
        limit: budgets.maxMacroDepth,
        actual: _macroDepth,
        span: span,
      );
    }
    _pending.add(const _EndMacroFrame());
    for (int i = tokens.length - 1; i >= 0; i--) {
      _pending.add(tokens[i]);
    }
  }

  /// Advances past all queued source tokens whose `span.start < targetOffset`
  /// (used after reading verbatim raw slices like `\verb|...|` directly from
  /// [source]).
  void discardRawUntilOffset(int targetOffset) {
    while (true) {
      _popFinishedFrames();
      if (_pending.isEmpty) {
        return;
      }
      final TexToken token = _pending.last as TexToken;
      if (token.span.start >= targetOffset) {
        return;
      }
      _pending.removeLast();
    }
  }

  /// Returns a safe source span around the current cursor position.
  SourceSpan currentSpan() {
    final TexToken? t = peek(skipSpaces: false);
    if (t != null) {
      return t.span;
    }
    return SourceSpan.empty(source.length);
  }

  void _popFinishedFrames() {
    while (_pending.isNotEmpty && _pending.last is _EndMacroFrame) {
      _pending.removeLast();
      if (_macroDepth > 0) {
        _macroDepth--;
      }
    }
  }
}

final class _EndMacroFrame {
  const _EndMacroFrame();
}
