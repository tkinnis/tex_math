import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  final Directory corpusDir = _resolveCorpusDir();
  final List<_CorpusEntry> entries = _loadAllCorpusCases(corpusDir);
  final Map<String, Object?> expectations = _loadExpectations(corpusDir);
  final Map<String, Object?> expectedCases =
      expectations['cases']! as Map<String, Object?>;

  group('Corpus Error & Grammar Parity (352 cases)', () {
    test('loads all 352 corpus cases matching expectations.json', () {
      expect(entries, hasLength(352));
      expect(expectedCases.length, 352);
      final int acceptedCount = entries
          .where((_CorpusEntry e) => e.accepted)
          .length;
      final int refusedCount = entries
          .where((_CorpusEntry e) => !e.accepted)
          .length;
      expect(acceptedCount, 315);
      expect(refusedCount, 37);
    });

    test('parses all 315 accepted cases into valid MathNode ASTs', () {
      final List<String> failures = <String>[];

      for (final _CorpusEntry entry in entries) {
        if (!entry.accepted) {
          continue;
        }
        final TexMathOptions opts = TexMathOptions(
          displayMode: entry.display
              ? TexMathDisplayMode.display
              : TexMathDisplayMode.inline,
          packages: entry.packages ?? TexMathOptions.defaultPackages,
        );
        try {
          final MathNode ast = parseTex(entry.tex, options: opts);
          _assertValidSpans(ast, entry.tex.length, entry.id);
          final String mml = mathNodeToMathMl(ast);
          final String spoken = mathNodeToSpokenText(ast);
          if (!mml.startsWith('<math')) {
            failures.add('${entry.id}: invalid MathML output');
          }
          if (spoken.isEmpty && entry.tex.trim().isNotEmpty) {
            // Valid only for pure phantom/space expressions if applicable.
            if (!entry.tex.contains(r'\phantom') &&
                !entry.tex.contains(r'\hphantom') &&
                !entry.tex.contains(r'\vphantom')) {
              failures.add('${entry.id}: empty spoken text');
            }
          }
        } catch (err) {
          failures.add('${entry.id}: threw $err');
        }
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('rejects all 37 error cases with exact TexMathErrorClass parity', () {
      final List<String> mismatches = <String>[];

      for (final _CorpusEntry entry in entries) {
        if (entry.accepted) {
          continue;
        }
        final Map<String, Object?>? exp =
            expectedCases[entry.id] as Map<String, Object?>?;
        final String? expectedClass =
            entry.errorClass ?? (exp?['oracleErrorClass'] as String?);
        final TexMathOptions opts = TexMathOptions(
          displayMode: entry.display
              ? TexMathDisplayMode.display
              : TexMathDisplayMode.inline,
          packages: entry.packages ?? TexMathOptions.defaultPackages,
        );

        try {
          parseTex(entry.tex, options: opts);
          mismatches.add(
            '${entry.id}: accepted input expected to fail with $expectedClass',
          );
        } on TexMathError catch (err) {
          if (expectedClass != null && err.errorClass.name != expectedClass) {
            mismatches.add(
              '${entry.id}: expected $expectedClass, got ${err.errorClass.name} '
              '(${err.message})',
            );
          }
        }
      }

      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    });

    test('respects noerrors, noundefined, and strictErrors=false', () {
      const TexMathOptions noErrorsOpts = TexMathOptions(
        packages: <String>['base', 'ams', 'noerrors'],
      );
      final MathNode errRoot = parseTex(r'x^2^3', options: noErrorsOpts);
      expect((errRoot as MathRootNode).children.single, isA<ErrorNode>());

      final MathNode nonStrictRoot = parseTex(
        r'\frac{a}{b',
        options: const TexMathOptions(strictErrors: false),
      );
      expect((nonStrictRoot as MathRootNode).children.single, isA<ErrorNode>());

      const TexMathOptions noUndefOpts = TexMathOptions(
        packages: <String>['base', 'noundefined'],
      );
      final MathNode undefRoot = parseTex(
        r'\unknownMacro + 1',
        options: noUndefOpts,
      );
      expect(mathNodeToMathMl(undefRoot), contains(r'\unknownMacro'));
      expect(
        () => parseTex(r'x^2^3', options: noUndefOpts),
        throwsA(
          isA<TexMathSyntaxError>().having(
            (TexMathSyntaxError e) => e.errorClass,
            'errorClass',
            TexMathErrorClass.doubleScript,
          ),
        ),
      );
    });
  });
}

void _assertValidSpans(MathNode node, int sourceLength, String id) {
  expect(
    node.span.start,
    greaterThanOrEqualTo(0),
    reason: '$id: negative span start on $node',
  );
  expect(
    node.span.end,
    lessThanOrEqualTo(sourceLength),
    reason: '$id: span end ${node.span.end} > $sourceLength on $node',
  );
  switch (node) {
    case MathRootNode(:final List<MathNode> children):
    case MathGroupNode(:final List<MathNode> children):
    case DelimiterNode(:final List<MathNode> children):
    case StyleNode(:final List<MathNode> children):
    case ColorNode(:final List<MathNode> children):
    case TextNode(:final List<MathNode> children):
      for (final MathNode child in children) {
        _assertValidSpans(child, sourceLength, id);
      }
    case FractionNode(:final MathNode numerator, :final MathNode denominator):
      _assertValidSpans(numerator, sourceLength, id);
      _assertValidSpans(denominator, sourceLength, id);
    case ScriptNode(
      :final MathNode base,
      :final MathNode? subscript,
      :final MathNode? superscript,
      :final MathNode? presubscript,
      :final MathNode? presuperscript,
    ):
      _assertValidSpans(base, sourceLength, id);
      if (subscript != null) {
        _assertValidSpans(subscript, sourceLength, id);
      }
      if (superscript != null) {
        _assertValidSpans(superscript, sourceLength, id);
      }
      if (presubscript != null) {
        _assertValidSpans(presubscript, sourceLength, id);
      }
      if (presuperscript != null) {
        _assertValidSpans(presuperscript, sourceLength, id);
      }
    case RadicalNode(:final MathNode radicand, :final MathNode? index):
      _assertValidSpans(radicand, sourceLength, id);
      if (index != null) {
        _assertValidSpans(index, sourceLength, id);
      }
    case AccentNode(:final MathNode base):
      _assertValidSpans(base, sourceLength, id);
    case MatrixNode(:final List<List<MathNode>> rows):
      for (final List<MathNode> row in rows) {
        for (final MathNode cell in row) {
          _assertValidSpans(cell, sourceLength, id);
        }
      }
    case TagNode(:final MathNode? body):
      if (body != null) {
        _assertValidSpans(body, sourceLength, id);
      }
    case SymbolNode():
    case OperatorNode():
    case SpaceNode():
    case ErrorNode():
      break;
  }
}

Directory _resolveCorpusDir() {
  for (final String candidate in <String>['corpus', '../../corpus']) {
    final Directory dir = Directory(candidate);
    if (dir.existsSync()) {
      return dir;
    }
  }
  throw StateError(
    'Unable to locate corpus directory from ${Directory.current}',
  );
}

Map<String, Object?> _loadExpectations(Directory corpusDir) {
  final File file = File('${corpusDir.path}/expectations.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

List<_CorpusEntry> _loadAllCorpusCases(Directory corpusDir) {
  final List<File> files =
      corpusDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.tex'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final RegExp headerPattern = RegExp(r'^%\s*([a-zA-Z0-9_]+)\s*:\s*(.*)$');
  final List<_CorpusEntry> result = <_CorpusEntry>[];

  for (final File file in files) {
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
    final String displayRaw = (headers['display'] ?? 'display').toLowerCase();
    final bool display = displayRaw == 'display' || displayRaw == 'true';
    final bool accepted =
        (headers['accepted'] ?? 'true').toLowerCase() == 'true';
    final String? packagesRaw = headers['packages'];
    final List<String>? packages = packagesRaw == null || packagesRaw.isEmpty
        ? null
        : packagesRaw
              .split(',')
              .map((String s) => s.trim())
              .where((String s) => s.isNotEmpty)
              .toList();
    result.add(
      _CorpusEntry(
        id: headers['id']!,
        display: display,
        accepted: accepted,
        errorClass: headers['error_class'],
        packages: packages,
        tex: lines.sublist(bodyStart).join('\n').trim(),
      ),
    );
  }
  return result;
}

final class _CorpusEntry {
  const _CorpusEntry({
    required this.id,
    required this.display,
    required this.accepted,
    required this.errorClass,
    required this.packages,
    required this.tex,
  });

  final String id;
  final bool display;
  final bool accepted;
  final String? errorClass;
  final List<String>? packages;
  final String tex;
}
