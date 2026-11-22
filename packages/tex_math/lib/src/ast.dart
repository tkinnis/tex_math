import 'dart:collection';

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

/// TeX Appendix G mathematical atom classification.
enum TexMathAtomClass {
  /// Ordinary atom (`\mathord`, letters, digits).
  ord,

  /// Large or named operator atom (`\mathop`, `\sum`, `\sin`).
  op,

  /// Binary operator atom (`\mathbin`, `+`, `-`, `\times`).
  bin,

  /// Relational operator atom (`\mathrel`, `=`, `<`, `\to`).
  rel,

  /// Opening delimiter atom (`\mathopen`, `(`, `[`).
  open,

  /// Closing delimiter atom (`\mathclose`, `)`, `]`).
  close,

  /// Punctuation atom (`\mathpunct`, `,`, `;`, `\colon`).
  punct,

  /// Inner subformula atom (`\mathinner`, fractions, `\left...\right`).
  inner,
}

/// Mathematical alphabet and font style variants.
enum TexMathFontVariant {
  /// Upright roman math text (`\mathrm`).
  normal,

  /// Upright bold (`\mathbf`).
  bold,

  /// Mathematical italic (`\mathit`).
  italic,

  /// Bold italic (`\boldsymbol`, `\mathbfit`).
  boldItalic,

  /// Calligraphic or script (`\mathcal`, `\mathscr`).
  script,

  /// Bold calligraphic or script.
  boldScript,

  /// Fraktur (`\mathfrak`).
  fraktur,

  /// Bold Fraktur.
  boldFraktur,

  /// Sans-serif (`\mathsf`).
  sansSerif,

  /// Bold sans-serif.
  boldSansSerif,

  /// Sans-serif italic.
  sansSerifItalic,

  /// Bold sans-serif italic.
  sansSerifBoldItalic,

  /// Monospace typewriter (`\mathtt`).
  monospace,

  /// Blackboard bold / double-struck (`\mathbb`, `\mathds`, `\mathbbm`).
  doubleStruck,

  /// Bold blackboard bold (`\mathbfbb`, bold `\mathbbm`).
  doubleStruckBold,

  /// Sans-serif double-struck (`\mathbbmss`, sans `\mathds`).
  doubleStruckSans,

  /// Monospace double-struck (`\mathbbmtt`).
  doubleStruckMonospace,
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
  /// Creates a root node with [children], [displayMode], and optional [labels].
  const MathRootNode({
    required super.span,
    required List<MathNode> children,
    this.displayMode = TexMathDisplayMode.display,
    Map<String, String> labels = const <String, String>{},
  }) : _children = children,
       _labels = labels;

  final List<MathNode> _children;
  final Map<String, String> _labels;

  /// Ordered top-level child nodes.
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

  /// Effective display mode for this expression.
  final TexMathDisplayMode displayMode;

  /// Label-to-tag bindings collected via `\label` and `\tag` within this tree.
  Map<String, String> get labels =>
      _freezeMap(_labels, const <String, String>{});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathRootNode &&
          span == other.span &&
          displayMode == other.displayMode &&
          _listEquals(_children, other._children) &&
          _mapEquals(_labels, other._labels);

  @override
  int get hashCode => Object.hash(
    span,
    displayMode,
    Object.hashAll(_children),
    _mapHash(_labels),
  );

  @override
  String toString() =>
      'MathRootNode(span: $span, displayMode: $displayMode, '
      'children: ${_children.length})';
}

/// Brace-delimited, implicit, or annotated mathematical sub-group `{...}`.
@immutable
final class MathGroupNode extends MathNode {
  /// Creates a group node wrapping [children].
  const MathGroupNode({
    required super.span,
    required List<MathNode> children,
    this.isExplicitGroup = true,
    this.atomClass,
    this.fontVariant,
    this.role,
    Map<String, String> attributes = const <String, String>{},
  }) : _children = children,
       _attributes = attributes;

  final List<MathNode> _children;
  final Map<String, String> _attributes;

  /// Ordered child nodes inside the group.
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

  /// Whether the group came from explicit `{...}` braces.
  final bool isExplicitGroup;

  /// Optional TeX atom class override (e.g. from `\mathbin`, `\mathrel`).
  final TexMathAtomClass? atomClass;

  /// Optional math alphabet font variant scoped to this group.
  final TexMathFontVariant? fontVariant;

  /// Optional structural role identifier (e.g. `phantom`, `boxed`, `bbox`,
  /// `cancel`, `enclose`, `substack`, `sideset`, `prooftree`, `href`).
  final String? role;

  /// Additional immutable metadata attributes associated with [role].
  Map<String, String> get attributes =>
      _freezeMap(_attributes, const <String, String>{});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MathGroupNode &&
          span == other.span &&
          isExplicitGroup == other.isExplicitGroup &&
          atomClass == other.atomClass &&
          fontVariant == other.fontVariant &&
          role == other.role &&
          _listEquals(_children, other._children) &&
          _mapEquals(_attributes, other._attributes);

  @override
  int get hashCode => Object.hash(
    span,
    isExplicitGroup,
    atomClass,
    fontVariant,
    role,
    Object.hashAll(_children),
    _mapHash(_attributes),
  );

  @override
  String toString() =>
      'MathGroupNode(span: $span, isExplicitGroup: $isExplicitGroup, '
      'role: $role, children: ${_children.length})';
}

/// Leaf symbol node such as an identifier, numeral, relation, or punctuation.
@immutable
final class SymbolNode extends MathNode {
  /// Creates a symbol node for [value].
  const SymbolNode({
    required super.span,
    required this.value,
    this.command,
    this.atomClass,
    this.fontVariant,
    this.isNegated = false,
    this.isStretchy = false,
  });

  /// Unicode symbol text represented by this node.
  final String value;

  /// Original TeX control sequence name if produced from a command.
  final String? command;

  /// Optional explicit TeX atom class override.
  final TexMathAtomClass? atomClass;

  /// Optional math alphabet variant active on this symbol.
  final TexMathFontVariant? fontVariant;

  /// Whether this symbol is negated (e.g. via `\not` or `\centernot`).
  final bool isNegated;

  /// Whether this symbol participates in stretchy delimiter or arrow sizing.
  final bool isStretchy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SymbolNode &&
          span == other.span &&
          value == other.value &&
          command == other.command &&
          atomClass == other.atomClass &&
          fontVariant == other.fontVariant &&
          isNegated == other.isNegated &&
          isStretchy == other.isStretchy;

  @override
  int get hashCode => Object.hash(
    span,
    value,
    command,
    atomClass,
    fontVariant,
    isNegated,
    isStretchy,
  );

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
    this.command,
    this.isDeclared = false,
    this.isExtensible = false,
  });

  /// Operator text or control sequence name.
  final String operatorName;

  /// Whether scripts attach above and below in display style.
  final bool hasLimits;

  /// Whether this operator uses display-size glyph variants.
  final bool isLarge;

  /// Original TeX command name if produced from a control sequence.
  final String? command;

  /// Whether this operator was produced by `\operatorname` or
  /// `\DeclareMathOperator`.
  final bool isDeclared;

  /// Whether this operator stretches horizontally to accommodate labels.
  final bool isExtensible;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperatorNode &&
          span == other.span &&
          operatorName == other.operatorName &&
          hasLimits == other.hasLimits &&
          isLarge == other.isLarge &&
          command == other.command &&
          isDeclared == other.isDeclared &&
          isExtensible == other.isExtensible;

  @override
  int get hashCode => Object.hash(
    span,
    operatorName,
    hasLimits,
    isLarge,
    command,
    isDeclared,
    isExtensible,
  );

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
    this.styleOverride,
    this.isBevelled = false,
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

  /// Optional forced math style override (e.g. `\dfrac`, `\tfrac`, `\cfrac`).
  final TexMathStyle? styleOverride;

  /// Whether the fraction uses a bevelled diagonal slash (e.g. `\nicefrac`).
  final bool isBevelled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FractionNode &&
          span == other.span &&
          numerator == other.numerator &&
          denominator == other.denominator &&
          ruleThicknessEm == other.ruleThicknessEm &&
          leftDelimiter == other.leftDelimiter &&
          rightDelimiter == other.rightDelimiter &&
          styleOverride == other.styleOverride &&
          isBevelled == other.isBevelled;

  @override
  int get hashCode => Object.hash(
    span,
    numerator,
    denominator,
    ruleThicknessEm,
    leftDelimiter,
    rightDelimiter,
    styleOverride,
    isBevelled,
  );

  @override
  String toString() =>
      'FractionNode(span: $span, ruleThicknessEm: $ruleThicknessEm)';
}

/// Subscript, superscript, and optional prescript attachment around a [base].
@immutable
final class ScriptNode extends MathNode {
  /// Creates a script node attached to [base].
  const ScriptNode({
    required super.span,
    required this.base,
    this.subscript,
    this.superscript,
    this.limitsAboveBelow = false,
    this.presubscript,
    this.presuperscript,
  });

  /// Base expression receiving the scripts.
  final MathNode base;

  /// Optional subscript expression (`_`).
  final MathNode? subscript;

  /// Optional superscript expression (`^`).
  final MathNode? superscript;

  /// Whether scripts should be stacked as limits above and below [base].
  final bool limitsAboveBelow;

  /// Optional leading presubscript expression (e.g. `\prescript`).
  final MathNode? presubscript;

  /// Optional leading presuperscript expression (e.g. `\prescript`).
  final MathNode? presuperscript;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptNode &&
          span == other.span &&
          base == other.base &&
          subscript == other.subscript &&
          superscript == other.superscript &&
          limitsAboveBelow == other.limitsAboveBelow &&
          presubscript == other.presubscript &&
          presuperscript == other.presuperscript;

  @override
  int get hashCode => Object.hash(
    span,
    base,
    subscript,
    superscript,
    limitsAboveBelow,
    presubscript,
    presuperscript,
  );

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
    required List<MathNode> children,
    this.leftDelimiter,
    this.rightDelimiter,
    this.fixedSizeEm,
  }) : _children = children;

  final List<MathNode> _children;

  /// Expressions enclosed between the delimiters.
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

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
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(
    span,
    leftDelimiter,
    rightDelimiter,
    fixedSizeEm,
    Object.hashAll(_children),
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
    required List<List<MathNode>> rows,
    required this.environment,
    List<String> columnAlignments = const <String>[],
    this.verticalAlignment,
    this.explicitWidthEm,
    this.leftDelimiter,
    this.rightDelimiter,
    this.isNumbered = false,
    Map<int, String> rowLines = const <int, String>{},
    Map<int, String> columnLines = const <int, String>{},
    Map<int, MathNode> columnSeparators = const <int, MathNode>{},
    Map<int, TagNode> rowTags = const <int, TagNode>{},
  }) : _rows = rows,
       _columnAlignments = columnAlignments,
       _rowLines = rowLines,
       _columnLines = columnLines,
       _columnSeparators = columnSeparators,
       _rowTags = rowTags;

  final List<List<MathNode>> _rows;
  final List<String> _columnAlignments;
  final Map<int, String> _rowLines;
  final Map<int, String> _columnLines;
  final Map<int, MathNode> _columnSeparators;
  final Map<int, TagNode> _rowTags;

  /// Two-dimensional list of cell nodes arranged by row then column.
  List<List<MathNode>> get rows => _rows.isEmpty
      ? const <List<MathNode>>[]
      : UnmodifiableListView<List<MathNode>>(_MatrixRowsView(_rows));

  /// TeX environment name (e.g. `pmatrix`, `align`, `array`).
  final String environment;

  /// Optional column alignment specifiers (`l`, `c`, `r`).
  List<String> get columnAlignments =>
      _freezeList(_columnAlignments, const <String>[]);

  /// Optional vertical table alignment (`t`, `b`, `c`).
  final String? verticalAlignment;

  /// Optional explicit table width in ems (e.g. `\begin{multlined}[t][10em]`).
  final double? explicitWidthEm;

  /// Optional left enclosing delimiter (e.g. `(` for `pmatrix`).
  final String? leftDelimiter;

  /// Optional right enclosing delimiter (e.g. `)` for `pmatrix`).
  final String? rightDelimiter;

  /// Whether rows carry equation numbers by default.
  final bool isNumbered;

  /// Horizontal rule styles keyed by row boundary index (`0` = top border).
  Map<int, String> get rowLines => _freezeMap(_rowLines, const <int, String>{});

  /// Vertical border rule styles (`solid` or `double`) keyed by column
  /// boundary index (`0` = left edge of the first column).
  Map<int, String> get columnLines =>
      _freezeMap(_columnLines, const <int, String>{});

  /// Pre-parsed custom column separator subtrees (`@{...}` / `!{...}`) keyed
  /// by column boundary index.
  Map<int, MathNode> get columnSeparators =>
      _freezeMap(_columnSeparators, const <int, MathNode>{});

  /// Explicit equation tags keyed by zero-based row index.
  Map<int, TagNode> get rowTags => _freezeMap(_rowTags, const <int, TagNode>{});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatrixNode &&
          span == other.span &&
          environment == other.environment &&
          verticalAlignment == other.verticalAlignment &&
          explicitWidthEm == other.explicitWidthEm &&
          leftDelimiter == other.leftDelimiter &&
          rightDelimiter == other.rightDelimiter &&
          isNumbered == other.isNumbered &&
          _listEquals(_columnAlignments, other._columnAlignments) &&
          _matrixRowsEquals(_rows, other._rows) &&
          _mapEquals(_rowLines, other._rowLines) &&
          _mapEquals(_columnLines, other._columnLines) &&
          _mapEquals(_columnSeparators, other._columnSeparators) &&
          _mapEquals(_rowTags, other._rowTags);

  @override
  int get hashCode => Object.hash(
    span,
    environment,
    verticalAlignment,
    explicitWidthEm,
    leftDelimiter,
    rightDelimiter,
    isNumbered,
    Object.hashAll(_columnAlignments),
    Object.hashAll(_rows.map(Object.hashAll)),
    _mapHash(_rowLines),
    _mapHash(_columnLines),
    _mapHash(_columnSeparators),
    _mapHash(_rowTags),
  );

  @override
  String toString() =>
      'MatrixNode(span: $span, environment: $environment, '
      'rows: ${_rows.length})';
}

/// Text-mode run embedded inside math mode (`\text`, `\mathrm`, `\textbf`).
@immutable
final class TextNode extends MathNode {
  /// Creates a text-mode node for [text] and optional structured [children].
  const TextNode({
    required super.span,
    required this.text,
    this.styleCommand,
    List<MathNode> children = const <MathNode>[],
  }) : _children = children;

  final List<MathNode> _children;

  /// Plain text payload.
  final String text;

  /// Optional TeX font or text wrapper command (e.g. `text`, `textbf`).
  final String? styleCommand;

  /// Optional nested text and inline math fragments inside rich text runs.
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextNode &&
          span == other.span &&
          text == other.text &&
          styleCommand == other.styleCommand &&
          _listEquals(_children, other._children);

  @override
  int get hashCode =>
      Object.hash(span, text, styleCommand, Object.hashAll(_children));

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

/// Style or size override node (`\displaystyle`, `\textstyle`, `\Large`).
@immutable
final class StyleNode extends MathNode {
  /// Creates a style node switching [children] to [style].
  const StyleNode({
    required super.span,
    required this.style,
    required List<MathNode> children,
    this.scaleEm,
  }) : _children = children;

  final List<MathNode> _children;

  /// Target Appendix G math layout style.
  final TexMathStyle style;

  /// Subtree nodes laid out under [style].
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

  /// Optional relative font-size scale factor (e.g. `1.44` for `\Large`).
  final double? scaleEm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StyleNode &&
          span == other.span &&
          style == other.style &&
          scaleEm == other.scaleEm &&
          _listEquals(_children, other._children);

  @override
  int get hashCode =>
      Object.hash(span, style, scaleEm, Object.hashAll(_children));

  @override
  String toString() =>
      'StyleNode(span: $span, style: $style, children: ${_children.length})';
}

/// Color scope node (`\color`, `\textcolor`, `\colorbox`, `\fcolorbox`).
@immutable
final class ColorNode extends MathNode {
  /// Creates a color scope node around [children].
  const ColorNode({
    required super.span,
    required this.role,
    required List<MathNode> children,
    this.colorValue,
    this.backgroundColor,
    this.borderColor,
  }) : _children = children;

  final List<MathNode> _children;

  /// Semantic color role for this subtree.
  final TexMathColorRole role;

  /// Optional explicit CSS/hex color string when [role] is
  /// [TexMathColorRole.custom].
  final String? colorValue;

  /// Colored child nodes.
  List<MathNode> get children => _freezeList(_children, const <MathNode>[]);

  /// Optional background color string (e.g. `\colorbox`, `\cellcolor`).
  final String? backgroundColor;

  /// Optional frame border color string (e.g. `\fcolorbox`).
  final String? borderColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorNode &&
          span == other.span &&
          role == other.role &&
          colorValue == other.colorValue &&
          backgroundColor == other.backgroundColor &&
          borderColor == other.borderColor &&
          _listEquals(_children, other._children);

  @override
  int get hashCode => Object.hash(
    span,
    role,
    colorValue,
    backgroundColor,
    borderColor,
    Object.hashAll(_children),
  );

  @override
  String toString() =>
      'ColorNode(span: $span, role: $role, colorValue: $colorValue)';
}

/// Equation tag, label, or reference annotation (`\tag`, `\label`, `\eqref`).
@immutable
final class TagNode extends MathNode {
  /// Creates an equation tag node with [label].
  const TagNode({
    required super.span,
    required this.label,
    this.targetId,
    this.isStarred = false,
    this.body,
    this.isReference = false,
    this.isLabelDefinition = false,
  });

  /// Tag text or label identifier.
  final String label;

  /// Optional target label identifier referenced by `\ref` or `\eqref`.
  final String? targetId;

  /// Whether `\tag*` or `\ref` suppressed enclosing parentheses.
  final bool isStarred;

  /// Optional tagged body expression.
  final MathNode? body;

  /// Whether this node represents a `\ref` or `\eqref` cross-reference.
  final bool isReference;

  /// Whether this node represents a `\label` definition.
  final bool isLabelDefinition;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagNode &&
          span == other.span &&
          label == other.label &&
          targetId == other.targetId &&
          isStarred == other.isStarred &&
          body == other.body &&
          isReference == other.isReference &&
          isLabelDefinition == other.isLabelDefinition;

  @override
  int get hashCode => Object.hash(
    span,
    label,
    targetId,
    isStarred,
    body,
    isReference,
    isLabelDefinition,
  );

  @override
  String toString() =>
      'TagNode(span: $span, label: $label, isStarred: $isStarred)';
}

/// Non-fatal diagnostic AST node emitted when `strictErrors` is `false` or
/// `noerrors` is enabled.
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

bool _listEquals<T>(List<T> a, List<T> b) {
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

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<K, V> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _mapHash<K, V>(Map<K, V> map) => Object.hashAllUnordered(
  map.entries.map(
    (MapEntry<K, V> entry) => Object.hash(entry.key, entry.value),
  ),
);

bool _matrixRowsEquals(List<List<MathNode>> a, List<List<MathNode>> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (!_listEquals(a[i], b[i])) {
      return false;
    }
  }
  return true;
}

List<T> _freezeList<T>(List<T> list, List<T> emptyConst) {
  if (list.isEmpty) {
    return emptyConst;
  }
  return list is UnmodifiableListView<T> ? list : UnmodifiableListView<T>(list);
}

Map<K, V> _freezeMap<K, V>(Map<K, V> map, Map<K, V> emptyConst) {
  if (map.isEmpty) {
    return emptyConst;
  }
  return map is UnmodifiableMapView<K, V>
      ? map
      : UnmodifiableMapView<K, V>(map);
}

final class _MatrixRowsView extends ListBase<List<MathNode>> {
  _MatrixRowsView(this._rows);

  final List<List<MathNode>> _rows;

  @override
  int get length => _rows.length;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Cannot modify an unmodifiable list');

  @override
  List<MathNode> operator [](int index) =>
      _freezeList(_rows[index], const <MathNode>[]);

  @override
  void operator []=(int index, List<MathNode> value) =>
      throw UnsupportedError('Cannot modify an unmodifiable list');
}
