import '../ast.dart';
import '../options.dart';
import '../source_span.dart';
import 'macros.dart';
import 'package_registry.dart';
import 'tokenizer.dart';

/// Shared parser host interface passed to environment, `physics`, and `mhchem`
/// helpers without introducing circular imports.
abstract interface class TexParserHost {
  /// Active token cursor over the input source.
  TexTokenCursor get cursor;

  /// Scoped macro, environment, and color definition table.
  TexMacroTable get macroTable;

  /// Active TeX package registry state and per-parse package options.
  TexActivePackages get activePackages;

  /// Immutable parse options for this expression.
  TexMathOptions get options;

  /// Current active math font variant, if any.
  TexMathFontVariant? get currentFontVariant;

  /// Enters a new AST/group nesting level, enforcing
  /// [TexMathBudgets.maxNestingDepth].
  void enterNesting(SourceSpan span);

  /// Exits the current AST/group nesting level.
  void exitNesting();

  /// Consumes an optional `*` token and returns whether one was present.
  bool consumeOptionalStar();

  /// Reads an optional `[...]` argument as raw tokens, or `null` if absent.
  List<TexToken>? readOptionalBracketTokens(String commandName);

  /// Reads an optional `[...]` argument flattened to text, or `null` if absent.
  String? readOptionalBracketText(String commandName);

  /// Reads a mandatory `{...}` (or single-token) argument as raw tokens.
  List<TexToken> readArgumentTokens(
    String commandName, {
    bool allowSingleToken = true,
  });

  /// Reads a mandatory `{...}` (or single-token) argument as raw source text.
  String readArgumentText(String commandName, {bool allowSingleToken = true});

  /// Reads tokens balanced between [openChar] and [closeChar].
  List<TexToken> readBalancedDelimiterTokens(
    String commandName,
    String openChar,
    String closeChar,
  );

  /// Parses [tokens] as an isolated math subexpression.
  MathNode parseSubTokens(
    List<TexToken> tokens, {
    required SourceSpan span,
    TexMathDisplayMode? displayMode,
    TexMathFontVariant? fontVariant,
    bool isExplicitGroup = false,
  });

  /// Parses [tokens] as a text-mode run (handling `$...$` inline math).
  TextNode parseTextTokens(
    List<TexToken> tokens, {
    required SourceSpan span,
    String? styleCommand,
  });

  /// Parses an inline TeX snippet string using [callSiteSpan] for valid spans.
  MathNode parseSyntheticTex(
    String tex, {
    required SourceSpan span,
    TexMathDisplayMode? displayMode,
    TexMathFontVariant? fontVariant,
  });

  /// Parses a cell inside an environment until `&`, `\\`, `\cr`, or `\end`.
  ({
    MathNode node,
    String? stopReason,
    SourceSpan span,
    bool rowHasTag,
    TagNode? rowTag,
    String? cellBackground,
    String? rowBackground,
    String? columnBackground,
  })
  parseEnvironmentCell({
    required String envName,
    required bool allowAlignTab,
    bool textMode = false,
  });

  /// Checks whether the next non-ignorable token is `\hline` or `\hdashline`
  /// and consumes it, returning its rule style (`solid` or `dashed`), or `null`.
  String? tryConsumeRowRule();

  /// Expands a matching active user environment `\end{name}` (from
  /// `\newenvironment`) into its replacement tokens if present at the cursor.
  bool tryExpandUserEnvEnd();

  /// Reads a closing `\end{envName}` and validates environment matching.
  SourceSpan consumeEndEnvironment(String envName, SourceSpan beginSpan);

  /// Reads a TeX delimiter token after `\left`, `\right`, `\middle`, or `\big`.
  String readDelimiterToken(String commandName, {bool allowPeriod = true});

  /// Consumes any trailing subscript/superscript/prime attachments on [base].
  MathNode attachScripts(MathNode base);
}
