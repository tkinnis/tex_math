import 'dart:math' as math;

import '../ast.dart';
import '../font.dart';
import '../options.dart';
import '../shared/layout_constants.dart';
import '../source_span.dart';
import 'box.dart';
import 'glyph_resolve.dart';
import 'stretchy.dart';
import 'style_spacing.dart';

/// Tier 1 matrix and alignment environment names supported by core layout.
const Set<String> tier1MatrixEnvironments = <String>{
  'math',
  'displaymath',
  'equation',
  'equation*',
  'eqnarray',
  'eqnarray*',
  'array',
  'darray',
  'matrix',
  'pmatrix',
  'bmatrix',
  'Bmatrix',
  'vmatrix',
  'Vmatrix',
  'smallmatrix',
  'subarray',
  'cases',
  'eqalign',
  'eqalignno',
  'leqalignno',
  'displaylines',
  'align',
  'align*',
  'aligned',
  'alignat',
  'alignat*',
  'alignedat',
  'xalignat',
  'xalignat*',
  'xxalignat',
  'flalign',
  'flalign*',
  'gather',
  'gather*',
  'gathered',
  'multline',
  'multline*',
  'split',
};

/// Callback invoked by [layoutMatrixNode] to lay out an individual cell node
/// in the resolved [TexMathStyle].
typedef MatrixCellLayouter = MathBox Function(
  MathNode node, {
  required TexMathStyle style,
  TexMathAtomClass? leadingImplicitClass,
});

/// Lays out a [MatrixNode] (arrays, matrices, cases, AMS alignments,
/// commutative diagrams, and proof-tree steps) using OpenType `MATH`
/// parameters from [mathTable] and [font].
MathBox layoutMatrixNode({
  required MatrixNode node,
  required MathFont font,
  required MathTableData mathTable,
  required TexMathStyle currentStyle,
  required MatrixCellLayouter layoutCell,
  double fontScale = 1.0,
  double? multlineWidthEm,
}) {
  final String env = node.environment;
  if (env == 'CD') {
    return _layoutCdMatrix(
      node: node,
      font: font,
      mathTable: mathTable,
      currentStyle: currentStyle,
      layoutCell: layoutCell,
      fontScale: fontScale,
    );
  }
  if (env == 'prooftree') {
    return layoutProoftreeElement(
      node,
      font: font,
      mathTable: mathTable,
      currentStyle: currentStyle,
      layoutCell: layoutCell,
      fontScale: fontScale,
    );
  }

  final MathConstants constants = mathTable.constants;
  final double upem = font.unitsPerEm.toDouble();
  final double scale = scaleForStyle(currentStyle, constants) * fontScale;
  final double axisEm = (constants.axisHeight / upem) * scale;
  final double ruleThicknessEm =
      (constants.fractionRuleThickness / upem) * scale;

  final _MatrixSpec spec = _specForEnvironment(env, currentStyle);

  final int rowCount = node.rows.length;
  int colCount = 0;
  for (final List<MathNode> row in node.rows) {
    if (row.length > colCount) {
      colCount = row.length;
    }
  }

  // Lay out every cell box and compute column widths, cell backgrounds, and
  // row heights/depths.
  final List<List<MathBox>> cellBoxes = <List<MathBox>>[];
  final List<List<int?>> cellBgColors = <List<int?>>[];
  final List<List<String?>> cellShoves = <List<String?>>[];
  final List<double> colWidths = List<double>.filled(colCount, 0.0);
  final List<double> rowHeights = List<double>.filled(rowCount, 0.0);
  final List<double> rowDepths = List<double>.filled(rowCount, 0.0);

  for (int r = 0; r < rowCount; r++) {
    final List<MathNode> row = node.rows[r];
    final List<MathBox> laidRow = <MathBox>[];
    final List<int?> bgRow = <int?>[];
    final List<String?> shoveRow = <String?>[];
    double maxH = spec.minRowHeightEm * scale;
    double maxD = spec.minRowDepthEm * scale;

    for (int c = 0; c < colCount; c++) {
      final MathNode? rawCell = c < row.length ? row[c] : null;
      final (MathNode? cellNode, int? cellBgArgb) = _unwrapCellBackground(
        rawCell,
      );
      bgRow.add(cellBgArgb);

      final String? shove = _extractShoveRole(cellNode);
      shoveRow.add(shove);

      final String colAlign = _alignmentForColumn(
        spec: spec,
        explicitAlignments: node.columnAlignments,
        columnIndex: c,
      );
      // AMS alignment left-columns prepend an implicit empty Ord so `&=`, `&+`
      // preserve relation/binary spacing against the preceding column; multline
      // continuation rows (`r > 0`) likewise prepend an implicit Ord so leading
      // `+` / `-` retains binary spacing.
      final TexMathAtomClass? implicitPrev =
          (spec.prependImplicitOrdInLeftCol && colAlign == 'l' && c > 0) ||
              (spec.isMultline && r > 0)
          ? TexMathAtomClass.ord
          : null;

      final MathBox cellBox = cellNode == null
          ? const KernBox(widthEm: 0.0)
          : layoutCell(
              cellNode,
              style: spec.cellStyle,
              leadingImplicitClass: implicitPrev,
            );
      laidRow.add(cellBox);
      if (cellBox.widthEm > colWidths[c]) {
        colWidths[c] = cellBox.widthEm;
      }
      if (cellBox.heightEm > maxH) {
        maxH = cellBox.heightEm;
      }
      if (cellBox.depthEm > maxD) {
        maxD = cellBox.depthEm;
      }
    }
    cellBoxes.add(laidRow);
    cellBgColors.add(bgRow);
    cellShoves.add(shoveRow);
    rowHeights[r] = maxH;
    rowDepths[r] = maxD;
  }

  // Lay out optional row tags (`\tag{...}`).
  final Map<int, MathBox> tagBoxes = <int, MathBox>{};
  double maxTagWidth = 0.0;
  for (final MapEntry<int, TagNode> entry in node.rowTags.entries) {
    final TagNode tag = entry.value;
    final String tagText = tag.isStarred ? tag.label : '(${tag.label})';
    final MathBox textBox = layoutCell(
      TextNode(span: tag.span, text: tagText, styleCommand: 'textrm'),
      style: TexMathStyle.text,
    );
    final AnchorBox anchor = AnchorBox(
      id: 'tag:${tag.label}',
      label: tag.label,
      span: tag.span,
    );
    final HBox combinedTag = HBox(
      children: <MathBox>[anchor, textBox],
      span: tag.span,
    );
    tagBoxes[entry.key] = combinedTag;
    if (combinedTag.widthEm > maxTagWidth) {
      maxTagWidth = combinedTag.widthEm;
    }
  }

  // Compute column X positions including vertical rules (`|`, `||`) and custom
  // `@{...}` column separators.
  final double colSepRuleGap = 2.5 * ruleThicknessEm;
  final double outerPadX = spec.outerPadEm * scale;
  final List<double> colX = List<double>.filled(colCount, 0.0);
  final List<double> colBgLeft = List<double>.filled(colCount, 0.0);
  final List<double> colBgRight = List<double>.filled(colCount, 0.0);
  final List<(double xEm, int barCount)> verticalRules = <(double, int)>[];
  final List<(double minX, double maxX)> barSpansAtBoundary =
      List<(double, double)>.filled(colCount + 1, (0.0, 0.0));
  final Map<int, ({double xEm, MathBox box})> customColSeparators =
      <int, ({double xEm, MathBox box})>{};

  final bool hasLeftBorderRule = _barCountForSeparator(node.columnLines[0]) > 0;
  final bool hasRightBorderRule =
      _barCountForSeparator(node.columnLines[colCount]) > 0;
  double cursorX = hasLeftBorderRule ? 0.0 : outerPadX;
  for (int c = 0; c <= colCount; c++) {
    final int barCount = _barCountForSeparator(node.columnLines[c]);
    final MathNode? sepNode = node.columnSeparators[c];
    final bool hasCustomSep = sepNode != null && barCount == 0;
    if (barCount > 0) {
      if (c > 0) {
        cursorX += 0.50 * scale;
      }
      final double barStart = cursorX;
      for (int b = 0; b < barCount; b++) {
        verticalRules.add((cursorX, 1));
        cursorX += ruleThicknessEm;
        if (b + 1 < barCount) {
          cursorX += colSepRuleGap;
        }
      }
      final double barEnd = cursorX;
      barSpansAtBoundary[c] = (barStart, barEnd);
      if (c < colCount) {
        cursorX += 0.50 * scale;
      }
    } else if (hasCustomSep) {
      final MathBox sepBox = layoutCell(sepNode, style: spec.cellStyle);
      customColSeparators[c] = (xEm: cursorX, box: sepBox);
      barSpansAtBoundary[c] = (cursorX, cursorX + sepBox.widthEm);
      cursorX += sepBox.widthEm;
    } else if (c > 0 && c < colCount) {
      final double gapStart = cursorX;
      final double gapW = _columnGapForIndex(spec, c - 1) * scale;
      barSpansAtBoundary[c] = (gapStart + gapW / 2.0, gapStart + gapW / 2.0);
    } else {
      barSpansAtBoundary[c] = (cursorX, cursorX);
    }
    if (c < colCount) {
      if (c > 0 && barCount == 0 && !hasCustomSep) {
        cursorX += _columnGapForIndex(spec, c - 1) * scale;
      }
      colX[c] = cursorX;
      cursorX += colWidths[c];
    }
  }
  double bodyWidthEm = cursorX + (hasRightBorderRule ? 0.0 : outerPadX);
  for (int c = 0; c < colCount; c++) {
    colBgLeft[c] = c == 0
        ? (hasLeftBorderRule ? barSpansAtBoundary[0].$2 : 0.0)
        : barSpansAtBoundary[c].$2;
    colBgRight[c] = c + 1 == colCount
        ? (hasRightBorderRule ? barSpansAtBoundary[colCount].$1 : bodyWidthEm)
        : barSpansAtBoundary[c + 1].$1;
  }
  final double maxRowW = colWidths.isEmpty ? 0.0 : colWidths[0];
  if (spec.isMultline && !spec.isMultlined) {
    final double indent = 1.0 * scale;
    if (multlineWidthEm != null) {
      bodyWidthEm = math.max(multlineWidthEm * scale, maxRowW + 2.0 * indent);
    } else {
      final double minStagger = rowCount > 1 ? 2.0 * scale : 0.0;
      bodyWidthEm = math.max(12.0 * scale, maxRowW + 2.0 * indent + minStagger);
    }
  } else if (spec.isMultlined) {
    double naturalW = 0.0;
    for (int r = 0; r < rowCount; r++) {
      final double rowCellW = colCount > 0 ? cellBoxes[r][0].widthEm : 0.0;
      final String? shove = colCount > 0 ? cellShoves[r][0] : null;
      double rowW = rowCellW;
      if (rowCount > 1) {
        if (r == 0 && shove != 'shoveright') {
          rowW += 1.0 * scale;
        } else if (r == rowCount - 1 && shove != 'shoveleft') {
          rowW += 1.0 * scale;
        }
      }
      if (rowW > naturalW) {
        naturalW = rowW;
      }
    }
    if (node.explicitWidthEm != null) {
      bodyWidthEm = math.max(node.explicitWidthEm! * scale, maxRowW);
    } else {
      bodyWidthEm = naturalW;
    }
  }
  if (colCount > 0 && !hasRightBorderRule) {
    colBgRight[colCount - 1] = bodyWidthEm;
  }

  // Compute row baseline Y offsets top-to-bottom (first row at top).
  final List<double> rowBaselinesTopDown = List<double>.filled(rowCount, 0.0);
  final List<double> rowBgTopDown = List<double>.filled(rowCount, 0.0);
  final List<double> rowBgBottomDown = List<double>.filled(rowCount, 0.0);
  final List<double> horizontalRuleY = <double>[];
  final List<(double topY, double bottomY)> hRuleSpanAtBoundary =
      List<(double, double)>.filled(rowCount + 1, (0.0, 0.0));
  double cursorTop = 0.0;
  final double outerPadY = spec.outerPadYEm * scale;
  cursorTop -= outerPadY;

  for (int r = 0; r <= rowCount; r++) {
    final String? hline = node.rowLines[r];
    final int hBars = _hlineCount(hline);
    if (hBars > 0) {
      if (r > 0) {
        cursorTop -=
            (r < rowCount
                ? spec.rowGapEm * 0.5
                : LayoutDefaults.fallbackRuleThicknessEm) *
            scale;
      }
      final double ruleTop = cursorTop;
      for (int b = 0; b < hBars; b++) {
        horizontalRuleY.add(cursorTop - ruleThicknessEm);
        cursorTop -= ruleThicknessEm;
        if (b + 1 < hBars) {
          cursorTop -= colSepRuleGap;
        }
      }
      final double ruleBottom = cursorTop;
      hRuleSpanAtBoundary[r] = (ruleTop, ruleBottom);
      if (r < rowCount) {
        cursorTop -=
            (r > 0
                ? spec.rowGapEm * 0.5
                : LayoutDefaults.fallbackRuleThicknessEm) *
            scale;
      }
    } else if (r > 0 && r < rowCount) {
      final double midGap = cursorTop - (spec.rowGapEm * 0.5) * scale;
      hRuleSpanAtBoundary[r] = (midGap, midGap);
      cursorTop -= spec.rowGapEm * scale;
    } else {
      hRuleSpanAtBoundary[r] = (cursorTop, cursorTop);
    }
    if (r < rowCount) {
      cursorTop -= rowHeights[r];
      rowBaselinesTopDown[r] = cursorTop;
      cursorTop -= rowDepths[r];
    }
  }
  cursorTop -= outerPadY;
  final double totalTableSpan = -cursorTop;
  for (int r = 0; r < rowCount; r++) {
    rowBgTopDown[r] = hRuleSpanAtBoundary[r].$2;
    rowBgBottomDown[r] = hRuleSpanAtBoundary[r + 1].$1;
  }

  // Vertical anchor alignment (`t`, `b`, or centered on `axisEm`).
  final double shiftY;
  if (rowCount == 0) {
    shiftY = 0.0;
  } else if (node.verticalAlignment == 't') {
    shiftY = -rowBaselinesTopDown.first;
  } else if (node.verticalAlignment == 'b') {
    shiftY = -rowBaselinesTopDown.last;
  } else {
    shiftY = axisEm + totalTableSpan / 2.0;
  }

  final List<VBoxChild> placed = <VBoxChild>[];
  // Paint cell background fills (`\cellcolor`, `\rowcolor`, `\columncolor`)
  // first so cell content and grid rules sit above them.
  for (int r = 0; r < rowCount; r++) {
    final double bgH = math.max(0.0, rowBgTopDown[r] - rowBgBottomDown[r]);
    final double bgY = rowBgBottomDown[r] + shiftY;
    for (int c = 0; c < colCount; c++) {
      final int? bgArgb = cellBgColors[r][c];
      if (bgArgb == null) {
        continue;
      }
      final double bgW = math.max(0.0, colBgRight[c] - colBgLeft[c]);
      if (bgW <= 0.0 || bgH <= 0.0) {
        continue;
      }
      placed.add(
        VBoxChild(
          box: RuleBox(
            widthEm: bgW,
            heightEm: bgH,
            colorRole: TexMathColorRole.custom,
            customColor: bgArgb,
            inheritColor: false,
            span: node.span,
          ),
          xEm: colBgLeft[c],
          yEm: bgY,
        ),
      );
    }
  }
  for (int r = 0; r < rowCount; r++) {
    final double rowY = rowBaselinesTopDown[r] + shiftY;
    for (int c = 0; c < colCount; c++) {
      final MathBox box = cellBoxes[r][c];
      final String? shove = cellShoves[r][c];
      final double colW = colWidths[c];
      final double dx;
      if (spec.isMultline) {
        final double indent = spec.isMultlined ? 0.0 : 1.0 * scale;
        final double innerW = bodyWidthEm - 2.0 * outerPadX;
        if (shove == 'shoveleft' || (shove == null && r == 0)) {
          dx = indent;
        } else if (shove == 'shoveright' ||
            (shove == null && r == rowCount - 1 && rowCount > 1)) {
          dx = math.max(indent, innerW - box.widthEm - indent);
        } else {
          dx = math.max(indent, (innerW - box.widthEm) / 2.0);
        }
      } else {
        final String align = _alignmentForColumn(
          spec: spec,
          explicitAlignments: node.columnAlignments,
          columnIndex: c,
        );
        switch (align) {
          case 'r':
            dx = colW - box.widthEm;
          case 'c':
            dx = (colW - box.widthEm) / 2.0;
          default:
            dx = 0.0;
        }
      }
      final ({double xEm, MathBox box})? preSep = customColSeparators[c];
      if (preSep != null) {
        placed.add(VBoxChild(box: preSep.box, xEm: preSep.xEm, yEm: rowY));
      }
      placed.add(VBoxChild(box: box, xEm: colX[c] + dx, yEm: rowY));
    }

    final ({double xEm, MathBox box})? trailingSep =
        customColSeparators[colCount];
    if (trailingSep != null) {
      placed.add(
        VBoxChild(box: trailingSep.box, xEm: trailingSep.xEm, yEm: rowY),
      );
    }

    final MathBox? tagBox = tagBoxes[r];
    if (tagBox != null) {
      final double tagX =
          bodyWidthEm + 0.9 * scale + (maxTagWidth - tagBox.widthEm);
      placed.add(VBoxChild(box: tagBox, xEm: tagX, yEm: rowY));
    }
  }

  // Horizontal rules (`\hline`).
  for (final double ry in horizontalRuleY) {
    placed.add(
      VBoxChild(
        box: RuleBox(
          widthEm: bodyWidthEm,
          heightEm: ruleThicknessEm,
          span: node.span,
        ),
        xEm: 0.0,
        yEm: ry + shiftY,
      ),
    );
  }

  // Vertical rules (`|`), clamped to outer `\hline` / row bounds so corners
  // stay flush without overshooting into `outerPadY`.
  if (rowCount > 0 && verticalRules.isNotEmpty) {
    final double vRuleTopDown = hRuleSpanAtBoundary[0].$1;
    final double vRuleBottomDown = hRuleSpanAtBoundary[rowCount].$2;
    final double vRuleHeight = math.max(0.0, vRuleTopDown - vRuleBottomDown);
    final double ruleBottomY = vRuleBottomDown + shiftY;
    for (final (double vx, _) in verticalRules) {
      placed.add(
        VBoxChild(
          box: RuleBox(
            widthEm: ruleThicknessEm,
            heightEm: vRuleHeight,
            span: node.span,
          ),
          xEm: vx,
          yEm: ruleBottomY,
        ),
      );
    }
  }

  final double finalWidth = tagBoxes.isNotEmpty
      ? bodyWidthEm + 0.9 * scale + maxTagWidth
      : bodyWidthEm;

  final VBox tableBox = VBox.positioned(
    children: placed,
    widthEm: finalWidth,
    heightEm: rowCount == 0 ? 0.0 : math.max(0.0, shiftY),
    depthEm: rowCount == 0 ? 0.0 : math.max(0.0, totalTableSpan - shiftY),
    atomClass: TexMathAtomClass.ord,
    span: node.span,
  );

  // Wrap delimiters for `pmatrix`, `bmatrix`, `Bmatrix`, `vmatrix`, `Vmatrix`,
  // and `cases` / `rcases`.
  final String? leftDelim = node.leftDelimiter;
  final String? rightDelim = node.rightDelimiter;
  final bool isLeftCases =
      env == 'cases' ||
      env == 'cases*' ||
      env == 'dcases' ||
      env == 'dcases*' ||
      env == 'numcases' ||
      env == 'subnumcases';
  final bool isRightCases =
      env == 'rcases' ||
      env == 'rcases*' ||
      env == 'drcases' ||
      env == 'drcases*';
  if (leftDelim == null &&
      rightDelim == null &&
      !isLeftCases &&
      !isRightCases) {
    return tableBox;
  }

  final double halfSpan = math.max(
    tableBox.heightEm - axisEm,
    tableBox.depthEm + axisEm,
  );
  final double targetDelimSpan = 2.0 * halfSpan;
  final List<MathBox> wrapped = <MathBox>[];
  if ((leftDelim != null && leftDelim != '.') || isRightCases) {
    wrapped.add(
      buildVerticalDelimiterBox(
        font: font,
        mathTable: mathTable,
        delimiter: isRightCases && leftDelim == null ? '.' : leftDelim,
        targetSpanEm: targetDelimSpan,
        atomClass: TexMathAtomClass.open,
        scale: scale,
        isNullDelimiterSpace: isRightCases && leftDelim == null,
        span: node.span,
      ),
    );
  }
  wrapped.add(tableBox);
  if (rightDelim != null || isLeftCases) {
    wrapped.add(
      buildVerticalDelimiterBox(
        font: font,
        mathTable: mathTable,
        delimiter: rightDelim,
        targetSpanEm: targetDelimSpan,
        atomClass: TexMathAtomClass.close,
        scale: scale,
        isNullDelimiterSpace: rightDelim == null || rightDelim == '.',
        span: node.span,
      ),
    );
  }

  return HBox(
    children: wrapped,
    atomClass: TexMathAtomClass.inner,
    span: node.span,
  );
}

class _MatrixSpec {
  const _MatrixSpec({
    required this.cellStyle,
    required this.colGapEm,
    required this.pairGapEm,
    required this.rowGapEm,
    required this.minRowHeightEm,
    required this.minRowDepthEm,
    required this.outerPadEm,
    required this.outerPadYEm,
    required this.defaultAlignments,
    required this.repeatDefaultAlignments,
    required this.prependImplicitOrdInLeftCol,
    required this.isMultline,
    this.isMultlined = false,
  });

  final TexMathStyle cellStyle;
  final double colGapEm;
  final double pairGapEm;
  final double rowGapEm;
  final double minRowHeightEm;
  final double minRowDepthEm;
  final double outerPadEm;
  final double outerPadYEm;
  final List<String> defaultAlignments;
  final bool repeatDefaultAlignments;
  final bool prependImplicitOrdInLeftCol;
  final bool isMultline;
  final bool isMultlined;
}

_MatrixSpec _specForEnvironment(String env, TexMathStyle enclosingStyle) {
  switch (env) {
    case 'smallmatrix':
    case 'smallmatrix*':
    case 'psmallmatrix':
    case 'psmallmatrix*':
    case 'bsmallmatrix':
    case 'bsmallmatrix*':
    case 'Bsmallmatrix':
    case 'Bsmallmatrix*':
    case 'vsmallmatrix':
    case 'vsmallmatrix*':
    case 'Vsmallmatrix':
    case 'Vsmallmatrix*':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.script,
        colGapEm: 0.278,
        pairGapEm: 0.278,
        rowGapEm: 0.14,
        minRowHeightEm: 0.37,
        minRowDepthEm: 0.13,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'subarray':
    case 'crampedsubarray':
      return _MatrixSpec(
        cellStyle: env == 'crampedsubarray'
            ? TexMathStyle.crampedScript
            : TexMathStyle.script,
        colGapEm: 0.278,
        pairGapEm: 0.278,
        rowGapEm: 0.12,
        minRowHeightEm: 0.44,
        minRowDepthEm: 0.14,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: const <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'cases':
    case 'cases*':
    case 'rcases':
    case 'rcases*':
    case 'dcases':
    case 'dcases*':
    case 'drcases':
    case 'drcases*':
    case 'numcases':
    case 'subnumcases':
      final bool isDisplay =
          env.startsWith('d') || env == 'numcases' || env == 'subnumcases';
      return _MatrixSpec(
        cellStyle: isDisplay ? TexMathStyle.display : TexMathStyle.text,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.20,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: const <String>['l', 'l'],
        repeatDefaultAlignments: false,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'array':
    case 'darray':
      return _MatrixSpec(
        cellStyle: env == 'darray' ? TexMathStyle.display : TexMathStyle.text,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.40,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.50,
        outerPadYEm: 0.125,
        defaultAlignments: const <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'matrix':
    case 'matrix*':
    case 'pmatrix':
    case 'pmatrix*':
    case 'bmatrix':
    case 'bmatrix*':
    case 'Bmatrix':
    case 'Bmatrix*':
    case 'vmatrix':
    case 'vmatrix*':
    case 'Vmatrix':
    case 'Vmatrix*':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.text,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.40,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'alignat':
    case 'alignat*':
    case 'alignedat':
    case 'xalignat':
    case 'xalignat*':
    case 'xxalignat':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 0.0,
        pairGapEm: 0.0,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['r', 'l'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: true,
        isMultline: false,
      );
    case 'align':
    case 'align*':
    case 'aligned':
    case 'eqalign':
    case 'eqalignno':
    case 'leqalignno':
    case 'flalign':
    case 'flalign*':
    case 'split':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 0.0,
        pairGapEm: 2.0,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['r', 'l'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: true,
        isMultline: false,
      );
    case 'eqnarray':
    case 'eqnarray*':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 0.278,
        pairGapEm: 0.278,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['r', 'c', 'l'],
        repeatDefaultAlignments: false,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'multline':
    case 'multline*':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 0.0,
        pairGapEm: 0.0,
        rowGapEm: 0.50,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['l'],
        repeatDefaultAlignments: false,
        prependImplicitOrdInLeftCol: false,
        isMultline: true,
        isMultlined: false,
      );
    case 'multlined':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 0.0,
        pairGapEm: 0.0,
        rowGapEm: 0.50,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['l'],
        repeatDefaultAlignments: false,
        prependImplicitOrdInLeftCol: false,
        isMultline: true,
        isMultlined: true,
      );
    case 'lgathered':
    case 'rgathered':
      return _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>[env == 'lgathered' ? 'l' : 'r'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    case 'gather':
    case 'gather*':
    case 'gathered':
    case 'displaylines':
    case 'equation':
    case 'equation*':
    case 'displaymath':
      return const _MatrixSpec(
        cellStyle: TexMathStyle.display,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
    default:
      return _MatrixSpec(
        cellStyle: enclosingStyle,
        colGapEm: 1.0,
        pairGapEm: 1.0,
        rowGapEm: 0.30,
        minRowHeightEm: 0.75,
        minRowDepthEm: 0.25,
        outerPadEm: 0.0,
        outerPadYEm: 0.0,
        defaultAlignments: const <String>['c'],
        repeatDefaultAlignments: true,
        prependImplicitOrdInLeftCol: false,
        isMultline: false,
      );
  }
}

double _columnGapForIndex(_MatrixSpec spec, int leftColIndex) {
  if (spec.repeatDefaultAlignments &&
      spec.defaultAlignments.length == 2 &&
      spec.defaultAlignments[0] == 'r' &&
      spec.defaultAlignments[1] == 'l') {
    return leftColIndex.isEven ? spec.colGapEm : spec.pairGapEm;
  }
  return spec.colGapEm;
}

String _alignmentForColumn({
  required _MatrixSpec spec,
  required List<String> explicitAlignments,
  required int columnIndex,
}) {
  if (explicitAlignments.isNotEmpty) {
    if (spec.repeatDefaultAlignments) {
      return explicitAlignments[columnIndex % explicitAlignments.length];
    }
    if (columnIndex < explicitAlignments.length) {
      return explicitAlignments[columnIndex];
    }
    return explicitAlignments.last;
  }
  if (spec.repeatDefaultAlignments) {
    return spec.defaultAlignments[columnIndex % spec.defaultAlignments.length];
  }
  if (columnIndex < spec.defaultAlignments.length) {
    return spec.defaultAlignments[columnIndex];
  }
  return spec.defaultAlignments.last;
}

String? _extractShoveRole(MathNode? node) {
  if (node is MathGroupNode) {
    if (node.role == 'shoveleft' || node.role == 'shoveright') {
      return node.role;
    }
    if (!node.isExplicitGroup) {
      for (final MathNode child in node.children) {
        if (child is TagNode && child.isLabelDefinition) {
          continue;
        }
        return _extractShoveRole(child);
      }
      return null;
    }
    if (node.children.length == 1) {
      return _extractShoveRole(node.children.first);
    }
  }
  return null;
}

int _barCountForSeparator(String? sep) {
  if (sep == null || sep.isEmpty) {
    return 0;
  }
  if (sep == 'solid') {
    return 1;
  }
  if (sep == 'double' || sep == '||') {
    return 2;
  }
  return '|'.allMatches(sep).length;
}

int _hlineCount(String? hline) {
  if (hline == null || hline.isEmpty) {
    return 0;
  }
  if (hline == 'double' || hline == 'solid_double') {
    return 2;
  }
  return 1;
}

(MathNode?, int?) _unwrapCellBackground(MathNode? cell) {
  if (cell == null) {
    return (null, null);
  }
  if (cell is ColorNode && cell.backgroundColor != null) {
    final int? bg = resolveColorSpecArgb(cell.backgroundColor);
    final MathNode inner = (cell.colorValue == null && cell.borderColor == null)
        ? MathGroupNode(
            span: cell.span,
            isExplicitGroup: false,
            children: cell.children,
          )
        : ColorNode(
            span: cell.span,
            role: cell.role,
            colorValue: cell.colorValue,
            borderColor: cell.borderColor,
            children: cell.children,
          );
    return (inner, bg);
  }
  return (cell, null);
}

bool _isEmptyCdCell(MathNode node) {
  return node is MathGroupNode &&
      node.children.isEmpty &&
      node.role == null &&
      node.atomClass == null;
}

({int codePoint, MathNode? labelA, MathNode? labelB})? _parseCdDirective(
  MathNode node,
) {
  if (node is OperatorNode &&
      node.isExtensible &&
      node.operatorName.isNotEmpty) {
    return (
      codePoint: firstCodePointOr(node.operatorName, 0),
      labelA: null,
      labelB: null,
    );
  }
  if (node is ScriptNode) {
    final MathNode base = node.base;
    if (base is OperatorNode &&
        base.isExtensible &&
        base.operatorName.isNotEmpty) {
      return (
        codePoint: firstCodePointOr(base.operatorName, 0),
        labelA: node.superscript,
        labelB: node.subscript,
      );
    }
  }
  if (node is SymbolNode && node.isStretchy && node.value.isNotEmpty) {
    return (
      codePoint: firstCodePointOr(node.value, 0),
      labelA: null,
      labelB: null,
    );
  }
  return null;
}

bool _isCdRowVerticalOnly(List<MathNode> row) {
  bool sawVertical = false;
  for (int i = 0; i < row.length; i++) {
    final MathNode cell = row[i];
    if (i.isEven) {
      if (!_isEmptyCdCell(cell)) {
        return false;
      }
      continue;
    }
    final ({int codePoint, MathNode? labelA, MathNode? labelB})? dir =
        _parseCdDirective(cell);
    if (dir != null) {
      if (dir.codePoint == 0x2191 ||
          dir.codePoint == 0x2193 ||
          dir.codePoint == 0x2225) {
        sawVertical = true;
      } else {
        return false;
      }
    } else if (!_isEmptyCdCell(cell)) {
      return false;
    }
  }
  return sawVertical || (row.length >= 2 && _isEmptyCdCell(row[0]));
}

MathBox _layoutCdMatrix({
  required MatrixNode node,
  required MathFont font,
  required MathTableData mathTable,
  required TexMathStyle currentStyle,
  required MatrixCellLayouter layoutCell,
  required double fontScale,
}) {
  final MathConstants constants = mathTable.constants;
  final double upem = font.unitsPerEm.toDouble();
  final double scale = scaleForStyle(currentStyle, constants) * fontScale;
  final double axisEm = (constants.axisHeight / upem) * scale;
  final TexMathStyle labelStyle = subscriptStyle(currentStyle);
  final double minHorizArrowEm = 2.2 * scale;
  final double minVertArrowEm = 2.2 * scale;
  final double hGapEm = 0.25 * scale;
  final double vGapEm = 0.20 * scale;

  // Normalize odd CD directive rows so vertical arrows map cleanly under even
  // vertex columns (`0, 2, 4, ...`).
  final List<List<MathNode>> normalizedRows = <List<MathNode>>[];
  int colCount = 0;
  for (final List<MathNode> row in node.rows) {
    final List<MathNode> mapped;
    if (_isCdRowVerticalOnly(row)) {
      mapped = <MathNode>[];
      for (int i = 1; i < row.length; i += 2) {
        mapped.add(row[i]);
        if (i + 2 < row.length) {
          mapped.add(
            MathGroupNode(span: node.span, children: const <MathNode>[]),
          );
        }
      }
    } else {
      mapped = row;
    }
    normalizedRows.add(mapped);
    if (mapped.length > colCount) {
      colCount = mapped.length;
    }
  }

  final int rowCount = normalizedRows.length;
  final List<double> colWidths = List<double>.filled(colCount, 0.0);
  final List<List<MathBox>> laidCells = List<List<MathBox>>.generate(
    rowCount,
    (_) => List<MathBox>.filled(colCount, const KernBox(widthEm: 0.0)),
  );
  final List<List<_CdCellData?>> parsedCells =
      List<List<_CdCellData?>>.generate(
        rowCount,
        (_) => List<_CdCellData?>.filled(colCount, null),
      );

  // Measure vertices and arrow labels first so arrow column widths expand to
  // fit labels cleanly.
  for (int r = 0; r < rowCount; r++) {
    final List<MathNode> row = normalizedRows[r];
    for (int c = 0; c < row.length; c++) {
      final MathNode cell = row[c];
      final ({int codePoint, MathNode? labelA, MathNode? labelB})? dir =
          _parseCdDirective(cell);
      if (dir == null) {
        if (!_isEmptyCdCell(cell)) {
          final MathBox box = layoutCell(cell, style: currentStyle);
          laidCells[r][c] = box;
          if (box.widthEm > colWidths[c]) {
            colWidths[c] = box.widthEm;
          }
        }
        continue;
      }

      final MathBox? labelABox = dir.labelA == null
          ? null
          : layoutCell(dir.labelA!, style: labelStyle);
      final MathBox? labelBBox = dir.labelB == null
          ? null
          : layoutCell(dir.labelB!, style: labelStyle);
      final bool isVert =
          dir.codePoint == 0x2191 ||
          dir.codePoint == 0x2193 ||
          dir.codePoint == 0x2225;
      parsedCells[r][c] = _CdCellData(
        codePoint: dir.codePoint,
        isVertical: isVert,
        labelA: labelABox,
        labelB: labelBBox,
      );
      if (!isVert) {
        final double labelMaxW = math.max(
          labelABox?.widthEm ?? 0.0,
          labelBBox?.widthEm ?? 0.0,
        );
        final double targetW = math.max(
          minHorizArrowEm,
          labelMaxW + 0.8 * scale,
        );
        if (targetW > colWidths[c]) {
          colWidths[c] = targetW;
        }
      } else {
        final MathBox probe = buildVerticalDelimiterBox(
          font: font,
          mathTable: mathTable,
          delimiter: String.fromCharCode(dir.codePoint),
          targetSpanEm: minVertArrowEm,
          atomClass: TexMathAtomClass.rel,
          scale: scale,
          span: cell.span,
        );
        final double labelW =
            probe.widthEm +
            (labelABox != null ? labelABox.widthEm + 0.18 * scale : 0.0) +
            (labelBBox != null ? labelBBox.widthEm + 0.18 * scale : 0.0);
        if (probe.widthEm > colWidths[c]) {
          colWidths[c] = probe.widthEm;
        }
        final double halfExtra = math.max(0.0, (labelW - colWidths[c]) / 2.0);
        if (c > 0 && halfExtra > 0.0) {
          colWidths[c - 1] = math.max(
            colWidths[c - 1],
            halfExtra + 0.6 * scale,
          );
        }
        if (c + 1 < colCount && halfExtra > 0.0) {
          colWidths[c + 1] = math.max(
            colWidths[c + 1],
            halfExtra + 0.6 * scale,
          );
        }
      }
    }
  }

  // Finalize horizontal and vertical arrow boxes using resolved column widths.
  final double topShiftMin = (constants.stretchStackTopShiftUp / upem) * scale;
  final double botShiftMin =
      (constants.stretchStackBottomShiftDown / upem) * scale;
  final double gapAbove = (constants.stretchStackGapAboveMin / upem) * scale;
  final double gapBelow = (constants.stretchStackGapBelowMin / upem) * scale;

  final List<double> rowHeights = List<double>.filled(rowCount, 0.0);
  final List<double> rowDepths = List<double>.filled(rowCount, 0.0);

  for (int r = 0; r < rowCount; r++) {
    double maxH = 0.0;
    double maxD = 0.0;
    for (int c = 0; c < colCount; c++) {
      final _CdCellData? data = parsedCells[r][c];
      if (data != null) {
        if (!data.isVertical) {
          final MathBox arrow = buildHorizontalStretchyBox(
            font: font,
            mathTable: mathTable,
            codePoint: data.codePoint,
            targetWidthEm: colWidths[c],
            scale: scale,
            atomClass: TexMathAtomClass.rel,
            span: node.span,
          );
          final double w = arrow.widthEm;
          final List<VBoxChild> parts = <VBoxChild>[VBoxChild(box: arrow)];
          double topY = arrow.heightEm;
          double botY = arrow.depthEm;
          final MathBox? over = data.labelA;
          if (over != null) {
            final double oy = math.max(
              topShiftMin,
              arrow.heightEm + gapAbove + over.depthEm,
            );
            parts.add(
              VBoxChild(box: over, xEm: (w - over.widthEm) / 2.0, yEm: oy),
            );
            topY = math.max(topY, oy + over.heightEm);
          }
          final MathBox? under = data.labelB;
          if (under != null) {
            final double uy = -math.max(
              botShiftMin,
              arrow.depthEm + gapBelow + under.heightEm,
            );
            parts.add(
              VBoxChild(box: under, xEm: (w - under.widthEm) / 2.0, yEm: uy),
            );
            botY = math.max(botY, -uy + under.depthEm);
          }
          laidCells[r][c] = VBox.positioned(
            children: parts,
            widthEm: w,
            heightEm: topY,
            depthEm: botY,
            atomClass: TexMathAtomClass.rel,
            span: node.span,
          );
        } else {
          final double labelH = math.max(
            data.labelA?.totalHeightEm ?? 0.0,
            data.labelB?.totalHeightEm ?? 0.0,
          );
          final double spanTarget = math.max(
            minVertArrowEm,
            labelH + 0.4 * scale,
          );
          final MathBox arrow = buildVerticalDelimiterBox(
            font: font,
            mathTable: mathTable,
            delimiter: String.fromCharCode(data.codePoint),
            targetSpanEm: spanTarget,
            atomClass: TexMathAtomClass.rel,
            scale: scale,
            span: node.span,
          );
          final double labelGap = 0.18 * scale;
          final double aw = arrow.widthEm;
          final List<VBoxChild> parts = <VBoxChild>[
            VBoxChild(box: arrow, xEm: 0.0, yEm: 0.0),
          ];
          final double arrowMidY = (arrow.heightEm - arrow.depthEm) / 2.0;
          final MathBox? leftLbl = data.labelA;
          if (leftLbl != null) {
            final double ly =
                arrowMidY - (leftLbl.heightEm - leftLbl.depthEm) / 2.0;
            parts.add(
              VBoxChild(
                box: leftLbl,
                xEm: -labelGap - leftLbl.widthEm,
                yEm: ly,
              ),
            );
          }
          final MathBox? rightLbl = data.labelB;
          if (rightLbl != null) {
            final double ry =
                arrowMidY - (rightLbl.heightEm - rightLbl.depthEm) / 2.0;
            parts.add(VBoxChild(box: rightLbl, xEm: aw + labelGap, yEm: ry));
          }
          laidCells[r][c] = VBox.positioned(
            children: parts,
            widthEm: aw,
            heightEm: arrow.heightEm,
            depthEm: arrow.depthEm,
            atomClass: TexMathAtomClass.rel,
            span: node.span,
          );
        }
      }
      final MathBox box = laidCells[r][c];
      if (box.heightEm > maxH) {
        maxH = box.heightEm;
      }
      if (box.depthEm > maxD) {
        maxD = box.depthEm;
      }
    }
    rowHeights[r] = maxH;
    rowDepths[r] = maxD;
  }

  // Compute left/right horizontal overhang for vertical arrow labels at edges.
  double leftPad = 0.0;
  double rightPad = 0.0;
  for (int r = 0; r < rowCount; r++) {
    for (int c = 0; c < colCount; c++) {
      final _CdCellData? data = parsedCells[r][c];
      if (data == null || !data.isVertical) {
        continue;
      }
      final double arrowW = laidCells[r][c].widthEm;
      if (c == 0 && data.labelA != null) {
        final double need =
            data.labelA!.widthEm + 0.18 * scale - (colWidths[0] - arrowW) / 2.0;
        if (need > leftPad) {
          leftPad = need;
        }
      }
      if (c == colCount - 1 && data.labelB != null) {
        final double need =
            data.labelB!.widthEm + 0.18 * scale - (colWidths[c] - arrowW) / 2.0;
        if (need > rightPad) {
          rightPad = need;
        }
      }
    }
  }

  final List<double> colX = List<double>.filled(colCount, 0.0);
  double cursorX = leftPad;
  for (int c = 0; c < colCount; c++) {
    if (c > 0) {
      cursorX += hGapEm;
    }
    colX[c] = cursorX;
    cursorX += colWidths[c];
  }
  final double totalW = cursorX + rightPad;

  double cursorTop = 0.0;
  final List<double> rowBaselinesTopDown = List<double>.filled(rowCount, 0.0);
  for (int r = 0; r < rowCount; r++) {
    if (r > 0) {
      cursorTop -= vGapEm;
    }
    cursorTop -= rowHeights[r];
    rowBaselinesTopDown[r] = cursorTop;
    cursorTop -= rowDepths[r];
  }
  final double totalSpan = -cursorTop;
  final double shiftY = rowCount == 0 ? 0.0 : axisEm + totalSpan / 2.0;

  final List<VBoxChild> placed = <VBoxChild>[];
  for (int r = 0; r < rowCount; r++) {
    final double rowY = rowBaselinesTopDown[r] + shiftY;
    for (int c = 0; c < colCount; c++) {
      final MathBox box = laidCells[r][c];
      if (box is KernBox && box.widthEm == 0.0) {
        continue;
      }
      final double dx = (colWidths[c] - box.widthEm) / 2.0;
      placed.add(VBoxChild(box: box, xEm: colX[c] + dx, yEm: rowY));
    }
  }

  return VBox.positioned(
    children: placed,
    widthEm: totalW,
    heightEm: rowCount == 0 ? 0.0 : math.max(0.0, shiftY),
    depthEm: rowCount == 0 ? 0.0 : math.max(0.0, totalSpan - shiftY),
    atomClass: TexMathAtomClass.ord,
    span: node.span,
  );
}

class _CdCellData {
  const _CdCellData({
    required this.codePoint,
    required this.isVertical,
    this.labelA,
    this.labelB,
  });

  final int codePoint;
  final bool isVertical;
  final MathBox? labelA;
  final MathBox? labelB;
}

/// Lays out a top-level `bussproofs` `prooftree` [MathGroupNode] or a stack of
/// proof trees horizontally side by side.
MathBox layoutProoftreeGroup({
  required MathGroupNode node,
  required MathFont font,
  required MathTableData mathTable,
  required TexMathStyle currentStyle,
  required MatrixCellLayouter layoutCell,
  double fontScale = 1.0,
}) {
  if (node.role == 'prooftree_rule') {
    return layoutProoftreeElement(
      node,
      font: font,
      mathTable: mathTable,
      currentStyle: currentStyle,
      layoutCell: layoutCell,
      fontScale: fontScale,
    );
  }
  final MathConstants constants = mathTable.constants;
  final double upem = font.unitsPerEm.toDouble();
  final double scale = scaleForStyle(currentStyle, constants) * fontScale;
  final double axisEm = (constants.axisHeight / upem) * scale;
  if (node.children.isEmpty) {
    return KernBox(widthEm: 0.0, span: node.span);
  }
  final MathBox combined;
  if (node.children.length == 1) {
    combined = layoutProoftreeElement(
      node.children.first,
      font: font,
      mathTable: mathTable,
      currentStyle: currentStyle,
      layoutCell: layoutCell,
      fontScale: fontScale,
    );
  } else {
    final List<MathBox> items = <MathBox>[];
    for (int i = 0; i < node.children.length; i++) {
      if (i > 0) {
        items.add(KernBox(widthEm: 1.0 * scale));
      }
      items.add(
        layoutProoftreeElement(
          node.children[i],
          font: font,
          mathTable: mathTable,
          currentStyle: currentStyle,
          layoutCell: layoutCell,
          fontScale: fontScale,
        ),
      );
    }
    combined = HBox(
      children: items,
      atomClass: TexMathAtomClass.ord,
      span: node.span,
    );
  }
  final double shiftY = axisEm - (combined.heightEm - combined.depthEm) / 2.0;
  return VBox.positioned(
    children: <VBoxChild>[VBoxChild(box: combined, xEm: 0.0, yEm: shiftY)],
    widthEm: combined.widthEm,
    atomClass: TexMathAtomClass.ord,
    span: node.span,
  );
}

/// Lays out a single node inside a `bussproofs` derivation tree recursively.
MathBox layoutProoftreeElement(
  MathNode node, {
  required MathFont font,
  required MathTableData mathTable,
  required TexMathStyle currentStyle,
  required MatrixCellLayouter layoutCell,
  double fontScale = 1.0,
}) {
  final MathConstants constants = mathTable.constants;
  final double upem = font.unitsPerEm.toDouble();
  final double scale = scaleForStyle(currentStyle, constants) * fontScale;
  final double ruleThicknessEm =
      (constants.fractionRuleThickness / upem) * scale;

  MathNode? leftLabelNode;
  MathNode? rightLabelNode;
  MatrixNode? ruleMatrix;

  if (node is MathGroupNode && node.role == 'prooftree_rule') {
    int matrixIdx = -1;
    for (int i = 0; i < node.children.length; i++) {
      final MathNode child = node.children[i];
      if (child is MatrixNode && child.environment == 'prooftree') {
        ruleMatrix = child;
        matrixIdx = i;
        break;
      }
    }
    if (matrixIdx > 0) {
      leftLabelNode = node.children.first;
    }
    if (matrixIdx >= 0 && matrixIdx + 1 < node.children.length) {
      rightLabelNode = node.children.last;
    }
  } else if (node is MatrixNode && node.environment == 'prooftree') {
    ruleMatrix = node;
  }

  if (ruleMatrix == null) {
    return layoutCell(node, style: currentStyle);
  }

  final List<MathNode> topNodes = ruleMatrix.rows.isNotEmpty
      ? ruleMatrix.rows[0]
      : const <MathNode>[];
  final List<MathNode> bottomNodes = ruleMatrix.rows.length > 1
      ? ruleMatrix.rows[1]
      : const <MathNode>[];

  MathBox buildRowBox(List<MathNode> items) {
    if (items.isEmpty) {
      return KernBox(widthEm: 0.0, span: node.span);
    }
    if (items.length == 1) {
      return layoutProoftreeElement(
        items.first,
        font: font,
        mathTable: mathTable,
        currentStyle: currentStyle,
        layoutCell: layoutCell,
        fontScale: fontScale,
      );
    }
    final List<MathBox> rowChildren = <MathBox>[];
    final double premiseGap = 1.4 * scale;
    for (int i = 0; i < items.length; i++) {
      if (i > 0) {
        rowChildren.add(KernBox(widthEm: premiseGap));
      }
      rowChildren.add(
        layoutProoftreeElement(
          items[i],
          font: font,
          mathTable: mathTable,
          currentStyle: currentStyle,
          layoutCell: layoutCell,
          fontScale: fontScale,
        ),
      );
    }
    return HBox(children: rowChildren, span: node.span);
  }

  final MathBox topBox = buildRowBox(topNodes);
  final MathBox bottomBox = buildRowBox(bottomNodes);
  final String lineStyle = ruleMatrix.rowLines[1] ?? 'solid';
  final double ruleWidthEm =
      math.max(topBox.widthEm, bottomBox.widthEm) + 0.30 * scale;
  final MathBox ruleBox = _buildProoftreeRuleBox(
    styleName: lineStyle,
    widthEm: ruleWidthEm,
    thicknessEm: ruleThicknessEm,
    scale: scale,
    span: node.span,
  );

  final MathBox? leftLabelBox = leftLabelNode == null
      ? null
      : layoutCell(leftLabelNode, style: currentStyle);
  final MathBox? rightLabelBox = rightLabelNode == null
      ? null
      : layoutCell(rightLabelNode, style: currentStyle);

  final double vPad = 0.22 * scale;
  final double labelGap = 0.25 * scale;
  final double centerXCore = ruleWidthEm / 2.0;
  final double leftExtend = leftLabelBox != null
      ? math.max(
          0.0,
          leftLabelBox.widthEm + labelGap - (centerXCore - ruleWidthEm / 2.0),
        )
      : 0.0;
  final double rightExtend = rightLabelBox != null
      ? math.max(
          0.0,
          rightLabelBox.widthEm + labelGap - (centerXCore - ruleWidthEm / 2.0),
        )
      : 0.0;

  final double originShiftX = leftExtend;
  final double ruleLeftX = originShiftX;
  final double totalW = originShiftX + ruleWidthEm + rightExtend;

  final double bottomBaselineY = 0.0;
  final double ruleBottomY = bottomBox.heightEm + vPad;
  final double ruleTopY = ruleBottomY + ruleBox.totalHeightEm;
  final double topBaselineY = ruleTopY + vPad + topBox.depthEm;
  final double ruleCenterY = (ruleBottomY + ruleTopY) / 2.0;

  final List<VBoxChild> placed = <VBoxChild>[
    VBoxChild(
      box: topBox,
      xEm: originShiftX + (ruleWidthEm - topBox.widthEm) / 2.0,
      yEm: topBaselineY,
    ),
    VBoxChild(box: ruleBox, xEm: ruleLeftX, yEm: ruleBottomY + ruleBox.depthEm),
    VBoxChild(
      box: bottomBox,
      xEm: originShiftX + (ruleWidthEm - bottomBox.widthEm) / 2.0,
      yEm: bottomBaselineY,
    ),
  ];

  double totalHeight = topBaselineY + topBox.heightEm;
  double totalDepth = bottomBox.depthEm;

  if (leftLabelBox != null) {
    final double ly =
        ruleCenterY - (leftLabelBox.heightEm - leftLabelBox.depthEm) / 2.0;
    placed.add(
      VBoxChild(
        box: leftLabelBox,
        xEm: ruleLeftX - labelGap - leftLabelBox.widthEm,
        yEm: ly,
      ),
    );
    totalHeight = math.max(totalHeight, ly + leftLabelBox.heightEm);
    totalDepth = math.max(totalDepth, -ly + leftLabelBox.depthEm);
  }

  if (rightLabelBox != null) {
    final double ry =
        ruleCenterY - (rightLabelBox.heightEm - rightLabelBox.depthEm) / 2.0;
    placed.add(
      VBoxChild(
        box: rightLabelBox,
        xEm: ruleLeftX + ruleWidthEm + labelGap,
        yEm: ry,
      ),
    );
    totalHeight = math.max(totalHeight, ry + rightLabelBox.heightEm);
    totalDepth = math.max(totalDepth, -ry + rightLabelBox.depthEm);
  }

  return VBox.positioned(
    children: placed,
    widthEm: totalW,
    heightEm: totalHeight,
    depthEm: totalDepth,
    atomClass: TexMathAtomClass.ord,
    span: node.span,
  );
}

MathBox _buildProoftreeRuleBox({
  required String styleName,
  required double widthEm,
  required double thicknessEm,
  required double scale,
  SourceSpan? span,
}) {
  switch (styleName) {
    case 'none':
      return KernBox(widthEm: widthEm, heightEm: thicknessEm, span: span);
    case 'double':
      final double gap = 2.0 * thicknessEm;
      final RuleBox bar = RuleBox(
        widthEm: widthEm,
        heightEm: thicknessEm,
        span: span,
      );
      return VBox.positioned(
        children: <VBoxChild>[
          VBoxChild(box: bar, xEm: 0.0, yEm: 0.0),
          VBoxChild(box: bar, xEm: 0.0, yEm: thicknessEm + gap),
        ],
        widthEm: widthEm,
        heightEm: 2.0 * thicknessEm + gap,
        depthEm: 0.0,
        span: span,
      );
    case 'dashed':
      final double targetDash = 0.22 * scale;
      final double targetGap = 0.14 * scale;
      final int count = math.max(
        2,
        ((widthEm + targetGap) / (targetDash + targetGap)).round(),
      );
      final double gap = count > 1
          ? math.min(targetGap, widthEm / (count * 2.5))
          : 0.0;
      final double dashW = math.max(
        thicknessEm,
        (widthEm - gap * (count - 1)) / count,
      );
      final List<MathBox> dashes = <MathBox>[];
      for (int i = 0; i < count; i++) {
        if (i > 0) {
          dashes.add(KernBox(widthEm: gap));
        }
        dashes.add(RuleBox(widthEm: dashW, heightEm: thicknessEm, span: span));
      }
      return HBox(children: dashes, span: span);
    case 'solid':
    default:
      return RuleBox(widthEm: widthEm, heightEm: thicknessEm, span: span);
  }
}
