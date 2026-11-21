import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'source_span.dart';

/// Machine-readable error categories aligned to MathJax TeX error classes.
enum TexMathErrorClass {
  /// Reference to an unknown TeX control sequence or macro.
  undefinedControlSequence,

  /// Expected closing or opening brace missing from input.
  missingBrace,

  /// Unexpected closing brace without a matching opening brace.
  extraBrace,

  /// Alignment tab `&` encountered outside an alignment environment.
  misplacedAlignmentTab,

  /// Row separator `\\` or `\cr` encountered outside an alignment context.
  misplacedNewline,

  /// Opening delimiter lacking a paired closing delimiter.
  missingDelimiter,

  /// Closing delimiter lacking a paired opening delimiter.
  extraDelimiter,

  /// Environment `\end{...}` does not match the active `\begin{...}`.
  mismatchedEnvironment,

  /// Multiple superscripts or subscripts attached to the same base atom.
  doubleScript,

  /// Command or construct is missing a required argument.
  missingArgument,

  /// Malformed `\newcommand`, `\renewcommand`, `\def`, or `\newenvironment`.
  invalidMacroDefinition,

  /// Unknown TeX environment name in `\begin{...}`.
  unknownEnvironment,

  /// Input, recursion, nesting, output item, or SVG byte budget exceeded.
  budgetExceeded,

  /// Invalid, empty, or corrupt OpenType font payload.
  invalidFont,

  /// Requested TeX feature, package, or pipeline stage is unimplemented.
  unsupportedFeature,

  /// General TeX syntax error not covered by a narrower class.
  syntaxError,
}

/// Base sealed exception thrown when parsing, expanding, laying out, or
/// exporting TeX math input fails.
@immutable
sealed class TexMathError implements Exception {
  /// Creates a TeX math error with a diagnostic [message], [errorClass], and
  /// optional source [span].
  const TexMathError(this.message, {required this.errorClass, this.span});

  /// Human-readable error description.
  final String message;

  /// Machine-readable classification of this error.
  final TexMathErrorClass errorClass;

  /// Optional UTF-16 source range where the error occurred.
  final SourceSpan? span;

  /// 1-based UTF-16 character index where the error occurred, or `null` when
  /// [span] is absent.
  int? get position => span == null ? null : span!.start + 1;

  /// Human-readable [message] annotated with `(at position <position>)` when
  /// [span] is present.
  String get formattedMessage =>
      span == null ? message : '$message (at position ${span!.start + 1})';

  /// Formats [formattedMessage] alongside [source] and a caret underline
  /// pointing at [span], or returns [formattedMessage] when [span] is `null`.
  String formatWithSource(String source) {
    final SourceSpan? activeSpan = span;
    if (activeSpan == null) {
      return formattedMessage;
    }
    final int col = activeSpan.start.clamp(0, source.length);
    final int end = activeSpan.end.clamp(col, source.length);
    final int caretWidth = math.max(1, end - col);
    return '$formattedMessage\n$source\n${' ' * col}${'^' * caretWidth}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathError &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          errorClass == other.errorClass &&
          span == other.span;

  @override
  int get hashCode => Object.hash(runtimeType, message, errorClass, span);

  @override
  String toString() {
    final String spanSuffix = span == null ? '' : ' at $span';
    return '$runtimeType(${errorClass.name}$spanSuffix): $message';
  }
}

/// Syntax error encountered while tokenizing or parsing TeX math input.
@immutable
final class TexMathSyntaxError extends TexMathError {
  /// Creates a syntax error with [message], [errorClass], and optional [span].
  const TexMathSyntaxError(
    super.message, {
    super.errorClass = TexMathErrorClass.syntaxError,
    super.span,
  });
}

/// Error raised during macro definition validation or macro expansion.
@immutable
final class TexMathMacroError extends TexMathError {
  /// Creates a macro error with [message], [errorClass], and optional [span].
  const TexMathMacroError(
    super.message, {
    super.errorClass = TexMathErrorClass.invalidMacroDefinition,
    super.span,
  });
}

/// Error raised when input, macro recursion, AST nesting, output item count,
/// SVG output length, or font byte size exceeds a configured safety budget.
@immutable
final class TexMathBudgetError extends TexMathError {
  /// Creates a budget error with [message], optional [budgetName], [limit],
  /// [actual], and [span].
  const TexMathBudgetError(
    super.message, {
    this.budgetName,
    this.limit,
    this.actual,
    super.span,
  }) : super(errorClass: TexMathErrorClass.budgetExceeded);

  /// Identifier of the budget that was exceeded, if known.
  final String? budgetName;

  /// Maximum allowed value for [budgetName].
  final int? limit;

  /// Observed value that exceeded [limit].
  final int? actual;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TexMathBudgetError &&
          budgetName == other.budgetName &&
          limit == other.limit &&
          actual == other.actual;

  @override
  int get hashCode => Object.hash(super.hashCode, budgetName, limit, actual);
}

/// Error raised when loading or decoding an OpenType math font fails.
@immutable
final class TexMathFontError extends TexMathError {
  /// Creates a font error with [message], [errorClass], and optional [span].
  const TexMathFontError(
    super.message, {
    super.errorClass = TexMathErrorClass.invalidFont,
    super.span,
  });
}

/// Error raised when a requested TeX feature or pipeline stage is not yet
/// supported by the active engine build.
@immutable
final class TexMathUnsupportedError extends TexMathError {
  /// Creates an unsupported-feature error with [message], [errorClass], and
  /// optional [span].
  const TexMathUnsupportedError(
    super.message, {
    super.errorClass = TexMathErrorClass.unsupportedFeature,
    super.span,
  });
}
