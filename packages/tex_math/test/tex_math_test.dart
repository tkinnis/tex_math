import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  group('SourceSpan', () {
    test('slices source strings and computes length', () {
      const String source = r'\frac{a}{b}';
      const SourceSpan span = SourceSpan(6, 7);
      expect(span.length, 1);
      expect(span.isEmpty, isFalse);
      expect(span.slice(source), 'a');
      expect(SourceSpan.zero.isEmpty, isTrue);
    });

    test('merges spans and implements value equality', () {
      const SourceSpan a = SourceSpan(2, 5);
      const SourceSpan b = SourceSpan(4, 9);
      expect(a.merge(b), const SourceSpan(2, 9));
      expect(b.merge(a), const SourceSpan(2, 9));
      expect(const SourceSpan(2, 5), equals(a));
      expect(const SourceSpan(2, 5).hashCode, equals(a.hashCode));
    });
  });

  group('TexMathBudgets and TexMathOptions', () {
    test('provides documented defaults and requireAllowlist', () {
      const TexMathBudgets budgets = TexMathBudgets();
      expect(budgets.maxInputLength, 50000);
      expect(budgets.maxMacroDepth, 64);
      expect(budgets.maxMacroExpansions, 10000);
      expect(budgets.maxNestingDepth, 64);
      expect(budgets.maxOutputItems, 50000);
      expect(budgets.maxSvgLength, 4000000);

      const TexMathOptions options = TexMathOptions();
      expect(options.displayMode, TexMathDisplayMode.display);
      expect(options.packages, contains('base'));
      expect(options.packages, contains('ams'));
      expect(options.packages, isNot(contains('noerrors')));
      expect(options.packages, isNot(contains('noundefined')));
      expect(options.requireAllowlist, contains('physics'));
      expect(options.requireAllowlist, isNot(contains('setoptions')));
      expect(options.macros, isEmpty);
      expect(options.strictErrors, isTrue);
      expect(options.multlineWidthEm, isNull);
      expect(options.tagMode, TexMathTagMode.none);
      expect(TexPackageRegistry.all, hasLength(42));
      expect(TexMathTagMode.values, <TexMathTagMode>[
        TexMathTagMode.none,
        TexMathTagMode.ams,
        TexMathTagMode.all,
      ]);
    });

    test(
      'supports copyWith, equality, toString, and assertions on new fields',
      () {
        const TexMathOptions base = TexMathOptions();
        final TexMathOptions updated = base.copyWith(
          multlineWidthEm: 25.0,
          tagMode: TexMathTagMode.ams,
        );
        expect(updated.multlineWidthEm, 25.0);
        expect(updated.tagMode, TexMathTagMode.ams);
        expect(updated, isNot(equals(base)));
        expect(
          updated,
          equals(
            const TexMathOptions(
              multlineWidthEm: 25.0,
              tagMode: TexMathTagMode.ams,
            ),
          ),
        );
        expect(
          updated.hashCode,
          equals(
            const TexMathOptions(
              multlineWidthEm: 25.0,
              tagMode: TexMathTagMode.ams,
            ).hashCode,
          ),
        );
        expect(updated.toString(), contains('multlineWidthEm: 25.0'));
        expect(updated.toString(), contains('tagMode: TexMathTagMode.ams'));

        for (final double bad in <double>[
          0.0,
          -1.0,
          double.infinity,
          double.negativeInfinity,
          double.nan,
        ]) {
          expect(
            () => TexMathOptions(multlineWidthEm: bad),
            throwsA(isA<AssertionError>()),
          );
        }
      },
    );
  });

  group('TexMathError sealed hierarchy', () {
    test('covers all error classes and subtypes exhaustively', () {
      const List<TexMathError> errors = <TexMathError>[
        TexMathSyntaxError(
          'Missing closing brace',
          errorClass: TexMathErrorClass.missingBrace,
          span: SourceSpan(0, 1),
        ),
        TexMathMacroError('Invalid macro signature', span: SourceSpan(1, 5)),
        TexMathBudgetError(
          'Input too long',
          budgetName: 'maxInputLength',
          limit: 10,
          actual: 12,
        ),
        TexMathFontError('Empty font'),
        TexMathUnsupportedError('Layout stage pending'),
      ];

      final List<String> tags = errors.map((TexMathError error) {
        return switch (error) {
          TexMathSyntaxError() => 'syntax:${error.errorClass.name}',
          TexMathMacroError() => 'macro:${error.errorClass.name}',
          TexMathBudgetError() => 'budget:${error.budgetName}',
          TexMathFontError() => 'font:${error.errorClass.name}',
          TexMathUnsupportedError() => 'unsupported:${error.errorClass.name}',
        };
      }).toList();

      expect(tags, <String>[
        'syntax:missingBrace',
        'macro:invalidMacroDefinition',
        'budget:maxInputLength',
        'font:invalidFont',
        'unsupported:unsupportedFeature',
      ]);
      expect(TexMathErrorClass.values, hasLength(16));
    });

    test('reports 1-based position, formattedMessage, and source carets', () {
      const String doublePrimeSource = "x^2'";
      late TexMathSyntaxError doublePrimeErr;
      try {
        parseTex(doublePrimeSource);
        fail('Expected TexMathSyntaxError for double prime');
      } on TexMathSyntaxError catch (err) {
        doublePrimeErr = err;
      }
      expect(doublePrimeErr.errorClass, TexMathErrorClass.doubleScript);
      expect(doublePrimeErr.message, 'Prime causes double exponent.');
      expect(doublePrimeErr.span, const SourceSpan(3, 4));
      expect(doublePrimeErr.position, 4);
      expect(
        doublePrimeErr.formattedMessage,
        'Prime causes double exponent. (at position 4)',
      );
      final String withSource = doublePrimeErr.formatWithSource(
        doublePrimeSource,
      );
      expect(
        withSource,
        "Prime causes double exponent. (at position 4)\nx^2'\n   ^",
      );
      final List<String> lines = withSource.split('\n');
      expect(lines, hasLength(3));
      expect(lines[2].indexOf('^'), lines[1].indexOf("'"));

      const String unclosedFrac = r'\frac{a';
      late TexMathSyntaxError unclosedErr;
      try {
        parseTex(unclosedFrac);
        fail('Expected TexMathSyntaxError for unclosed frac');
      } on TexMathSyntaxError catch (err) {
        unclosedErr = err;
      }
      expect(unclosedErr.errorClass, TexMathErrorClass.missingBrace);
      expect(unclosedErr.position, 6);

      // Empty EOF span from parser (`\frac{a}` missing second argument, or `{a`).
      const String missingSecondArg = r'\frac{a}';
      late TexMathSyntaxError eofErr;
      try {
        parseTex(missingSecondArg);
        fail('Expected TexMathSyntaxError for missing denominator');
      } on TexMathSyntaxError catch (err) {
        eofErr = err;
      }
      expect(eofErr.errorClass, TexMathErrorClass.missingArgument);
      expect(eofErr.span, SourceSpan.empty(missingSecondArg.length));
      expect(eofErr.position, missingSecondArg.length + 1);
      expect(
        eofErr.formatWithSource(missingSecondArg),
        '${eofErr.formattedMessage}\n$missingSecondArg\n'
        '${' ' * missingSecondArg.length}^',
      );

      // Empty EOF span explicitly constructed on `\frac{a` plus out-of-bounds clamping.
      const TexMathSyntaxError explicitEof = TexMathSyntaxError(
        'Unexpected end of input.',
        errorClass: TexMathErrorClass.missingBrace,
        span: SourceSpan.empty(7),
      );
      expect(explicitEof.position, 8);
      expect(
        explicitEof.formatWithSource(unclosedFrac),
        'Unexpected end of input. (at position 8)\n\\frac{a\n       ^',
      );
      const TexMathSyntaxError clampedErr = TexMathSyntaxError(
        'Out of range span.',
        span: SourceSpan(10, 15),
      );
      expect(
        clampedErr.formatWithSource('abc'),
        'Out of range span. (at position 11)\nabc\n   ^',
      );

      // Wide multi-character span renders proportional caret width.
      const TexMathSyntaxError wideErr = TexMathSyntaxError(
        'Unknown command',
        span: SourceSpan(2, 6),
      );
      expect(
        wideErr.formatWithSource(r'x+\bad+y'),
        'Unknown command (at position 3)\nx+\\bad+y\n  ^^^^',
      );

      // `span == null` returns null position and omits position/caret lines.
      const TexMathFontError noSpanErr = TexMathFontError('Empty font');
      expect(noSpanErr.position, isNull);
      expect(noSpanErr.formattedMessage, 'Empty font');
      expect(noSpanErr.formatWithSource('x + y'), 'Empty font');
    });
  });

  group('MathNode sealed hierarchy', () {
    test('supports exhaustive switching over all 16 AST node classes', () {
      const SourceSpan span = SourceSpan(0, 1);
      const SymbolNode x = SymbolNode(span: span, value: 'x');
      const SymbolNode y = SymbolNode(span: span, value: 'y');
      final List<MathNode> nodes = <MathNode>[
        const MathRootNode(span: span, children: <MathNode>[x]),
        const MathGroupNode(span: span, children: <MathNode>[x]),
        x,
        const OperatorNode(span: span, operatorName: 'sum', hasLimits: true),
        const FractionNode(span: span, numerator: x, denominator: y),
        const ScriptNode(span: span, base: x, superscript: y),
        const RadicalNode(span: span, radicand: x, index: y),
        const AccentNode(span: span, base: x, accent: 'hat'),
        const DelimiterNode(
          span: span,
          children: <MathNode>[x],
          leftDelimiter: '(',
          rightDelimiter: ')',
        ),
        const MatrixNode(
          span: span,
          rows: <List<MathNode>>[
            <MathNode>[x, y],
          ],
          environment: 'pmatrix',
        ),
        const TextNode(span: span, text: 'if'),
        const SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
        const StyleNode(
          span: span,
          style: TexMathStyle.display,
          children: <MathNode>[x],
        ),
        const ColorNode(
          span: span,
          role: TexMathColorRole.accent,
          children: <MathNode>[x],
        ),
        const TagNode(span: span, label: '1', body: x),
        const ErrorNode(
          span: span,
          error: TexMathSyntaxError('bad'),
          rawSource: r'\bad',
        ),
      ];

      final List<String> kinds = nodes.map((MathNode node) {
        return switch (node) {
          MathRootNode() => 'root',
          MathGroupNode() => 'group',
          SymbolNode() => 'symbol',
          OperatorNode() => 'operator',
          FractionNode() => 'fraction',
          ScriptNode() => 'script',
          RadicalNode() => 'radical',
          AccentNode() => 'accent',
          DelimiterNode() => 'delimiter',
          MatrixNode() => 'matrix',
          TextNode() => 'text',
          SpaceNode() => 'space',
          StyleNode() => 'style',
          ColorNode() => 'color',
          TagNode() => 'tag',
          ErrorNode() => 'error',
        };
      }).toList();

      expect(kinds, <String>[
        'root',
        'group',
        'symbol',
        'operator',
        'fraction',
        'script',
        'radical',
        'accent',
        'delimiter',
        'matrix',
        'text',
        'space',
        'style',
        'color',
        'tag',
        'error',
      ]);
      for (final MathNode node in nodes) {
        expect(node.span, span);
      }
    });
  });

  group('MathFont and PathCommand', () {
    test('validates font bytes and switches over PathCommand', () {
      expect(
        () => MathFont.fromBytes(Uint8List(0)),
        throwsA(isA<TexMathFontError>()),
      );
      expect(
        () => MathFont.fromBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
        throwsA(isA<TexMathFontError>()),
      );
      expect(
        () => MathFont.fromBytes(
          Uint8List.fromList(<int>[
            0x4F,
            0x54,
            0x54,
            0x4F,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
          maxBytes: 8,
        ),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => MathFont.fromBytes(
          Uint8List.fromList(<int>[
            0x4F,
            0x54,
            0x54,
            0x4F,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
          ]),
        ),
        throwsA(isA<TexMathFontError>()),
      );

      const GlyphOutline outline = GlyphOutline(
        glyphId: 42,
        advanceWidth: 500,
        commands: <PathCommand>[
          MoveTo(0, 0),
          LineTo(100, 0),
          QuadTo(120, 50, 100, 100),
          CubicTo(60, 120, 40, 120, 0, 100),
          ClosePath(),
        ],
      );
      expect(
        outline.toSvgPathData(),
        'M0 0 L100 0 Q120 50 100 100 C60 120 40 120 0 100 Z',
      );
    });
  });

  group('DisplayList, RenderResult, and DisplayMetrics', () {
    test('computes unit metrics, SVG XML, MathML, and spoken text', () {
      const DisplayMetrics metrics = DisplayMetrics(
        widthEm: 2.0,
        heightEm: 1.0,
        depthEm: 0.5,
        unitsPerEm: 1000,
      );
      expect(metrics.baselineEm, 1.0);
      expect(metrics.totalHeightEm, 1.5);
      expect(metrics.widthUnits, 2000);
      expect(metrics.heightUnits, 1000);
      expect(metrics.depthUnits, 500);

      const DisplayList list = DisplayList(
        metrics: metrics,
        items: <DisplayItem>[
          GlyphItem(
            glyphId: 10,
            codePoint: 0x0078,
            xEm: 0.1,
            yEm: 0.4,
            outline: GlyphOutline(
              glyphId: 10,
              commands: <PathCommand>[
                MoveTo(0, 0),
                LineTo(200, 400),
                ClosePath(),
              ],
            ),
          ),
          GlyphItem(
            glyphId: 11,
            codePoint: 0x0079,
            xEm: 0.8,
            yEm: -0.2,
            colorRole: TexMathColorRole.custom,
            customColor: 0xFF1E40AF,
          ),
          RuleItem(
            xEm: 0.0,
            yEm: 0.2,
            widthEm: 2.0,
            heightEm: 0.05,
            colorRole: TexMathColorRole.accent,
          ),
          AnchorItem(id: 'label-1', xEm: 1.9, yEm: 0.0, label: 'eq'),
        ],
      );

      final String svg = list.toSvg(fontSize: 20, title: 'x over y');
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('<title>x over y</title>'));
      expect(svg, contains('<path d="M0 0 L200 400 Z"'));
      expect(svg, contains('<text '));
      expect(svg, contains('fill="#1E40AF"'));
      expect(svg, contains('<rect '));
      expect(svg, contains('fill="#2563EB"'));
      expect(svg, contains('id="label-1"'));
      expect(svg, endsWith('</svg>'));

      expect(
        () => list.toSvg(maxSvgLength: 16),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => list.toSvg(maxOutputItems: 2),
        throwsA(isA<TexMathBudgetError>()),
      );

      final MathNode tree = parseTex(r'\frac{x}{y}');
      final RenderResult renderResult = RenderResult(
        displayList: list,
        syntaxTree: tree,
        source: r'\frac{x}{y}',
      );
      expect(renderResult.toMathMl(), contains('<mfrac>'));
      expect(renderResult.toSpokenText(), 'x over y');
    });

    test(
      'AnchorItem exposes hitbox bounds, safe href getter, and SVG <a> hitbox',
      () {
        const AnchorItem safeAnchor = AnchorItem(
          id: 'href:https://example.org/a&b',
          xEm: 1.0,
          yEm: 0.0,
          widthEm: 2.5,
          heightEm: 0.8,
          depthEm: 0.2,
          label: 'https://example.org/a&b',
        );
        const AnchorItem safeAnchorCopy = AnchorItem(
          id: 'href:https://example.org/a&b',
          xEm: 1.0,
          yEm: 0.0,
          widthEm: 2.5,
          heightEm: 0.8,
          depthEm: 0.2,
          label: 'https://example.org/a&b',
        );
        const AnchorItem unsafeAnchor = AnchorItem(
          id: 'href:javascript:alert(1)',
          xEm: 0.0,
          yEm: 0.0,
          widthEm: 2.0,
          heightEm: 1.0,
          depthEm: 0.0,
          label: 'javascript:alert(1)',
        );
        const AnchorItem refAnchor = AnchorItem(
          id: 'ref:eq:1',
          xEm: 0.0,
          yEm: 0.0,
          widthEm: 1.0,
          heightEm: 0.7,
          depthEm: 0.2,
          label: 'eq:1',
        );

        expect(safeAnchor, equals(safeAnchorCopy));
        expect(safeAnchor.hashCode, equals(safeAnchorCopy.hashCode));
        expect(safeAnchor.toString(), contains('widthEm: 2.5'));
        expect(safeAnchor.href, 'https://example.org/a&b');
        expect(unsafeAnchor.href, isNull);
        expect(refAnchor.href, isNull);

        const DisplayList dl = DisplayList(
          metrics: DisplayMetrics(
            widthEm: 4.0,
            heightEm: 1.0,
            depthEm: 0.5,
            baselineEm: 1.0,
          ),
          items: <DisplayItem>[safeAnchor, unsafeAnchor, refAnchor],
        );
        final String svg = dl.toSvg(fontSize: 10.0);
        expect(svg, contains('id="href:https://example.org/a&amp;b"'));
        expect(
          svg,
          endsWith(
            '<a href="https://example.org/a&amp;b" '
            'data-href="https://example.org/a&amp;b">'
            '<rect x="10" y="2" width="25" height="10" '
            'fill="none" pointer-events="all"/></a></svg>',
          ),
        );
        expect(svg, isNot(contains('href="javascript:')));
      },
    );

    test(
      'MatrixNode.explicitWidthEm and TagNode.targetId participate in equality',
      () {
        const SourceSpan span = SourceSpan(0, 1);
        const MatrixNode m1 = MatrixNode(
          span: span,
          rows: <List<MathNode>>[],
          environment: 'multlined',
          explicitWidthEm: 10.0,
        );
        const MatrixNode m2 = MatrixNode(
          span: span,
          rows: <List<MathNode>>[],
          environment: 'multlined',
          explicitWidthEm: 12.0,
        );
        expect(m1, isNot(equals(m2)));
        expect(m1.explicitWidthEm, 10.0);

        const TagNode t1 = TagNode(
          span: span,
          label: '1',
          targetId: 'eq:a',
          isReference: true,
        );
        const TagNode t2 = TagNode(
          span: span,
          label: '1',
          targetId: 'eq:b',
          isReference: true,
        );
        expect(t1, isNot(equals(t2)));
        expect(t1.targetId, 'eq:a');
      },
    );
  });

  group('TexMathEngine budgets and Wave 1 layout boundary', () {
    test('enforces maxInputLength and parses/exports while layout throws', () {
      const TexMathOptions tinyBudget = TexMathOptions(
        budgets: TexMathBudgets(maxInputLength: 5),
      );
      const TexMathEngine engine = TexMathEngine(defaultOptions: tinyBudget);

      expect(
        () => engine.parse('123456'),
        throwsA(
          isA<TexMathBudgetError>().having(
            (TexMathBudgetError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.budgetExceeded,
          ),
        ),
      );
      expect(() => engine.render('123456'), throwsA(isA<TexMathBudgetError>()));
      expect(
        () => engine.renderToSvg('123456'),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => engine.toMathMl('123456'),
        throwsA(isA<TexMathBudgetError>()),
      );
      expect(
        () => engine.toSpokenText('123456'),
        throwsA(isA<TexMathBudgetError>()),
      );

      final MathNode parsed = parseTex(r'x');
      expect(parsed, isA<MathRootNode>());
      expect(const TexMathEngine().toMathMl(r'x'), contains('<mi>x</mi>'));
      expect(const TexMathEngine().toSpokenText(r'x'), 'x');
      expect(() => renderTex(r'x'), throwsA(isA<TexMathFontError>()));
      expect(() => renderTexToSvg(r'x'), throwsA(isA<TexMathFontError>()));
    });

    test('enforces maxNestingDepth on layout input trees', () {
      const TexMathEngine engine = TexMathEngine(
        defaultOptions: TexMathOptions(
          budgets: TexMathBudgets(maxNestingDepth: 2),
        ),
      );
      const MathRootNode deepTree = MathRootNode(
        span: SourceSpan(0, 1),
        children: <MathNode>[
          MathGroupNode(
            span: SourceSpan(0, 1),
            children: <MathNode>[
              SymbolNode(span: SourceSpan(0, 1), value: 'x'),
            ],
          ),
        ],
      );
      expect(() => engine.layout(deepTree), throwsA(isA<TexMathBudgetError>()));
      expect(
        () => const TexMathEngine().layout(deepTree),
        throwsA(isA<TexMathFontError>()),
      );
    });
  });

  group('Color model resolution and span propagation', () {
    test('resolves RGB (0-255), rgb (0-1), HTML, and gray color models', () {
      expect(resolveTexColor('220,20,60', model: 'RGB'), '#DC143C');
      expect(resolveTexColor(' 220 , 20 , 60 ', model: ' RGB '), '#DC143C');
      expect(resolveTexColor('300,-10,255', model: 'RGB'), '#FF00FF');

      expect(resolveTexColor('1, 0.5, 0', model: 'rgb'), '#FF8000');
      expect(resolveTexColor('0.2, 0.4, 0.6', model: 'Rgb'), '#336699');

      expect(resolveTexColor('dc143c', model: 'HTML'), '#DC143C');
      expect(resolveTexColor('#1e40af', model: 'html'), '#1E40AF');

      expect(resolveTexColor('0.5', model: 'gray'), '#808080');
      expect(resolveTexColor('0.2', model: 'GRAY'), '#333333');
    });

    test(
      'propagates SourceSpan on invalid HTML or non-finite color channels',
      () {
        const SourceSpan directSpan = SourceSpan(10, 16);
        expect(
          () => resolveTexColor('ZZZZZZ', model: 'HTML', span: directSpan),
          throwsA(
            isA<TexMathSyntaxError>().having(
              (TexMathSyntaxError e) => e.span,
              'span',
              directSpan,
            ),
          ),
        );
        expect(
          () => resolveTexColor('NaN,0,0', model: 'rgb', span: directSpan),
          throwsA(
            isA<TexMathSyntaxError>().having(
              (TexMathSyntaxError e) => e.span,
              'span',
              directSpan,
            ),
          ),
        );
        expect(
          () => resolveTexColor('Infinity', model: 'gray', span: directSpan),
          throwsA(
            isA<TexMathSyntaxError>().having(
              (TexMathSyntaxError e) => e.span,
              'span',
              directSpan,
            ),
          ),
        );

        expect(
          () => parseTex(r'\textcolor[HTML]{ZZZZZZ}{x}'),
          throwsA(
            isA<TexMathSyntaxError>()
                .having((TexMathSyntaxError e) => e.span, 'span', isNotNull)
                .having((TexMathSyntaxError e) => e.position, 'position', 1),
          ),
        );
        expect(
          () => parseTex(r'a + \textcolor[rgb]{NaN,0,0}{x}'),
          throwsA(
            isA<TexMathSyntaxError>()
                .having((TexMathSyntaxError e) => e.span, 'span', isNotNull)
                .having((TexMathSyntaxError e) => e.position, 'position', 5),
          ),
        );
      },
    );

    test(
      'parses RGB/rgb/HTML/gray color commands into expected ColorNode hex',
      () {
        final MathRootNode root = parseTex(
          r'\textcolor[RGB]{220,20,60}{\alpha}'
          r' + \textcolor[rgb]{0,0.5,1}{x}'
          r' + \textcolor[HTML]{1e40af}{y}'
          r' + \textcolor[gray]{0.5}{z}',
        ) as MathRootNode;
        final List<ColorNode> colors = root.children
            .whereType<ColorNode>()
            .toList();
        expect(colors, hasLength(4));
        expect(colors[0].colorValue, '#DC143C');
        expect(colors[1].colorValue, '#0080FF');
        expect(colors[2].colorValue, '#1E40AF');
        expect(colors[3].colorValue, '#808080');
      },
    );
  });
}
