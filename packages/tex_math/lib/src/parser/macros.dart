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

  Map<String, TexMacroEntry>? _macros;
  Map<String, TexUserEnvDef>? _environments;
  Map<String, String>? _colors;

  /// Macro entries defined in this scope.
  Map<String, TexMacroEntry> get macros =>
      _macros ??= <String, TexMacroEntry>{};

  /// User environment definitions in this scope.
  Map<String, TexUserEnvDef> get environments =>
      _environments ??= <String, TexUserEnvDef>{};

  /// Custom colors defined via `\definecolor` in this scope.
  Map<String, String> get colors => _colors ??= <String, String>{};
}

/// Scoped immutable-lookup table storing macros, user environments, and colors.
final class TexMacroTable {
  /// Initializes the root scope with [preconfiguredMacros].
  TexMacroTable({Map<String, String> preconfiguredMacros = const {}}) {
    final TexScopeFrame root = TexScopeFrame();
    _scopes.add(root);
    if (preconfiguredMacros.isNotEmpty) {
      final Map<String, TexMacroEntry> macros = root.macros;
      for (final MapEntry<String, String> entry
          in preconfiguredMacros.entries) {
        final String name = entry.key.startsWith('\\')
            ? entry.key.substring(1)
            : entry.key;
        final List<TexToken> sourceTokens = tokenizeTex(entry.value);
        final List<TexToken> body = List<TexToken>.generate(
          sourceTokens.length,
          (int i) {
            final TexToken t = sourceTokens[i];
            return TexToken(
              kind: t.kind,
              text: t.text,
              span: SourceSpan.zero,
              catCode: t.catCode,
              isControlWord: t.isControlWord,
            );
          },
          growable: false,
        );
        final int arity = _inferArityFromTokens(body);
        macros[name] = TexUserMacroEntry(
          name: name,
          paramCount: arity,
          body: body,
        );
      }
      _macroCount = macros.length;
    }
  }

  final List<TexScopeFrame> _scopes = <TexScopeFrame>[];
  int _pendingEmptyBraces = 0;
  int _macroCount = 0;
  int _envCount = 0;
  int _colorCount = 0;

  /// Opens a brace-local scope (`{`).
  void pushBraceScope() => _pendingEmptyBraces++;

  /// Closes a brace-local scope (`}`).
  void popBraceScope() {
    if (_pendingEmptyBraces > 0) {
      _pendingEmptyBraces--;
      return;
    }
    if (_scopes.length > 1 &&
        !_scopes.last.isBegingroup &&
        !_scopes.last.isSandbox) {
      _subtractFrameCounts(_scopes.removeLast());
    }
  }

  /// Opens a `\begingroup` scope.
  void pushBegingroup() {
    _flushPendingBraces();
    _scopes.add(TexScopeFrame(isBegingroup: true));
  }

  /// Closes scopes back through the nearest matching `\begingroup`.
  bool popBegingroup() {
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isBegingroup) {
        for (int j = i; j < _scopes.length; j++) {
          _subtractFrameCounts(_scopes[j]);
        }
        _scopes.removeRange(i, _scopes.length);
        _pendingEmptyBraces = 0;
        return true;
      }
      if (_scopes[i].isSandbox) {
        return false;
      }
    }
    return false;
  }

  /// Opens a `\begingroupSandbox` boundary.
  void pushSandbox() {
    _flushPendingBraces();
    _scopes.add(TexScopeFrame(isSandbox: true));
  }

  /// Resets scopes back to and removing the nearest `\begingroupSandbox`.
  bool resetSandbox() {
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isSandbox) {
        for (int j = i; j < _scopes.length; j++) {
          _subtractFrameCounts(_scopes[j]);
        }
        _scopes.removeRange(i, _scopes.length);
        _pendingEmptyBraces = 0;
        return true;
      }
    }
    return false;
  }

  /// Looks up a macro entry by [name] (without leading `\`).
  TexMacroEntry? lookupMacro(String name) {
    if (_macroCount == 0) {
      return null;
    }
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final Map<String, TexMacroEntry>? macros = _scopes[i]._macros;
      if (macros != null) {
        final TexMacroEntry? entry = macros[name];
        if (entry != null) {
          return entry;
        }
      }
    }
    return null;
  }

  /// Looks up a user environment definition by [name].
  TexUserEnvDef? lookupEnvironment(String name) {
    if (_envCount == 0) {
      return null;
    }
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final Map<String, TexUserEnvDef>? environments = _scopes[i]._environments;
      if (environments != null) {
        final TexUserEnvDef? env = environments[name];
        if (env != null) {
          return env;
        }
      }
    }
    return null;
  }

  /// Looks up a `\definecolor` binding by [name].
  String? lookupColor(String name) {
    if (_colorCount == 0) {
      return null;
    }
    final String lower = name.toLowerCase();
    for (int i = _scopes.length - 1; i >= 0; i--) {
      final Map<String, String>? colors = _scopes[i]._colors;
      if (colors != null) {
        final String? value = colors[lower];
        if (value != null) {
          return value;
        }
      }
    }
    return null;
  }

  /// Collects all visible custom colors into a lookup map.
  Map<String, String> visibleColors() {
    if (_colorCount == 0) {
      return const <String, String>{};
    }
    final Map<String, String> merged = <String, String>{};
    for (final TexScopeFrame frame in _scopes) {
      final Map<String, String>? colors = frame._colors;
      if (colors != null) {
        merged.addAll(colors);
      }
    }
    return merged;
  }

  /// Registers a macro in the current scope or root/sandbox scope when [global].
  void defineMacro(String name, TexMacroEntry entry, {bool global = false}) {
    final Map<String, TexMacroEntry> macros = _targetScope(
      global: global,
    ).macros;
    final int prevLength = macros.length;
    macros[name] = entry;
    _macroCount += macros.length - prevLength;
  }

  /// Registers a user environment in the current scope or global scope.
  void defineEnvironment(
    String name,
    TexUserEnvDef def, {
    bool global = false,
  }) {
    final Map<String, TexUserEnvDef> environments = _targetScope(
      global: global,
    ).environments;
    final int prevLength = environments.length;
    environments[name] = def;
    _envCount += environments.length - prevLength;
  }

  /// Registers a custom color in the current or global scope.
  void defineColor(String name, String resolvedHex, {bool global = false}) {
    final Map<String, String> colors = _targetScope(global: global).colors;
    final int prevLength = colors.length;
    colors[name.toLowerCase()] = resolvedHex;
    _colorCount += colors.length - prevLength;
  }

  TexScopeFrame _targetScope({required bool global}) {
    if (!global) {
      _flushPendingBraces();
      return _scopes.last;
    }
    for (int i = _scopes.length - 1; i >= 1; i--) {
      if (_scopes[i].isSandbox) {
        return _scopes[i];
      }
    }
    return _scopes.first;
  }

  void _flushPendingBraces() {
    while (_pendingEmptyBraces > 0) {
      _scopes.add(TexScopeFrame());
      _pendingEmptyBraces--;
    }
  }

  void _subtractFrameCounts(TexScopeFrame frame) {
    final Map<String, TexMacroEntry>? macros = frame._macros;
    if (macros != null) {
      _macroCount -= macros.length;
    }
    final Map<String, TexUserEnvDef>? environments = frame._environments;
    if (environments != null) {
      _envCount -= environments.length;
    }
    final Map<String, String>? colors = frame._colors;
    if (colors != null) {
      _colorCount -= colors.length;
    }
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

/// Shared mutable macro expansion and cumulative token-allocation counters
/// carried across the root [TexTokenCursor] and nested subexpression cursors.
final class TexTokenBudgetState {
  /// Cumulative macro expansions performed across the whole parse.
  int expansionCount = 0;

  /// Cumulative tokens materialized across tokenization and macro substitution.
  int tokenCount = 0;

  /// Records [count] tokens against [budgets] and throws [TexMathBudgetError]
  /// when exceeding [TexMathBudgets.maxTokens].
  void chargeTokens(
    int count, {
    required TexMathBudgets budgets,
    SourceSpan? span,
  }) {
    if (count <= 0) {
      return;
    }
    tokenCount += count;
    if (tokenCount > budgets.maxTokens) {
      throw TexMathBudgetError(
        'Token count ($tokenCount) exceeded maxTokens (${budgets.maxTokens}).',
        budgetName: 'maxTokens',
        limit: budgets.maxTokens,
        actual: tokenCount,
        span: span,
      );
    }
  }
}

/// Substitutes `#1`..`#9` placeholders in [body] with [args], preserving valid
/// [SourceSpan] coordinates on every emitted token and enforcing
/// [TexMathBudgets.maxTokens] via optional [budgetState].
List<TexToken> substituteMacroParams({
  required List<TexToken> body,
  required List<List<TexToken>> args,
  required SourceSpan fallbackSpan,
  TexMathBudgets? budgets,
  TexTokenBudgetState? budgetState,
}) {
  final List<TexToken> result = <TexToken>[];
  for (int i = 0; i < body.length; i++) {
    final TexToken token = body[i];
    if (token.kind == TexTokenKind.parameter && i + 1 < body.length) {
      final TexToken next = body[i + 1];
      if (next.kind == TexTokenKind.parameter) {
        budgetState?.chargeTokens(
          1,
          budgets: budgets ?? const TexMathBudgets(),
          span: fallbackSpan,
        );
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
            final List<TexToken> argTokens = args[argIndex];
            budgetState?.chargeTokens(
              argTokens.length,
              budgets: budgets ?? const TexMathBudgets(),
              span: fallbackSpan,
            );
            result.addAll(argTokens);
          }
          i++;
          continue;
        }
      }
    }
    budgetState?.chargeTokens(
      1,
      budgets: budgets ?? const TexMathBudgets(),
      span: fallbackSpan,
    );
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

/// Queue-backed expandable TeX token cursor enforcing macro depth, expansion,
/// and cumulative token budgets.
final class TexTokenCursor {
  /// Creates a token cursor over [source] and its scanned [initialTokens].
  TexTokenCursor({
    required this.source,
    required List<TexToken> initialTokens,
    required this.budgets,
    TexTokenBudgetState? budgetState,
    int initialMacroDepth = 0,
  }) : budgetState = budgetState ?? TexTokenBudgetState(),
       _minMacroDepth = initialMacroDepth,
       _macroDepth = initialMacroDepth,
       _pending = _reverseTokens(initialTokens) {
    if (budgetState == null) {
      this.budgetState.chargeTokens(initialTokens.length, budgets: budgets);
    }
  }

  /// Raw UTF-16 input string (used for verbatim slicing and span validation).
  final String source;

  /// Safety budgets enforced during expansion.
  final TexMathBudgets budgets;

  /// Shared cumulative expansion and token budget state.
  final TexTokenBudgetState budgetState;

  final int _minMacroDepth;

  /// Reversed stack of queued tokens and frame markers (top is at `last`).
  final List<Object> _pending;

  int _macroDepth;

  /// Total macro/environment expansions executed so far.
  int get expansionCount => budgetState.expansionCount;

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
  /// [TexMathBudgets.maxMacroDepth], [TexMathBudgets.maxMacroExpansions], and
  /// [TexMathBudgets.maxTokens].
  void pushMacroExpansion(
    List<TexToken> tokens, {
    SourceSpan? span,
    bool chargeTokens = true,
  }) {
    budgetState.expansionCount++;
    if (budgetState.expansionCount > budgets.maxMacroExpansions) {
      throw TexMathBudgetError(
        'Macro expansions (${budgetState.expansionCount}) exceeded '
        'maxMacroExpansions (${budgets.maxMacroExpansions}).',
        budgetName: 'maxMacroExpansions',
        limit: budgets.maxMacroExpansions,
        actual: budgetState.expansionCount,
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
    if (chargeTokens) {
      budgetState.chargeTokens(tokens.length, budgets: budgets, span: span);
    }
    _pending.add(const _EndMacroFrame());
    for (int i = tokens.length - 1; i >= 0; i--) {
      _pending.add(tokens[i]);
    }
  }

  /// Zero-allocation lookahead checking whether upcoming non-ignorable tokens
  /// in [_pending] match every non-space token of [delimiter].
  bool matchesDelimiterAhead(List<TexToken> delimiter) {
    _popFinishedFrames();
    int pendingIdx = _pending.length - 1;
    for (int i = 0; i < delimiter.length; i++) {
      final TexToken exp = delimiter[i];
      if (exp.kind == TexTokenKind.space) {
        continue;
      }
      TexToken? matched;
      while (pendingIdx >= 0) {
        final Object item = _pending[pendingIdx--];
        if (item is _EndMacroFrame) {
          continue;
        }
        final TexToken candidate = item as TexToken;
        if (candidate.isIgnorableInMath) {
          continue;
        }
        matched = candidate;
        break;
      }
      if (matched == null ||
          matched.kind != exp.kind ||
          matched.text != exp.text) {
        return false;
      }
    }
    return true;
  }

  /// Consumes the non-ignorable tokens matched by [matchesDelimiterAhead].
  void consumeDelimiterAhead(List<TexToken> delimiter) {
    for (int i = 0; i < delimiter.length; i++) {
      if (delimiter[i].kind == TexTokenKind.space) {
        continue;
      }
      next();
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
      if (_macroDepth > _minMacroDepth) {
        _macroDepth--;
      }
    }
  }
}

final class _EndMacroFrame {
  const _EndMacroFrame();
}

List<Object> _reverseTokens(List<TexToken> tokens) {
  final int count = tokens.length;
  final List<Object> reversed = List<Object>.filled(
    count,
    const _EndMacroFrame(),
    growable: true,
  );
  for (int i = 0; i < count; i++) {
    reversed[count - 1 - i] = tokens[i];
  }
  return reversed;
}
