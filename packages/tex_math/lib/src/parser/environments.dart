import '../ast.dart';
import '../error.dart';
import '../options.dart';
import '../shared/math_symbols.dart';
import '../source_span.dart';
import 'parser_host.dart';
import 'tokenizer.dart';

/// Descriptor for a built-in TeX math environment.
final class TexEnvironmentSpec {
  /// Creates an environment specification.
  const TexEnvironmentSpec({
    required this.packageName,
    this.leftDelimiter,
    this.rightDelimiter,
    this.defaultAlignments = const <String>['c'],
    this.allowAlignTab = true,
    this.maxColumns,
    this.requiresColSpec = false,
    this.requiresPairCountArg = false,
    this.optionalVerticalAlign = false,
    this.optionalColAlign = false,
    this.secondColTextMode = false,
    this.isNumbered = false,
    this.isInlineWrapper = false,
    this.isSingleCellWrapper = false,
  });

  /// Owning TeX package name.
  final String packageName;

  /// Optional left enclosing delimiter.
  final String? leftDelimiter;

  /// Optional right enclosing delimiter.
  final String? rightDelimiter;

  /// Repeating default column alignments (`l`, `c`, `r`).
  final List<String> defaultAlignments;

  /// Whether `&` alignment tabs are permitted in rows.
  final bool allowAlignTab;

  /// Optional hard cap on columns per row.
  final int? maxColumns;

  /// Whether a mandatory `{colspec}` argument precedes rows (`array`).
  final bool requiresColSpec;

  /// Whether a mandatory `{n}` pair-count argument precedes rows (`alignat`).
  final bool requiresPairCountArg;

  /// Whether an optional `[t|b|c]` vertical alignment argument is accepted.
  final bool optionalVerticalAlign;

  /// Whether an optional `[l|c|r]` matrix column alignment is accepted.
  final bool optionalColAlign;

  /// Whether the second column is parsed in text-with-inline-math mode.
  final bool secondColTextMode;

  /// Whether rows are equation-numbered by default.
  final bool isNumbered;

  /// Whether this environment simply wraps a math expression (`math`, `displaymath`).
  final bool isInlineWrapper;

  /// Whether this environment parses a linear body (`equation`, `equation*`, `spreadlines`).
  final bool isSingleCellWrapper;
}

/// Built-in TeX math environments keyed by environment name.
const Map<String, TexEnvironmentSpec> builtinEnvironments =
    <String, TexEnvironmentSpec>{
      // Base
      'math': TexEnvironmentSpec(
        packageName: 'base',
        allowAlignTab: false,
        maxColumns: 1,
        isInlineWrapper: true,
      ),
      'displaymath': TexEnvironmentSpec(
        packageName: 'base',
        allowAlignTab: false,
        maxColumns: 1,
        isInlineWrapper: true,
      ),
      'equation': TexEnvironmentSpec(
        packageName: 'base',
        allowAlignTab: false,
        maxColumns: 1,
        isNumbered: true,
        isSingleCellWrapper: true,
      ),
      'eqnarray': TexEnvironmentSpec(
        packageName: 'base',
        defaultAlignments: <String>['r', 'c', 'l'],
        maxColumns: 3,
        isNumbered: true,
      ),
      'array': TexEnvironmentSpec(
        packageName: 'base',
        requiresColSpec: true,
        optionalVerticalAlign: true,
      ),
      'darray': TexEnvironmentSpec(
        packageName: 'base',
        requiresColSpec: true,
        optionalVerticalAlign: true,
      ),
      'matrix': TexEnvironmentSpec(packageName: 'base'),
      'pmatrix': TexEnvironmentSpec(
        packageName: 'base',
        leftDelimiter: '(',
        rightDelimiter: ')',
      ),
      'cases': TexEnvironmentSpec(
        packageName: 'base',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
      ),
      'eqalign': TexEnvironmentSpec(
        packageName: 'base',
        defaultAlignments: <String>['r', 'l'],
      ),
      'eqalignno': TexEnvironmentSpec(
        packageName: 'base',
        defaultAlignments: <String>['r', 'l'],
        isNumbered: true,
      ),
      'leqalignno': TexEnvironmentSpec(
        packageName: 'base',
        defaultAlignments: <String>['r', 'l'],
        isNumbered: true,
      ),
      'displaylines': TexEnvironmentSpec(
        packageName: 'base',
        allowAlignTab: false,
        maxColumns: 1,
      ),

      // AMS
      'equation*': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
        isSingleCellWrapper: true,
      ),
      'eqnarray*': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'c', 'l'],
        maxColumns: 3,
      ),
      'bmatrix': TexEnvironmentSpec(
        packageName: 'ams',
        leftDelimiter: '[',
        rightDelimiter: ']',
      ),
      'Bmatrix': TexEnvironmentSpec(
        packageName: 'ams',
        leftDelimiter: '{',
        rightDelimiter: '}',
      ),
      'vmatrix': TexEnvironmentSpec(
        packageName: 'ams',
        leftDelimiter: '|',
        rightDelimiter: '|',
      ),
      'Vmatrix': TexEnvironmentSpec(
        packageName: 'ams',
        leftDelimiter: '\u2016',
        rightDelimiter: '\u2016',
      ),
      'smallmatrix': TexEnvironmentSpec(packageName: 'ams'),
      'subarray': TexEnvironmentSpec(
        packageName: 'ams',
        requiresColSpec: true,
        allowAlignTab: false,
        maxColumns: 1,
      ),
      'align': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        isNumbered: true,
      ),
      'align*': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
      ),
      'aligned': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        optionalVerticalAlign: true,
      ),
      'alignat': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
        isNumbered: true,
      ),
      'alignat*': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
      ),
      'alignedat': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
        optionalVerticalAlign: true,
      ),
      'xalignat': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
        isNumbered: true,
      ),
      'xalignat*': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
      ),
      'xxalignat': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        requiresPairCountArg: true,
      ),
      'flalign': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        isNumbered: true,
      ),
      'flalign*': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
      ),
      'gather': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
        isNumbered: true,
      ),
      'gather*': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
      ),
      'gathered': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
        optionalVerticalAlign: true,
      ),
      'multline': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
        isNumbered: true,
      ),
      'multline*': TexEnvironmentSpec(
        packageName: 'ams',
        allowAlignTab: false,
        maxColumns: 1,
      ),
      'split': TexEnvironmentSpec(
        packageName: 'ams',
        defaultAlignments: <String>['r', 'l'],
        maxColumns: 2,
      ),

      // Cases
      'numcases': TexEnvironmentSpec(
        packageName: 'cases',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
        isNumbered: true,
      ),
      'subnumcases': TexEnvironmentSpec(
        packageName: 'cases',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
        isNumbered: true,
      ),

      // Mathtools
      'dcases': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
      ),
      'rcases': TexEnvironmentSpec(
        packageName: 'mathtools',
        rightDelimiter: '}',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
      ),
      'drcases': TexEnvironmentSpec(
        packageName: 'mathtools',
        rightDelimiter: '}',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
      ),
      'cases*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
      ),
      'dcases*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
      ),
      'rcases*': TexEnvironmentSpec(
        packageName: 'mathtools',
        rightDelimiter: '}',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
      ),
      'drcases*': TexEnvironmentSpec(
        packageName: 'mathtools',
        rightDelimiter: '}',
        defaultAlignments: <String>['l', 'l'],
        maxColumns: 2,
        secondColTextMode: true,
      ),
      'matrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        optionalColAlign: true,
      ),
      'pmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '(',
        rightDelimiter: ')',
        optionalColAlign: true,
      ),
      'bmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '[',
        rightDelimiter: ']',
        optionalColAlign: true,
      ),
      'Bmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        rightDelimiter: '}',
        optionalColAlign: true,
      ),
      'vmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '|',
        rightDelimiter: '|',
        optionalColAlign: true,
      ),
      'Vmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '\u2016',
        rightDelimiter: '\u2016',
        optionalColAlign: true,
      ),
      'smallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        optionalColAlign: true,
      ),
      'psmallmatrix': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '(',
        rightDelimiter: ')',
      ),
      'psmallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '(',
        rightDelimiter: ')',
        optionalColAlign: true,
      ),
      'bsmallmatrix': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '[',
        rightDelimiter: ']',
      ),
      'bsmallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '[',
        rightDelimiter: ']',
        optionalColAlign: true,
      ),
      'Bsmallmatrix': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        rightDelimiter: '}',
      ),
      'Bsmallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '{',
        rightDelimiter: '}',
        optionalColAlign: true,
      ),
      'vsmallmatrix': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '|',
        rightDelimiter: '|',
      ),
      'vsmallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '|',
        rightDelimiter: '|',
        optionalColAlign: true,
      ),
      'Vsmallmatrix': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '\u2016',
        rightDelimiter: '\u2016',
      ),
      'Vsmallmatrix*': TexEnvironmentSpec(
        packageName: 'mathtools',
        leftDelimiter: '\u2016',
        rightDelimiter: '\u2016',
        optionalColAlign: true,
      ),
      'crampedsubarray': TexEnvironmentSpec(
        packageName: 'mathtools',
        requiresColSpec: true,
        allowAlignTab: false,
        maxColumns: 1,
      ),
      'multlined': TexEnvironmentSpec(
        packageName: 'mathtools',
        allowAlignTab: false,
        maxColumns: 1,
        optionalVerticalAlign: true,
      ),
      'lgathered': TexEnvironmentSpec(
        packageName: 'mathtools',
        defaultAlignments: <String>['l'],
        allowAlignTab: false,
        maxColumns: 1,
        optionalVerticalAlign: true,
      ),
      'rgathered': TexEnvironmentSpec(
        packageName: 'mathtools',
        defaultAlignments: <String>['r'],
        allowAlignTab: false,
        maxColumns: 1,
        optionalVerticalAlign: true,
      ),
      'spreadlines': TexEnvironmentSpec(
        packageName: 'mathtools',
        isSingleCellWrapper: true,
      ),

      // Specialized environments
      'CD': TexEnvironmentSpec(packageName: 'amscd'),
      'prooftree': TexEnvironmentSpec(packageName: 'bussproofs'),
      'empheq': TexEnvironmentSpec(packageName: 'empheq'),
    };

/// Parses an environment `\begin{envName} ... \end{envName}`.
MathNode parseEnvironment({
  required TexParserHost host,
  required String envName,
  required SourceSpan beginSpan,
}) {
  if (envName == 'CD' && host.activePackages.has('amscd')) {
    return _parseCdEnvironment(host, beginSpan);
  }
  if (envName == 'prooftree' && host.activePackages.has('bussproofs')) {
    return _parseProoftreeEnvironment(host, beginSpan);
  }
  if (envName == 'empheq' && host.activePackages.has('empheq')) {
    return _parseEmpheqEnvironment(host, beginSpan);
  }

  final TexEnvironmentSpec? spec = builtinEnvironments[envName];
  if (spec == null || !host.activePackages.has(spec.packageName)) {
    throw TexMathSyntaxError(
      'Unknown environment "$envName".',
      errorClass: TexMathErrorClass.unknownEnvironment,
      span: beginSpan,
    );
  }

  // `numcases` and `subnumcases` accept a leading `{lhs}` expression argument.
  MathNode? casesLhs;
  if (envName == 'numcases' || envName == 'subnumcases') {
    final List<TexToken> lhsTokens = host.readArgumentTokens('begin{$envName}');
    casesLhs = host.parseSubTokens(lhsTokens, span: beginSpan);
  }

  // `spreadlines` accepts a dimension argument `{dimen}`.
  if (envName == 'spreadlines') {
    host.readArgumentText('begin{spreadlines}');
  }

  String? vAlign;
  double? explicitWidthEm;
  if (envName == 'multlined') {
    final String? firstOpt = host.readOptionalBracketText('begin{$envName}');
    String? rawWidth;
    if (firstOpt != null) {
      final String trimmedFirst = firstOpt.trim();
      if (trimmedFirst == 't' || trimmedFirst == 'b' || trimmedFirst == 'c') {
        vAlign = trimmedFirst;
        rawWidth = host.readOptionalBracketText('begin{$envName}');
      } else {
        rawWidth = firstOpt;
      }
    }
    if (rawWidth != null) {
      final String trimmedWidth = rawWidth.trim();
      if (trimmedWidth.isNotEmpty) {
        if (!isValidTexDimension(trimmedWidth)) {
          throw TexMathSyntaxError(
            'Width argument for \\begin{multlined} must be a valid TeX '
            'dimension: "$trimmedWidth".',
            span: beginSpan,
          );
        }
        explicitWidthEm = parseTexDimensionToEm(trimmedWidth);
      }
    }
  } else if (spec.optionalVerticalAlign) {
    final String? opt = host.readOptionalBracketText('begin{$envName}');
    if (opt != null && opt.trim().isNotEmpty) {
      vAlign = opt.trim();
    }
  }

  List<String> colAligns = spec.defaultAlignments;
  Map<int, String> colLines = const <int, String>{};
  Map<int, MathNode> colSeparators = const <int, MathNode>{};
  Map<int, List<TexToken>> colPrefixes = const <int, List<TexToken>>{};
  if (spec.optionalColAlign) {
    final String? opt = host.readOptionalBracketText('begin{$envName}');
    if (opt != null && opt.trim().isNotEmpty) {
      colAligns = <String>[opt.trim()[0]];
    }
  }

  if (spec.requiresColSpec) {
    final List<TexToken> specTokens = host.readArgumentTokens(
      'begin{$envName}',
    );
    final _ParsedColSpec parsedSpec = _parseArrayColSpec(specTokens, host);
    colAligns = parsedSpec.alignments;
    colLines = parsedSpec.lines;
    colSeparators = parsedSpec.separators;
    colPrefixes = parsedSpec.prefixes;
  }

  int? maxCols = spec.maxColumns;
  if (spec.requiresPairCountArg) {
    final String rawN = host.readArgumentText('begin{$envName}').trim();
    final int? pairs = int.tryParse(rawN);
    if (pairs == null || pairs < 0) {
      throw TexMathSyntaxError(
        'Argument to \\begin{$envName} must be a non-negative integer.',
        span: beginSpan,
      );
    }
    maxCols = pairs == 0 ? 1 : pairs * 2;
  }

  if (spec.isInlineWrapper || spec.isSingleCellWrapper) {
    final cell = host.parseEnvironmentCell(
      envName: envName,
      allowAlignTab: false,
    );
    final SourceSpan endSpan = host.consumeEndEnvironment(envName, beginSpan);
    final SourceSpan totalSpan = beginSpan.merge(endSpan);
    return _buildSingleCellEnvNode(
      host: host,
      spec: spec,
      envName: envName,
      totalSpan: totalSpan,
      node: cell.node,
      rowTag: cell.rowTag,
      rowHasNoTag: cell.rowHasNoTag,
      rowLabel: cell.rowLabel,
    );
  }

  final List<List<MathNode>> rows = <List<MathNode>>[];
  final Map<int, String> rowLines = <int, String>{};
  final Map<int, String> colBackgrounds = <int, String>{};
  final _EnvTagTracker tagTracker = _EnvTagTracker(
    host: host,
    spec: spec,
    isNumberedMultline: envName == 'multline',
    fallbackSpan: beginSpan,
  );
  List<MathNode> currentRow = <MathNode>[];
  String? currentRowBackground;

  while (true) {
    if (currentRow.isEmpty) {
      final String? ruleStyle = host.tryConsumeRowRule();
      if (ruleStyle != null) {
        final String? existing = rowLines[rows.length];
        if (existing == null) {
          rowLines[rows.length] = ruleStyle;
        } else if (existing == 'solid' && ruleStyle == 'solid') {
          rowLines[rows.length] = 'double';
        }
        continue;
      }
    }

    // Check immediately for \end{envName} when at row start after `\\`.
    if (currentRow.isEmpty && _isAtEndEnv(host, envName)) {
      break;
    }

    final int colIndex = currentRow.length;
    final bool useTextMode = spec.secondColTextMode && colIndex == 1;
    final List<TexToken>? prefix = colPrefixes[colIndex];
    if (prefix != null && prefix.isNotEmpty) {
      host.cursor.pushTokens(prefix);
    }

    final cell = host.parseEnvironmentCell(
      envName: envName,
      allowAlignTab: spec.allowAlignTab,
      textMode: useTextMode,
    );
    final String? stopReason = cell.stopReason;
    final SourceSpan span = cell.span;

    if (cell.rowBackground != null) {
      if (colIndex != 0) {
        throw TexMathSyntaxError(
          '\\rowcolor must appear at the beginning of a row.',
          span: span,
        );
      }
      currentRowBackground = cell.rowBackground;
    }
    if (cell.columnBackground != null) {
      if (rows.isNotEmpty &&
          colBackgrounds[colIndex] != cell.columnBackground) {
        throw TexMathSyntaxError(
          '\\columncolor must be defined in the top row or column preamble.',
          span: span,
        );
      }
      colBackgrounds[colIndex] = cell.columnBackground!;
    }
    final String? effectiveBg =
        cell.cellBackground ?? currentRowBackground ?? colBackgrounds[colIndex];
    final MathNode finalCellNode = effectiveBg == null
        ? cell.node
        : ColorNode(
            span: cell.node.span,
            role: TexMathColorRole.custom,
            backgroundColor: effectiveBg,
            children: <MathNode>[cell.node],
          );

    currentRow.add(finalCellNode);
    tagTracker.recordCell(
      span: span,
      rowTag: cell.rowTag,
      rowHasNoTag: cell.rowHasNoTag,
      rowLabel: cell.rowLabel,
    );

    if (maxCols != null && currentRow.length > maxCols) {
      throw TexMathSyntaxError(
        'Too many alignment tabs (&) in \\begin{$envName}.',
        errorClass: TexMathErrorClass.misplacedAlignmentTab,
        span: span,
      );
    }

    if (stopReason == 'amp') {
      continue;
    }

    rows.add(currentRow);
    tagTracker.finishRow(rows.length - 1);
    currentRow = <MathNode>[];
    currentRowBackground = null;

    if (stopReason == 'cr') {
      continue;
    }
    break;
  }

  final SourceSpan endSpan = host.consumeEndEnvironment(envName, beginSpan);
  final SourceSpan totalSpan = beginSpan.merge(endSpan);
  tagTracker.finishTable(rows.length, totalSpan);

  final MatrixNode matrix = MatrixNode(
    span: totalSpan,
    rows: List<List<MathNode>>.unmodifiable(
      rows.map(List<MathNode>.unmodifiable),
    ),
    environment: envName,
    columnAlignments: List<String>.unmodifiable(colAligns),
    verticalAlignment: vAlign,
    explicitWidthEm: explicitWidthEm,
    leftDelimiter: spec.leftDelimiter,
    rightDelimiter: spec.rightDelimiter,
    isNumbered: spec.isNumbered,
    rowLines: Map<int, String>.unmodifiable(rowLines),
    columnLines: Map<int, String>.unmodifiable(colLines),
    columnSeparators: Map<int, MathNode>.unmodifiable(colSeparators),
    rowTags: Map<int, TagNode>.unmodifiable(tagTracker.rowTags),
  );

  if (casesLhs != null) {
    return MathGroupNode(
      span: totalSpan,
      isExplicitGroup: false,
      role: envName,
      children: <MathNode>[casesLhs, matrix],
    );
  }
  return matrix;
}

bool _isAtEndEnv(TexParserHost host, String envName) {
  while (host.tryExpandUserEnvEnd()) {}
  final TexToken? t = host.cursor.peek();
  return t != null && t.kind == TexTokenKind.controlSequence && t.text == 'end';
}

final class _ParsedColSpec {
  const _ParsedColSpec({
    required this.alignments,
    required this.lines,
    required this.separators,
    required this.prefixes,
  });

  final List<String> alignments;
  final Map<int, String> lines;
  final Map<int, MathNode> separators;
  final Map<int, List<TexToken>> prefixes;
}

_ParsedColSpec _parseArrayColSpec(List<TexToken> tokens, TexParserHost host) {
  final List<TexToken> expanded = _expandColSpecStars(tokens, host);
  final List<String> alignments = <String>[];
  final Map<int, String> lines = <int, String>{};
  final Map<int, MathNode> separators = <int, MathNode>{};
  final Map<int, List<TexToken>> prefixes = <int, List<TexToken>>{};
  List<TexToken> pendingPrefix = <TexToken>[];

  int i = 0;
  while (i < expanded.length) {
    final TexToken t = expanded[i];
    if (t.isIgnorableInMath) {
      i++;
      continue;
    }
    if (t.kind == TexTokenKind.other && t.text == '|') {
      final int colPos = alignments.length;
      if (lines[colPos] == 'solid') {
        lines[colPos] = 'double';
      } else {
        lines[colPos] = 'solid';
      }
      i++;
      continue;
    }
    if (t.kind == TexTokenKind.other && (t.text == '@' || t.text == '!')) {
      i++;
      final (:group, :nextIndex) = _readBalancedGroupFromList(expanded, i);
      i = nextIndex;
      final SourceSpan sepSpan = group.isEmpty
          ? t.span
          : group.first.span.merge(group.last.span);
      separators[alignments.length] = host.parseSubTokens(group, span: sepSpan);
      continue;
    }
    if (t.kind == TexTokenKind.other && t.text == '>') {
      i++;
      final (:group, :nextIndex) = _readBalancedGroupFromList(expanded, i);
      i = nextIndex;
      pendingPrefix = <TexToken>[...pendingPrefix, ...group];
      continue;
    }
    if (t.kind == TexTokenKind.other && t.text == '<') {
      i++;
      final (:group, :nextIndex) = _readBalancedGroupFromList(expanded, i);
      i = nextIndex;
      continue;
    }
    if (t.kind == TexTokenKind.letter) {
      final String ch = t.text;
      if (ch == 'l' || ch == 'c' || ch == 'r') {
        if (pendingPrefix.isNotEmpty) {
          prefixes[alignments.length] = pendingPrefix;
          pendingPrefix = <TexToken>[];
        }
        alignments.add(ch);
        i++;
        continue;
      }
      if (ch == 'p' || ch == 'm' || ch == 'b') {
        i++;
        final (:group, :nextIndex) = _readBalancedGroupFromList(expanded, i);
        i = nextIndex;
        if (pendingPrefix.isNotEmpty) {
          prefixes[alignments.length] = pendingPrefix;
          pendingPrefix = <TexToken>[];
        }
        alignments.add('l');
        continue;
      }
    }
    i++;
  }

  return _ParsedColSpec(
    alignments: alignments.isEmpty ? const <String>['c'] : alignments,
    lines: lines,
    separators: separators,
    prefixes: prefixes,
  );
}

List<TexToken> _expandColSpecStars(List<TexToken> tokens, TexParserHost host) {
  final List<TexToken> out = <TexToken>[];
  int i = 0;
  while (i < tokens.length) {
    final TexToken t = tokens[i];
    if (t.kind == TexTokenKind.other && t.text == '*') {
      i++;
      final (:group, :nextIndex) = _readBalancedGroupFromList(tokens, i);
      i = nextIndex;
      final String countRaw = group
          .map((TexToken tok) => tok.text)
          .join()
          .trim();
      final int count = int.tryParse(countRaw) ?? 0;
      final ({List<TexToken> group, int nextIndex}) bodyRead =
          _readBalancedGroupFromList(tokens, i);
      i = bodyRead.nextIndex;
      final List<TexToken> repeatedBody;
      host.enterNesting(t.span);
      try {
        repeatedBody = _expandColSpecStars(bodyRead.group, host);
      } finally {
        host.exitNesting();
      }
      if (repeatedBody.isEmpty || count <= 0) {
        continue;
      }
      final int cappedCount = count > 256 ? 256 : count;
      for (int c = 0; c < cappedCount && out.length < 256; c++) {
        out.addAll(repeatedBody);
      }
      continue;
    }
    out.add(t);
    i++;
  }
  return out;
}

({List<TexToken> group, int nextIndex}) _readBalancedGroupFromList(
  List<TexToken> tokens,
  int start,
) {
  int i = start;
  while (i < tokens.length && tokens[i].isIgnorableInMath) {
    i++;
  }
  if (i >= tokens.length) {
    return (group: const <TexToken>[], nextIndex: i);
  }
  if (tokens[i].kind != TexTokenKind.beginGroup) {
    return (group: <TexToken>[tokens[i]], nextIndex: i + 1);
  }
  int depth = 1;
  i++;
  final List<TexToken> out = <TexToken>[];
  while (i < tokens.length && depth > 0) {
    final TexToken tok = tokens[i];
    if (tok.kind == TexTokenKind.beginGroup) {
      depth++;
      out.add(tok);
    } else if (tok.kind == TexTokenKind.endGroup) {
      depth--;
      if (depth > 0) {
        out.add(tok);
      }
    } else {
      out.add(tok);
    }
    i++;
  }
  return (group: out, nextIndex: i);
}

MathNode _parseEmpheqEnvironment(TexParserHost host, SourceSpan beginSpan) {
  final String? optStr = host.readOptionalBracketText('begin{empheq}');
  final String targetRaw = host.readArgumentText('begin{empheq}').trim();
  final List<String> eqParts = targetRaw.split('=');
  final String innerEnv = eqParts.first.trim();
  final String? pairCount = eqParts.length > 1 ? eqParts[1].trim() : null;

  final TexEnvironmentSpec? innerSpec = builtinEnvironments[innerEnv];
  if (innerSpec == null || !host.activePackages.has(innerSpec.packageName)) {
    throw TexMathSyntaxError(
      'Invalid environment "$innerEnv" for empheq.',
      errorClass: TexMathErrorClass.syntaxError,
      span: beginSpan,
    );
  }

  String? leftDelim;
  String? rightDelim;
  if (optStr != null && optStr.isNotEmpty) {
    for (final String kv in optStr.split(',')) {
      final int eq = kv.indexOf('=');
      if (eq < 0) {
        continue;
      }
      final String k = kv.substring(0, eq).trim();
      final String v = kv.substring(eq + 1).trim();
      final String? resolved = _resolveEmpheqDelim(v);
      if (k == 'left') {
        leftDelim = resolved;
      } else if (k == 'right') {
        rightDelim = resolved;
      }
    }
  }

  final MathNode innerNode = _parseEmpheqBody(
    host: host,
    innerEnv: innerEnv,
    outerEnv: 'empheq',
    beginSpan: beginSpan,
    pairCount: pairCount,
  );
  final SourceSpan endSpan = host.consumeEndEnvironment('empheq', beginSpan);
  final SourceSpan totalSpan = beginSpan.merge(endSpan);

  if (leftDelim != null || rightDelim != null) {
    if (innerNode is TagNode &&
        !innerNode.isLabelDefinition &&
        !innerNode.isReference) {
      final MathNode delimited = DelimiterNode(
        span: totalSpan,
        leftDelimiter: leftDelim,
        rightDelimiter: rightDelim,
        children: <MathNode>[if (innerNode.body != null) innerNode.body!],
      );
      return TagNode(
        span: totalSpan,
        label: innerNode.label,
        isStarred: innerNode.isStarred,
        body: delimited,
      );
    }
    return DelimiterNode(
      span: totalSpan,
      leftDelimiter: leftDelim,
      rightDelimiter: rightDelim,
      children: <MathNode>[innerNode],
    );
  }
  return innerNode;
}

MathNode _buildSingleCellEnvNode({
  required TexParserHost host,
  required TexEnvironmentSpec spec,
  required String envName,
  required SourceSpan totalSpan,
  required MathNode node,
  required TagNode? rowTag,
  required bool rowHasNoTag,
  required String? rowLabel,
}) {
  if (rowTag != null) {
    if (rowLabel != null) {
      host.bindLabel(rowLabel, rowTag.label);
    }
    return TagNode(
      span: totalSpan,
      label: rowTag.label,
      isStarred: rowTag.isStarred,
      body: node,
    );
  }
  if (!rowHasNoTag &&
      spec.isNumbered &&
      host.options.tagMode != TexMathTagMode.none) {
    final String tagStr = '${host.nextAutoTag()}';
    if (rowLabel != null) {
      host.bindLabel(rowLabel, tagStr);
    }
    return TagNode(span: totalSpan, label: tagStr, body: node);
  }
  if (spec.isInlineWrapper) {
    return StyleNode(
      span: totalSpan,
      style: envName == 'math' ? TexMathStyle.text : TexMathStyle.display,
      children: <MathNode>[node],
    );
  }
  return MathGroupNode(
    span: totalSpan,
    isExplicitGroup: false,
    role: envName,
    children: <MathNode>[node],
  );
}

final class _EnvTagTracker {
  _EnvTagTracker({
    required this.host,
    required this.spec,
    required this.isNumberedMultline,
    required this.fallbackSpan,
  });

  final TexParserHost host;
  final TexEnvironmentSpec spec;
  final bool isNumberedMultline;
  final SourceSpan fallbackSpan;

  final Map<int, TagNode> rowTags = <int, TagNode>{};
  final List<String> _pendingRowLabels = <String>[];
  final List<String> _unboundMultlineLabels = <String>[];
  TagNode? _pendingRowTag;
  bool _pendingRowHasNoTag = false;
  SourceSpan? _pendingRowSpan;
  bool _multlineHasNoTag = false;

  void recordCell({
    required SourceSpan span,
    required TagNode? rowTag,
    required bool rowHasNoTag,
    required String? rowLabel,
  }) {
    _pendingRowSpan = _pendingRowSpan == null
        ? span
        : _pendingRowSpan!.merge(span);
    if (rowTag != null) {
      _pendingRowTag = rowTag;
    }
    if (rowHasNoTag) {
      _pendingRowHasNoTag = true;
    }
    if (rowLabel != null) {
      _pendingRowLabels.add(rowLabel);
    }
  }

  void finishRow(int rowIdx) {
    final TagNode? rowTag = _pendingRowTag;
    if (isNumberedMultline) {
      if (_pendingRowHasNoTag) {
        _multlineHasNoTag = true;
      }
      if (rowTag != null) {
        rowTags[rowIdx] = rowTag;
        for (final String lbl in _pendingRowLabels) {
          host.bindLabel(lbl, rowTag.label);
        }
      } else if (_pendingRowLabels.isNotEmpty) {
        _unboundMultlineLabels.addAll(_pendingRowLabels);
      }
    } else if (rowTag != null) {
      rowTags[rowIdx] = rowTag;
      for (final String lbl in _pendingRowLabels) {
        host.bindLabel(lbl, rowTag.label);
      }
    } else if (!_pendingRowHasNoTag &&
        spec.isNumbered &&
        host.options.tagMode != TexMathTagMode.none) {
      final String tagStr = '${host.nextAutoTag()}';
      rowTags[rowIdx] = TagNode(
        span: _pendingRowSpan ?? fallbackSpan,
        label: tagStr,
      );
      for (final String lbl in _pendingRowLabels) {
        host.bindLabel(lbl, tagStr);
      }
    }
    _pendingRowTag = null;
    _pendingRowHasNoTag = false;
    _pendingRowLabels.clear();
    _pendingRowSpan = null;
  }

  void finishTable(int rowCount, SourceSpan tableSpan) {
    if (!isNumberedMultline || rowCount <= 0) {
      return;
    }
    if (rowTags.isNotEmpty) {
      final String explicitTag = rowTags.values.first.label;
      for (final String lbl in _unboundMultlineLabels) {
        host.bindLabel(lbl, explicitTag);
      }
    } else if (!_multlineHasNoTag &&
        host.options.tagMode != TexMathTagMode.none) {
      final String tagStr = '${host.nextAutoTag()}';
      rowTags[rowCount - 1] = TagNode(span: tableSpan, label: tagStr);
      for (final String lbl in _unboundMultlineLabels) {
        host.bindLabel(lbl, tagStr);
      }
    }
  }
}

MathNode _parseEmpheqBody({
  required TexParserHost host,
  required String innerEnv,
  required String outerEnv,
  required SourceSpan beginSpan,
  String? pairCount,
}) {
  final TexEnvironmentSpec spec = builtinEnvironments[innerEnv]!;
  int? maxCols = spec.maxColumns;
  if (spec.requiresPairCountArg) {
    final String rawN = (pairCount ?? host.readArgumentText('begin{$innerEnv}'))
        .trim();
    final int pairs = int.tryParse(rawN) ?? 1;
    maxCols = pairs == 0 ? 1 : pairs * 2;
  }
  if (spec.isSingleCellWrapper) {
    final cell = host.parseEnvironmentCell(
      envName: outerEnv,
      allowAlignTab: false,
    );
    return _buildSingleCellEnvNode(
      host: host,
      spec: spec,
      envName: innerEnv,
      totalSpan: beginSpan,
      node: cell.node,
      rowTag: cell.rowTag,
      rowHasNoTag: cell.rowHasNoTag,
      rowLabel: cell.rowLabel,
    );
  }
  final List<List<MathNode>> rows = <List<MathNode>>[];
  final _EnvTagTracker tagTracker = _EnvTagTracker(
    host: host,
    spec: spec,
    isNumberedMultline: innerEnv == 'multline',
    fallbackSpan: beginSpan,
  );
  List<MathNode> currentRow = <MathNode>[];

  while (true) {
    if (currentRow.isEmpty && _isAtEndEnv(host, outerEnv)) {
      break;
    }
    final cell = host.parseEnvironmentCell(
      envName: outerEnv,
      allowAlignTab: spec.allowAlignTab,
    );
    final MathNode node = cell.node;
    final String? stopReason = cell.stopReason;
    final SourceSpan span = cell.span;
    currentRow.add(node);
    tagTracker.recordCell(
      span: span,
      rowTag: cell.rowTag,
      rowHasNoTag: cell.rowHasNoTag,
      rowLabel: cell.rowLabel,
    );
    if (maxCols != null && currentRow.length > maxCols) {
      throw TexMathSyntaxError(
        'Too many alignment tabs (&) in \\begin{$innerEnv}.',
        errorClass: TexMathErrorClass.misplacedAlignmentTab,
        span: span,
      );
    }
    if (stopReason == 'amp') {
      continue;
    }
    rows.add(currentRow);
    tagTracker.finishRow(rows.length - 1);
    currentRow = <MathNode>[];
    if (stopReason == 'cr') {
      continue;
    }
    break;
  }
  tagTracker.finishTable(rows.length, beginSpan);
  return MatrixNode(
    span: beginSpan,
    rows: List<List<MathNode>>.unmodifiable(
      rows.map(List<MathNode>.unmodifiable),
    ),
    environment: innerEnv,
    columnAlignments: spec.defaultAlignments,
    isNumbered: spec.isNumbered,
    rowTags: Map<int, TagNode>.unmodifiable(tagTracker.rowTags),
  );
}

String? _resolveEmpheqDelim(String raw) => resolveEmpheqDelimiter(raw);

MathNode _parseCdEnvironment(TexParserHost host, SourceSpan beginSpan) {
  final List<List<MathNode>> rows = <List<MathNode>>[];
  List<MathNode> currentRow = <MathNode>[];
  List<TexToken> cellTokens = <TexToken>[];

  void flushCell() {
    if (cellTokens.isEmpty) {
      currentRow.add(
        MathGroupNode(span: beginSpan, children: const <MathNode>[]),
      );
    } else {
      final SourceSpan cellSpan = cellTokens.first.span.merge(
        cellTokens.last.span,
      );
      currentRow.add(host.parseSubTokens(cellTokens, span: cellSpan));
      cellTokens = <TexToken>[];
    }
  }

  while (true) {
    final TexToken? tok = host.cursor.peek(skipSpaces: false);
    if (tok == null) {
      throw TexMathSyntaxError(
        'Missing \\end{CD}.',
        errorClass: TexMathErrorClass.mismatchedEnvironment,
        span: beginSpan,
      );
    }
    if (tok.kind == TexTokenKind.controlSequence && tok.text == 'end') {
      if (host.tryExpandUserEnvEnd()) {
        continue;
      }
      if (cellTokens.isNotEmpty || currentRow.isNotEmpty) {
        flushCell();
        rows.add(currentRow);
      }
      break;
    }
    if (tok.kind == TexTokenKind.controlSequence &&
        (tok.text == '\\' || tok.text == 'cr')) {
      host.cursor.nextRaw();
      flushCell();
      rows.add(currentRow);
      currentRow = <MathNode>[];
      continue;
    }
    if (tok.kind == TexTokenKind.other && tok.text == '@') {
      host.cursor.nextRaw();
      final TexToken? dirTok = host.cursor.peek(skipSpaces: false);
      if (dirTok == null) {
        continue;
      }
      final String dir = dirTok.text;
      if (dir == '>' || dir == '<' || dir == 'V' || dir == 'A') {
        flushCell();
        host.cursor.nextRaw();
        final List<TexToken> label1 = _readCdLabelUntil(host, dir, beginSpan);
        final List<TexToken> label2 = _readCdLabelUntil(host, dir, beginSpan);
        final String arrowChar = switch (dir) {
          '>' => '\u2192',
          '<' => '\u2190',
          'V' => '\u2193',
          _ => '\u2191',
        };
        final OperatorNode arrowOp = OperatorNode(
          span: dirTok.span,
          operatorName: arrowChar,
          hasLimits: true,
          isExtensible: true,
        );
        final MathNode? overNode = label1.isEmpty
            ? null
            : host.parseSubTokens(label1, span: dirTok.span);
        final MathNode? underNode = label2.isEmpty
            ? null
            : host.parseSubTokens(label2, span: dirTok.span);
        currentRow.add(
          (overNode != null || underNode != null)
              ? ScriptNode(
                  span: dirTok.span,
                  base: arrowOp,
                  superscript: overNode,
                  subscript: underNode,
                  limitsAboveBelow: true,
                )
              : arrowOp,
        );
        continue;
      }
      if (dir == '=' || dir == '|' || dir == '.') {
        flushCell();
        host.cursor.nextRaw();
        if (dir == '=') {
          currentRow.add(
            SymbolNode(
              span: dirTok.span,
              value: '=',
              atomClass: TexMathAtomClass.rel,
              isStretchy: true,
            ),
          );
        } else if (dir == '|') {
          currentRow.add(
            SymbolNode(
              span: dirTok.span,
              value: '\u2225',
              atomClass: TexMathAtomClass.rel,
              isStretchy: true,
            ),
          );
        } else {
          currentRow.add(
            MathGroupNode(span: dirTok.span, children: const <MathNode>[]),
          );
        }
        continue;
      }
      cellTokens.add(tok);
      continue;
    }

    cellTokens.add(host.cursor.nextRaw()!);
  }

  final SourceSpan endSpan = host.consumeEndEnvironment('CD', beginSpan);
  return MatrixNode(
    span: beginSpan.merge(endSpan),
    rows: rows,
    environment: 'CD',
    columnAlignments: const <String>['c'],
  );
}

List<TexToken> _readCdLabelUntil(
  TexParserHost host,
  String delim,
  SourceSpan fallbackSpan,
) {
  final List<TexToken> out = <TexToken>[];
  int braceDepth = 0;
  while (true) {
    final TexToken? tok = host.cursor.nextRaw();
    if (tok == null) {
      throw TexMathSyntaxError(
        'Missing "$delim" delimiter in CD diagram.',
        errorClass: TexMathErrorClass.missingArgument,
        span: fallbackSpan,
      );
    }
    if (tok.kind == TexTokenKind.beginGroup) {
      braceDepth++;
      out.add(tok);
    } else if (tok.kind == TexTokenKind.endGroup) {
      if (braceDepth > 0) {
        braceDepth--;
      }
      out.add(tok);
    } else if (braceDepth == 0 && tok.text == delim) {
      return out;
    } else {
      out.add(tok);
    }
  }
}

MathNode _parseProoftreeEnvironment(TexParserHost host, SourceSpan beginSpan) {
  final List<MathNode> proofStack = <MathNode>[];
  String defaultLine = 'solid';
  String currentLine = 'solid';
  MathNode? leftLabel;
  MathNode? rightLabel;
  bool rootAtTop = false;

  MathNode parseProofContent(List<TexToken> tokens, SourceSpan span) {
    final List<TexToken> trimmed = tokens
        .where((TexToken t) => t.kind != TexTokenKind.comment)
        .toList();
    if (trimmed.length >= 2 &&
        trimmed.first.kind == TexTokenKind.mathShift &&
        trimmed.last.kind == TexTokenKind.mathShift) {
      return host.parseSubTokens(
        trimmed.sublist(1, trimmed.length - 1),
        span: span,
      );
    }
    return host.parseTextTokens(trimmed, span: span);
  }

  while (true) {
    final TexToken? tok = host.cursor.peek();
    if (tok == null) {
      throw TexMathSyntaxError(
        'Missing \\end{prooftree}.',
        errorClass: TexMathErrorClass.mismatchedEnvironment,
        span: beginSpan,
      );
    }
    if (tok.kind == TexTokenKind.controlSequence && tok.text == 'end') {
      if (host.tryExpandUserEnvEnd()) {
        continue;
      }
      break;
    }
    host.cursor.next();
    if (tok.kind != TexTokenKind.controlSequence) {
      continue;
    }
    switch (tok.text) {
      case 'AxiomC':
      case 'Axiom':
        final List<TexToken> arg = host.readArgumentTokens(tok.text);
        proofStack.add(parseProofContent(arg, tok.span));
      case 'UnaryInfC':
      case 'UnaryInf':
      case 'BinaryInfC':
      case 'BinaryInf':
      case 'TrinaryInfC':
      case 'TrinaryInf':
      case 'QuaternaryInfC':
      case 'QuaternaryInf':
      case 'QuinaryInfC':
      case 'QuinaryInf':
        final int arity = switch (tok.text) {
          'UnaryInfC' || 'UnaryInf' => 1,
          'BinaryInfC' || 'BinaryInf' => 2,
          'TrinaryInfC' || 'TrinaryInf' => 3,
          'QuaternaryInfC' || 'QuaternaryInf' => 4,
          _ => 5,
        };
        if (proofStack.length < arity) {
          throw TexMathSyntaxError(
            'Proof tree badly specified for \\${tok.text}.',
            span: tok.span,
          );
        }
        final List<MathNode> premises = proofStack.sublist(
          proofStack.length - arity,
        );
        proofStack.removeRange(proofStack.length - arity, proofStack.length);
        final MathNode conclusion = parseProofContent(
          host.readArgumentTokens(tok.text),
          tok.span,
        );
        final List<MathNode> topRow = rootAtTop
            ? <MathNode>[conclusion]
            : premises;
        final List<MathNode> bottomRow = rootAtTop
            ? premises
            : <MathNode>[conclusion];
        final MatrixNode ruleTable = MatrixNode(
          span: tok.span,
          environment: 'prooftree',
          rows: <List<MathNode>>[topRow, bottomRow],
          rowLines: <int, String>{1: currentLine},
        );
        currentLine = defaultLine;
        if (leftLabel != null || rightLabel != null) {
          proofStack.add(
            MathGroupNode(
              span: tok.span,
              isExplicitGroup: false,
              role: 'prooftree_rule',
              children: <MathNode>[?leftLabel, ruleTable, ?rightLabel],
            ),
          );
          leftLabel = null;
          rightLabel = null;
        } else {
          proofStack.add(ruleTable);
        }
      case 'LeftLabel':
        leftLabel = parseProofContent(
          host.readArgumentTokens(tok.text),
          tok.span,
        );
      case 'RightLabel':
        rightLabel = parseProofContent(
          host.readArgumentTokens(tok.text),
          tok.span,
        );
      case 'dashedLine':
        currentLine = 'dashed';
      case 'doubleLine':
        currentLine = 'double';
      case 'solidLine':
        currentLine = 'solid';
      case 'noLine':
        currentLine = 'none';
      case 'alwaysDashedLine':
        defaultLine = 'dashed';
        currentLine = 'dashed';
      case 'alwaysDoubleLine':
        defaultLine = 'double';
        currentLine = 'double';
      case 'alwaysSolidLine':
        defaultLine = 'solid';
        currentLine = 'solid';
      case 'alwaysNoLine':
        defaultLine = 'none';
        currentLine = 'none';
      case 'rootAtTop':
        rootAtTop = true;
      case 'rootAtBottom':
        rootAtTop = false;
      default:
        throw TexMathSyntaxError(
          'Unknown command \\${tok.text} inside prooftree.',
          errorClass: TexMathErrorClass.undefinedControlSequence,
          span: tok.span,
        );
    }
  }

  final SourceSpan endSpan = host.consumeEndEnvironment('prooftree', beginSpan);
  return MathGroupNode(
    span: beginSpan.merge(endSpan),
    isExplicitGroup: false,
    role: 'prooftree',
    children: proofStack,
  );
}
