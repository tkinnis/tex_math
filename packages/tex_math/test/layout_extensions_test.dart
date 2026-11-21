import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  late MathFont bundledFont;
  late TexMathEngine engine;

  setUpAll(() {
    final File fontFile = _locateBundledFont();
    bundledFont = MathFont.fromBytes(fontFile.readAsBytesSync());
    engine = TexMathEngine(font: bundledFont);
  });

  group('Tier 2 extension layout', () {
    test('lays out amscd commutative diagrams with stretched arrows', () {
      final TexMathOptions opts = _allOpts();
      final RenderResult result = engine.render(
        r'\begin{CD} A @>f>> B \\ @VVgV @VVhV \\ C @= D \end{CD}',
        options: opts,
      );
      final DisplayList dl = result.displayList;
      expect(dl.metrics.widthEm, greaterThan(4.0));
      expect(dl.metrics.heightEm, greaterThan(1.5));
      expect(dl.metrics.depthEm, greaterThan(1.0));
      final String svg = result.toSvg();
      expect(svg, contains('<path d='));
      expect(svg, isNot(contains('<text')));
    });

    test('lays out bbox padding, background fill, and border rules', () {
      final RenderResult result = engine.render(
        r'\bbox[5px,border:2px solid red,yellow]{x+1}',
        options: _allOpts(),
      );
      final DisplayList dl = result.displayList;
      final List<RuleItem> rules = dl.items.whereType<RuleItem>().toList();
      expect(rules.length, 2);
      expect(rules[0].strokeWidthEm, isNull);
      expect(rules[0].customColor, 0xFFFFFF00);
      expect(rules[1].strokeWidthEm, closeTo(2.0 / 16.0, 1e-6));
      expect(rules[1].customColor, 0xFFFF0000);
      expect(dl.metrics.widthEm, greaterThan(1.5));
    });

    test(
      'lays out bussproofs proof trees with solid, dashed, double rules',
      () {
        final RenderResult solid = engine.render(
          r'\begin{prooftree}'
          r'\AxiomC{$A$} \AxiomC{$B$}'
          r'\RightLabel{$\land I$}'
          r'\BinaryInfC{$A \land B$}'
          r'\end{prooftree}',
          options: _allOpts(),
        );
        expect(solid.displayList.items.whereType<RuleItem>(), hasLength(1));
        expect(solid.displayList.metrics.widthEm, greaterThan(2.5));

        final RenderResult dashed = engine.render(
          r'\begin{prooftree}'
          r'\AxiomC{$P$}'
          r'\dashedLine'
          r'\UnaryInfC{$Q$}'
          r'\end{prooftree}',
          options: _allOpts(),
        );
        expect(
          dashed.displayList.items.whereType<RuleItem>().length,
          greaterThanOrEqualTo(2),
        );

        final RenderResult doubleRule = engine.render(
          r'\begin{prooftree}'
          r'\AxiomC{$X$}'
          r'\doubleLine'
          r'\UnaryInfC{$Y$}'
          r'\end{prooftree}',
          options: _allOpts(),
        );
        expect(
          doubleRule.displayList.items.whereType<RuleItem>(),
          hasLength(2),
        );
      },
    );

    test('lays out cancel, bcancel, xcancel, and cancelto strokes', () {
      for (final String tex in <String>[
        r'\cancel{x+y}',
        r'\bcancel{a}',
        r'\xcancel{b}',
        r'\cancelto{0}{x+1}',
      ]) {
        final RenderResult result = engine.render(tex, options: _allOpts());
        final List<GlyphItem> strokePaths = result.displayList.items
            .whereType<GlyphItem>()
            .where((GlyphItem g) => g.glyphId == 0 && g.outline != null)
            .toList();
        expect(strokePaths, isNotEmpty, reason: 'Expected stroke path in $tex');
        final String svg = result.toSvg();
        expect(svg, contains('<path d='));
        expect(svg, isNot(contains('<text')));
      }
    });

    test('lays out enclose box, roundedbox, circle, strike, and longdiv', () {
      for (final String notation in <String>[
        'box',
        'roundedbox',
        'circle',
        'updiagonalstrike',
        'downdiagonalstrike',
        'updiagonalarrow',
        'horizontalstrike',
        'verticalstrike',
        'actuarial',
        'madruwb',
        'phasorangle',
        'longdiv',
        'radical',
      ]) {
        final RenderResult result = engine.render(
          '\\enclose{$notation}{x+1}',
          options: _allOpts(),
        );
        final String svg = result.toSvg();
        expect(result.displayList.items, isNotEmpty, reason: notation);
        expect(svg, isNot(contains('<text')), reason: notation);
        expect(svg, isNot(contains('NaN')), reason: notation);
      }
    });

    test('lays out cases, numcases, subnumcases, and empheq', () {
      final RenderResult numcases = engine.render(
        r'\begin{numcases}{|x|=} x & for $x \ge 0$ \\ -x & for $x < 0$ \end{numcases}',
        options: _allOpts(),
      );
      expect(numcases.displayList.metrics.widthEm, greaterThan(5.0));

      final RenderResult subnumcases = engine.render(
        r'\begin{subnumcases}{f(x)=} 1 & if $x>0$ \\ 0 & otherwise \end{subnumcases}',
        options: _allOpts(),
      );
      expect(subnumcases.displayList.metrics.widthEm, greaterThan(5.0));

      final RenderResult empheq = engine.render(
        r'\begin{empheq}[left=\empheqlbrace]{align} x &= 1 \\ y &= 2 \end{empheq}',
        options: _allOpts(),
      );
      expect(empheq.displayList.metrics.heightEm, greaterThan(1.0));
      expect(empheq.toSvg(), isNot(contains('<text')));
    });

    test('lays out centernot, extpfeil, colortbl, and colorbox/fcolorbox', () {
      final RenderResult cnot = engine.render(
        r'A \centernot\implies B + \centernot\longrightarrow C',
        options: _allOpts(),
      );
      final List<GlyphItem> slashItems = cnot.displayList.items
          .whereType<GlyphItem>()
          .where((GlyphItem g) => g.codePoint == 0x29F8)
          .toList();
      expect(slashItems.length, 2);

      final RenderResult arrow = engine.render(
        r'A \xrightarrow[below]{above} B \xmapsto{map} C \xlongequal{=} D',
        options: _allOpts(),
      );
      expect(arrow.displayList.metrics.widthEm, greaterThan(4.0));

      final RenderResult table = engine.render(
        r'\begin{array}{|c|c|} \hline \rowcolor{cyan} a & b \\ \hline c & \cellcolor{yellow} d \\ \hline \end{array}',
        options: _allOpts(),
      );
      final List<RuleItem> coloredCells = table.displayList.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.customColor != null)
          .toList();
      expect(coloredCells.length, greaterThanOrEqualTo(3));

      final RenderResult colorbox = engine.render(
        r'\colorbox{yellow}{x} + \fcolorbox{blue}{white}{y}',
        options: _allOpts(),
      );
      expect(
        colorbox.displayList.items.whereType<RuleItem>().length,
        greaterThanOrEqualTo(3),
      );
    });

    test('lays out mathtools dcases, rcases, matrix*, brackets, mathclap, '
        'prescript, and bevelled fractions', () {
      final RenderResult dcases = engine.render(
        r'\begin{dcases} \frac{a}{b} & x>0 \\ 0 & x\le 0 \end{dcases} + \begin{rcases} u \\ v \end{rcases}',
        options: _allOpts(),
      );
      expect(dcases.displayList.metrics.widthEm, greaterThan(5.0));

      final RenderResult matStar = engine.render(
        r'\begin{pmatrix*}[r] -1 & 2 \\ 3 & -4 \end{pmatrix*}',
        options: _allOpts(),
      );
      expect(matStar.displayList.metrics.heightEm, greaterThan(1.0));

      final RenderResult underOver = engine.render(
        r'\underbracket{a+b}_{k} + \overbracket{c+d}^{m} + \sum_{\mathclap{i=1}}^{n} x_i',
        options: _allOpts(),
      );
      expect(underOver.displayList.metrics.widthEm, greaterThan(4.0));

      final RenderResult prescript = engine.render(
        r'\prescript{14}{6}{C}^{*}_{+}',
        options: _allOpts(),
      );
      final List<GlyphItem> preGlyphs = prescript.displayList.items
          .whereType<GlyphItem>()
          .toList();
      expect(preGlyphs.length, 6);
      // Prescripts appear before the base C horizontally.
      expect(preGlyphs[0].xEm, lessThan(preGlyphs[3].xEm));
      expect(preGlyphs[2].xEm, lessThan(preGlyphs[3].xEm));
      // Base C appears before trailing subscripts/superscripts.
      expect(preGlyphs[3].xEm, lessThan(preGlyphs[4].xEm));

      // Skewed / bevelled fraction laid out from OpenType MATH constants.
      const SourceSpan span = SourceSpan(0, 1);
      final MathNode bevelledAst = const MathRootNode(
        span: span,
        children: <MathNode>[
          FractionNode(
            span: span,
            numerator: SymbolNode(span: span, value: '1'),
            denominator: SymbolNode(span: span, value: '2'),
            isBevelled: true,
          ),
        ],
      );
      final DisplayList bevelledDl = engine.layout(bevelledAst);
      final List<GlyphItem> bGlyphs = bevelledDl.items
          .whereType<GlyphItem>()
          .toList();
      expect(bGlyphs.length, 3);
      expect(bGlyphs[0].yEm, greaterThan(0.2));
      expect(bGlyphs[2].yEm, lessThan(-0.1));
      expect(bGlyphs[0].xEm, lessThan(bGlyphs[1].xEm));
      expect(bGlyphs[1].xEm, lessThan(bGlyphs[2].xEm));
    });

    test('lays out mhchem, action, html, texhtml, and ErrorNode fallback', () {
      final RenderResult chem = engine.render(
        r'\ce{2H2 + O2 -> 2H2O} + \pu{9.8 m/s^2}',
        options: _allOpts(),
      );
      expect(chem.toSvg(), isNot(contains('<text')));

      final RenderResult htmlAction = engine.render(
        r'\href{https://example.com}{x} + \cssId{eq:target}{y} + \mathtip{z}{tip} + \toggle{a}{b}\endtoggle',
        options: _allOpts(),
      );
      final List<AnchorItem> anchors = htmlAction.displayList.items
          .whereType<AnchorItem>()
          .toList();
      expect(anchors.length, greaterThanOrEqualTo(4));

      final RenderResult texhtml = engine.render(
        r'<tex-html><span>hi</span></tex-html>',
        options: _allOpts(),
      );
      expect(texhtml.displayList.items.whereType<GlyphItem>(), isNotEmpty);

      // Direct ErrorNode layout (`noerrors` / `noundefined` fallback).
      const SourceSpan s = SourceSpan(0, 9);
      const MathNode errTree = MathRootNode(
        span: s,
        children: <MathNode>[
          ErrorNode(
            span: s,
            error: TexMathSyntaxError('Unknown command'),
            rawSource: r'\boguscmd',
          ),
        ],
      );
      final DisplayList errDl = engine.layout(errTree);
      final List<GlyphItem> errGlyphs = errDl.items
          .whereType<GlyphItem>()
          .toList();
      expect(errGlyphs, isNotEmpty);
      for (final GlyphItem g in errGlyphs) {
        expect(g.colorRole, TexMathColorRole.error);
      }
    });
  });

  group('Tier 3 extension layout', () {
    test('lays out physics, units, bbm, bboldx, dsfont, and fontsizev3', () {
      final RenderResult phys = engine.render(
        r'\dv{f}{x} + \pdv[2]{g}{x}{y} + \mqty(a & b \\ c & d) + \bra{\psi}\ket{\phi}',
        options: _allOpts(),
      );
      expect(phys.displayList.metrics.widthEm, greaterThan(10.0));
      expect(phys.toSvg(), isNot(contains('<text')));

      final RenderResult unit = engine.render(
        r'\unit[5]{m/s} + \nicefrac{1}{2} + \unitfrac[3]{kg}{m^3}',
        options: _allOpts(),
      );
      expect(unit.displayList.items.whereType<GlyphItem>(), isNotEmpty);
      expect(unit.toSvg(), isNot(contains('<text')));

      final RenderResult bb = engine.render(
        r'\mathbbm{1} + \mathds{R} + \mathds{C}',
        options: _allOpts(),
      );
      expect(bb.toSvg(), isNot(contains('<text')));

      final RenderResult tinyRes = engine.render(
        r'\tiny x',
        options: _allOpts(),
      );
      final RenderResult hugeRes = engine.render(
        r'\huge x',
        options: _allOpts(),
      );
      final GlyphItem tinyGlyph = tinyRes.displayList.items
          .whereType<GlyphItem>()
          .first;
      final GlyphItem hugeGlyph = hugeRes.displayList.items
          .whereType<GlyphItem>()
          .first;
      expect(hugeGlyph.scaleX, greaterThan(tinyGlyph.scaleX * 2.0));
      expect(
        hugeRes.displayList.metrics.widthEm,
        greaterThan(tinyRes.displayList.metrics.widthEm * 2.0),
      );
    });
  });

  group('Top-level DisplayBreakHint metadata', () {
    test('emits breakHints at top-level Bin and Rel operators only', () {
      final DisplayList dl = engine.render('a + b = c - d').displayList;
      expect(dl.breakHints, hasLength(3));
      expect(dl.breakHints[0].kind, MathBreakKind.afterBinary);
      expect(dl.breakHints[0].penalty, 700);
      expect(dl.breakHints[1].kind, MathBreakKind.afterRelation);
      expect(dl.breakHints[1].penalty, 500);
      expect(dl.breakHints[2].kind, MathBreakKind.afterBinary);

      // Strict horizontal monotonicity and valid afterItemIndex alignment.
      for (int i = 0; i < dl.breakHints.length; i++) {
        final DisplayBreakHint hint = dl.breakHints[i];
        final GlyphItem opGlyph = dl.items[hint.afterItemIndex] as GlyphItem;
        expect(hint.xEm, closeTo(opGlyph.xEm + opGlyph.advanceEm, 1e-9));
        if (i > 0) {
          expect(hint.xEm, greaterThan(dl.breakHints[i - 1].xEm));
        }
      }
    });

    test('suppresses breakHints on unary operators and nested subtrees', () {
      final DisplayList unary = engine.render('-a').displayList;
      expect(unary.breakHints, isEmpty);

      final DisplayList nested = engine
          .render(r'\frac{a+b}{c=d} + \sqrt{x-y} + \left(m+n\right) + x^{p+q}')
          .displayList;
      expect(
        nested.breakHints.where(
          (DisplayBreakHint h) => h.kind == MathBreakKind.afterBinary,
        ),
        hasLength(3),
      );
      expect(
        nested.breakHints.where(
          (DisplayBreakHint h) => h.kind == MathBreakKind.afterRelation,
        ),
        isEmpty,
      );

      final DisplayList explicitGroup = engine.render('{a + b}').displayList;
      expect(explicitGroup.breakHints, isEmpty);
    });

    test('emits explicit breakHint for top-level double backslash', () {
      final DisplayList dl = engine.render(r'a \\ b').displayList;
      expect(dl.breakHints, hasLength(1));
      expect(dl.breakHints.first.kind, MathBreakKind.explicit);
      expect(dl.breakHints.first.breakPoint.isExplicit, isTrue);
      expect(dl.breakHints.first.breakPoint.isGood, isTrue);
    });
  });

  group('Full 352-case corpus layout and SVG integrity', () {
    test('all 315 accepted corpus items lay out cleanly into valid SVG and '
        'all 37 error fixtures match oracleErrorClass', () {
      final Map<String, Object?> doc = jsonDecode(
        _expectationsFile().readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> cases = doc['cases']! as Map<String, Object?>;
      expect(cases.length, 352);

      int acceptedCount = 0;
      int errorCount = 0;

      for (final MapEntry<String, Object?> entry in cases.entries) {
        final String id = entry.key;
        final Map<String, Object?> spec = entry.value! as Map<String, Object?>;
        final String raw = _resolveRepoFile(spec['path']! as String)
            .readAsStringSync();
        final String tex = _stripCorpusComments(raw);
        final bool isDisplay = spec['display']! as bool;
        final List<String> packages =
            (spec['packages'] as List<Object?>?)?.cast<String>() ??
            TexMathOptions.defaultPackages;
        final bool oracleAccepted = spec['oracleAccepted']! as bool;
        final String? expectedErrorClass = spec['oracleErrorClass'] as String?;

        final TexMathOptions opts = TexMathOptions(
          displayMode: isDisplay
              ? TexMathDisplayMode.display
              : TexMathDisplayMode.inline,
          packages: packages,
        );

        if (oracleAccepted) {
          acceptedCount++;
          final RenderResult result = engine.render(tex, options: opts);
          final DisplayList dl = result.displayList;
          expect(dl.metrics.widthEm.isFinite, isTrue, reason: id);
          expect(dl.metrics.heightEm.isFinite, isTrue, reason: id);
          expect(dl.metrics.depthEm.isFinite, isTrue, reason: id);

          final String svg = result.toSvg();
          expect(svg.startsWith('<svg '), isTrue, reason: id);
          expect(svg.endsWith('</svg>'), isTrue, reason: id);
          expect(svg, isNot(contains('<text')), reason: id);
          expect(svg, isNot(contains('NaN')), reason: id);
          expect(svg, isNot(contains('Infinity')), reason: id);
        } else {
          errorCount++;
          Object? caught;
          try {
            engine.render(tex, options: opts);
          } on TexMathError catch (err) {
            caught = err;
            if (expectedErrorClass != null) {
              expect(err.errorClass.name, expectedErrorClass, reason: id);
            }
          }
          expect(caught, isA<TexMathError>(), reason: id);
        }
      }

      expect(acceptedCount, 315);
      expect(errorCount, 37);
    });
  });

  group('Color models, colortbl bounds, framed boxes, and corpus geometry', () {
    test(
      'renders [RGB], [rgb], [HTML], and [gray] into expected ARGB and SVG',
      () {
        final RenderResult rgbUpper = engine.render(
          r'\textcolor[RGB]{220,20,60}{\alpha}',
          options: _allOpts(),
        );
        final List<GlyphItem> upperGlyphs = rgbUpper.displayList.items
            .whereType<GlyphItem>()
            .toList();
        expect(upperGlyphs, isNotEmpty);
        for (final GlyphItem g in upperGlyphs) {
          expect(g.colorRole, TexMathColorRole.custom);
          expect(g.customColor, 0xFFDC143C);
        }
        expect(rgbUpper.toSvg(), contains('fill="#DC143C"'));

        final RenderResult mixedModels = engine.render(
          r'\textcolor[rgb]{1,0,0.5}{x}'
          r' + \textcolor[HTML]{1e40af}{y}'
          r' + \textcolor[gray]{0.5}{z}'
          r' + \colorbox[RGB]{220,20,60}{w}',
          options: _allOpts(),
        );
        final List<GlyphItem> modelGlyphs = mixedModels.displayList.items
            .whereType<GlyphItem>()
            .toList();
        expect(
          modelGlyphs.where((GlyphItem g) => g.customColor == 0xFFFF0080),
          isNotEmpty,
        );
        expect(
          modelGlyphs.where((GlyphItem g) => g.customColor == 0xFF1E40AF),
          isNotEmpty,
        );
        expect(
          modelGlyphs.where((GlyphItem g) => g.customColor == 0xFF808080),
          isNotEmpty,
        );
        final List<RuleItem> bgRules = mixedModels.displayList.items
            .whereType<RuleItem>()
            .where((RuleItem r) => r.customColor == 0xFFDC143C)
            .toList();
        expect(bgRules, hasLength(1));

        final String mixedSvg = mixedModels.toSvg();
        expect(mixedSvg, contains('fill="#FF0080"'));
        expect(mixedSvg, contains('fill="#1E40AF"'));
        expect(mixedSvg, contains('fill="#808080"'));
        expect(mixedSvg, contains('fill="#DC143C"'));
      },
    );

    test('keeps colortbl row/cell backgrounds bounded inside grid rules', () {
      void assertColortblBounded(
        String tex, {
        required bool expectTopHline,
        required bool expectBottomHline,
      }) {
        final DisplayList dl = engine
            .render(tex, options: _allOpts())
            .displayList;
        final List<RuleItem> allRules = dl.items.whereType<RuleItem>().toList();
        final List<RuleItem> bgRects = allRules
            .where(
              (RuleItem r) => r.customColor != null && r.strokeWidthEm == null,
            )
            .toList();
        final List<RuleItem> hRules =
            allRules
                .where(
                  (RuleItem r) =>
                      r.customColor == null &&
                      r.strokeWidthEm == null &&
                      r.widthEm > r.heightEm,
                )
                .toList()
              ..sort((RuleItem a, RuleItem b) => b.yEm.compareTo(a.yEm));
        final List<RuleItem> vRules =
            allRules
                .where(
                  (RuleItem r) =>
                      r.customColor == null &&
                      r.strokeWidthEm == null &&
                      r.heightEm > r.widthEm,
                )
                .toList()
              ..sort((RuleItem a, RuleItem b) => a.xEm.compareTo(b.xEm));

        expect(bgRects, isNotEmpty);
        expect(vRules, hasLength(3));
        final double gridMinX = vRules.first.xEm + vRules.first.widthEm;
        final double gridMaxX = vRules.last.xEm;
        final double vTopY = vRules.first.yEm + vRules.first.heightEm;
        final double vBottomY = vRules.first.yEm;
        final double bgMaxAllowedY = expectTopHline ? hRules.first.yEm : vTopY;
        final double bgMinAllowedY = expectBottomHline
            ? hRules.last.yEm + hRules.last.heightEm
            : vBottomY;

        for (final RuleItem bg in bgRects) {
          expect(bg.xEm, greaterThanOrEqualTo(gridMinX - 1e-9));
          expect(bg.xEm + bg.widthEm, lessThanOrEqualTo(gridMaxX + 1e-9));
          expect(bg.yEm, greaterThanOrEqualTo(bgMinAllowedY - 1e-9));
          expect(bg.yEm + bg.heightEm, lessThanOrEqualTo(bgMaxAllowedY + 1e-9));
          expect(bg.yEm, greaterThanOrEqualTo(vBottomY - 1e-9));
          expect(bg.yEm + bg.heightEm, lessThanOrEqualTo(vTopY + 1e-9));
        }

        if (!expectTopHline) {
          final RuleItem topRowBg = bgRects.reduce(
            (RuleItem a, RuleItem b) =>
                (a.yEm + a.heightEm) >= (b.yEm + b.heightEm) ? a : b,
          );
          expect(topRowBg.yEm + topRowBg.heightEm, closeTo(vTopY, 1e-9));
        }
        if (!expectBottomHline) {
          final RuleItem botRowBg = bgRects.reduce(
            (RuleItem a, RuleItem b) => a.yEm <= b.yEm ? a : b,
          );
          expect(botRowBg.yEm, closeTo(vBottomY, 1e-9));
        }
      }

      // Full outer \hline grid.
      assertColortblBounded(
        r'\begin{array}{|c|c|} \hline \rowcolor{cyan} a & b \\ \hline c & \cellcolor{yellow} d \\ \hline \end{array}',
        expectTopHline: true,
        expectBottomHline: true,
      );
      // Outer \hline omitted (row backgrounds must clamp to vertical rules).
      assertColortblBounded(
        r'\begin{array}{|c|c|} \rowcolor{cyan} a & b \\ c & \cellcolor{yellow} d \end{array}',
        expectTopHline: false,
        expectBottomHline: false,
      );
      // Top-only \hline.
      assertColortblBounded(
        r'\begin{array}{|c|c|} \hline \rowcolor{cyan} a & b \\ c & \cellcolor{yellow} d \end{array}',
        expectTopHline: true,
        expectBottomHline: false,
      );
      // Bottom-only \hline.
      assertColortblBounded(
        r'\begin{array}{|c|c|} \rowcolor{cyan} a & b \\ c & \cellcolor{yellow} d \\ \hline \end{array}',
        expectTopHline: false,
        expectBottomHline: true,
      );
    });

    test('verifies framed-box corner geometry for boxed, fcolorbox, bbox, and enclose', () {
      void assertStrokedFrameMatchesBounds(
        DisplayList dl, {
        int? expectedBgColor,
        int? expectedBorderColor,
      }) {
        final List<RuleItem> rules = dl.items.whereType<RuleItem>().toList();
        final RuleItem border = rules.singleWhere(
          (RuleItem r) => r.strokeWidthEm != null,
        );
        final double halfStroke = border.strokeWidthEm! / 2.0;
        expect(border.xEm - halfStroke, closeTo(0.0, 1e-9));
        expect(
          border.xEm + border.widthEm + halfStroke,
          closeTo(dl.metrics.widthEm, 1e-9),
        );
        expect(border.yEm - halfStroke, closeTo(-dl.metrics.depthEm, 1e-9));
        expect(
          border.yEm + border.heightEm + halfStroke,
          closeTo(dl.metrics.heightEm, 1e-9),
        );
        if (expectedBorderColor != null) {
          expect(border.customColor, expectedBorderColor);
        }
        if (expectedBgColor != null) {
          final RuleItem fill = rules.singleWhere(
            (RuleItem r) => r.strokeWidthEm == null,
          );
          expect(fill.customColor, expectedBgColor);
          expect(fill.xEm, closeTo(border.xEm, 1e-9));
          expect(fill.yEm, closeTo(border.yEm, 1e-9));
          expect(fill.widthEm, closeTo(border.widthEm, 1e-9));
          expect(fill.heightEm, closeTo(border.heightEm, 1e-9));
        }
      }

      assertStrokedFrameMatchesBounds(
        engine.render(r'\boxed{x+1}', options: _allOpts()).displayList,
      );
      assertStrokedFrameMatchesBounds(
        engine
            .render(r'\fcolorbox{blue}{yellow}{x+1}', options: _allOpts())
            .displayList,
        expectedBgColor: 0xFFFFFF00,
        expectedBorderColor: 0xFF0000FF,
      );
      assertStrokedFrameMatchesBounds(
        engine
            .render(
              r'\bbox[5px,border:2px solid red,yellow]{x+1}',
              options: _allOpts(),
            )
            .displayList,
        expectedBgColor: 0xFFFFFF00,
        expectedBorderColor: 0xFFFF0000,
      );

      final DisplayList encloseDl = engine
          .render(r'\enclose{top,bottom,left,right}{x+1}', options: _allOpts())
          .displayList;
      final List<RuleItem> sideRules = encloseDl.items
          .whereType<RuleItem>()
          .toList();
      expect(sideRules, hasLength(4));
      final List<RuleItem> hSides =
          sideRules.where((RuleItem r) => r.widthEm > r.heightEm).toList()
            ..sort((RuleItem a, RuleItem b) => b.yEm.compareTo(a.yEm));
      final List<RuleItem> vSides =
          sideRules.where((RuleItem r) => r.heightEm > r.widthEm).toList()
            ..sort((RuleItem a, RuleItem b) => a.xEm.compareTo(b.xEm));
      expect(hSides, hasLength(2));
      expect(vSides, hasLength(2));

      final RuleItem topSide = hSides.first;
      final RuleItem botSide = hSides.last;
      final RuleItem leftSide = vSides.first;
      final RuleItem rightSide = vSides.last;
      final double stroke = topSide.heightEm;
      expect(botSide.heightEm, closeTo(stroke, 1e-9));
      expect(leftSide.widthEm, closeTo(stroke, 1e-9));
      expect(rightSide.widthEm, closeTo(stroke, 1e-9));

      expect(topSide.xEm, closeTo(0.0, 1e-9));
      expect(topSide.widthEm, closeTo(encloseDl.metrics.widthEm, 1e-9));
      expect(
        topSide.yEm + topSide.heightEm,
        closeTo(encloseDl.metrics.heightEm, 1e-9),
      );
      expect(botSide.xEm, closeTo(0.0, 1e-9));
      expect(botSide.widthEm, closeTo(encloseDl.metrics.widthEm, 1e-9));
      expect(botSide.yEm, closeTo(-encloseDl.metrics.depthEm, 1e-9));
      expect(leftSide.xEm, closeTo(0.0, 1e-9));
      expect(leftSide.yEm, closeTo(botSide.yEm, 1e-9));
      expect(
        leftSide.yEm + leftSide.heightEm,
        closeTo(topSide.yEm + topSide.heightEm, 1e-9),
      );
      expect(
        rightSide.xEm + rightSide.widthEm,
        closeTo(encloseDl.metrics.widthEm, 1e-9),
      );
      expect(rightSide.yEm, closeTo(botSide.yEm, 1e-9));
      expect(
        rightSide.yEm + rightSide.heightEm,
        closeTo(topSide.yEm + topSide.heightEm, 1e-9),
      );
    });

    test('checks corpus-wide finite geometry and framed array rule bounds when corpus exists', () {
      Directory? corpusDir;
      for (final String candidate in <String>['corpus', '../../corpus']) {
        final Directory dir = Directory(candidate);
        if (dir.existsSync()) {
          corpusDir = dir;
          break;
        }
      }
      if (corpusDir == null) {
        return;
      }

      final List<File> texFiles =
          corpusDir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.tex'))
              .toList()
            ..sort((File a, File b) => a.path.compareTo(b.path));
      final RegExp headerPattern = RegExp(r'^%\s*([a-zA-Z0-9_]+)\s*:\s*(.*)$');

      int checkedAccepted = 0;
      for (final File file in texFiles) {
        final List<String> lines = file.readAsLinesSync();
        final Map<String, String> headers = <String, String>{};
        int bodyStart = 0;
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          final RegExpMatch? m = headerPattern.firstMatch(line);
          if (m != null) {
            headers[m.group(1)!.trim().toLowerCase()] = m.group(2)!.trim();
            bodyStart = i + 1;
            continue;
          }
          if (line.trim().isEmpty && headers.isNotEmpty) {
            bodyStart = i + 1;
            continue;
          }
          break;
        }
        final bool accepted =
            (headers['accepted'] ?? 'true').toLowerCase() == 'true';
        if (!accepted) {
          continue;
        }
        checkedAccepted++;

        final String id = headers['id'] ?? file.path;
        final String displayRaw = (headers['display'] ?? 'display')
            .toLowerCase();
        final bool isDisplay = displayRaw == 'display' || displayRaw == 'true';
        final String? packagesRaw = headers['packages'];
        final List<String> packages = packagesRaw == null || packagesRaw.isEmpty
            ? TexMathOptions.defaultPackages
            : packagesRaw
                  .split(',')
                  .map((String s) => s.trim())
                  .where((String s) => s.isNotEmpty)
                  .toList();
        final String tex = lines.sublist(bodyStart).join('\n').trim();

        final RenderResult result = engine.render(
          tex,
          options: TexMathOptions(
            displayMode: isDisplay
                ? TexMathDisplayMode.display
                : TexMathDisplayMode.inline,
            packages: packages,
          ),
        );
        final DisplayList dl = result.displayList;
        expect(dl.metrics.widthEm.isFinite, isTrue, reason: id);
        expect(dl.metrics.heightEm.isFinite, isTrue, reason: id);
        expect(dl.metrics.depthEm.isFinite, isTrue, reason: id);
        expect(dl.metrics.baselineEm.isFinite, isTrue, reason: id);
        expect(dl.metrics.widthEm, greaterThanOrEqualTo(0.0), reason: id);
        expect(dl.metrics.heightEm, greaterThanOrEqualTo(0.0), reason: id);
        expect(dl.metrics.depthEm, greaterThanOrEqualTo(0.0), reason: id);

        for (final DisplayItem item in dl.items) {
          switch (item) {
            case GlyphItem():
              expect(item.xEm.isFinite, isTrue, reason: id);
              expect(item.yEm.isFinite, isTrue, reason: id);
              expect(item.scaleX.isFinite, isTrue, reason: id);
              expect(item.scaleY.isFinite, isTrue, reason: id);
              expect(item.advanceEm.isFinite, isTrue, reason: id);
              expect(item.scaleX, greaterThanOrEqualTo(0.0), reason: id);
              expect(item.scaleY, greaterThanOrEqualTo(0.0), reason: id);
              expect(item.advanceEm, greaterThanOrEqualTo(0.0), reason: id);
            case RuleItem():
              expect(item.xEm.isFinite, isTrue, reason: id);
              expect(item.yEm.isFinite, isTrue, reason: id);
              expect(item.widthEm.isFinite, isTrue, reason: id);
              expect(item.heightEm.isFinite, isTrue, reason: id);
              expect(item.widthEm, greaterThanOrEqualTo(0.0), reason: id);
              expect(item.heightEm, greaterThanOrEqualTo(0.0), reason: id);
              if (item.strokeWidthEm != null) {
                expect(item.strokeWidthEm!.isFinite, isTrue, reason: id);
                expect(
                  item.strokeWidthEm!,
                  greaterThanOrEqualTo(0.0),
                  reason: id,
                );
              }
            case AnchorItem():
              expect(item.xEm.isFinite, isTrue, reason: id);
              expect(item.yEm.isFinite, isTrue, reason: id);
          }
        }

        // Framed array grids: vertical rules must never overshoot outer `\hline`s.
        final MathRootNode root = result.syntaxTree as MathRootNode;
        if (root.children.length == 1 && root.children.single is MatrixNode) {
          final MatrixNode matrix = root.children.single as MatrixNode;
          final bool isArray =
              matrix.environment == 'array' || matrix.environment == 'darray';
          final bool hasTopHline = matrix.rowLines[0] != null;
          final bool hasBottomHline =
              matrix.rowLines[matrix.rows.length] != null;
          final bool hasVline = matrix.columnLines.values.any(
            (String s) => s.contains('|'),
          );
          if (isArray && hasVline && (hasTopHline || hasBottomHline)) {
            final List<RuleItem> gridHRules = dl.items
                .whereType<RuleItem>()
                .where(
                  (RuleItem r) =>
                      r.customColor == null &&
                      r.strokeWidthEm == null &&
                      r.widthEm > r.heightEm &&
                      (r.widthEm - dl.metrics.widthEm).abs() < 1e-6,
                )
                .toList();
            final List<RuleItem> gridVRules = dl.items
                .whereType<RuleItem>()
                .where(
                  (RuleItem r) =>
                      r.customColor == null &&
                      r.strokeWidthEm == null &&
                      r.heightEm > r.widthEm,
                )
                .toList();
            if (gridHRules.isNotEmpty && gridVRules.isNotEmpty) {
              final double maxHTop = gridHRules
                  .map((RuleItem r) => r.yEm + r.heightEm)
                  .reduce(math.max);
              final double minHBot = gridHRules
                  .map((RuleItem r) => r.yEm)
                  .reduce(math.min);
              for (final RuleItem v in gridVRules) {
                if (hasTopHline) {
                  expect(
                    v.yEm + v.heightEm,
                    lessThanOrEqualTo(maxHTop + 1e-9),
                    reason: '$id vertical rule overshoots top \\hline',
                  );
                }
                if (hasBottomHline) {
                  expect(
                    v.yEm,
                    greaterThanOrEqualTo(minHBot - 1e-9),
                    reason: '$id vertical rule overshoots bottom \\hline',
                  );
                }
              }
            }
          }
        }
      }

      expect(checkedAccepted, 315);
    });
  });
}

TexMathOptions _allOpts() => TexMathOptions(
  displayMode: TexMathDisplayMode.display,
  packages: TexPackageRegistry.allNames,
);

File _locateBundledFont() {
  return _resolveRepoFile(
    'packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
  );
}

File _expectationsFile() {
  return _resolveRepoFile('corpus/expectations.json');
}

File _resolveRepoFile(String repoRelative) {
  final File direct = File(repoRelative);
  if (direct.existsSync()) {
    return direct;
  }
  final File fromPackage = File('../../$repoRelative');
  if (fromPackage.existsSync()) {
    return fromPackage;
  }
  throw StateError(
    'Unable to locate $repoRelative from ${Directory.current.path}.',
  );
}

String _stripCorpusComments(String raw) {
  return raw
      .split('\n')
      .where(
        (String line) =>
            !line.trimLeft().startsWith('%') && line.trim().isNotEmpty,
      )
      .join('\n');
}
