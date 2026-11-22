import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tex_math/src/layout/box.dart';
import 'package:tex_math/src/layout/style_spacing.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  late MathFont bundledFont;
  late TexMathEngine engine;

  setUpAll(() {
    final File fontFile = _locateBundledFont();
    bundledFont = MathFont.fromBytes(fontFile.readAsBytesSync());
    engine = TexMathEngine(font: bundledFont);
  });

  group('Box model and DisplayList conversion', () {
    test('computes HBox and VBox bounds, color overrides, and budgets', () {
      const GlyphBox a = GlyphBox(
        glyphId: 10,
        codePoint: 0x1D44E,
        widthEm: 0.5,
        heightEm: 0.45,
        depthEm: 0.01,
        atomClass: TexMathAtomClass.ord,
        breakPoint: BreakPoint(kind: MathBreakKind.afterBinary, penalty: 700),
      );
      const RuleBox rule = RuleBox(
        widthEm: 1.0,
        heightEm: 0.04,
        depthEm: 0.0,
        strokeWidthEm: 0.067,
      );
      const AnchorBox anchor = AnchorBox(id: 'eq:1', label: '1');
      final HBox row = HBox(
        children: <MathBox>[
          a,
          const KernBox(widthEm: 0.2),
          rule.withMetadata(
            colorRole: TexMathColorRole.accent,
            inheritColor: false,
          ),
          anchor,
        ],
        colorRole: TexMathColorRole.custom,
        customColor: 0xFF0055AA,
        inheritColor: false,
      );

      expect(row.widthEm, closeTo(1.7, 1e-9));
      expect(row.heightEm, closeTo(0.45, 1e-9));
      expect(row.depthEm, closeTo(0.01, 1e-9));

      final DisplayList dl = row.toDisplayList(unitsPerEm: 1000, source: 'a');
      expect(dl.items, hasLength(3));
      final GlyphItem glyphItem = dl.items[0] as GlyphItem;
      expect(glyphItem.colorRole, TexMathColorRole.custom);
      expect(glyphItem.customColor, 0xFF0055AA);

      final RuleItem ruleItem = dl.items[1] as RuleItem;
      expect(ruleItem.xEm, closeTo(0.7, 1e-9));
      expect(ruleItem.strokeWidthEm, closeTo(0.067, 1e-9));
      expect(ruleItem.colorRole, TexMathColorRole.accent);

      final String svg = dl.toSvg();
      expect(svg, contains('fill="none" stroke="#2563EB"'));
      expect(svg, contains('id="eq:1"'));

      expect(
        () => row.toDisplayList(maxOutputItems: 2),
        throwsA(isA<TexMathBudgetError>()),
      );
    });

    test('requires non-null MathFont with MATH table on layout', () {
      final MathNode tree = parseTex('x + y');
      expect(
        () => const TexMathEngine().layout(tree),
        throwsA(
          isA<TexMathFontError>().having(
            (TexMathFontError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.invalidFont,
          ),
        ),
      );
    });
  });

  group('Appendix G style, ssty variants, spacing, and Unicode mapping', () {
    test('supports style scale transitions and opt-in ssty script glyphs', () {
      final RenderResult defaultScript = engine.render(
        r'x_{a}^{2}',
        options: const TexMathOptions(useOpticalScriptVariants: false),
      );
      final RenderResult opticalScript = engine.render(
        r'x_{a}^{2}',
        options: const TexMathOptions(useOpticalScriptVariants: true),
      );

      final List<GlyphItem> defaultGlyphs = defaultScript.displayList.items
          .whereType<GlyphItem>()
          .toList();
      final List<GlyphItem> opticalGlyphs = opticalScript.displayList.items
          .whereType<GlyphItem>()
          .toList();
      expect(defaultGlyphs, hasLength(3));
      expect(opticalGlyphs, hasLength(3));

      // Base 'x' uses same glyph ID; script '2' and 'a' switch when ssty exists.
      expect(opticalGlyphs[0].glyphId, equals(defaultGlyphs[0].glyphId));
      expect(opticalGlyphs[1].glyphId, isNot(equals(defaultGlyphs[1].glyphId)));
      expect(opticalGlyphs[2].glyphId, isNot(equals(defaultGlyphs[2].glyphId)));
      expect(defaultGlyphs[1].scaleX, closeTo(0.70, 1e-9));
    });

    test('promotes unary minus/plus and suppresses medium script spacing', () {
      final List<GlyphItem> unaryGlyphs = engine
          .render(r'-x')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      expect(unaryGlyphs[0].codePoint, 0x2212);
      // Unary minus behaves as Ord -> Ord with zero medium space after it.
      final double minusAdv =
          bundledFont.metricsForGlyph(unaryGlyphs[0].glyphId).advanceWidth /
          bundledFont.unitsPerEm;
      expect(unaryGlyphs[1].xEm, closeTo(minusAdv, 1e-6));

      final List<GlyphItem> binaryGlyphs = engine
          .render(r'x - y')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      final double xAdv =
          bundledFont.metricsForGlyph(binaryGlyphs[0].glyphId).advanceWidth /
          bundledFont.unitsPerEm;
      expect(binaryGlyphs[1].xEm, closeTo(xAdv + medMuSkipEm, 1e-6));

      final List<GlyphItem> scriptBin = engine
          .render(r'z_{a + b}')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      final double aSubAdv =
          (bundledFont.metricsForGlyph(scriptBin[1].glyphId).advanceWidth /
              bundledFont.unitsPerEm) *
          scriptBin[1].scaleX;
      // Inside subscripts, Ord -> Bin inserts zero medium space.
      expect(scriptBin[2].xEm - scriptBin[1].xEm, closeTo(aSubAdv, 1e-6));
    });

    test('maps math alphabets, dotless i/j, and U+2061 SVG safely', () {
      final List<GlyphItem> alphaGlyphs = engine
          .render(r'\mathcal{L} + \mathbb{R} + \mathfrak{g} + \imath + \jmath')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      expect(alphaGlyphs[0].codePoint, 0x2112);
      expect(alphaGlyphs[2].codePoint, 0x211D);
      expect(alphaGlyphs[4].codePoint, 0x1D524);
      expect(alphaGlyphs[6].codePoint, 0x1D6A4);
      expect(alphaGlyphs[8].codePoint, 0x1D6A5);

      final RenderResult sinRes = engine.render(r'\sin x');
      final List<GlyphItem> sinGlyphs = sinRes.displayList.items
          .whereType<GlyphItem>()
          .toList();
      expect(sinGlyphs.any((GlyphItem g) => g.codePoint == 0x2061), isTrue);

      final String svg = sinRes.toSvg();
      expect(svg, contains('<path d="'));
      expect(svg, contains('data-codepoint="0x2061"'));
      expect(svg, isNot(contains('<text')));
    });

    test('evaluates OpenType MathKern 4-corner kerning on scripts', () {
      // Compare V^2 and P_i widths with raw sum to confirm kern adjustments.
      final List<GlyphItem> vSup = engine
          .render(r'V^2')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      final double vAdv =
          bundledFont.metricsForGlyph(vSup[0].glyphId).advanceWidth /
          bundledFont.unitsPerEm;
      final double? vIc = bundledFont.mathTable!.glyphInfo.italicsCorrection(
        vSup[0].glyphId,
      );
      expect(
        vSup[1].xEm,
        lessThanOrEqualTo(vAdv + (vIc ?? 0.0) / 1000.0 + 1e-6),
      );
    });
  });

  group('OpenType MATH GlyphAssembly and stretchy constructs', () {
    test('assembles tall delimiters and tall sqrt using unencoded parts', () {
      final RenderResult tallMatrix = engine.render(
        r'\left(\begin{matrix} 1 \\ 2 \\ 3 \\ 4 \end{matrix}\right)',
      );
      final List<GlyphItem> glyphs = tallMatrix.displayList.items
          .whereType<GlyphItem>()
          .toList();
      final List<GlyphItem> assemblyParts = glyphs
          .where((GlyphItem g) => g.codePoint == 0)
          .toList();
      expect(assemblyParts.length, greaterThanOrEqualTo(6));
      for (final GlyphItem part in assemblyParts) {
        expect(part.outline, isNotNull);
        expect(part.outline!.isEmpty, isFalse);
      }
      expect(tallMatrix.displayList.metrics.totalHeightEm, greaterThan(4.5));
      final String svg = tallMatrix.toSvg();
      expect(svg, contains('data-codepoint="0x0"'));
      expect(svg, contains('<path d="'));

      final RenderResult tallSqrt = engine.render(
        r'\sqrt{\begin{matrix} a \\ b \\ c \\ d \end{matrix}}',
      );
      expect(tallSqrt.displayList.items.whereType<RuleItem>(), hasLength(1));
      expect(
        tallSqrt.displayList.items.whereType<GlyphItem>().any(
          (GlyphItem g) => g.codePoint == 0,
        ),
        isTrue,
      );
    });

    test('renders horizontal stretchy accents, braces, and arrows', () {
      final RenderResult overbrace = engine.render(
        r'\overbrace{a + b + c + d + e + f}^{6\text{ terms}}',
      );
      expect(overbrace.displayList.metrics.widthEm, greaterThan(4.0));
      expect(overbrace.toSvg(), contains('<path d="'));

      final RenderResult arrow = engine.render(
        r'A \xrightarrow[\text{below}]{\text{above condition}} B',
      );
      expect(arrow.displayList.metrics.widthEm, greaterThan(5.0));
      expect(arrow.displayList.metrics.heightEm, greaterThan(0.9));
      expect(arrow.displayList.metrics.depthEm, greaterThan(0.5));
    });
  });

  group('Tier 1, Stretchy, and Notebooks end-to-end coverage', () {
    test('lays out all 175 Tier 1, Stretchy, and Notebook corpus cases', () {
      final Map<String, Object?> raw = jsonDecode(
        _expectationsFile().readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> cases = raw['cases']! as Map<String, Object?>;

      int evaluated = 0;
      for (final MapEntry<String, Object?> entry in cases.entries) {
        final String id = entry.key;
        if (!id.startsWith('tier1_core/') &&
            !id.startsWith('stretchy/') &&
            !id.startsWith('notebooks/')) {
          continue;
        }
        final Map<String, Object?> spec = entry.value! as Map<String, Object?>;
        final String texPath = spec['path']! as String;
        final String tex = _stripCorpusComments(
          _resolveRepoFile(texPath).readAsStringSync(),
        );
        final bool isDisplay = spec['display']! as bool;
        final List<String> pkgs =
            (spec['packages'] as List<Object?>?)?.cast<String>() ??
            TexMathOptions.defaultPackages;

        final RenderResult result = engine.render(
          tex,
          options: TexMathOptions(
            displayMode: isDisplay
                ? TexMathDisplayMode.display
                : TexMathDisplayMode.inline,
            packages: pkgs,
          ),
        );
        expect(result.displayList.metrics.widthEm, greaterThanOrEqualTo(0.0));
        final String svg = result.toSvg();
        expect(svg, startsWith('<svg '));
        expect(svg, endsWith('</svg>'));
        evaluated++;
      }
      expect(evaluated, 175);
    });

    test('matches MathJax 4.1.3 within 0.02em on calibrated Tier 1 suite', () {
      final Map<String, Object?> raw = jsonDecode(
        _expectationsFile().readAsStringSync(),
      ) as Map<String, Object?>;
      final Map<String, Object?> cases = raw['cases']! as Map<String, Object?>;

      const List<String> calibratedIds = <String>[
        'tier1_core/ams/Vmatrix_Bmatrix',
        'tier1_core/ams/align_basic',
        'tier1_core/ams/align_star',
        'tier1_core/ams/aligned_braced',
        'tier1_core/ams/ams_alignat',
        'tier1_core/ams/ams_boxed_mod',
        'tier1_core/ams/ams_eqno_text',
        'tier1_core/ams/ams_logic_symbols',
        'tier1_core/ams/ams_set_symbols',
        'tier1_core/ams/binom_variants',
        'tier1_core/ams/bmatrix_basic',
        'tier1_core/ams/cases_basic',
        'tier1_core/ams/gathered_inline',
        'tier1_core/ams/pmatrix_basic',
        'tier1_core/ams/text_commands',
        'tier1_core/ams/vmatrix_basic',
        'tier1_core/base/array_basic',
        'tier1_core/base/array_colsep_at',
        'tier1_core/base/array_inline',
        'tier1_core/base/array_top_bottom_align',
        'tier1_core/base/arrows_vertical_diag',
        'tier1_core/base/fonts_greek_upper',
        'tier1_core/base/operators_operatorname',
        'tier1_core/base/relations_negated_not',
        'tier1_core/base/spacing_kern_mkern',
        'tier1_core/base/spacing_smash_rlap_llap',
        'tier1_core/base/spacing_vphantom_hphantom',
        'tier1_core/base/styles_atom_classes',
        'tier1_core/base/styles_four_levels',
        'tier1_core/base/styles_mathchoice',
        'tier1_core/configmacros/configmacros_ams_interop',
        'tier1_core/configmacros/configmacros_base_interop',
        'tier1_core/newcommand/def_delimited',
        'tier1_core/newcommand/newcommand_with_args',
        'tier1_core/newcommand/newcommand_zero_args',
        'tier1_core/newcommand/newenvironment_basic',
        'tier1_core/newcommand/renewenvironment_basic',
        'tier1_core/textmacros/textmacros_inline_math',
        'stretchy/left_right_brackets_braces',
        'stretchy/manual_big_sizes_brackets_angles',
        'stretchy/manual_big_sizes_parens',
      ];

      for (final String id in calibratedIds) {
        final Map<String, Object?> spec = cases[id]! as Map<String, Object?>;
        final String tex = _stripCorpusComments(
          _resolveRepoFile(spec['path']! as String).readAsStringSync(),
        );
        final bool isDisplay = spec['display']! as bool;
        final List<String> pkgs =
            (spec['packages'] as List<Object?>?)?.cast<String>() ??
            TexMathOptions.defaultPackages;

        final DisplayList dl = engine
            .render(
              tex,
              options: TexMathOptions(
                displayMode: isDisplay
                    ? TexMathDisplayMode.display
                    : TexMathDisplayMode.inline,
                packages: pkgs,
              ),
            )
            .displayList;

        final Map<String, Object?> box = spec['box']! as Map<String, Object?>;
        expect(
          dl.metrics.widthEm,
          closeTo((box['width']! as num).toDouble(), 0.02),
          reason: '$id widthEm',
        );
        expect(
          dl.metrics.heightEm,
          closeTo((box['height']! as num).toDouble(), 0.02),
          reason: '$id heightEm',
        );
        expect(
          dl.metrics.depthEm,
          closeTo((box['depth']! as num).toDouble(), 0.02),
          reason: '$id depthEm',
        );

        final List<Object?> expectedGlyphs = spec['glyphs']! as List<Object?>;
        final List<GlyphItem> actualGlyphs = dl.items
            .whereType<GlyphItem>()
            .toList();
        expect(actualGlyphs, hasLength(expectedGlyphs.length), reason: id);
        for (int i = 0; i < expectedGlyphs.length; i++) {
          final Map<String, Object?> og =
              expectedGlyphs[i]! as Map<String, Object?>;
          final GlyphItem ag = actualGlyphs[i];
          expect(
            ag.xEm,
            closeTo((og['x']! as num).toDouble(), 0.02),
            reason: '$id glyph[$i] xEm',
          );
          expect(
            ag.yEm,
            closeTo((og['y']! as num).toDouble(), 0.02),
            reason: '$id glyph[$i] yEm',
          );
        }
      }
    });
  });

  group('Array rule & framed-box corner alignment geometry', () {
    test(
      'aligns full-grid array_rules corners flush while preserving outerPadY',
      () {
        final DisplayList dl = engine
            .render(
              r'\begin{array}{|c|c|} \hline x & y \\ \hline z & w \\ \hline \end{array}',
            )
            .displayList;
        final double ruleThickness =
            bundledFont.mathTable!.constants.fractionRuleThickness /
            bundledFont.unitsPerEm;
        final List<RuleItem> rules = dl.items.whereType<RuleItem>().toList();
        final List<RuleItem> hRules =
            rules.where((RuleItem r) => r.widthEm > r.heightEm).toList()
              ..sort((RuleItem a, RuleItem b) => b.yEm.compareTo(a.yEm));
        final List<RuleItem> vRules =
            rules.where((RuleItem r) => r.heightEm > r.widthEm).toList()
              ..sort((RuleItem a, RuleItem b) => a.xEm.compareTo(b.xEm));

        expect(hRules, hasLength(3));
        expect(vRules, hasLength(3));

        final RuleItem topH = hRules.first;
        final RuleItem botH = hRules.last;
        final double gridTopY = topH.yEm + topH.heightEm;
        final double gridBottomY = botH.yEm;

        for (final RuleItem h in hRules) {
          expect(h.xEm, closeTo(0.0, 1e-9));
          expect(h.widthEm, closeTo(dl.metrics.widthEm, 1e-9));
          expect(h.heightEm, closeTo(ruleThickness, 1e-9));
        }
        for (final RuleItem v in vRules) {
          expect(v.widthEm, closeTo(ruleThickness, 1e-9));
          expect(v.yEm, closeTo(gridBottomY, 1e-9));
          expect(v.heightEm, closeTo(gridTopY - gridBottomY, 1e-9));
          expect(v.yEm + v.heightEm, closeTo(gridTopY, 1e-9));
        }

        // Outer horizontal corners touch outer vertical rules flush.
        expect(vRules.first.xEm, closeTo(topH.xEm, 1e-9));
        expect(
          vRules.last.xEm + vRules.last.widthEm,
          closeTo(topH.xEm + topH.widthEm, 1e-9),
        );

        // outerPadY (0.125em) stays in overall box metrics for MathJax parity.
        expect(dl.metrics.heightEm - gridTopY, closeTo(0.125, 1e-9));
        expect(gridBottomY - (-dl.metrics.depthEm), closeTo(0.125, 1e-9));
      },
    );

    test('aligns double rules (|| and \\hline\\hline) cleanly at corners', () {
      final DisplayList dl = engine
          .render(
            r'\begin{array}{||c||c||} \hline\hline x & y \\ \hline\hline z & w \\ \hline\hline \end{array}',
          )
          .displayList;
      final double ruleThickness =
          bundledFont.mathTable!.constants.fractionRuleThickness /
          bundledFont.unitsPerEm;
      final List<RuleItem> rules = dl.items.whereType<RuleItem>().toList();
      final List<RuleItem> hRules =
          rules.where((RuleItem r) => r.widthEm > r.heightEm).toList()
            ..sort((RuleItem a, RuleItem b) => b.yEm.compareTo(a.yEm));
      final List<RuleItem> vRules =
          rules.where((RuleItem r) => r.heightEm > r.widthEm).toList()
            ..sort((RuleItem a, RuleItem b) => a.xEm.compareTo(b.xEm));

      expect(hRules, hasLength(6));
      expect(vRules, hasLength(6));

      final double outerTopY = hRules.first.yEm + hRules.first.heightEm;
      final double outerBottomY = hRules.last.yEm;
      for (final RuleItem h in hRules) {
        expect(h.xEm, closeTo(0.0, 1e-9));
        expect(h.widthEm, closeTo(dl.metrics.widthEm, 1e-9));
        expect(h.heightEm, closeTo(ruleThickness, 1e-9));
      }
      for (final RuleItem v in vRules) {
        expect(v.widthEm, closeTo(ruleThickness, 1e-9));
        expect(v.yEm, closeTo(outerBottomY, 1e-9));
        expect(v.heightEm, closeTo(outerTopY - outerBottomY, 1e-9));
      }
      expect(vRules.first.xEm, closeTo(0.0, 1e-9));
      expect(
        vRules.last.xEm + vRules.last.widthEm,
        closeTo(dl.metrics.widthEm, 1e-9),
      );
      expect(
        vRules[1].xEm - (vRules[0].xEm + vRules[0].widthEm),
        closeTo(2.5 * ruleThickness, 1e-9),
      );
      expect(
        hRules[0].yEm - (hRules[1].yEm + hRules[1].heightEm),
        closeTo(2.5 * ruleThickness, 1e-9),
      );
    });

    test('clamps vertical rules for top-only, bottom-only, no \\hline, and empty arrays', () {
      // Top-only \hline.
      final DisplayList topOnly = engine
          .render(r'\begin{array}{|c|c|} \hline x & y \\ z & w \end{array}')
          .displayList;
      final List<RuleItem> topHRules = topOnly.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.widthEm > r.heightEm)
          .toList();
      final List<RuleItem> topVRules = topOnly.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.heightEm > r.widthEm)
          .toList();
      expect(topHRules, hasLength(1));
      expect(topVRules, hasLength(3));
      final double topOnlyTop =
          topHRules.single.yEm + topHRules.single.heightEm;
      for (final RuleItem v in topVRules) {
        expect(v.yEm + v.heightEm, closeTo(topOnlyTop, 1e-9));
        expect(v.yEm, closeTo(-topOnly.metrics.depthEm + 0.125, 1e-9));
      }

      // Bottom-only \hline.
      final DisplayList botOnly = engine
          .render(r'\begin{array}{|c|c|} x & y \\ z & w \\ \hline \end{array}')
          .displayList;
      final List<RuleItem> botHRules = botOnly.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.widthEm > r.heightEm)
          .toList();
      final List<RuleItem> botVRules = botOnly.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.heightEm > r.widthEm)
          .toList();
      expect(botHRules, hasLength(1));
      expect(botVRules, hasLength(3));
      for (final RuleItem v in botVRules) {
        expect(v.yEm, closeTo(botHRules.single.yEm, 1e-9));
        expect(
          v.yEm + v.heightEm,
          closeTo(botOnly.metrics.heightEm - 0.125, 1e-9),
        );
      }

      // No \hline.
      final DisplayList noHline = engine
          .render(r'\begin{array}{|c|c|} x & y \\ z & w \end{array}')
          .displayList;
      final List<RuleItem> noHRules = noHline.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.widthEm > r.heightEm)
          .toList();
      final List<RuleItem> noVRules = noHline.items
          .whereType<RuleItem>()
          .where((RuleItem r) => r.heightEm > r.widthEm)
          .toList();
      expect(noHRules, isEmpty);
      expect(noVRules, hasLength(3));
      for (final RuleItem v in noVRules) {
        expect(v.yEm, closeTo(-noHline.metrics.depthEm + 0.125, 1e-9));
        expect(
          v.yEm + v.heightEm,
          closeTo(noHline.metrics.heightEm - 0.125, 1e-9),
        );
      }

      // Empty array (rowCount == 0) omits vertical rules.
      final DisplayList emptyArray = engine
          .render(r'\begin{array}{|c|c|} \end{array}')
          .displayList;
      expect(emptyArray.items.whereType<RuleItem>(), isEmpty);
      expect(emptyArray.metrics.heightEm, closeTo(0.0, 1e-9));
      expect(emptyArray.metrics.depthEm, closeTo(0.0, 1e-9));
    });

    test('aligns \\boxed frame stroke outer bounds flush with box metrics', () {
      final DisplayList dl = engine.render(r'\boxed{x+1}').displayList;
      final RuleItem border = dl.items.whereType<RuleItem>().single;
      expect(border.strokeWidthEm, isNotNull);
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
    });
  });

  group('Text-mode \\textit, \\emph, and nested style toggling', () {
    test('renders textmacros_styles and textmacros_dashes_emph with Unicode math alphanumerics', () {
      final DisplayList stylesDl = engine
          .render(
            r'\text{normal \textbf{bold} \textit{italic} \texttt{mono} \textsf{sans}}',
          )
          .displayList;
      final List<int> styleCps = stylesDl.items
          .whereType<GlyphItem>()
          .where((GlyphItem g) => g.codePoint != 0x00A0 && g.codePoint != 0x20)
          .map((GlyphItem g) => g.codePoint)
          .toList();
      for (final GlyphItem g in stylesDl.items.whereType<GlyphItem>()) {
        expect(
          g.glyphId,
          isNonZero,
          reason: 'Missing glyph for U+${g.codePoint.toRadixString(16)}',
        );
      }
      expect(styleCps, <int>[
        // normal
        0x6E, 0x6F, 0x72, 0x6D, 0x61, 0x6C,
        // bold
        0x1D41B, 0x1D428, 0x1D425, 0x1D41D,
        // italic
        0x1D456, 0x1D461, 0x1D44E, 0x1D459, 0x1D456, 0x1D450,
        // mono
        0x1D696, 0x1D698, 0x1D697, 0x1D698,
        // sans
        0x1D5CC, 0x1D5BA, 0x1D5C7, 0x1D5CC,
      ]);

      final DisplayList emphDl = engine
          .render(
            r"\text{a---b, c--d, ``quoted'' \emph{emph}}",
            options: const TexMathOptions(
              displayMode: TexMathDisplayMode.inline,
            ),
          )
          .displayList;
      final List<int> emphCps = emphDl.items
          .whereType<GlyphItem>()
          .where((GlyphItem g) => g.codePoint != 0x00A0 && g.codePoint != 0x20)
          .map((GlyphItem g) => g.codePoint)
          .toList();
      for (final GlyphItem g in emphDl.items.whereType<GlyphItem>()) {
        expect(
          g.glyphId,
          isNonZero,
          reason: 'Missing glyph for U+${g.codePoint.toRadixString(16)}',
        );
      }
      expect(emphCps, <int>[
        0x61,
        0x2014,
        0x62,
        0x2C,
        0x63,
        0x2013,
        0x64,
        0x2C,
        0x201C,
        0x71,
        0x75,
        0x6F,
        0x74,
        0x65,
        0x64,
        0x201D,
        0x1D452,
        0x1D45A,
        0x1D45D,
        0x210E,
      ]);
    });

    test('toggles nested \\emph and \\textit / \\emph while preserving non-letters and error parity', () {
      final RenderResult nestedEmph = engine.render(
        r'\text{\emph{outer \emph{inner} outer}}',
      );
      final List<int> nestedCps = nestedEmph.displayList.items
          .whereType<GlyphItem>()
          .where((GlyphItem g) => g.codePoint != 0x00A0 && g.codePoint != 0x20)
          .map((GlyphItem g) => g.codePoint)
          .toList();
      expect(nestedCps, <int>[
        // outer (italic)
        0x1D45C, 0x1D462, 0x1D461, 0x1D452, 0x1D45F,
        // inner (upright)
        0x69, 0x6E, 0x6E, 0x65, 0x72,
        // outer (italic)
        0x1D45C, 0x1D462, 0x1D461, 0x1D452, 0x1D45F,
      ]);
      final String nestedMathMl = nestedEmph.toMathMl();
      expect(
        nestedMathMl,
        contains('<mtext mathvariant="italic">outer </mtext>'),
      );
      expect(nestedMathMl, contains('<mtext>inner</mtext>'));
      expect(
        nestedMathMl,
        contains('<mtext mathvariant="italic"> outer</mtext>'),
      );

      for (final String tex in const <String>[
        r'\text{\textit{outer \emph{inner}}}',
        r'\textit{outer \emph{inner}}',
      ]) {
        final List<int> cps = engine
            .render(tex)
            .displayList
            .items
            .whereType<GlyphItem>()
            .where(
              (GlyphItem g) => g.codePoint != 0x00A0 && g.codePoint != 0x20,
            )
            .map((GlyphItem g) => g.codePoint)
            .toList();
        expect(cps, <int>[
          0x1D45C,
          0x1D462,
          0x1D461,
          0x1D452,
          0x1D45F,
          0x69,
          0x6E,
          0x6E,
          0x65,
          0x72,
        ], reason: tex);
      }

      // Digits, punctuation, and ligatures inside \textit remain unchanged.
      final List<int> nonAlpha = engine
          .render(r'\text{\textit{a12--}}')
          .displayList
          .items
          .whereType<GlyphItem>()
          .map((GlyphItem g) => g.codePoint)
          .toList();
      expect(nonAlpha, <int>[0x1D44E, 0x31, 0x32, 0x2013]);

      // Direct TextNode inherits enclosing variant only when styleCommand == null.
      const MathRootNode inheritTree = MathRootNode(
        span: SourceSpan.zero,
        children: <MathNode>[
          MathGroupNode(
            span: SourceSpan.zero,
            fontVariant: TexMathFontVariant.bold,
            children: <MathNode>[
              TextNode(span: SourceSpan.zero, text: 'a'),
              TextNode(
                span: SourceSpan.zero,
                text: 'b',
                styleCommand: 'textrm',
              ),
            ],
          ),
        ],
      );
      final List<int> inheritCps = engine
          .layout(inheritTree)
          .items
          .whereType<GlyphItem>()
          .map((GlyphItem g) => g.codePoint)
          .toList();
      expect(inheritCps, <int>[0x1D41A, 0x62]);

      // MathJax 4.1.3 error parity: \textsl, top-level \emph, and nested \text/\mbox are rejected.
      for (final String badTex in const <String>[
        r'\textsl{x}',
        r'\emph{x}',
        r'\text{\text{x}}',
        r'\text{\mbox{x}}',
      ]) {
        expect(
          () => engine.render(badTex),
          throwsA(isA<TexMathSyntaxError>()),
          reason: 'Expected syntax error for $badTex',
        );
      }
    });
  });

  group('Multline, multlined, and shove alignment', () {
    test(
      'lays out ams_shove with 12em width, 4em span, and strict stagger',
      () {
        final DisplayList dl = engine
            .render(
              r'\begin{multline} \shoveleft{a + b} \\ c + d \\ \shoveright{e + f} \end{multline}',
            )
            .displayList;
        expect(dl.metrics.widthEm, 12.0);
        expect(dl.metrics.heightEm, closeTo(2.25, 1e-6));
        expect(dl.metrics.depthEm, closeTo(1.75, 1e-6));

        final List<GlyphItem> glyphs = dl.items.whereType<GlyphItem>().toList();
        expect(glyphs, hasLength(9));
        expect(glyphs[0].xEm, closeTo(1.0, 1e-6));
        expect(glyphs[0].xEm, lessThan(glyphs[3].xEm));
        expect(glyphs[3].xEm, lessThan(glyphs[6].xEm));
        expect(glyphs[8].xEm + glyphs[8].advanceEm, closeTo(11.0, 1e-6));
      },
    );

    test('lays out multline_basic with 0.50em row gap, stagger, and binary leading +', () {
      final DisplayList dl = engine
          .render(
            r'\begin{multline} a + b + c + d \\ + e + f + g + h \end{multline}',
          )
          .displayList;
      expect(dl.metrics.heightEm, closeTo(1.50, 1e-6));
      expect(dl.metrics.depthEm, closeTo(1.00, 1e-6));

      final List<GlyphItem> glyphs = dl.items.whereType<GlyphItem>().toList();
      expect(glyphs, hasLength(15));
      expect(glyphs[0].xEm, closeTo(1.0, 1e-6));
      // Row 1 starts after row 0 and ends 1em from right edge.
      expect(glyphs[7].xEm, greaterThan(glyphs[0].xEm));
      expect(
        glyphs[14].xEm + glyphs[14].advanceEm,
        closeTo(dl.metrics.widthEm - 1.0, 1e-6),
      );

      // Compare `+ e` distance in continuation row against binary `a + e` vs unary `+e`.
      final List<GlyphItem> binRef = engine
          .render('a + e')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      final List<GlyphItem> unaryRef = engine
          .render('+ e')
          .displayList
          .items
          .whereType<GlyphItem>()
          .toList();
      final double multlinePlusToE = glyphs[8].xEm - glyphs[7].xEm;
      final double binaryPlusToE = binRef[2].xEm - binRef[1].xEm;
      final double unaryPlusToE = unaryRef[1].xEm - unaryRef[0].xEm;
      expect(multlinePlusToE, closeTo(binaryPlusToE, 1e-6));
      expect(multlinePlusToE, greaterThan(unaryPlusToE + 0.15));
    });

    test('prevents collapse/overflow/inversion on wide equal-length multline rows', () {
      const String longLine = 'a + b + c + d + e + f + g + h + i + j + k + l';
      final DisplayList dl = engine
          .render(
            '\\begin{multline} $longLine \\\\ $longLine \\\\ $longLine \\end{multline}',
          )
          .displayList;
      expect(dl.metrics.widthEm, greaterThan(12.0));

      final List<GlyphItem> glyphs = dl.items.whereType<GlyphItem>().toList();
      final double row0Y = glyphs.first.yEm;
      final double row2Y = glyphs.last.yEm;
      final List<GlyphItem> row0 = glyphs
          .where((GlyphItem g) => (g.yEm - row0Y).abs() < 1e-6)
          .toList();
      final List<GlyphItem> row2 = glyphs
          .where((GlyphItem g) => (g.yEm - row2Y).abs() < 1e-6)
          .toList();
      final List<GlyphItem> row1 = glyphs
          .where(
            (GlyphItem g) =>
                (g.yEm - row0Y).abs() > 0.1 && (g.yEm - row2Y).abs() > 0.1,
          )
          .toList();

      expect(row0.first.xEm, closeTo(1.0, 1e-6));
      expect(row0.first.xEm, lessThan(row1.first.xEm));
      expect(row1.first.xEm, lessThan(row2.first.xEm));
      expect(
        row2.last.xEm + row2.last.advanceEm,
        closeTo(dl.metrics.widthEm - 1.0, 1e-6),
      );
    });

    test(
      'honors TexMathOptions.multlineWidthEm and mathtools shove shifts',
      () {
        final DisplayList wideDl = engine
            .render(
              r'\begin{multline} \shoveleft{a + b} \\ c + d \\ \shoveright{e + f} \end{multline}',
              options: const TexMathOptions(multlineWidthEm: 25.0),
            )
            .displayList;
        expect(wideDl.metrics.widthEm, 25.0);
        final List<GlyphItem> wideGlyphs = wideDl.items
            .whereType<GlyphItem>()
            .toList();
        expect(wideGlyphs[0].xEm, closeTo(1.0, 1e-6));
        expect(wideGlyphs[3].xEm, greaterThan(10.0));
        expect(
          wideGlyphs[8].xEm + wideGlyphs[8].advanceEm,
          closeTo(24.0, 1e-6),
        );

        final DisplayList shiftedDl = engine
            .render(
              r'\begin{multline} \shoveleft[2em]{a + b} \\ \shoveright[2em]{e + f} \end{multline}',
            )
            .displayList;
        final List<GlyphItem> shiftedGlyphs = shiftedDl.items
            .whereType<GlyphItem>()
            .toList();
        expect(shiftedGlyphs[0].xEm, closeTo(3.0, 1e-6));
        expect(
          shiftedGlyphs[5].xEm + shiftedGlyphs[5].advanceEm,
          closeTo(shiftedDl.metrics.widthEm - 3.0, 1e-6),
        );

        // Multi-child cells (`\shoveleft{a+b}\label{eq:1}` and `\shoveleft{a+b}+c`) preserve shove.
        final RenderResult shoveLabeled = engine.render(
          r'\begin{multline} a + b \\ \shoveleft{c + d}\label{eq:s1} \\ \shoveleft{e + f} + g \end{multline}',
          options: const TexMathOptions(tagMode: TexMathTagMode.ams),
        );
        expect((shoveLabeled.syntaxTree as MathRootNode).labels['eq:s1'], '1');
        final List<GlyphItem> shoveGlyphs = shoveLabeled.displayList.items
            .whereType<GlyphItem>()
            .toList();
        // `c` (index 3) and `e` (index 6) are both shoved left to x == 1.0.
        expect(shoveGlyphs[3].xEm, closeTo(1.0, 1e-6));
        expect(shoveGlyphs[6].xEm, closeTo(1.0, 1e-6));
      },
    );

    test(
      'lays out multlined compact natural width and optional [pos][width] args',
      () {
        final DisplayList autoDl = engine
            .render(r'\begin{multlined} a + b \\ a + b \end{multlined}')
            .displayList;
        expect(autoDl.metrics.widthEm, lessThan(12.0));
        final List<GlyphItem> autoGlyphs = autoDl.items
            .whereType<GlyphItem>()
            .toList();
        expect(autoGlyphs[0].xEm, closeTo(0.0, 1e-6));
        expect(
          autoGlyphs[5].xEm + autoGlyphs[5].advanceEm,
          closeTo(autoDl.metrics.widthEm, 1e-6),
        );
        expect(autoGlyphs[3].xEm, closeTo(1.0, 1e-6));

        final DisplayList unequalDl = engine
            .render(r'\begin{multlined} a + b \\ c + d \end{multlined}')
            .displayList;
        final List<GlyphItem> unequalGlyphs = unequalDl.items
            .whereType<GlyphItem>()
            .toList();
        expect(unequalGlyphs[0].xEm, closeTo(0.0, 1e-6));
        expect(unequalGlyphs[3].xEm, greaterThanOrEqualTo(1.0 - 1e-6));
        expect(
          unequalGlyphs[5].xEm + unequalGlyphs[5].advanceEm,
          closeTo(unequalDl.metrics.widthEm, 1e-6),
        );

        final RenderResult topWidth = engine.render(
          r'\begin{multlined}[t][10em] a + b \\ c + d \end{multlined}',
        );
        final MatrixNode topMatrix =
            (topWidth.syntaxTree as MathRootNode).children.single as MatrixNode;
        expect(topMatrix.verticalAlignment, 't');
        expect(topMatrix.explicitWidthEm, 10.0);
        expect(topWidth.displayList.metrics.widthEm, 10.0);
        final List<GlyphItem> topGlyphs = topWidth.displayList.items
            .whereType<GlyphItem>()
            .toList();
        expect(topGlyphs[0].yEm, closeTo(0.0, 1e-6));
        expect(topGlyphs[5].xEm + topGlyphs[5].advanceEm, closeTo(10.0, 1e-6));

        final RenderResult widthOnly = engine.render(
          r'\begin{multlined}[10em] a + b \\ c + d \end{multlined}',
        );
        final MatrixNode widthMatrix =
            (widthOnly.syntaxTree as MathRootNode).children.single
                as MatrixNode;
        expect(widthMatrix.verticalAlignment, isNull);
        expect(widthMatrix.explicitWidthEm, 10.0);
        expect(widthOnly.displayList.metrics.widthEm, 10.0);

        for (final String bad in const <String>[
          r'\begin{multlined}[bad] a \\ b \end{multlined}',
          r'\begin{multlined}[t][bad] a \\ b \end{multlined}',
        ]) {
          expect(
            () => engine.render(bad),
            throwsA(isA<TexMathSyntaxError>()),
            reason: bad,
          );
        }
      },
    );
  });

  group('Tag modes, label/ref/eqref, and href links', () {
    test('implements TexMathTagMode none, ams, and all consistently', () {
      const String labelEqrefTex =
          r'\begin{equation} E = mc^2 \label{eq:einstein} \end{equation}\quad \text{see }\eqref{eq:einstein}, \ref{eq:einstein}';

      // Default / none: no auto-tag, unresolved `???` and `(???)`, targetId preserved.
      final RenderResult noneRes = engine.render(labelEqrefTex);
      final MathRootNode noneRoot = noneRes.syntaxTree as MathRootNode;
      expect(noneRoot.labels, isEmpty);
      final List<AnchorItem> noneRefs = noneRes.displayList.items
          .whereType<AnchorItem>()
          .where((AnchorItem a) => a.id.startsWith('ref:'))
          .toList();
      expect(noneRefs, hasLength(2));
      expect(noneRefs[0].id, 'ref:eq:einstein');
      expect(noneRefs[0].label, 'eq:einstein');
      expect(noneRefs[0].widthEm, greaterThan(0.0));
      expect(noneRes.toMathMl(), contains('<mtext>(???)</mtext>'));
      expect(noneRes.toMathMl(), contains('<mtext>???</mtext>'));

      // AMS: numbered equation gets (1) and resolves \eqref and \ref.
      final RenderResult amsRes = engine.render(
        labelEqrefTex,
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      );
      final MathRootNode amsRoot = amsRes.syntaxTree as MathRootNode;
      expect(amsRoot.labels['eq:einstein'], '1');
      expect(amsRes.toMathMl(), contains('<mtext>(1)</mtext>'));
      expect(amsRes.toMathMl(), contains('<mtext>1</mtext>'));

      // Unresolved ref/eqref in math mode and text mode both produce `???` and targetId.
      final MathRootNode missingRefs = engine.parse(
        r'\eqref{missing} + \ref{missing2} + \text{\eqref{tmissing} \ref{tmissing2}}',
      ) as MathRootNode;
      final List<TagNode> refNodes = <TagNode>[
        missingRefs.children[0] as TagNode,
        missingRefs.children[2] as TagNode,
        ...((missingRefs.children[4] as TextNode).children
            .whereType<TagNode>()),
      ];
      expect(refNodes, hasLength(4));
      expect(refNodes.map((TagNode t) => t.label).toList(), <String>[
        '???',
        '???',
        '???',
        '???',
      ]);
      expect(refNodes.map((TagNode t) => t.targetId).toList(), <String>[
        'missing',
        'missing2',
        'tmissing',
        'tmissing2',
      ]);

      // Multline single auto-tag on last row, \notag suppression, and explicit \tag override.
      final RenderResult multlineAms = engine.render(
        r'\begin{multline} a \label{m1} \\ b \\ c \end{multline}\quad\eqref{m1}',
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      );
      final MatrixNode multMatrix =
          (multlineAms.syntaxTree as MathRootNode).children.first as MatrixNode;
      expect(multMatrix.rowTags.keys, <int>[2]);
      expect(multMatrix.rowTags[2]!.label, '1');
      expect((multlineAms.syntaxTree as MathRootNode).labels['m1'], '1');

      final RenderResult multlineNoTag = engine.render(
        r'\begin{multline} a \label{m2} \\ b \notag \\ c \end{multline}\quad\eqref{m2}',
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      );
      final MatrixNode multNoTagMatrix =
          (multlineNoTag.syntaxTree as MathRootNode).children.first
              as MatrixNode;
      expect(multNoTagMatrix.rowTags, isEmpty);
      expect((multlineNoTag.syntaxTree as MathRootNode).labels, isEmpty);

      final RenderResult multlineExplicit = engine.render(
        r'\begin{multline} a \tag{*} \label{m3} \\ b \end{multline}\quad\eqref{m3}',
      );
      final MatrixNode multExplicitMatrix =
          (multlineExplicit.syntaxTree as MathRootNode).children.first
              as MatrixNode;
      expect(multExplicitMatrix.rowTags.keys, <int>[0]);
      expect(multExplicitMatrix.rowTags[0]!.label, '*');
      expect((multlineExplicit.syntaxTree as MathRootNode).labels['m3'], '*');

      // Align & gather \notag + cross-row label isolation + order-independent label/tag.
      final MathRootNode alignAms = engine.parse(
        r'\begin{align} a &= b \label{a1} \\ c &= d \notag \\ e &= f \label{a2} \end{align}',
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      ) as MathRootNode;
      final MatrixNode alignMatrix = alignAms.children.single as MatrixNode;
      expect(alignMatrix.rowTags.keys, <int>[0, 2]);
      expect(alignMatrix.rowTags[0]!.label, '1');
      expect(alignMatrix.rowTags[2]!.label, '2');
      expect(alignAms.labels['a1'], '1');
      expect(alignAms.labels['a2'], '2');

      final MathRootNode gatherAms = engine.parse(
        r'\begin{gather} x \notag \\ y \label{g1} \end{gather}',
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      ) as MathRootNode;
      final MatrixNode gatherMatrix = gatherAms.children.single as MatrixNode;
      expect(gatherMatrix.rowTags.keys, <int>[1]);
      expect(gatherMatrix.rowTags[1]!.label, '1');
      expect(gatherAms.labels['g1'], '1');

      final MathRootNode noLeakNone = engine.parse(
        r'\begin{align} a &= b \label{leak} \\ c &= d \tag{*} \end{align}',
      ) as MathRootNode;
      expect(noLeakNone.labels.containsKey('leak'), isFalse);

      final MathRootNode bothOrders = engine.parse(
        r'\begin{align} a &= b \label{x1}\tag{A} \\ c &= d \tag{B}\label{x2} \end{align}',
      ) as MathRootNode;
      expect(bothOrders.labels['x1'], 'A');
      expect(bothOrders.labels['x2'], 'B');

      // TexMathTagMode.all: wraps top-level display math without double-wrapping display envs.
      final MathRootNode allTop = engine.parse(
        r'E = mc^2 \label{top}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allTop.children.single, isA<TagNode>());
      expect((allTop.children.single as TagNode).label, '1');
      expect(allTop.labels['top'], '1');

      final MathRootNode allInline = engine.parse(
        r'E = mc^2',
        options: const TexMathOptions(
          displayMode: TexMathDisplayMode.inline,
          tagMode: TexMathTagMode.all,
        ),
      ) as MathRootNode;
      expect(allInline.children, hasLength(4));
      expect(allInline.children.whereType<TagNode>(), isEmpty);

      final MathRootNode allNotag = engine.parse(
        r'E = mc^2 \notag',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allNotag.children, hasLength(4));
      expect(allNotag.children.whereType<TagNode>(), isEmpty);

      final MathRootNode allEqStar = engine.parse(
        r'\begin{equation*} E = mc^2 \end{equation*}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allEqStar.children.single, isA<MathGroupNode>());

      final MathRootNode allPmatrix = engine.parse(
        r'\begin{pmatrix} 1 \\ 2 \end{pmatrix}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allPmatrix.children.single, isA<TagNode>());

      final MathRootNode allAligned = engine.parse(
        r'\begin{aligned} a &= b \\ c &= d \end{aligned}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allAligned.children.single, isA<TagNode>());

      final MathRootNode allMultlineStar = engine.parse(
        r'\begin{multline*} a \\ b \end{multline*}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allMultlineStar.children.single, isA<MatrixNode>());

      final MathRootNode allEmpheqEq = engine.parse(
        r'\begin{empheq}[left=\empheqlangle,right=\empheqrangle]{equation} x = 1 \end{empheq}',
        options: const TexMathOptions(tagMode: TexMathTagMode.all),
      ) as MathRootNode;
      expect(allEmpheqEq.children.single, isA<TagNode>());
      expect((allEmpheqEq.children.single as TagNode).label, '1');
      expect(
        (allEmpheqEq.children.single as TagNode).body,
        isA<DelimiterNode>(),
      );
    });

    test('styles \\href and \\ref with accent color, hitbox bounds, SVG <a>, and safe URI checks', () {
      final RenderResult hrefRes = engine.render(
        r'\href{https://example.org}{E = mc^2}',
      );
      final DisplayList dl = hrefRes.displayList;
      final List<GlyphItem> glyphs = dl.items.whereType<GlyphItem>().toList();
      expect(glyphs, isNotEmpty);
      for (final GlyphItem g in glyphs) {
        expect(g.colorRole, TexMathColorRole.accent);
      }

      final AnchorItem anchor = dl.items.whereType<AnchorItem>().single;
      expect(anchor.id, 'href:https://example.org');
      expect(anchor.label, 'https://example.org');
      expect(anchor.href, 'https://example.org');
      expect(anchor.widthEm, closeTo(dl.metrics.widthEm, 1e-6));
      expect(anchor.heightEm, closeTo(dl.metrics.heightEm, 1e-6));
      expect(anchor.depthEm, closeTo(dl.metrics.depthEm, 1e-6));

      final String svg = hrefRes.toSvg();
      expect(svg, contains('id="href:https://example.org"'));
      expect(svg, contains('data-anchor="true"'));
      expect(svg, contains('<a href="https://example.org"'));
      expect(svg, contains('pointer-events="all"/></a></svg>'));

      // Inner \color overrides accent while outer href parts keep accent.
      final DisplayList fullOverride = engine
          .render(r'\href{https://example.org}{\color{red} E = mc^2}')
          .displayList;
      for (final GlyphItem g in fullOverride.items.whereType<GlyphItem>()) {
        expect(g.colorRole, TexMathColorRole.custom);
        expect(g.customColor, 0xFFFF0000);
      }

      final DisplayList partialOverride = engine
          .render(r'\href{https://example.org}{E + \textcolor{red}{x}}')
          .displayList;
      final List<GlyphItem> partialGlyphs = partialOverride.items
          .whereType<GlyphItem>()
          .toList();
      expect(partialGlyphs[0].colorRole, TexMathColorRole.accent);
      expect(partialGlyphs[1].colorRole, TexMathColorRole.accent);
      expect(partialGlyphs[2].colorRole, TexMathColorRole.custom);
      expect(partialGlyphs[2].customColor, 0xFFFF0000);

      // \eqref reference glyphs carry accent color and AnchorItem has no href.
      final RenderResult refRes = engine.render(
        r'\begin{equation} x \label{e} \end{equation}\quad\eqref{e}',
        options: const TexMathOptions(tagMode: TexMathTagMode.ams),
      );
      final AnchorItem refAnchor = refRes.displayList.items
          .whereType<AnchorItem>()
          .firstWhere((AnchorItem a) => a.id == 'ref:e');
      expect(refAnchor.href, isNull);
      expect(refAnchor.widthEm, greaterThan(0.0));
      expect(refAnchor.heightEm, greaterThan(0.0));
      final List<GlyphItem> refGlyphs = refRes.displayList.items
          .whereType<GlyphItem>()
          .where((GlyphItem g) => g.colorRole == TexMathColorRole.accent)
          .toList();
      expect(refGlyphs, hasLength(3)); // (1)

      // Manually constructed AST with unsafe href scheme is stripped in layout and SVG.
      const MathRootNode unsafeAst = MathRootNode(
        span: SourceSpan.zero,
        children: <MathNode>[
          MathGroupNode(
            span: SourceSpan.zero,
            role: 'href',
            attributes: <String, String>{'href': 'javascript:evil()'},
            children: <MathNode>[SymbolNode(span: SourceSpan.zero, value: 'x')],
          ),
        ],
      );
      final DisplayList unsafeDl = engine.layout(unsafeAst);
      expect(unsafeDl.items.whereType<AnchorItem>(), isEmpty);
      expect(
        unsafeDl.items.whereType<GlyphItem>().single.colorRole,
        TexMathColorRole.foreground,
      );
      expect(unsafeDl.toSvg(), isNot(contains('<a ')));
    });
  });
}

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
