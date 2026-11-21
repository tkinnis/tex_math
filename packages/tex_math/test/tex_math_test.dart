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
    test('provides documented Phase 1 defaults', () {
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
      expect(options.macros, isEmpty);
      expect(options.strictErrors, isTrue);
    });
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
        TexMathUnsupportedError('Unimplemented in Phase 1'),
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
        throwsA(isA<TexMathUnsupportedError>()),
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

  group('DisplayList and DisplayMetrics', () {
    test('computes unit metrics and serializes standalone SVG XML', () {
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
    });
  });

  group('TexMathEngine and top-level Phase 1 stubs', () {
    test(
      'enforces maxInputLength budget before throwing unsupported error',
      () {
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
        expect(
          () => engine.render('123456'),
          throwsA(isA<TexMathBudgetError>()),
        );
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

        expect(() => parseTex(r'x'), throwsA(isA<TexMathUnsupportedError>()));
        expect(() => renderTex(r'x'), throwsA(isA<TexMathUnsupportedError>()));
        expect(
          () => renderTexToSvg(r'x'),
          throwsA(isA<TexMathUnsupportedError>()),
        );
      },
    );

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
        throwsA(isA<TexMathUnsupportedError>()),
      );
    });
  });
}
