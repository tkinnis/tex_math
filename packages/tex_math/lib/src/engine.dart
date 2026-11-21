import 'package:meta/meta.dart';

import 'ast.dart';
import 'display_list.dart';
import 'error.dart';
import 'font.dart';
import 'options.dart';
import 'source_span.dart';

/// Stateless TeX math parsing, Appendix G layout, and rendering entry point.
@immutable
final class TexMathEngine {
  /// Creates an engine configured with [defaultOptions] and optional [font].
  const TexMathEngine({
    this.defaultOptions = const TexMathOptions(),
    this.font,
  });

  /// Default options applied when per-call options are omitted.
  final TexMathOptions defaultOptions;

  /// Default math font used during layout when per-call [font] is omitted.
  final MathFont? font;

  /// Parses [source] into a typed [MathNode] syntax tree.
  ///
  /// Enforces [TexMathBudgets.maxInputLength] before parsing and throws
  /// [TexMathUnsupportedError] in Phase 1.
  MathNode parse(String source, {TexMathOptions? options}) {
    final TexMathOptions effective = options ?? defaultOptions;
    _enforceInputLengthBudget(source, effective.budgets);
    throw TexMathUnsupportedError(
      'TeX parsing is unimplemented in Phase 1.',
      span: SourceSpan(0, source.length),
    );
  }

  /// Lays out [syntaxTree] into a flat [DisplayList].
  ///
  /// Enforces [TexMathBudgets.maxNestingDepth] on [syntaxTree] and throws
  /// [TexMathUnsupportedError] in Phase 1.
  DisplayList layout(
    MathNode syntaxTree, {
    TexMathOptions? options,
    MathFont? font,
  }) {
    final TexMathOptions effective = options ?? defaultOptions;
    _enforceNestingDepthBudget(syntaxTree, effective.budgets, 1);
    throw TexMathUnsupportedError(
      'Appendix G math layout is unimplemented in Phase 1.',
      span: syntaxTree.span,
    );
  }

  /// Parses and lays out [source], returning a complete [RenderResult].
  ///
  /// Enforces [TexMathBudgets.maxInputLength] before throwing
  /// [TexMathUnsupportedError] in Phase 1.
  RenderResult render(
    String source, {
    TexMathOptions? options,
    MathFont? font,
  }) {
    final MathNode tree = parse(source, options: options);
    final DisplayList displayList = layout(
      tree,
      options: options,
      font: font ?? this.font,
    );
    return RenderResult(
      displayList: displayList,
      syntaxTree: tree,
      source: source,
    );
  }

  /// Parses, lays out, and serializes [source] directly to standalone SVG XML.
  ///
  /// Enforces [TexMathBudgets.maxInputLength] before throwing
  /// [TexMathUnsupportedError] in Phase 1.
  String renderToSvg(
    String source, {
    TexMathOptions? options,
    MathFont? font,
    double fontSize = 16.0,
  }) {
    final TexMathOptions effective = options ?? defaultOptions;
    final RenderResult result = render(source, options: effective, font: font);
    return result.toSvg(
      fontSize: fontSize,
      maxOutputItems: effective.budgets.maxOutputItems,
      maxSvgLength: effective.budgets.maxSvgLength,
    );
  }

  /// Parses [source] and emits Presentation MathML.
  ///
  /// Enforces [TexMathBudgets.maxInputLength] before throwing
  /// [TexMathUnsupportedError] in Phase 1.
  String toMathMl(String source, {TexMathOptions? options}) {
    final TexMathOptions effective = options ?? defaultOptions;
    _enforceInputLengthBudget(source, effective.budgets);
    throw TexMathUnsupportedError(
      'Presentation MathML emission is unimplemented in Phase 1.',
      span: SourceSpan(0, source.length),
    );
  }

  /// Parses [source] and emits plain spoken text for assistive technologies.
  ///
  /// Enforces [TexMathBudgets.maxInputLength] before throwing
  /// [TexMathUnsupportedError] in Phase 1.
  String toSpokenText(String source, {TexMathOptions? options}) {
    final TexMathOptions effective = options ?? defaultOptions;
    _enforceInputLengthBudget(source, effective.budgets);
    throw TexMathUnsupportedError(
      'Spoken-text generation is unimplemented in Phase 1.',
      span: SourceSpan(0, source.length),
    );
  }

  static void _enforceInputLengthBudget(String source, TexMathBudgets budgets) {
    if (source.length > budgets.maxInputLength) {
      throw TexMathBudgetError(
        'Input length ${source.length} exceeds maxInputLength '
        '(${budgets.maxInputLength}).',
        budgetName: 'maxInputLength',
        limit: budgets.maxInputLength,
        actual: source.length,
        span: SourceSpan(budgets.maxInputLength, source.length),
      );
    }
  }

  static void _enforceNestingDepthBudget(
    MathNode node,
    TexMathBudgets budgets,
    int depth,
  ) {
    if (depth > budgets.maxNestingDepth) {
      throw TexMathBudgetError(
        'Syntax tree nesting depth $depth exceeds maxNestingDepth '
        '(${budgets.maxNestingDepth}).',
        budgetName: 'maxNestingDepth',
        limit: budgets.maxNestingDepth,
        actual: depth,
        span: node.span,
      );
    }
    switch (node) {
      case MathRootNode(:final List<MathNode> children):
      case MathGroupNode(:final List<MathNode> children):
      case DelimiterNode(:final List<MathNode> children):
      case StyleNode(:final List<MathNode> children):
      case ColorNode(:final List<MathNode> children):
        for (final MathNode child in children) {
          _enforceNestingDepthBudget(child, budgets, depth + 1);
        }
      case FractionNode(:final MathNode numerator, :final MathNode denominator):
        _enforceNestingDepthBudget(numerator, budgets, depth + 1);
        _enforceNestingDepthBudget(denominator, budgets, depth + 1);
      case ScriptNode(
        :final MathNode base,
        :final MathNode? subscript,
        :final MathNode? superscript,
      ):
        _enforceNestingDepthBudget(base, budgets, depth + 1);
        if (subscript != null) {
          _enforceNestingDepthBudget(subscript, budgets, depth + 1);
        }
        if (superscript != null) {
          _enforceNestingDepthBudget(superscript, budgets, depth + 1);
        }
      case RadicalNode(:final MathNode radicand, :final MathNode? index):
        _enforceNestingDepthBudget(radicand, budgets, depth + 1);
        if (index != null) {
          _enforceNestingDepthBudget(index, budgets, depth + 1);
        }
      case AccentNode(:final MathNode base):
        _enforceNestingDepthBudget(base, budgets, depth + 1);
      case MatrixNode(:final List<List<MathNode>> rows):
        for (final List<MathNode> row in rows) {
          for (final MathNode cell in row) {
            _enforceNestingDepthBudget(cell, budgets, depth + 1);
          }
        }
      case TagNode(:final MathNode? body):
        if (body != null) {
          _enforceNestingDepthBudget(body, budgets, depth + 1);
        }
      case SymbolNode():
      case OperatorNode():
      case TextNode():
      case SpaceNode():
      case ErrorNode():
        break;
    }
  }
}

/// Top-level convenience wrapper calling [TexMathEngine.parse].
MathNode parseTex(
  String source, {
  TexMathOptions options = const TexMathOptions(),
}) {
  return const TexMathEngine().parse(source, options: options);
}

/// Top-level convenience wrapper calling [TexMathEngine.render].
RenderResult renderTex(
  String source, {
  TexMathOptions options = const TexMathOptions(),
  MathFont? font,
}) {
  return const TexMathEngine().render(source, options: options, font: font);
}

/// Top-level convenience wrapper calling [TexMathEngine.renderToSvg].
String renderTexToSvg(
  String source, {
  TexMathOptions options = const TexMathOptions(),
  MathFont? font,
  double fontSize = 16.0,
}) {
  return const TexMathEngine().renderToSvg(
    source,
    options: options,
    font: font,
    fontSize: fontSize,
  );
}
