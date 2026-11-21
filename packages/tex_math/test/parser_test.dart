import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  group('Stage 1: Tokenizer', () {
    test('assigns TeX catcodes and preserves exact UTF-16 SourceSpan', () {
      const String source =
          r'\frac{a_1^2}{\alpha} % comment'
          '\n'
          r'+ x\,y';
      final List<TexToken> tokens = tokenizeTex(source);

      final TexToken frac = tokens.first;
      expect(frac.kind, TexTokenKind.controlSequence);
      expect(frac.text, 'frac');
      expect(frac.isControlWord, isTrue);
      expect(frac.span.slice(source), r'\frac');

      final TexToken comment = tokens.firstWhere(
        (TexToken t) => t.kind == TexTokenKind.comment,
      );
      expect(comment.span.slice(source), startsWith('% comment'));

      final TexToken thinSpace = tokens.lastWhere(
        (TexToken t) => t.kind == TexTokenKind.controlSequence,
      );
      expect(thinSpace.text, ',');
      expect(thinSpace.isControlWord, isFalse);
      expect(thinSpace.span.slice(source), r'\,');
    });

    test('preserves surrogate pairs as single UTF-16 tokens', () {
      const String source = 'x + \u{1D538}';
      final List<TexToken> tokens = tokenizeTex(source);
      final TexToken last = tokens.last;
      expect(last.text, '\u{1D538}');
      expect(last.span.length, 2);
      expect(last.span.slice(source), '\u{1D538}');
    });
  });

  group('Stage 2: Macro Expander', () {
    test('expands TexMathOptions.macros and scoped user macros', () {
      const TexMathOptions opts = TexMathOptions(
        macros: <String, String>{'R': r'\mathbb{R}', 'vecb': r'\mathbf{#1}'},
      );
      final MathRootNode tree =
          parseTex(r'x \in \R + \vecb{v}', options: opts) as MathRootNode;
      expect(tree.children, isNotEmpty);
      expect(mathNodeToSpokenText(tree), contains('in R plus v'));
    });

    test('supports delimited \\def, \\let, and \\newenvironment', () {
      final MathNode delimited = parseTex(
        r'\def\pair(#1,#2){(#1;#2)}\pair(1,2)',
      );
      expect(mathNodeToSpokenText(delimited), '( 1 ; 2 )');

      final MathNode aliased = parseTex(
        r'\let\eps\varepsilon \let\oldfrac\frac \oldfrac{\eps}{2}',
      );
      expect(mathNodeToMathMl(aliased), contains('<mfrac>'));

      final MathNode envNode = parseTex(
        r'\newenvironment{aug}[1]{\left[\begin{array}{#1}}{\end{array}\right]}'
        r'\begin{aug}{cc|c} 1 & 2 & 3 \\ 4 & 5 & 6 \end{aug}',
      );
      expect(envNode, isA<MathRootNode>());
      final MathRootNode root = envNode as MathRootNode;
      expect(root.children.single, isA<DelimiterNode>());
      final DelimiterNode delim = root.children.single as DelimiterNode;
      expect(delim.leftDelimiter, '[');
      expect(delim.rightDelimiter, ']');
      expect(delim.children.single, isA<MatrixNode>());
    });

    test('supports \\begingroup, \\endgroup, and \\begingroupSandbox', () {
      const TexMathOptions opts = TexMathOptions(
        packages: <String>['base', 'newcommand', 'begingroup'],
      );
      final MathNode scoped = parseTex(
        r'\begingroup\def\tmp{a+1}\tmp\endgroup + y',
        options: opts,
      );
      expect(mathNodeToSpokenText(scoped), 'a plus 1 plus y');

      expect(
        () => parseTex(r'\begingroup\def\tmp{a}\endgroup\tmp', options: opts),
        throwsA(
          isA<TexMathSyntaxError>().having(
            (TexMathSyntaxError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.undefinedControlSequence,
          ),
        ),
      );

      final MathNode sandbox = parseTex(
        r'\begingroupSandbox\def\tmp{a+b}\tmp\begingroupReset',
        options: opts,
      );
      expect(mathNodeToSpokenText(sandbox), 'a plus b');
    });

    test('enforces macro recursion and nesting budgets', () {
      expect(
        () => parseTex(r'\def\loop{\loop}\loop'),
        throwsA(
          isA<TexMathBudgetError>().having(
            (TexMathBudgetError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.budgetExceeded,
          ),
        ),
      );

      const String deepBraces =
          '{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{'
          '{{{{{{{{{{{{{{{{{{{{x}}}}}}}}}}}}}}}}}}}}'
          '}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}';
      expect(() => parseTex(deepBraces), throwsA(isA<TexMathBudgetError>()));
    });
  });

  group('Stage 3: Package Registry and Specialized Parsers', () {
    test('registers all 42 MathJax 4.1.3 packages and enforces allowlist', () {
      expect(TexPackageRegistry.all, hasLength(42));
      expect(
        TexPackageRegistry.all.where(
          (TexPackageDescriptor d) => d.isDefaultJupyterLab,
        ),
        hasLength(31),
      );

      final MathNode allowed = parseTex(r'\require{physics}\dv{f}{x}');
      expect(mathNodeToMathMl(allowed), contains('<mfrac>'));

      expect(
        () => parseTex(r'\require{setoptions}'),
        throwsA(
          isA<TexMathSyntaxError>().having(
            (TexMathSyntaxError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.syntaxError,
          ),
        ),
      );

      const TexMathOptions customAllow = TexMathOptions(
        requireAllowlist: <String>['dsfont'],
      );
      expect(
        parseTex(r'\require{dsfont}\mathds{R}', options: customAllow),
        isA<MathRootNode>(),
      );
      expect(
        () => parseTex(r'\require{physics}\dv{f}{x}', options: customAllow),
        throwsA(isA<TexMathSyntaxError>()),
      );
    });

    test('parses mhchem, physics, amscd, and bussproofs constructs', () {
      final MathNode chem = parseTex(
        r'\ce{^{238}_{92}U -> ^{234}_{90}Th + ^{4}_{2}He^{2+}}',
      );
      expect(mathNodeToMathMl(chem), contains('<msubsup>'));

      const TexMathOptions physOpts = TexMathOptions(
        packages: <String>['base', 'ams', 'physics'],
      );
      final MathNode phys = parseTex(
        r'\bra{\psi}\ket{\phi} + \pdv{f}{x}{y} + \mqty(a & b \\ c & d)',
        options: physOpts,
      );
      expect(mathNodeToMathMl(phys), contains('<mtable>'));

      final MathNode cd = parseTex(
        r'\begin{CD} A @>f>> B \\ @VVgV @VVhV \\ C @= D \end{CD}',
      );
      expect((cd as MathRootNode).children.single, isA<MatrixNode>());

      final MathNode proof = parseTex(
        r'\begin{prooftree} \AxiomC{$A$} \AxiomC{$B$} '
        r'\BinaryInfC{$A \land B$} \end{prooftree}',
      );
      expect(mathNodeToMathMl(proof), contains('<mtable>'));
    });

    test('computes mathUnicodeCodePoint for font variants', () {
      expect(
        mathUnicodeCodePoint(0x52, TexMathFontVariant.doubleStruck),
        0x211D,
      );
      expect(mathUnicodeCodePoint(0x78, TexMathFontVariant.italic), 0x1D465);
      expect(mathUnicodeCodePoint(0x41, TexMathFontVariant.bold), 0x1D400);
      expect(
        mathUnicodeCodePoint(0x03B1, TexMathFontVariant.boldItalic),
        0x1D736,
      );
      expect(mathUnicodeCodePoint(0x03B1, TexMathFontVariant.normal), 0x03B1);
    });
  });
}
