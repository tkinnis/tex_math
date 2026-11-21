import 'package:meta/meta.dart';

import 'error.dart';
import 'options.dart';
import 'source_span.dart';

/// TeX math layout styles corresponding to Appendix G style transitions.
enum TexMathStyle {
  /// Display style (`\displaystyle`).
  display,

  /// Inline text style (`\textstyle`).
  text,

  /// First-level script style (`\scriptstyle`).
  script,

  /// Nested script style (`\scriptscriptstyle`).
  scriptScript,

  /// Cramped display style (e.g. under radicals or denominators).
  crampedDisplay,

  /// Cramped text style.
  crampedText,

  /// Cramped first-level script style.
  crampedScript,

  /// Cramped nested script style.
  crampedScriptScript,
}

/// Base sealed node of the typed TeX math syntax tree.
///
/// Every AST node preserves its UTF-16 [span] within the input source for
/// diagnostic reporting, accessibility, and source extraction.
@immutable
sealed class MathNode {
  /// Base constructor requiring a source [span].
  const MathNode({required this.span});

  /// Source span in the original TeX input.
  final SourceSpan span;
}

/// Root node of a parsed TeX mathematical expression.
@immutable
final class MathRootNode extends MathNode {
  /// Creates a root node with [children] and [displayMode].
  const MathRootNode({
    required super.span,
    required this.children,
    this.displayMode = TexMathDisplayMode.display,
  });

  /// Ordered top-level child nodes.
  final List<MathNode> children;

  /// Effective display mode for this expression.
  final TexMathDisplayMode displayMode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathRootNode &&
          span == other.span &&
          displayMode == other.displayMode &&
          _nodeListEquals(children, other.children);

  @override
  int get hashCode => Object.hash(span, displayMode, Object.hashAll(children));

  @override
  String toString() =>
      'MathRootNode(span: $span, displayMode: $displayMode, '
      'children: ${children.length})';
}

/// Brace-delimited or implicit mathematical sub-group `{...}`.
@immutable
final class MathGroupNode extends MathNode {
  /// Creates a group node wrapping [children].
  const MathGroupNode({
    required super.span,
    required this.children,
    this.isExplicitGroup = true,
  });

  /// Ordered child nodes inside the group.
  final List<MathNode> children;

  /// Whether the group came from explicit `{...}` braces.
  final bool isExplicitGroup;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathGroupNode &&
          span == other.span &&
          isExplicitGroup == other.isExplicitGroup &&
          _nodeListEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(span, isExplicitGroup, Object.hashAll(children));

  @override
  String toString() =>
      'MathGroupNode(span: $span, isExplicitGroup: $isExplicitGroup, '
      'children: ${children.length})';
}

/// Leaf symbol node such as an identifier, numeral, relation, or punctuation.
@immutable
final class SymbolNode extends MathNode {
  /// Creates a symbol node for [value].
  const SymbolNode({required super.span, required this.value, this.command});

  /// Unicode symbol text represented by this node.
  final String value;

  /// Original TeX control sequence name if produced from a command.
  final String? command;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SymbolNode &&
          span == other.span &&
          value == other.value &&
          command == other.command;

  @override
  int get hashCode => Object.hash(span, value, command);

  @override
  String toString() =>
      'SymbolNode(span: $span, value: $value, command: $command)';
}

/// Large or named mathematical operator such as `\sum`, `\int`, or `\lim`.
@immutable
final class OperatorNode extends MathNode {
  /// Creates an operator node for [operatorName].
  const OperatorNode({
    required super.span,
    required this.operatorName,
    this.hasLimits = false,
    this.isLarge = false,
  });

  /// Operator text or control sequence name.
  final String operatorName;

  /// Whether scripts attach above and below in display style.
  final bool hasLimits;

  /// Whether this operator uses display-size glyph variants.
  final bool isLarge;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperatorNode &&
          span == other.span &&
          operatorName == other.operatorName &&
          hasLimits == other.hasLimits &&
          isLarge == other.isLarge;

  @override
  int get hashCode => Object.hash(span, operatorName, hasLimits, isLarge);

  @override
  String toString() =>
      'OperatorNode(span: $span, operatorName: $operatorName, '
      'hasLimits: $hasLimits, isLarge: $isLarge)';
}

/// Fraction or binomial construct (`\frac`, `\dfrac`, `\tfrac`, `\binom`).
@immutable
final class FractionNode extends MathNode {
  /// Creates a fraction node with [numerator] and [denominator].
  const FractionNode({
    required super.span,
    required this.numerator,
    required this.denominator,
    this.ruleThicknessEm,
    this.leftDelimiter,
    this.rightDelimiter,
  });

  /// Upper numerator subtree.
  final MathNode numerator;

  /// Lower denominator subtree.
  final MathNode denominator;

  /// Optional explicit fraction bar thickness in ems; `0` omits the bar.
  final double? ruleThicknessEm;

  /// Optional left enclosing delimiter (e.g. `(` for `\binom`).
  final String? leftDelimiter;

  /// Optional right enclosing delimiter (e.g. `)` for `\binom`).
  final String? rightDelimiter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FractionNode &&
          span == other.span &&
          numerator == other.numerator &&
          denominator == other.denominator &&
          ruleThicknessEm == other.ruleThicknessEm &&
          leftDelimiter == other.leftDelimiter &&
          rightDelimiter == other.rightDelimiter;

  @override
  int get hashCode => Object.hash(
    span,
    numerator,
    denominator,
    ruleThicknessEm,
    leftDelimiter,
    rightDelimiter,
  );

  @override
  String toString() =>
      'FractionNode(span: $span, ruleThicknessEm: $ruleThicknessEm)';
}

/// Subscript and/or superscript attachment around a [base] node.
@immutable
final class ScriptNode extends MathNode {
  /// Creates a script node attached to [base].
  const ScriptNode({
    required super.span,
    required this.base,
    this.subscript,
    this.superscript,
    this.limitsAboveBelow = false,
  });

  /// Base expression receiving the scripts.
  final MathNode base;

  /// Optional subscript expression (`_`).
  final MathNode? subscript;

  /// Optional superscript expression (`^`).
  final MathNode? superscript;

  /// Whether scripts should be stacked as limits above and below [base].
  final bool limitsAboveBelow;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptNode &&
          span == other.span &&
          base == other.base &&
          subscript == other.subscript &&
          superscript == other.superscript &&
          limitsAboveBelow == other.limitsAboveBelow;

  @override
  int get hashCode =>
      Object.hash(span, base, subscript, superscript, limitsAboveBelow);

  @override
  String toString() =>
      'ScriptNode(span: $span, limitsAboveBelow: $limitsAboveBelow)';
}

/// Square or nth root construct (`\sqrt[index]{radicand}`).
@immutable
final class RadicalNode extends MathNode {
  /// Creates a radical node over [radicand] with optional [index].
  const RadicalNode({required super.span, required this.radicand, this.index});

  /// Expression under the radical vinculum.
  final MathNode radicand;

  /// Optional root degree index expression.
  final MathNode? index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RadicalNode &&
          span == other.span &&
          radicand == other.radicand &&
          index == other.index;

  @override
  int get hashCode => Object.hash(span, radicand, index);

  @override
  String toString() => 'RadicalNode(span: $span, hasIndex: ${index != null})';
}

/// Mathematical accent applied above or below a [base] expression.
@immutable
final class AccentNode extends MathNode {
  /// Creates an accent node applying [accent] to [base].
  const AccentNode({
    required super.span,
    required this.base,
    required this.accent,
    this.isWide = false,
    this.isUnder = false,
  });

  /// Base expression receiving the accent.
  final MathNode base;

  /// Accent symbol or command name (e.g. `hat`, `widehat`, `bar`).
  final String accent;

  /// Whether the accent stretches across wide bases.
  final bool isWide;

  /// Whether the accent is placed underneath [base].
  final bool isUnder;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccentNode &&
          span == other.span &&
          base == other.base &&
          accent == other.accent &&
          isWide == other.isWide &&
          isUnder == other.isUnder;

  @override
  int get hashCode => Object.hash(span, base, accent, isWide, isUnder);

  @override
  String toString() =>
      'AccentNode(span: $span, accent: $accent, isWide: $isWide, '
      'isUnder: $isUnder)';
}

/// Paired or scaled delimiter group (`\left...\right` or `\big...`).
@immutable
final class DelimiterNode extends MathNode {
  /// Creates a delimited group node around [children].
  const DelimiterNode({
    required super.span,
    required this.children,
    this.leftDelimiter,
    this.rightDelimiter,
    this.fixedSizeEm,
  });

  /// Expressions enclosed between the delimiters.
  final List<MathNode> children;

  /// Left delimiter symbol, or `null` for `\left.`.
  final String? leftDelimiter;

  /// Right delimiter symbol, or `null` for `\right.`.
  final String? rightDelimiter;

  /// Fixed delimiter height override in ems, or `null` for stretchy sizing.
  final double? fixedSizeEm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DelimiterNode &&
          span == other.span &&
          leftDelimiter == other.leftDelimiter &&
          rightDelimiter == other.rightDelimiter &&
          fixedSizeEm == other.fixedSizeEm &&
          _nodeListEquals(children, other.children);

  @override
  int get hashCode => Object.hash(
    span,
    leftDelimiter,
    rightDelimiter,
    fixedSizeEm,
    Object.hashAll(children),
  );

  @override
  String toString() =>
      'DelimiterNode(span: $span, left: $leftDelimiter, '
      'right: $rightDelimiter)';
}

/// Rectangular grid, array, or alignment environment node.
@immutable
final class MatrixNode extends MathNode {
  /// Creates a matrix or alignment node with [rows] and [environment].
  const MatrixNode({
    required super.span,
    required this.rows,
    required this.environment,
    this.columnAlignments = const <String>[],
  });

  /// Two-dimensional list of cell nodes arranged by row then column.
  final List<List<MathNode>> rows;

  /// TeX environment name (e.g. `pmatrix`, `align`, `array`).
  final String environment;

  /// Optional column alignment specifiers (`l`, `c`, `r`).
  final List<String> columnAlignments;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixNode &&
          span == other.span &&
          environment == other.environment &&
          _stringListEquals(columnAlignments, other.columnAlignments) &&
          _matrixRowsEquals(rows, other.rows);

  @override
  int get hashCode => Object.hash(
    span,
    environment,
    Object.hashAll(columnAlignments),
    Object.hashAll(rows.map(Object.hashAll)),
  );

  @override
  String toString() =>
      'MatrixNode(span: $span, environment: $environment, '
      'rows: ${rows.length})';
}

/// Text-mode run embedded inside math mode (`\text`, `\mathrm`, `\textbf`).
@immutable
final class TextNode extends MathNode {
  /// Creates a text-mode node for [text].
  const TextNode({required super.span, required this.text, this.styleCommand});

  /// Plain text payload.
  final String text;

  /// Optional TeX font or text wrapper command (e.g. `text`, `textbf`).
  final String? styleCommand;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextNode &&
          span == other.span &&
          text == other.text &&
          styleCommand == other.styleCommand;

  @override
  int get hashCode => Object.hash(span, text, styleCommand);

  @override
  String toString() =>
      'TextNode(span: $span, text: $text, styleCommand: $styleCommand)';
}

/// Explicit horizontal spacing atom (`\,`, `\:`, `\;`, `\quad`, `\hspace`).
@immutable
final class SpaceNode extends MathNode {
  /// Creates an explicit horizontal space node of [widthEm] ems.
  const SpaceNode({required super.span, required this.widthEm, this.command});

  /// Horizontal width in ems (negative for `\!`).
  final double widthEm;

  /// Optional TeX spacing command name.
  final String? command;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpaceNode &&
          span == other.span &&
          widthEm == other.widthEm &&
          command == other.command;

  @override
  int get hashCode => Object.hash(span, widthEm, command);

  @override
  String toString() =>
      'SpaceNode(span: $span, widthEm: $widthEm, command: $command)';
}

/// Style override node (`\displaystyle`, `\textstyle`, `\scriptstyle`).
@immutable
final class StyleNode extends MathNode {
  /// Creates a style node switching [children] to [style].
  const StyleNode({
    required super.span,
    required this.style,
    required this.children,
  });

  /// Target Appendix G math layout style.
  final TexMathStyle style;

  /// Subtree nodes laid out under [style].
  final List<MathNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StyleNode &&
          span == other.span &&
          style == other.style &&
          _nodeListEquals(children, other.children);

  @override
  int get hashCode => Object.hash(span, style, Object.hashAll(children));

  @override
  String toString() =>
      'StyleNode(span: $span, style: $style, children: ${children.length})';
}

/// Color scope node (`\color`, `\textcolor`, or semantic role override).
@immutable
final class ColorNode extends MathNode {
  /// Creates a color scope node around [children].
  const ColorNode({
    required super.span,
    required this.role,
    required this.children,
    this.colorValue,
  });

  /// Semantic color role for this subtree.
  final TexMathColorRole role;

  /// Optional explicit CSS/hex color string when [role] is
  /// [TexMathColorRole.custom].
  final String? colorValue;

  /// Colored child nodes.
  final List<MathNode> children;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorNode &&
          span == other.span &&
          role == other.role &&
          colorValue == other.colorValue &&
          _nodeListEquals(children, other.children);

  @override
  int get hashCode =>
      Object.hash(span, role, colorValue, Object.hashAll(children));

  @override
  String toString() =>
      'ColorNode(span: $span, role: $role, colorValue: $colorValue)';
}

/// Equation tag or label annotation (`\tag`, `\tag*`, `\label`).
@immutable
final class TagNode extends MathNode {
  /// Creates an equation tag node with [label].
  const TagNode({
    required super.span,
    required this.label,
    this.isStarred = false,
    this.body,
  });

  /// Tag text or label identifier.
  final String label;

  /// Whether `\tag*` suppressed automatic enclosing parentheses.
  final bool isStarred;

  /// Optional tagged body expression.
  final MathNode? body;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagNode &&
          span == other.span &&
          label == other.label &&
          isStarred == other.isStarred &&
          body == other.body;

  @override
  int get hashCode => Object.hash(span, label, isStarred, body);

  @override
  String toString() =>
      'TagNode(span: $span, label: $label, isStarred: $isStarred)';
}

/// Non-fatal diagnostic AST node emitted when `strictErrors` is `false`.
@immutable
final class ErrorNode extends MathNode {
  /// Creates an error AST node recording [error] and [rawSource].
  const ErrorNode({
    required super.span,
    required this.error,
    required this.rawSource,
  });

  /// Structured error raised at [span].
  final TexMathError error;

  /// Unparsed source slice associated with [error].
  final String rawSource;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorNode &&
          span == other.span &&
          error == other.error &&
          rawSource == other.rawSource;

  @override
  int get hashCode => Object.hash(span, error, rawSource);

  @override
  String toString() => 'ErrorNode(span: $span, error: $error)';
}

bool _nodeListEquals(List<MathNode> a, List<MathNode> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _stringListEquals(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _matrixRowsEquals(List<List<MathNode>> a, List<List<MathNode>> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (!_nodeListEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}
