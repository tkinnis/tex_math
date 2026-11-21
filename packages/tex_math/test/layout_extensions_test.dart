import 'dart:convert';
import 'dart:io';

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
