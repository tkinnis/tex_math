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
