import '../ast.dart';
import '../error.dart';
import '../source_span.dart';
import 'parser_host.dart';
import 'tokenizer.dart';

/// Handles `physics` package macros when `physics` is enabled.
abstract final class PhysicsParser {
  /// Attempts to parse a `physics` command named [commandName].
  ///
  /// Returns `null` if [commandName] is not a `physics` command.
  static MathNode? tryParseCommand(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    switch (commandName) {
      case 'quantity':
      case 'qty':
        return _parseQuantity(host, commandName, span, requiredArg: false);
      case 'pqty':
        return _parseQuantity(
          host,
          commandName,
          span,
          open: '(',
          close: ')',
          requiredArg: true,
        );
      case 'bqty':
        return _parseQuantity(
          host,
          commandName,
          span,
          open: '[',
          close: ']',
          requiredArg: true,
        );
      case 'vqty':
      case 'abs':
      case 'absolutevalue':
        return _parseQuantity(
          host,
          commandName,
          span,
          open: '|',
          close: '|',
          requiredArg: true,
        );
      case 'Bqty':
        return _parseQuantity(
          host,
          commandName,
          span,
          open: '{',
          close: '}',
          requiredArg: true,
        );
      case 'norm':
        return _parseQuantity(
          host,
          commandName,
          span,
          open: '\u2016',
          close: '\u2016',
          requiredArg: true,
        );
      case 'order':
        return _parseOrder(host, commandName, span);
      case 'eval':
      case 'evaluated':
        return _parseEval(host, commandName, span);
      case 'comm':
      case 'commutator':
        return _parseCommutator(host, commandName, span, open: '[', close: ']');
      case 'acomm':
      case 'anticommutator':
      case 'pb':
      case 'poissonbracket':
        return _parseCommutator(host, commandName, span, open: '{', close: '}');
      case 'bra':
        return _parseBra(host, commandName, span);
      case 'ket':
        return _parseKet(host, commandName, span);
      case 'braket':
      case 'ip':
      case 'innerproduct':
        return _parseBraKet(host, commandName, span);
      case 'ketbra':
      case 'dyad':
      case 'op':
      case 'outerproduct':
        return _parseKetBra(host, commandName, span);
      case 'expval':
      case 'ev':
      case 'expectationvalue':
        return _parseExpectation(host, commandName, span);
      case 'mel':
      case 'matrixel':
      case 'matrixelement':
        return _parseMatrixElement(host, commandName, span);
      case 'dd':
      case 'differential':
        return _parseDifferential(host, commandName, span, isVariation: false);
      case 'var':
      case 'variation':
        return _parseDifferential(host, commandName, span, isVariation: true);
      case 'diffd':
        return SymbolNode(
          span: span,
          value: 'd',
          command: 'diffd',
          fontVariant: host.activePackages.physicsItalicDiff
              ? TexMathFontVariant.italic
              : TexMathFontVariant.normal,
        );
      case 'dv':
      case 'derivative':
        return _parseDerivative(host, commandName, span, kind: _DerivKind.diff);
      case 'pdv':
      case 'pderivative':
      case 'partialderivative':
        return _parseDerivative(
          host,
          commandName,
          span,
          kind: _DerivKind.partial,
        );
      case 'fdv':
      case 'fderivative':
      case 'functionalderivative':
        return _parseDerivative(
          host,
          commandName,
          span,
          kind: _DerivKind.functional,
        );
      case 'flatfrac':
        final MathNode num = host.parseSubTokens(
          host.readArgumentTokens(commandName),
          span: span,
        );
        final MathNode den = host.parseSubTokens(
          host.readArgumentTokens(commandName),
          span: span,
        );
        return FractionNode(
          span: span,
          numerator: num,
          denominator: den,
          isBevelled: true,
        );
      case 'vb':
      case 'vectorbold':
        final bool star = host.consumeOptionalStar();
        final List<TexToken> tokens = host.readArgumentTokens(commandName);
        return host.parseSubTokens(
          tokens,
          span: span,
          fontVariant: star
              ? TexMathFontVariant.boldItalic
              : TexMathFontVariant.bold,
        );
      case 'va':
      case 'vectorarrow':
        final bool star = host.consumeOptionalStar();
        final List<TexToken> tokens = host.readArgumentTokens(commandName);
        final MathNode inner = host.parseSubTokens(
          tokens,
          span: span,
          fontVariant: star
              ? TexMathFontVariant.boldItalic
              : TexMathFontVariant.bold,
        );
        return AccentNode(span: span, base: inner, accent: '\u2192');
      case 'vu':
      case 'vectorunit':
        final bool star = host.consumeOptionalStar();
        final List<TexToken> tokens = host.readArgumentTokens(commandName);
        final MathNode inner = host.parseSubTokens(
          tokens,
          span: span,
          fontVariant: star
              ? TexMathFontVariant.boldItalic
              : TexMathFontVariant.bold,
        );
        return AccentNode(span: span, base: inner, accent: '\u005E');
      case 'vnabla':
        final SymbolNode nabla = SymbolNode(
          span: span,
          value: '\u2207',
          command: 'nabla',
          fontVariant: TexMathFontVariant.bold,
        );
        return host.activePackages.physicsArrowDel
            ? AccentNode(span: span, base: nabla, accent: '\u2192')
            : nabla;
      case 'grad':
      case 'gradient':
        return _parseVectorOp(
          host,
          commandName,
          span,
          SymbolNode(
            span: span,
            value: '\u2207',
            command: 'nabla',
            atomClass: TexMathAtomClass.op,
            fontVariant: TexMathFontVariant.bold,
          ),
        );
      case 'div':
      case 'divergence':
        return _parseVectorOp(
          host,
          commandName,
          span,
          MathGroupNode(
            span: span,
            isExplicitGroup: false,
            children: <MathNode>[
              SymbolNode(
                span: span,
                value: '\u2207',
                command: 'nabla',
                fontVariant: TexMathFontVariant.bold,
              ),
              SymbolNode(
                span: span,
                value: '\u22C5',
                command: 'cdot',
                atomClass: TexMathAtomClass.bin,
                fontVariant: TexMathFontVariant.bold,
              ),
            ],
          ),
        );
      case 'curl':
        return _parseVectorOp(
          host,
          commandName,
          span,
          MathGroupNode(
            span: span,
            isExplicitGroup: false,
            children: <MathNode>[
              SymbolNode(
                span: span,
                value: '\u2207',
                command: 'nabla',
                fontVariant: TexMathFontVariant.bold,
              ),
              SymbolNode(
                span: span,
                value: '\u00D7',
                command: 'times',
                atomClass: TexMathAtomClass.bin,
              ),
            ],
          ),
        );
      case 'laplacian':
        return _parseVectorOp(
          host,
          commandName,
          span,
          ScriptNode(
            span: span,
            base: SymbolNode(span: span, value: '\u2207', command: 'nabla'),
            superscript: SymbolNode(span: span, value: '2'),
          ),
        );
      case 'tr':
      case 'Tr':
      case 'rank':
      case 'erf':
        return _parsePhysicsNamedOp(host, commandName, span, commandName);
      case 'trace':
        return _parsePhysicsNamedOp(host, commandName, span, 'tr');
      case 'Trace':
        return _parsePhysicsNamedOp(host, commandName, span, 'Tr');
      case 'Res':
        return _parsePhysicsNamedOp(
          host,
          commandName,
          span,
          'Res',
          hasLimits: true,
        );
      case 'pv':
        return _parsePhysicsNamedOp(host, commandName, span, 'P');
      case 'PV':
        return _parsePhysicsNamedOp(host, commandName, span, 'P.V.');
      case 'mqty':
      case 'matrixquantity':
        return _parseMatrixQuantity(host, commandName, span, isSmall: false);
      case 'smqty':
      case 'smallmatrixquantity':
        return _parseMatrixQuantity(host, commandName, span, isSmall: true);
      case 'pmqty':
      case 'Pmqty':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '(',
          ')',
          isSmall: false,
        );
      case 'bmqty':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '[',
          ']',
          isSmall: false,
        );
      case 'vmqty':
      case 'mdet':
      case 'matrixdeterminant':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '|',
          '|',
          isSmall: false,
        );
      case 'spmqty':
      case 'sPmqty':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '(',
          ')',
          isSmall: true,
        );
      case 'sbmqty':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '[',
          ']',
          isSmall: true,
        );
      case 'svmqty':
      case 'smdet':
        return _parseFixedDelimMatrix(
          host,
          commandName,
          span,
          '|',
          '|',
          isSmall: true,
        );
      case 'dmat':
      case 'diagonalmatrix':
        return _parseDiagMatrix(host, commandName, span, anti: false);
      case 'admat':
      case 'antidiagonalmatrix':
        return _parseDiagMatrix(host, commandName, span, anti: true);
      case 'imat':
      case 'identitymatrix':
        return _parseIdentityMatrix(host, commandName, span);
      case 'xmat':
      case 'xmatrix':
        return _parseXMatrix(host, commandName, span);
      case 'zmat':
      case 'zeromatrix':
        return _parseZeroMatrix(host, commandName, span);
      case 'pmat':
      case 'paulimatrix':
        return _parsePauliMatrix(host, commandName, span);
      case 'qq':
      case 'qqtext':
        final bool star = host.consumeOptionalStar();
        final String text = host.readArgumentText(commandName);
        return MathGroupNode(
          span: span,
          isExplicitGroup: false,
          children: <MathNode>[
            if (!star) SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
            TextNode(span: span, text: text, styleCommand: 'text'),
            SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
          ],
        );
      case 'qcomma':
      case 'qc':
        return TextNode(span: span, text: ',', styleCommand: 'text');
      case 'qcc':
        return _quickQuadText(span, 'c.c.');
      case 'qif':
      case 'qthen':
      case 'qelse':
      case 'qotherwise':
      case 'qunless':
      case 'qgiven':
      case 'qusing':
      case 'qassume':
      case 'qsince':
      case 'qlet':
      case 'qfor':
      case 'qall':
      case 'qeven':
      case 'qodd':
      case 'qinteger':
      case 'qand':
      case 'qor':
      case 'qas':
      case 'qin':
        return _quickQuadText(span, commandName.substring(1));
      case 'dotproduct':
      case 'vdot':
        return SymbolNode(
          span: span,
          value: '\u22C5',
          command: commandName,
          atomClass: TexMathAtomClass.bin,
          fontVariant: TexMathFontVariant.bold,
        );
      case 'crossproduct':
      case 'cross':
      case 'cp':
        return SymbolNode(
          span: span,
          value: '\u00D7',
          command: commandName,
          atomClass: TexMathAtomClass.bin,
        );
      case 'gradientnabla':
        return SymbolNode(
          span: span,
          value: '\u2207',
          command: commandName,
          fontVariant: TexMathFontVariant.bold,
        );
      case 'divsymbol':
      case 'divisionsymbol':
        return SymbolNode(
          span: span,
          value: '\u00F7',
          command: commandName,
          atomClass: TexMathAtomClass.bin,
        );
      case 'real':
        return SymbolNode(
          span: span,
          value: '\u211C',
          command: 'real',
          fontVariant: TexMathFontVariant.normal,
        );
      case 'imaginary':
        return SymbolNode(
          span: span,
          value: '\u2111',
          command: 'imaginary',
          fontVariant: TexMathFontVariant.normal,
        );
      default:
        return null;
    }
  }

  static MathNode _quickQuadText(SourceSpan span, String word) {
    return MathGroupNode(
      span: span,
      isExplicitGroup: false,
      children: <MathNode>[
        SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
        TextNode(span: span, text: word, styleCommand: 'text'),
        SpaceNode(span: span, widthEm: 1.0, command: 'quad'),
      ],
    );
  }

  static double? _consumeOptionalBigSize(TexParserHost host) {
    final TexToken? next = host.cursor.peek();
    if (next == null || next.kind != TexTokenKind.controlSequence) {
      return null;
    }
    final double? size = switch (next.text) {
      'big' => 0.85,
      'Big' => 1.15,
      'bigg' => 1.45,
      'Bigg' => 1.75,
      _ => null,
    };
    if (size != null) {
      host.cursor.next();
    }
    return size;
  }

  static MathNode _parseQuantity(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    String open = '(',
    String close = ')',
    required bool requiredArg,
  }) {
    final bool star = requiredArg ? host.consumeOptionalStar() : false;
    final double? fixedSize = _consumeOptionalBigSize(host);
    final TexToken? next = host.cursor.peek();

    if (requiredArg) {
      if (next == null || next.kind != TexTokenKind.beginGroup) {
        if (next != null &&
            (next.text == '(' || next.text == '[' || next.text == '|')) {
          final (String l, String r) = switch (next.text) {
            '(' => ('(', ')'),
            '[' => ('[', ']'),
            _ => ('|', '|'),
          };
          final List<TexToken> tokens = host.readBalancedDelimiterTokens(
            commandName,
            l,
            r,
          );
          final MathNode body = host.parseSubTokens(tokens, span: span);
          return DelimiterNode(
            span: span,
            leftDelimiter: open,
            rightDelimiter: close,
            fixedSizeEm: star ? 0.0 : fixedSize,
            children: <MathNode>[body],
          );
        }
        throw TexMathSyntaxError(
          'Missing argument for \\$commandName.',
          errorClass: TexMathErrorClass.missingArgument,
          span: next?.span ?? span,
        );
      }
      final List<TexToken> argTokens = host.readArgumentTokens(commandName);
      final MathNode body = host.parseSubTokens(argTokens, span: span);
      return DelimiterNode(
        span: span,
        leftDelimiter: open,
        rightDelimiter: close,
        fixedSizeEm: star ? 0.0 : fixedSize,
        children: <MathNode>[body],
      );
    }

    if (next != null && next.kind == TexTokenKind.beginGroup) {
      final List<TexToken> argTokens = host.readArgumentTokens(commandName);
      final MathNode body = host.parseSubTokens(argTokens, span: span);
      return DelimiterNode(
        span: span,
        leftDelimiter: '{',
        rightDelimiter: '}',
        fixedSizeEm: fixedSize,
        children: <MathNode>[body],
      );
    }
    if (next != null &&
        (next.text == '(' || next.text == '[' || next.text == '|')) {
      final (String l, String r) = switch (next.text) {
        '(' => ('(', ')'),
        '[' => ('[', ']'),
        _ => ('|', '|'),
      };
      final List<TexToken> tokens = host.readBalancedDelimiterTokens(
        commandName,
        l,
        r,
      );
      final MathNode body = host.parseSubTokens(tokens, span: span);
      return DelimiterNode(
        span: span,
        leftDelimiter: l,
        rightDelimiter: r,
        fixedSizeEm: fixedSize,
        children: <MathNode>[body],
      );
    }
    return DelimiterNode(
      span: span,
      leftDelimiter: open,
      rightDelimiter: close,
      children: const <MathNode>[],
    );
  }

  static MathNode _parseOrder(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final DelimiterNode arg = _parseQuantity(
      host,
      commandName,
      span,
      requiredArg: true,
    ) as DelimiterNode;
    return MathGroupNode(
      span: span,
      isExplicitGroup: false,
      children: <MathNode>[
        SymbolNode(
          span: span,
          value: 'O',
          command: 'order',
          atomClass: TexMathAtomClass.op,
          fontVariant: TexMathFontVariant.script,
        ),
        arg,
      ],
    );
  }

  static MathNode _parseEval(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star = host.consumeOptionalStar();
    final TexToken? next = host.cursor.peek();
    late final MathNode body;
    String? leftDelim;
    if (next != null && next.kind == TexTokenKind.beginGroup) {
      body = host.parseSubTokens(
        host.readArgumentTokens(commandName),
        span: span,
      );
    } else if (next != null && (next.text == '(' || next.text == '[')) {
      final String open = next.text;
      leftDelim = open;
      body = host.parseSubTokens(
        host.readBalancedDelimiterTokens(commandName, open, '|'),
        span: span,
      );
    } else {
      body = MathGroupNode(span: span, children: const <MathNode>[]);
    }
    final MathNode inner = star
        ? MathGroupNode(span: span, role: 'smash', children: <MathNode>[body])
        : body;
    return DelimiterNode(
      span: span,
      leftDelimiter: leftDelim,
      rightDelimiter: '|',
      children: <MathNode>[inner],
    );
  }

  static MathNode _parseCommutator(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    required String open,
    required String close,
  }) {
    final bool star = host.consumeOptionalStar();
    final double? fixedSize = _consumeOptionalBigSize(host);
    final List<TexToken> a = host.readArgumentTokens(commandName);
    final List<TexToken> b = host.readArgumentTokens(commandName);
    final MathNode leftNode = host.parseSubTokens(a, span: span);
    final MathNode rightNode = host.parseSubTokens(b, span: span);
    return DelimiterNode(
      span: span,
      leftDelimiter: open,
      rightDelimiter: close,
      fixedSizeEm: star ? 0.0 : fixedSize,
      children: <MathNode>[
        leftNode,
        SymbolNode(span: span, value: ',', atomClass: TexMathAtomClass.punct),
        rightNode,
      ],
    );
  }

  static MathNode _parseBra(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool starBra = host.consumeOptionalStar();
    final MathNode bra = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final TexToken? next = host.cursor.peek();
    if (next != null &&
        next.kind == TexTokenKind.controlSequence &&
        next.text == 'ket') {
      host.cursor.next();
      final bool starKet = host.consumeOptionalStar();
      final MathNode ket = host.parseSubTokens(
        host.readArgumentTokens('ket'),
        span: span,
      );
      return DelimiterNode(
        span: span,
        leftDelimiter: '\u27E8',
        rightDelimiter: '\u27E9',
        fixedSizeEm: (starBra || starKet) ? 0.0 : null,
        children: <MathNode>[
          bra,
          SymbolNode(
            span: span,
            value: '|',
            command: 'middle',
            atomClass: TexMathAtomClass.ord,
            isStretchy: true,
          ),
          ket,
        ],
      );
    }
    return DelimiterNode(
      span: span,
      leftDelimiter: '\u27E8',
      rightDelimiter: '|',
      fixedSizeEm: starBra ? 0.0 : null,
      children: <MathNode>[bra],
    );
  }

  static MathNode _parseKet(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star = host.consumeOptionalStar();
    final MathNode ket = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    return DelimiterNode(
      span: span,
      leftDelimiter: '|',
      rightDelimiter: '\u27E9',
      fixedSizeEm: star ? 0.0 : null,
      children: <MathNode>[ket],
    );
  }

  static MathNode _parseBraKet(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star = host.consumeOptionalStar();
    final MathNode first = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final TexToken? next = host.cursor.peek();
    final MathNode second =
        (next != null && next.kind == TexTokenKind.beginGroup)
        ? host.parseSubTokens(host.readArgumentTokens(commandName), span: span)
        : first;
    return DelimiterNode(
      span: span,
      leftDelimiter: '\u27E8',
      rightDelimiter: '\u27E9',
      fixedSizeEm: star ? 0.0 : null,
      children: <MathNode>[
        first,
        SymbolNode(
          span: span,
          value: '|',
          command: 'middle',
          atomClass: TexMathAtomClass.ord,
          isStretchy: true,
        ),
        second,
      ],
    );
  }

  static MathNode _parseKetBra(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star = host.consumeOptionalStar();
    final MathNode first = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final TexToken? next = host.cursor.peek();
    final MathNode second =
        (next != null && next.kind == TexTokenKind.beginGroup)
        ? host.parseSubTokens(host.readArgumentTokens(commandName), span: span)
        : first;
    return MathGroupNode(
      span: span,
      isExplicitGroup: false,
      children: <MathNode>[
        DelimiterNode(
          span: span,
          leftDelimiter: '|',
          rightDelimiter: '\u27E9',
          fixedSizeEm: star ? 0.0 : null,
          children: <MathNode>[first],
        ),
        SpaceNode(span: span, widthEm: -3.0 / 18.0, command: '!'),
        DelimiterNode(
          span: span,
          leftDelimiter: '\u27E8',
          rightDelimiter: '|',
          fixedSizeEm: star ? 0.0 : null,
          children: <MathNode>[second],
        ),
      ],
    );
  }

  static MathNode _parseExpectation(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star1 = host.consumeOptionalStar();
    final bool star2 = star1 ? host.consumeOptionalStar() : false;
    final MathNode first = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final TexToken? next = host.cursor.peek();
    if (next != null && next.kind == TexTokenKind.beginGroup) {
      final MathNode state = host.parseSubTokens(
        host.readArgumentTokens(commandName),
        span: span,
      );
      return DelimiterNode(
        span: span,
        leftDelimiter: '\u27E8',
        rightDelimiter: '\u27E9',
        fixedSizeEm: (star1 && !star2) ? 0.0 : null,
        children: <MathNode>[
          state,
          SymbolNode(
            span: span,
            value: '|',
            command: 'middle',
            isStretchy: true,
          ),
          first,
          SymbolNode(
            span: span,
            value: '|',
            command: 'middle',
            isStretchy: true,
          ),
          state,
        ],
      );
    }
    return DelimiterNode(
      span: span,
      leftDelimiter: '\u27E8',
      rightDelimiter: '\u27E9',
      fixedSizeEm: star1 ? 0.0 : null,
      children: <MathNode>[first],
    );
  }

  static MathNode _parseMatrixElement(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star1 = host.consumeOptionalStar();
    final bool star2 = star1 ? host.consumeOptionalStar() : false;
    final MathNode left = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final MathNode mid = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    final MathNode right = host.parseSubTokens(
      host.readArgumentTokens(commandName),
      span: span,
    );
    return DelimiterNode(
      span: span,
      leftDelimiter: '\u27E8',
      rightDelimiter: '\u27E9',
      fixedSizeEm: (star1 && !star2) ? 0.0 : null,
      children: <MathNode>[
        left,
        SymbolNode(span: span, value: '|', command: 'middle', isStretchy: true),
        mid,
        SymbolNode(span: span, value: '|', command: 'middle', isStretchy: true),
        right,
      ],
    );
  }

  static MathNode _parseDifferential(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    required bool isVariation,
  }) {
    final List<TexToken>? optOrder = host.readOptionalBracketTokens(
      commandName,
    );
    final SymbolNode diffSym = isVariation
        ? SymbolNode(
            span: span,
            value: '\u03B4',
            command: 'delta',
            fontVariant: TexMathFontVariant.italic,
          )
        : SymbolNode(
            span: span,
            value: 'd',
            command: 'diffd',
            fontVariant: host.activePackages.physicsItalicDiff
                ? TexMathFontVariant.italic
                : TexMathFontVariant.normal,
          );
    final MathNode op = optOrder != null
        ? ScriptNode(
            span: span,
            base: diffSym,
            superscript: host.parseSubTokens(optOrder, span: span),
          )
        : diffSym;

    final TexToken? next = host.cursor.peek();
    if (next != null && next.kind == TexTokenKind.beginGroup) {
      final MathNode arg = host.parseSubTokens(
        host.readArgumentTokens(commandName),
        span: span,
      );
      return MathGroupNode(
        span: span,
        atomClass: TexMathAtomClass.op,
        isExplicitGroup: false,
        children: <MathNode>[op, arg],
      );
    }
    if (next != null && next.text == '(') {
      final List<TexToken> tokens = host.readBalancedDelimiterTokens(
        commandName,
        '(',
        ')',
      );
      return MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: <MathNode>[
          op,
          DelimiterNode(
            span: span,
            leftDelimiter: '(',
            rightDelimiter: ')',
            children: <MathNode>[host.parseSubTokens(tokens, span: span)],
          ),
        ],
      );
    }
    return op;
  }

  static MathNode _parseDerivative(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    required _DerivKind kind,
  }) {
    final bool star = host.consumeOptionalStar();
    final List<TexToken>? optOrder = host.readOptionalBracketTokens(
      commandName,
    );
    final List<List<TexToken>> args = <List<TexToken>>[
      host.readArgumentTokens(commandName),
    ];
    final int maxArgs = kind == _DerivKind.partial ? 3 : 2;
    while (args.length < maxArgs) {
      final TexToken? next = host.cursor.peek();
      if (next == null || next.kind != TexTokenKind.beginGroup) {
        break;
      }
      args.add(host.readArgumentTokens(commandName));
    }

    SymbolNode makeDiffSym() => switch (kind) {
      _DerivKind.diff => SymbolNode(
        span: span,
        value: 'd',
        command: 'diffd',
        fontVariant: host.activePackages.physicsItalicDiff
            ? TexMathFontVariant.italic
            : TexMathFontVariant.normal,
      ),
      _DerivKind.partial => SymbolNode(
        span: span,
        value: '\u2202',
        command: 'partial',
        fontVariant: TexMathFontVariant.italic,
      ),
      _DerivKind.functional => SymbolNode(
        span: span,
        value: '\u03B4',
        command: 'delta',
        fontVariant: TexMathFontVariant.italic,
      ),
    };

    MathNode? orderNode;
    if (kind == _DerivKind.partial && args.length > 2) {
      orderNode = SymbolNode(span: span, value: '${args.length - 1}');
    } else if (optOrder != null) {
      orderNode = host.parseSubTokens(optOrder, span: span);
    }

    final MathNode numDiff = orderNode != null
        ? ScriptNode(span: span, base: makeDiffSym(), superscript: orderNode)
        : makeDiffSym();

    final List<MathNode> numChildren = <MathNode>[numDiff];
    if (args.length > 1) {
      numChildren.add(host.parseSubTokens(args[0], span: span));
    }

    final List<MathNode> denChildren = <MathNode>[];
    if (args.length == 1) {
      final MathNode v = host.parseSubTokens(args[0], span: span);
      denChildren.add(makeDiffSym());
      denChildren.add(
        orderNode != null
            ? ScriptNode(span: span, base: v, superscript: orderNode)
            : v,
      );
    } else {
      final MathNode firstVar = host.parseSubTokens(args[1], span: span);
      denChildren.add(makeDiffSym());
      denChildren.add(
        (orderNode != null && !(kind == _DerivKind.partial && args.length > 2))
            ? ScriptNode(span: span, base: firstVar, superscript: orderNode)
            : firstVar,
      );
      for (int i = 2; i < args.length; i++) {
        denChildren.add(makeDiffSym());
        denChildren.add(host.parseSubTokens(args[i], span: span));
      }
    }

    return FractionNode(
      span: span,
      numerator: MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: numChildren,
      ),
      denominator: MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: denChildren,
      ),
      isBevelled: star,
    );
  }

  static MathNode _parseVectorOp(
    TexParserHost host,
    String commandName,
    SourceSpan span,
    MathNode op,
  ) {
    final TexToken? next = host.cursor.peek();
    if (next != null && (next.text == '(' || next.text == '[')) {
      final String open = next.text;
      final String close = open == '(' ? ')' : ']';
      final List<TexToken> tokens = host.readBalancedDelimiterTokens(
        commandName,
        open,
        close,
      );
      return MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: <MathNode>[
          op,
          DelimiterNode(
            span: span,
            leftDelimiter: open,
            rightDelimiter: close,
            children: <MathNode>[host.parseSubTokens(tokens, span: span)],
          ),
        ],
      );
    }
    return op;
  }

  static MathNode _parsePhysicsNamedOp(
    TexParserHost host,
    String commandName,
    SourceSpan span,
    String opText, {
    bool hasLimits = false,
  }) {
    final OperatorNode base = OperatorNode(
      span: span,
      operatorName: opText,
      command: commandName,
      hasLimits: hasLimits,
    );
    final MathNode attached = host.attachScripts(base);
    final TexToken? next = host.cursor.peek();
    if (next != null && next.text == '(') {
      final List<TexToken> tokens = host.readBalancedDelimiterTokens(
        commandName,
        '(',
        ')',
      );
      return MathGroupNode(
        span: span,
        isExplicitGroup: false,
        children: <MathNode>[
          attached,
          DelimiterNode(
            span: span,
            leftDelimiter: '(',
            rightDelimiter: ')',
            children: <MathNode>[host.parseSubTokens(tokens, span: span)],
          ),
        ],
      );
    }
    return attached;
  }

  static MathNode _parseMatrixQuantity(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    required bool isSmall,
  }) {
    final bool star = host.consumeOptionalStar();
    final TexToken? next = host.cursor.peek();
    String? open;
    String? close;
    late final String contentTex;
    if (next != null && next.kind == TexTokenKind.beginGroup) {
      contentTex = host.readArgumentText(commandName);
    } else if (next != null && next.text == '(') {
      open = star ? '\u27EE' : '(';
      close = star ? '\u27EF' : ')';
      contentTex = _tokensToSourceText(
        host.readBalancedDelimiterTokens(commandName, '(', ')'),
        host.cursor.source,
      );
    } else if (next != null && next.text == '[') {
      open = '[';
      close = ']';
      contentTex = _tokensToSourceText(
        host.readBalancedDelimiterTokens(commandName, '[', ']'),
        host.cursor.source,
      );
    } else if (next != null && next.text == '|') {
      open = '|';
      close = '|';
      contentTex = _tokensToSourceText(
        host.readBalancedDelimiterTokens(commandName, '|', '|'),
        host.cursor.source,
      );
    } else {
      return DelimiterNode(
        span: span,
        leftDelimiter: '(',
        rightDelimiter: ')',
        children: const <MathNode>[],
      );
    }

    final String env = isSmall ? 'smallmatrix' : 'matrix';
    final String wrapped = '\\begin{$env} $contentTex \\end{$env}';
    final MathNode inner = host.parseSyntheticTex(wrapped, span: span);
    if (open == null && close == null) {
      return inner;
    }
    return DelimiterNode(
      span: span,
      leftDelimiter: open,
      rightDelimiter: close,
      children: <MathNode>[inner],
    );
  }

  static MathNode _parseFixedDelimMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span,
    String open,
    String close, {
    required bool isSmall,
  }) {
    final String contentTex = host.readArgumentText(commandName);
    final String env = isSmall ? 'smallmatrix' : 'matrix';
    final MathNode inner = host.parseSyntheticTex(
      '\\begin{$env} $contentTex \\end{$env}',
      span: span,
    );
    return DelimiterNode(
      span: span,
      leftDelimiter: open,
      rightDelimiter: close,
      children: <MathNode>[inner],
    );
  }

  static MathNode _parseDiagMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span, {
    required bool anti,
  }) {
    final String raw = host.readArgumentText(commandName);
    final List<String> entries = _splitTopLevelCommas(raw);
    final StringBuffer rows = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      if (i > 0) {
        rows.write(r' \\ ');
      }
      final int leadCols = anti ? entries.length - 1 - i : i;
      for (int c = 0; c < leadCols; c++) {
        rows.write('& ');
      }
      rows.write(entries[i].trim());
    }
    return host.parseSyntheticTex(
      '\\begin{matrix} $rows \\end{matrix}',
      span: span,
    );
  }

  static MathNode _parseIdentityMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final String raw = host.readArgumentText(commandName).trim();
    final int? size = int.tryParse(raw);
    if (size == null) {
      throw TexMathSyntaxError(
        'Invalid size "$raw" for \\$commandName.',
        span: span,
      );
    }
    if (size <= 1) {
      return SymbolNode(span: span, value: '1');
    }
    final StringBuffer rows = StringBuffer();
    for (int r = 0; r < size; r++) {
      if (r > 0) {
        rows.write(r' \\ ');
      }
      for (int c = 0; c < size; c++) {
        if (c > 0) {
          rows.write(' & ');
        }
        rows.write(r == c ? '1' : '0');
      }
    }
    return host.parseSyntheticTex(
      '\\begin{matrix} $rows \\end{matrix}',
      span: span,
    );
  }

  static MathNode _parseXMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final bool star = host.consumeOptionalStar();
    final String elem = host.readArgumentText(commandName).trim();
    final String rRaw = host.readArgumentText(commandName).trim();
    final String cRaw = host.readArgumentText(commandName).trim();
    final int? rows = int.tryParse(rRaw);
    final int? cols = int.tryParse(cRaw);
    if (rows == null || cols == null || rows < 1 || cols < 1) {
      throw TexMathSyntaxError(
        'Invalid dimensions ($rRaw, $cRaw) for \\$commandName.',
        span: span,
      );
    }
    final StringBuffer buf = StringBuffer();
    for (int r = 1; r <= rows; r++) {
      if (r > 1) {
        buf.write(r' \\ ');
      }
      for (int c = 1; c <= cols; c++) {
        if (c > 1) {
          buf.write(' & ');
        }
        if (!star) {
          buf.write(elem);
        } else if (rows == 1 && cols == 1) {
          buf.write(elem);
        } else if (rows == 1) {
          buf.write('${elem}_{$c}');
        } else if (cols == 1) {
          buf.write('${elem}_{$r}');
        } else {
          buf.write('${elem}_{{$r}{$c}}');
        }
      }
    }
    return host.parseSyntheticTex(
      '\\begin{matrix} $buf \\end{matrix}',
      span: span,
    );
  }

  static MathNode _parseZeroMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final String rRaw = host.readArgumentText(commandName).trim();
    final String cRaw = host.readArgumentText(commandName).trim();
    final int? rows = int.tryParse(rRaw);
    final int? cols = int.tryParse(cRaw);
    if (rows == null || cols == null || rows < 1 || cols < 1) {
      throw TexMathSyntaxError(
        'Invalid dimensions ($rRaw, $cRaw) for \\$commandName.',
        span: span,
      );
    }
    final StringBuffer buf = StringBuffer();
    for (int r = 0; r < rows; r++) {
      if (r > 0) {
        buf.write(r' \\ ');
      }
      for (int c = 0; c < cols; c++) {
        if (c > 0) {
          buf.write(' & ');
        }
        buf.write('0');
      }
    }
    return host.parseSyntheticTex(
      '\\begin{matrix} $buf \\end{matrix}',
      span: span,
    );
  }

  static MathNode _parsePauliMatrix(
    TexParserHost host,
    String commandName,
    SourceSpan span,
  ) {
    final String arg = host.readArgumentText(commandName).trim();
    final String body = switch (arg) {
      '0' => r'1 & 0 \\ 0 & 1',
      '1' || 'x' => r'0 & 1 \\ 1 & 0',
      '2' || 'y' => r'0 & -i \\ i & 0',
      '3' || 'z' => r'1 & 0 \\ 0 & -1',
      _ => throw TexMathSyntaxError(
        'Invalid Pauli matrix index "$arg".',
        span: span,
      ),
    };
    return host.parseSyntheticTex(
      '\\begin{matrix} $body \\end{matrix}',
      span: span,
    );
  }

  static List<String> _splitTopLevelCommas(String input) {
    final List<String> parts = <String>[];
    int depth = 0;
    int start = 0;
    for (int i = 0; i < input.length; i++) {
      final int cu = input.codeUnitAt(i);
      if (cu == 0x5C) {
        i++;
        continue;
      }
      if (cu == 0x7B) {
        depth++;
      } else if (cu == 0x7D && depth > 0) {
        depth--;
      } else if (cu == 0x2C && depth == 0) {
        parts.add(input.substring(start, i));
        start = i + 1;
      }
    }
    parts.add(input.substring(start));
    return parts;
  }

  static String _tokensToSourceText(List<TexToken> tokens, String fullSource) {
    if (tokens.isEmpty) {
      return '';
    }
    final SourceSpan first = tokens.first.span;
    final SourceSpan last = tokens.last.span;
    if (first.start <= last.end && last.end <= fullSource.length) {
      return fullSource.substring(first.start, last.end);
    }
    return tokens.map((TexToken t) => t.rawText).join(' ');
  }
}

enum _DerivKind { diff, partial, functional }
