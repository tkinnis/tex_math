import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tex_math/src/font/binary_reader.dart';
import 'package:tex_math/src/font/variation.dart';
import 'package:tex_math/src/layout/box.dart';
import 'package:tex_math/src/layout/glyph_resolve.dart'
    show defaultMathVariantForCodePoint;
import 'package:tex_math/src/parser/symbol_map.dart';
import 'package:tex_math/src/shared/math_symbols.dart'
    show boldSymbolVariantFor;
import 'package:tex_math/tex_math.dart';

Uint8List _readBundledMathFontBytes() {
  for (final String candidate in const <String>[
    '../tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
    'packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
  ]) {
    final File file = File(candidate);
    if (file.existsSync()) {
      return file.readAsBytesSync();
    }
  }
  throw StateError('Unable to locate bundled NewCMMath-Regular.otf fixture.');
}

void main() {
  late MathFont bundledFont;

  setUpAll(() {
    bundledFont = MathFont.fromBytes(_readBundledMathFontBytes());
  });

  group('Architecture & Package Invariants', () {
    test('ARCH-1/SEC-4: MatrixNode.columnSeparators stores pre-parsed ASTs and '
        'expands colSpec stars safely', () {
      final MathRootNode root =
          parseTex(
                r'\def\sep{\times}\begin{array}{c@{\sep}c!{|}c}a&b&c\end{array}',
              )
              as MathRootNode;
      final MatrixNode array = root.children.single as MatrixNode;
      expect(array.columnSeparators[1], isA<MathNode>());
      expect(mathNodeToSpokenText(array.columnSeparators[1]!), 'times');
      expect(array.columnSeparators[2], isA<MathNode>());

      // Empty or zero-count star repetition skips cleanly instead of looping.
      final MathNode emptyStar = parseTex(
        r'\begin{array}{*{5}{}c*{0}{r}}a\end{array}',
      );
      expect(emptyStar, isA<MathRootNode>());

      // Repeat count > 256 caps cleanly and nested *{...} depth > maxNestingDepth throws.
      final MathRootNode cappedRoot =
          parseTex(r'\begin{array}{*{300}{c}}a\end{array}') as MathRootNode;
      final MatrixNode cappedArray = cappedRoot.children.single as MatrixNode;
      expect(cappedArray.columnAlignments.length, lessThanOrEqualTo(256));
      expect(
        () => parseTex(
          r'\begin{array}{*{1}{*{1}{*{1}{c}}}}a\end{array}',
          options: const TexMathOptions(
            budgets: TexMathBudgets(maxNestingDepth: 2),
          ),
        ),
        throwsA(isA<TexMathBudgetError>()),
      );
    });

    test(
      'ARCH-2: Rule 12 accentBaseHeight/flattenedAccentBaseHeight & xHeight ex',
      () {
        // Verify flattenedAccentBaseHeight fallback when accentBaseHeight == 0,
        // and custom OS/2 xHeight for \bbox[1ex].
        final Uint8List customFontBytes = _buildMinimalTrueTypeFont(
          accentBaseHeight: 0,
          flattenedAccentBaseHeight: 600,
          xHeight: 550,
          topLeftKernHeightCut: 400,
          topLeftKernBefore: 180,
          topLeftKernAtTop: 0,
        );
        final MathFont customFont = MathFont.fromBytes(customFontBytes);
        final TexMathEngine engine = TexMathEngine(font: customFont);

        final RenderResult bboxRes = engine.render(r'\bbox[1ex]{x}');
        final GlyphItem glyph = bboxRes.displayList.items
            .whereType<GlyphItem>()
            .firstWhere((GlyphItem g) => g.codePoint != 0);
        expect(glyph.xEm, closeTo(0.55, 1e-4));

        // Base 'A' height (700 units = 0.7em) > flattenedAccentBaseHeight (0.6em),
        // so accent shifts up by 0.7 - 0.6 = 0.1em.
        final RenderResult accRes = engine.render(r'\hat{A}');
        final List<GlyphItem> accGlyphs = accRes.displayList.items
            .whereType<GlyphItem>()
            .toList();
        expect(accGlyphs[1].yEm, closeTo(0.1, 1e-4));

        // Prescript topLeft kern evaluates top-corner formula: at low corner
        // (< 900), topLeft adds -0.18em kerning between prescript and base.
        final MathFont unkernedFont = MathFont.fromBytes(
          _buildMinimalTrueTypeFont(
            accentBaseHeight: 0,
            flattenedAccentBaseHeight: 600,
            xHeight: 550,
          ),
        );
        final RenderResult preUnkerned = TexMathEngine(
          font: unkernedFont,
        ).render(r'\prescript{p}{}{x}');
        final RenderResult preKerned = engine.render(r'\prescript{p}{}{x}');
        expect(
          preKerned.displayList.metrics.widthEm,
          closeTo(preUnkerned.displayList.metrics.widthEm - 0.18, 1e-4),
        );
      },
    );

    test('ARCH-8(b): physics & units AST builders preserve spans and caps', () {
      const TexMathOptions physicsOpts = TexMathOptions(
        packages: <String>[
          ...TexMathOptions.defaultPackages,
          'physics',
          'units',
        ],
      );
      final MathRootNode tree =
          parseTex(
                r'\dmat{1,2} + \imat{2} + \units{9.8}{m/s^2}',
                options: physicsOpts,
              )
              as MathRootNode;
      expect(tree.children, isNotEmpty);
      expect(
        () => parseTex(r'\imat{100}', options: physicsOpts),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(r'\xmat{a}{100}{100}', options: physicsOpts),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(r'\zmat{100}{100}', options: physicsOpts),
        throwsA(isA<TexMathBudgetError>()),
      );
    });
  });

  group('Dart Invariants, Value Semantics & Signatures', () {
    test(
      'DF-7(c)/DF-10/DF-11/ARCH-6: equality, signatures, and immutability',
      () {
        final MathFont sameFont = MathFont.fromBytes(
          _readBundledMathFontBytes(),
        );
        final MathFont otherFont = MathFont.fromBytes(
          _buildMinimalTrueTypeFont(xHeight: 400),
        );
        expect(bundledFont.signature, sameFont.signature);
        expect(bundledFont, equals(sameFont));
        expect(bundledFont.hashCode, equals(sameFont.hashCode));
        expect(bundledFont == otherFont, isFalse);
        expect(bundledFont.signature == otherFont.signature, isFalse);

        final TexMathEngine engineA = TexMathEngine(font: bundledFont);
        final TexMathEngine engineB = TexMathEngine(font: sameFont);
        final TexMathEngine engineC = TexMathEngine(font: otherFont);
        expect(engineA, equals(engineB));
        expect(engineA.hashCode, equals(engineB.hashCode));
        expect(engineA == engineC, isFalse);

        final RenderResult renderResult = engineA.render('x + y');
        expect(renderResult.displayList.fontSignature, bundledFont.signature);

        // AST collections are unmodifiable even when constructed with mutable args.
        final SymbolNode sym = const SymbolNode(
          span: SourceSpan.zero,
          value: 'x',
        );
        final MathRootNode mutableRoot = MathRootNode(
          span: SourceSpan.zero,
          children: <MathNode>[sym],
          labels: <String, String>{'eq:1': '1'},
        );
        expect(() => mutableRoot.children.add(sym), throwsUnsupportedError);
        expect(() => mutableRoot.labels['a'] = '2', throwsUnsupportedError);

        final MatrixNode mutableMatrix = MatrixNode(
          span: SourceSpan.zero,
          environment: 'pmatrix',
          rows: <List<MathNode>>[
            <MathNode>[sym],
          ],
          columnAlignments: <String>['c'],
          rowLines: <int, String>{0: 'solid'},
          columnLines: <int, String>{0: 'solid'},
          columnSeparators: <int, MathNode>{0: sym},
          rowTags: <int, TagNode>{
            0: const TagNode(span: SourceSpan.zero, label: '1'),
          },
        );
        expect(
          () => mutableMatrix.rows.add(<MathNode>[sym]),
          throwsUnsupportedError,
        );
        expect(() => mutableMatrix.rows[0].add(sym), throwsUnsupportedError);
        expect(
          () => mutableMatrix.columnAlignments.add('r'),
          throwsUnsupportedError,
        );
        expect(
          () => mutableMatrix.columnSeparators[1] = sym,
          throwsUnsupportedError,
        );

        final TexMathOptions opts = TexMathOptions(
          packages: <String>['base'],
          requireAllowlist: <String>['physics'],
          macros: <String, String>{'foo': 'x'},
        );
        expect(() => opts.packages.add('ams'), throwsUnsupportedError);
        expect(() => opts.requireAllowlist.add('verb'), throwsUnsupportedError);
        expect(() => opts.macros['bar'] = 'y', throwsUnsupportedError);

        final GlyphOutline outline = GlyphOutline(
          glyphId: 1,
          commands: <PathCommand>[const MoveTo(0, 0), const ClosePath()],
        );
        expect(
          () => outline.commands.add(const ClosePath()),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'DF-17: value equality on MathBox, MathConstants, and registry types',
      () {
        const KernBox k1 = KernBox(widthEm: 0.5);
        const KernBox k2 = KernBox(widthEm: 0.5);
        const KernBox k3 = KernBox(widthEm: 0.25);
        expect(k1, equals(k2));
        expect(k1.hashCode, equals(k2.hashCode));
        expect(k1 == k3, isFalse);

        final HBox h1 = HBox(children: const <MathBox>[k1]);
        final HBox h2 = HBox(children: const <MathBox>[k2]);
        expect(h1, equals(h2));
        expect(h1.hashCode, equals(h2.hashCode));

        const VBoxChild vc1 = VBoxChild(box: k1, xEm: 1.0, yEm: 2.0);
        const VBoxChild vc2 = VBoxChild(box: k2, xEm: 1.0, yEm: 2.0);
        expect(vc1, equals(vc2));
        expect(vc1.hashCode, equals(vc2.hashCode));

        expect(
          bundledFont.mathTable!.constants,
          equals(bundledFont.mathTable!.constants),
        );
        expect(
          TexPackageRegistry.byName['base'],
          equals(TexPackageRegistry.byName['base']),
        );
        expect(baseSymbolMap['alpha'], equals(baseSymbolMap['alpha']));

        // ColorNode delegates leading atom class (no ApplyFunction before '=').
        final TexMathEngine engine = TexMathEngine(font: bundledFont);
        final RenderResult sinEqColor = engine.render(r'\sin \color{red}=');
        expect(
          sinEqColor.displayList.items.whereType<GlyphItem>().any(
            (GlyphItem g) => g.codePoint == 0x2061,
          ),
          isFalse,
        );
      },
    );
  });

  group('Performance & Streaming Exporters', () {
    test(
      'PERF-6/9/10: assembly O(1), hinted cache, SVG budget & streaming export',
      () {
        final TexMathEngine engine = TexMathEngine(font: bundledFont);
        // Stretchy assembly solver handles large target heights cleanly.
        final RenderResult tall = engine.render(
          r'\left(\begin{matrix}a\\b\\c\\d\\e\\f\end{matrix}\right)',
        );
        expect(tall.displayList.metrics.heightEm, greaterThan(3.0));

        // Per-ppem hinted outline cache returns distinct outlines cleanly.
        final int gid = bundledFont.glyphIdForCodePoint(0x0041);
        final GlyphOutline? h1 = bundledFont.outlineForGlyph(
          gid,
          ppem: 12.0,
          enableHinting: true,
        );
        final GlyphOutline? h2 = bundledFont.outlineForGlyph(
          gid,
          ppem: 24.0,
          enableHinting: true,
        );
        final GlyphOutline? h1Again = bundledFont.outlineForGlyph(
          gid,
          ppem: 12.0,
          enableHinting: true,
        );
        expect(h1, isNotNull);
        expect(h2, isNotNull);
        expect(identical(h1, h1Again), isTrue);

        // Incremental maxSvgLength check throws before materializing huge SVG.
        expect(
          () => tall.toSvg(maxSvgLength: 50),
          throwsA(isA<TexMathBudgetError>()),
        );

        // Streaming MathML and spoken text retain exact formatting.
        final MathNode expr = parseTex(
          r'x^2 + y^3 + x^\prime + \sqrt[3]{z} + \begin{pmatrix}1&2\\3&4\end{pmatrix}',
        );
        expect(mathNodeToMathMl(expr), contains('<msup>'));
        final String spoken = mathNodeToSpokenText(expr);
        expect(spoken, contains('x squared'));
        expect(spoken, contains('y cubed'));
        expect(spoken, contains('x prime'));
        expect(spoken, contains('cube root of z'));
        expect(spoken, contains('2 by 2 matrix'));
      },
    );
  });

  group('Security Hardening (SEC-2 through SEC-11)', () {
    test(
      'SEC-2: defeats cumulative token bombs across macros, edef & subtokens',
      () {
        // Nested exponential expansion under custom maxTokens.
        expect(
          () => parseTex(
            r'\def\a{xx}\def\b{\a\a}\def\c{\b\b}\def\d{\c\c}\d\d\d\d',
            options: const TexMathOptions(
              budgets: TexMathBudgets(maxTokens: 20),
            ),
          ),
          throwsA(isA<TexMathBudgetError>()),
        );

        // Exponential growth inside \edef body enforces shared maxTokens budget.
        expect(
          () => parseTex(
            r'\def\a{xxxxxxxx}\edef\b{\a\a\a\a\a}\b',
            options: const TexMathOptions(
              budgets: TexMathBudgets(maxTokens: 25),
            ),
          ),
          throwsA(isA<TexMathBudgetError>()),
        );

        // Macro bomb inside array @{...} separator shares budget.
        expect(
          () => parseTex(
            r'\def\a{xxxxxx}\begin{array}{c@{\a\a\a\a}c}1&2\end{array}',
            options: const TexMathOptions(
              budgets: TexMathBudgets(maxTokens: 15),
            ),
          ),
          throwsA(isA<TexMathBudgetError>()),
        );
      },
    );

    test('SEC-6: bounds all 5 unchecked recursion paths and export depth', () {
      const TexMathOptions shallow = TexMathOptions(
        budgets: TexMathBudgets(maxNestingDepth: 4),
      );
      expect(
        () => parseTex(
          r'\color{red}a\color{blue}b\color{green}c\color{black}d\color{red}e',
          options: shallow,
        ),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(r'\not\not\not\not\not =', options: shallow),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(r'\frac1\frac1\frac1\frac1\frac1 a', options: shallow),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(
          r'\text{\textbf{\textit{\textsf{\texttt{\textrm{x}}}}}}',
          options: shallow,
        ),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => parseTex(r'\ce{{{{{{H2O}}}}}}', options: shallow),
        throwsA(isA<TexMathBudgetError>()),
      );

      // Deep expressions rejected across parse(), toMathMl(), and toSpokenText().
      const String deepTex = '{{{{{{{{x}}}}}}}}';
      final TexMathEngine shallowEngine = TexMathEngine(
        font: bundledFont,
        defaultOptions: shallow,
      );
      expect(
        () => shallowEngine.parse(deepTex),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => shallowEngine.toMathMl(deepTex),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => shallowEngine.toSpokenText(deepTex),
        throwsA(isA<TexMathBudgetError>()),
      );
    });

    test(
      'SEC-7/8/10: rejects malformed binary coverage, cycles, and NaN/Inf',
      () {
        // Overlapping Format 2 Coverage ranges fail with TexMathFontError.
        final BytesBuilder covBytes = BytesBuilder()
          ..add(const <int>[0, 2, 0, 2]) // Format 2, 2 ranges
          ..add(const <int>[0, 1, 0, 5, 0, 0]) // [1, 5]
          ..add(const <int>[0, 5, 0, 8, 0, 5]); // [5, 8] overlaps 5!
        expect(
          () => CoverageTable.parse(
            FontByteReader(covBytes.toBytes()),
            0,
            'TestCov',
          ),
          throwsA(isA<TexMathFontError>()),
        );

        // regionIndexCount == 0 in ItemVariationStore short-circuits cleanly.
        final BytesBuilder ivsBytes = BytesBuilder()
          ..add(const <int>[
            0, 1, // format = 1
            0, 0, 0, 12, // regionListOffset = 12
            0, 1, // itemVariationDataCount = 1
            0, 0, 0, 16, // dataOffset[0] = 16
            // regionList at 12: axisCount=1, regionCount=0
            0, 1, 0, 0,
            // ItemVariationData at 16: itemCount=50000, wordDeltaCount=0, regionIndexCount=0
            0xC3, 0x50, 0, 0, 0, 0,
          ]);
        final ItemVariationStore ivs = ItemVariationStore.parse(
          FontByteReader(ivsBytes.toBytes()),
          0,
          <double>[0.5],
        );
        expect(ivs.deltaFor(0, 0), 0.0);

        // Composite glyf self-cycle / excessive DAG throws TexMathFontError.
        final Uint8List cyclicGlyfFont = _buildCyclicCompositeTrueTypeFont();
        final MathFont cycFont = MathFont.fromBytes(cyclicGlyfFont);
        expect(
          () => cycFont.outlineForGlyph(1),
          throwsA(isA<TexMathFontError>()),
        );

        // Type 2 divide-by-zero producing non-finite stack value throws.
        final Uint8List nanCffFont = _buildNanType2CffFont();
        final MathFont cffFont = MathFont.fromBytes(nanCffFont);
        expect(
          () => cffFont.outlineForGlyph(1),
          throwsA(isA<TexMathFontError>()),
        );
      },
    );

    test('SEC-9/10/11: sanitizes URIs, colors, CSS/RGB numbers, and XML 1.0', () {
      // Safe href URIs succeed; unsafe schemes are rejected.
      final MathNode safeHref = parseTex(r'\href{https://example.org}{x}');
      expect(
        mathNodeToMathMl(safeHref),
        contains('href="https://example.org"'),
      );
      expect(
        () => parseTex(r'\href{javascript:alert(1)}{x}'),
        throwsA(isA<TexMathSyntaxError>()),
      );
      expect(
        () => parseTex(r'\href{data:text/html,<script>}{x}'),
        throwsA(isA<TexMathSyntaxError>()),
      );
      expect(
        () => parseTex(r'\href{vbscript:msgbox(1)}{x}'),
        throwsA(isA<TexMathSyntaxError>()),
      );

      // Direct AST with unsafe href or crafted MathML color strips attributes.
      const MathGroupNode badHrefAst = MathGroupNode(
        span: SourceSpan.zero,
        role: 'href',
        attributes: <String, String>{'href': 'javascript:evil()'},
        children: <MathNode>[SymbolNode(span: SourceSpan.zero, value: 'x')],
      );
      expect(mathNodeToMathMl(badHrefAst), isNot(contains('javascript:')));

      const ColorNode badColorAst = ColorNode(
        span: SourceSpan.zero,
        role: TexMathColorRole.custom,
        colorValue: 'red" onclick="alert(1)',
        children: <MathNode>[SymbolNode(span: SourceSpan.zero, value: 'x')],
      );
      expect(mathNodeToMathMl(badColorAst), isNot(contains('onclick')));

      // Non-finite RGB / overflowing CSS lengths throw syntax errors.
      expect(
        () => parseTex(r'\color[rgb]{NaN,0,0} x'),
        throwsA(isA<TexMathSyntaxError>()),
      );
      final TexMathEngine engine = TexMathEngine(font: bundledFont);
      expect(
        () => engine.render('\\bbox[${'9' * 400}em]{x}'),
        throwsA(isA<TexMathSyntaxError>()),
      );

      // XML 1.0 disallowed control characters and lone surrogates are stripped
      // across MathML and SVG exporters.
      final SymbolNode dirtyText = SymbolNode(
        span: SourceSpan.zero,
        value: 'a\u0000\u0008\uD800b',
      );
      final String ml = mathNodeToMathMl(dirtyText);
      expect(ml, contains('<mi>ab</mi>'));
      expect(ml.codeUnits, isNot(contains(0)));
      expect(ml.codeUnits, isNot(contains(8)));
      expect(ml.codeUnits, isNot(contains(0xD800)));

      // \unicode{0} rejected cleanly as disallowed XML scalar.
      expect(
        () => parseTex(r'\unicode{0}'),
        throwsA(isA<TexMathSyntaxError>()),
      );
    });

    test(
      'AUDIT: boldsymbol scoping, boldSymbolVariantFor, texhtml tag stack, and \\style safety',
      () {
        // Re-exported defaultMathVariantForCodePoint and boldSymbolVariantFor contract.
        expect(defaultMathVariantForCodePoint(0x45), TexMathFontVariant.italic);
        expect(defaultMathVariantForCodePoint(0x03A3), isNull);
        expect(
          boldSymbolVariantFor(TexMathFontVariant.normal, 0x2207),
          TexMathFontVariant.bold,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.italic, 0x45),
          TexMathFontVariant.boldItalic,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.script, 0x41),
          TexMathFontVariant.boldScript,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.fraktur, 0x41),
          TexMathFontVariant.boldFraktur,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.sansSerif, 0x41),
          TexMathFontVariant.boldSansSerif,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.sansSerifItalic, 0x41),
          TexMathFontVariant.sansSerifBoldItalic,
        );
        expect(
          boldSymbolVariantFor(TexMathFontVariant.doubleStruck, 0x52),
          TexMathFontVariant.doubleStruckBold,
        );

        final TexMathEngine engine = TexMathEngine(font: bundledFont);

        // \boldsymbol scope does not leak past its brace argument.
        final List<int> scopedCps = engine
            .render(r'{\boldsymbol{x}} y')
            .displayList
            .items
            .whereType<GlyphItem>()
            .map((GlyphItem g) => g.codePoint)
            .toList();
        expect(scopedCps, <int>[0x1D499, 0x1D466]);

        // Malformed/unknown/empty <tex-html> tags never drop text or emit empty runs.
        const TexMathOptions htmlOpts = TexMathOptions(
          packages: <String>['base', 'html', 'texhtml'],
        );
        final MathGroupNode emptyHtml =
            (parseTex('<tex-html><em></em></tex-html>', options: htmlOpts)
                        as MathRootNode)
                    .children
                    .single
                as MathGroupNode;
        expect(emptyHtml.children, hasLength(1));
        final TextNode emptyText = emptyHtml.children.single as TextNode;
        expect(emptyText.text, isEmpty);
        expect(emptyText.styleCommand, 'text');

        final List<int> unknownWrapped = engine
            .render(
              '<tex-html><em>a<span>b</span>c</em></tex-html>',
              options: htmlOpts,
            )
            .displayList
            .items
            .whereType<GlyphItem>()
            .map((GlyphItem g) => g.codePoint)
            .toList();
        expect(unknownWrapped, <int>[0x1D44E, 0x1D44F, 0x1D450]);

        // Invalid/unsafe CSS values in \style are ignored cleanly.
        final DisplayList badStyleDl = engine
            .render(
              r'\style{color: notacolor; background-color: url(evil)}{x}',
              options: htmlOpts,
            )
            .displayList;
        expect(badStyleDl.items.whereType<RuleItem>(), isEmpty);
        final GlyphItem badStyleGlyph = badStyleDl.items
            .whereType<GlyphItem>()
            .single;
        expect(badStyleGlyph.colorRole, TexMathColorRole.foreground);
        expect(badStyleGlyph.customColor, isNull);
      },
    );
  });
}

Uint8List _buildMinimalTrueTypeFont({
  int xHeight = 431,
  int accentBaseHeight = 450,
  int flattenedAccentBaseHeight = 664,
  int topLeftKernHeightCut = 0,
  int topLeftKernBefore = 0,
  int topLeftKernAtTop = 0,
}) {
  // Glyph 0: .notdef, Glyph 1: 'A', Glyph 2: 'x', Glyph 3: '^', Glyph 4: 'p'.
  const int numGlyphs = 5;
  final _Bin head = _Bin()
    ..u32(0x00010000)
    ..u32(0x00010000)
    ..u32(0)
    ..u32(0x5F0F3CF5)
    ..u16(0)
    ..u16(1000)
    ..zero(16)
    ..i16(-100)
    ..i16(-200)
    ..i16(800)
    ..i16(900)
    ..u16(0)
    ..u16(8)
    ..i16(2)
    ..i16(0)
    ..i16(0);

  final _Bin hhea = _Bin()
    ..u32(0x00010000)
    ..i16(800)
    ..i16(-200)
    ..i16(200)
    ..u16(800)
    ..zero(22)
    ..u16(numGlyphs);

  final _Bin maxp = _Bin()
    ..u32(0x00010000)
    ..u16(numGlyphs)
    ..zero(26);

  final _Bin hmtx = _Bin()
    ..u16(500)
    ..i16(0)
    ..u16(750)
    ..i16(50)
    ..u16(572)
    ..i16(20)
    ..u16(500)
    ..i16(100)
    ..u16(500)
    ..i16(20);

  final _Bin os2 = _Bin()
    ..u16(2)
    ..zero(84)
    ..i16(xHeight)
    ..i16(700)
    ..zero(6);

  final _Bin glyf = _Bin();
  final List<int> locaOffsets = <int>[];
  void addSimpleRectGlyph(int xMin, int yMin, int xMax, int yMax) {
    locaOffsets.add(glyf.length ~/ 2);
    glyf
      ..i16(1)
      ..i16(xMin)
      ..i16(yMin)
      ..i16(xMax)
      ..i16(yMax)
      ..u16(2)
      ..u16(0)
      ..u8(0x01)
      ..u8(0x01)
      ..u8(0x01)
      ..i16(xMin)
      ..i16(xMax - xMin)
      ..i16(0)
      ..i16(yMin)
      ..i16(0)
      ..i16(yMax - yMin);
    while (glyf.length % 2 != 0) {
      glyf.u8(0);
    }
  }

  addSimpleRectGlyph(0, 0, 400, 500);
  addSimpleRectGlyph(50, 0, 700, 700);
  addSimpleRectGlyph(20, 0, 550, 442);
  addSimpleRectGlyph(100, 516, 400, 692);
  addSimpleRectGlyph(20, -200, 480, 442);
  locaOffsets.add(glyf.length ~/ 2);

  final _Bin loca = _Bin();
  for (final int off in locaOffsets) {
    loca.u16(off);
  }

  final List<({int cp, int gid})> mappings = <({int cp, int gid})>[
    (cp: 0x0041, gid: 1),
    (cp: 0x0070, gid: 4),
    (cp: 0x0078, gid: 2),
    (cp: 0x02C6, gid: 3),
    (cp: 0x1D434, gid: 1),
    (cp: 0x1D45D, gid: 4),
    (cp: 0x1D465, gid: 2),
  ];
  final _Bin cmap = _Bin()
    ..u16(0)
    ..u16(1)
    ..u16(3)
    ..u16(10)
    ..u32(12)
    ..u16(12)
    ..u16(0)
    ..u32(16 + mappings.length * 12)
    ..u32(0)
    ..u32(mappings.length);
  for (final ({int cp, int gid}) m in mappings) {
    cmap
      ..u32(m.cp)
      ..u32(m.cp)
      ..u32(m.gid);
  }

  final _Bin constants = _Bin()
    ..i16(70)
    ..i16(50)
    ..u16(1000)
    ..u16(1300);
  for (int i = 0; i < 51; i++) {
    int val = 0;
    if (i == 1) val = 250;
    if (i == 2) val = accentBaseHeight;
    if (i == 3) val = flattenedAccentBaseHeight;
    if (i == 34) val = 40;
    if (i == 39) val = 120;
    if (i == 42) val = 120;
    constants
      ..i16(val)
      ..u16(0);
  }
  constants.i16(60);

  // GlyphInfo (at offset 224) with MathKern for gid 2 ('x'):
  // Header is 8 bytes; MathKernInfo starts at GI+8, and its internal offsets
  // are relative to MathKernInfo.
  final _Bin cleanGi = _Bin()
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u16(8)
    // MathKernInfo at GI+8:
    ..u16(12) // Coverage Format 1 at KI+12 (= GI+20)
    ..u16(1) // 1 glyph
    ..u16(0) // topRight
    ..u16(18) // topLeft MathKern at KI+18 (= GI+26)
    ..u16(0) // bottomRight
    ..u16(0) // bottomLeft
    // KI+12 (6 bytes): Coverage Format 1 for gid 2 ('x'):
    ..u16(1)
    ..u16(1)
    ..u16(2)
    // KI+18: MathKern with 1 height cut:
    ..u16(1) // heightCount = 1
    ..i16(topLeftKernHeightCut)
    ..u16(0)
    ..i16(topLeftKernBefore)
    ..u16(0)
    ..i16(topLeftKernAtTop)
    ..u16(0);

  final _Bin variants = _Bin()
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u16(0);

  const int constOff = 10;
  final int giOff = constOff + constants.length;
  final int varOff = giOff + cleanGi.length;
  final _Bin mathTbl = _Bin()
    ..u32(0x00010000)
    ..u16(constOff)
    ..u16(giOff)
    ..u16(varOff)
    ..add(constants)
    ..add(cleanGi)
    ..add(variants);

  return _assembleSfnt(0x00010000, <String, Uint8List>{
    'MATH': mathTbl.toBytes(),
    'OS/2': os2.toBytes(),
    'cmap': cmap.toBytes(),
    'glyf': glyf.toBytes(),
    'head': head.toBytes(),
    'hhea': hhea.toBytes(),
    'hmtx': hmtx.toBytes(),
    'loca': loca.toBytes(),
    'maxp': maxp.toBytes(),
  });
}

Uint8List _buildCyclicCompositeTrueTypeFont() {
  final _Bin head = _Bin()
    ..u32(0x00010000)
    ..u32(0x00010000)
    ..u32(0)
    ..u32(0x5F0F3CF5)
    ..u16(0)
    ..u16(1000)
    ..zero(16)
    ..i16(0)
    ..i16(0)
    ..i16(500)
    ..i16(500)
    ..u16(0)
    ..u16(8)
    ..i16(2)
    ..i16(0)
    ..i16(0);
  final _Bin hhea = _Bin()
    ..u32(0x00010000)
    ..i16(800)
    ..i16(-200)
    ..i16(0)
    ..u16(500)
    ..zero(22)
    ..u16(2);
  final _Bin maxp = _Bin()
    ..u32(0x00010000)
    ..u16(2)
    ..zero(26);
  final _Bin hmtx = _Bin()
    ..u16(500)
    ..i16(0)
    ..u16(500)
    ..i16(0);
  // Glyph 0: empty. Glyph 1: composite (numberOfContours=-1) pointing to gid 1!
  final _Bin glyf = _Bin()
    ..i16(-1) // numberOfContours < 0 -> composite
    ..i16(0)
    ..i16(0)
    ..i16(500)
    ..i16(500)
    ..u16(0x0002) // ARGS_ARE_XY_VALUES (byte offsets, no more components)
    ..u16(1) // child glyphIndex = 1 (self cycle!)
    ..i8(0)
    ..i8(0);
  final _Bin loca = _Bin()
    ..u16(0)
    ..u16(0) // gid 1 starts at 0
    ..u16(glyf.length ~/ 2);
  final _Bin cmap = _Bin()
    ..u16(0)
    ..u16(1)
    ..u16(3)
    ..u16(10)
    ..u32(12)
    ..u16(12)
    ..u16(0)
    ..u32(28)
    ..u32(0)
    ..u32(1)
    ..u32(0x41)
    ..u32(0x41)
    ..u32(1);
  return _assembleSfnt(0x00010000, <String, Uint8List>{
    'cmap': cmap.toBytes(),
    'glyf': glyf.toBytes(),
    'head': head.toBytes(),
    'hhea': hhea.toBytes(),
    'hmtx': hmtx.toBytes(),
    'loca': loca.toBytes(),
    'maxp': maxp.toBytes(),
  });
}

Uint8List _buildNanType2CffFont() {
  final _Bin head = _Bin()
    ..u32(0x00010000)
    ..u32(0x00010000)
    ..u32(0)
    ..u32(0x5F0F3CF5)
    ..u16(0)
    ..u16(1000)
    ..zero(16)
    ..i16(0)
    ..i16(0)
    ..i16(500)
    ..i16(500)
    ..u16(0)
    ..u16(8)
    ..i16(2)
    ..i16(0)
    ..i16(0);
  final _Bin hhea = _Bin()
    ..u32(0x00010000)
    ..i16(800)
    ..i16(-200)
    ..i16(0)
    ..u16(500)
    ..zero(22)
    ..u16(2);
  final _Bin maxp = _Bin()
    ..u32(0x00005000)
    ..u16(2);
  final _Bin hmtx = _Bin()
    ..u16(500)
    ..i16(0)
    ..u16(500)
    ..i16(0);
  final _Bin cmap = _Bin()
    ..u16(0)
    ..u16(1)
    ..u16(3)
    ..u16(10)
    ..u32(12)
    ..u16(12)
    ..u16(0)
    ..u32(28)
    ..u32(0)
    ..u32(1)
    ..u32(0x41)
    ..u32(0x41)
    ..u32(1);

  // Build CFF v1: header + Name INDEX + Top DICT INDEX + String INDEX +
  // Global Subr INDEX + CharStrings INDEX + Private DICT (0).
  // gid 0 charstring: endchar (14).
  // gid 1 charstring: 1 0 div (12, 12) 0 rmoveto (21) endchar (14) -> NaN/Inf!
  // Type 2 int x encoded as 139 + x.
  final Uint8List cs0 = Uint8List.fromList(<int>[14]);
  final Uint8List cs1 = Uint8List.fromList(<int>[
    255, 0x7F, 0xFF, 0xFF, 0xFF, // fixed 32767.99998
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    12, 27, 12, 24, // dup, mul
    139, 21, 14, // 0 rmoveto endchar
  ]);
  final Uint8List csIndex = _cffIndex(<Uint8List>[cs0, cs1]);
  final Uint8List nameIndex = _cffIndex(<Uint8List>[
    Uint8List.fromList('TestFont'.codeUnits),
  ]);
  final Uint8List stringIndex = _cffIndex(const <Uint8List>[]);
  final Uint8List gsubrIndex = _cffIndex(const <Uint8List>[]);

  // Placeholder Top DICT with charStrings offset: encode using 5-byte int (29 + i32) + op 17.
  int csOff =
      4 + nameIndex.length + 12 + stringIndex.length + gsubrIndex.length;
  // Wait compute exact TopDICT INDEX size first: 1 item of 6 bytes -> INDEX header 2+1+2 + 6 = 11 bytes.
  final _Bin dummyTop = _Bin()
    ..u8(29)
    ..i32(0)
    ..u8(17); // CharStrings offset
  final int topIndexLen = _cffIndex(<Uint8List>[dummyTop.toBytes()]).length;
  csOff =
      4 +
      nameIndex.length +
      topIndexLen +
      stringIndex.length +
      gsubrIndex.length;
  final _Bin topDict = _Bin()
    ..u8(29)
    ..i32(csOff)
    ..u8(17);
  final Uint8List topIndex = _cffIndex(<Uint8List>[topDict.toBytes()]);

  final _Bin cff = _Bin()
    ..u8(1)
    ..u8(0)
    ..u8(4)
    ..u8(1)
    ..addBytes(nameIndex)
    ..addBytes(topIndex)
    ..addBytes(stringIndex)
    ..addBytes(gsubrIndex)
    ..addBytes(csIndex);

  return _assembleSfnt(0x4F54544F, <String, Uint8List>{
    'CFF ': cff.toBytes(),
    'cmap': cmap.toBytes(),
    'head': head.toBytes(),
    'hhea': hhea.toBytes(),
    'hmtx': hmtx.toBytes(),
    'maxp': maxp.toBytes(),
  });
}

Uint8List _cffIndex(List<Uint8List> items) {
  final _Bin out = _Bin()..u16(items.length);
  if (items.isEmpty) {
    return out.toBytes();
  }
  out.u8(2); // offSize = 2
  int off = 1;
  out.u16(off);
  for (final Uint8List item in items) {
    off += item.length;
    out.u16(off);
  }
  for (final Uint8List item in items) {
    out.addBytes(item);
  }
  return out.toBytes();
}

Uint8List _assembleSfnt(int sfntTag, Map<String, Uint8List> tables) {
  final List<String> tags = tables.keys.toList()..sort();
  final _Bin out = _Bin()
    ..u32(sfntTag)
    ..u16(tags.length)
    ..u16(0)
    ..u16(0)
    ..u16(0);
  int dataOffset = 12 + tags.length * 16;
  final List<({String tag, int offset, Uint8List data})> placed =
      <({String tag, int offset, Uint8List data})>[];
  for (final String tag in tags) {
    final Uint8List data = tables[tag]!;
    placed.add((tag: tag, offset: dataOffset, data: data));
    dataOffset += (data.length + 3) & ~3;
  }
  for (final ({String tag, int offset, Uint8List data}) entry in placed) {
    out
      ..addBytes(Uint8List.fromList(entry.tag.codeUnits))
      ..u32(0)
      ..u32(entry.offset)
      ..u32(entry.data.length);
  }
  for (final ({String tag, int offset, Uint8List data}) entry in placed) {
    out.addBytes(entry.data);
    while (out.length % 4 != 0) {
      out.u8(0);
    }
  }
  return out.toBytes();
}

final class _Bin {
  final BytesBuilder _b = BytesBuilder();

  int get length => _b.length;

  void u8(int v) => _b.addByte(v & 0xFF);
  void i8(int v) => _b.addByte(v & 0xFF);
  void u16(int v) {
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void i16(int v) => u16(v);
  void u32(int v) {
    _b.addByte((v >> 24) & 0xFF);
    _b.addByte((v >> 16) & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void i32(int v) => u32(v);
  void zero(int count) {
    for (int i = 0; i < count; i++) {
      _b.addByte(0);
    }
  }

  void add(_Bin other) => _b.add(other.toBytes());
  void addBytes(Uint8List bytes) => _b.add(bytes);
  Uint8List toBytes() => _b.toBytes();
}
