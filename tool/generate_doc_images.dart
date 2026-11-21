import 'dart:io';

import 'package:tex_math/tex_math.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: dart run tool/generate_doc_images.dart [--check]');
    return;
  }

  final bool checkOnly = args.contains('--check');
  final Map<String, String> assets = <String, String>{
    'doc/images/display_list_sample.svg': _buildDisplayListSampleSvg(),
    'doc/images/box_metrics_diagram.svg': _buildBoxMetricsDiagramSvg(),
  };

  final Directory imageDir = Directory('doc/images');
  if (!checkOnly && !imageDir.existsSync()) {
    imageDir.createSync(recursive: true);
  }

  for (final MapEntry<String, String> entry in assets.entries) {
    final String path = entry.key;
    final String svg = '${entry.value}\n';
    _validateSvgXml(path, svg);

    final File file = File(path);
    if (checkOnly) {
      if (!file.existsSync() || file.readAsStringSync() != svg) {
        stderr.writeln('ERROR: $path is missing or out of date.');
        exitCode = 1;
      }
      continue;
    }

    file.writeAsStringSync(svg);
    stdout.writeln('Generated $path (${svg.length} bytes).');
  }
}

String _buildDisplayListSampleSvg() {
  const GlyphOutline plusOutline = GlyphOutline(
    glyphId: 43,
    advanceWidth: 778,
    commands: <PathCommand>[
      MoveTo(355, 50),
      LineTo(423, 50),
      LineTo(423, 216),
      LineTo(589, 216),
      LineTo(589, 284),
      LineTo(423, 284),
      LineTo(423, 450),
      LineTo(355, 450),
      LineTo(355, 284),
      LineTo(189, 284),
      LineTo(189, 216),
      LineTo(355, 216),
      ClosePath(),
    ],
  );

  const GlyphOutline minusOutline = GlyphOutline(
    glyphId: 8722,
    advanceWidth: 778,
    commands: <PathCommand>[
      MoveTo(189, 216),
      LineTo(589, 216),
      LineTo(589, 284),
      LineTo(189, 284),
      ClosePath(),
    ],
  );

  const DisplayList displayList = DisplayList(
    source: r'\frac{a + b}{c - d}',
    metrics: DisplayMetrics(
      widthEm: 4.4,
      heightEm: 1.5,
      depthEm: 1.1,
      baselineEm: 1.5,
      unitsPerEm: 1000,
    ),
    items: <DisplayItem>[
      RuleItem(
        xEm: 0.1,
        yEm: -0.01,
        widthEm: 4.2,
        heightEm: 0.02,
        colorRole: TexMathColorRole.muted,
      ),
      AnchorItem(id: 'origin', xEm: 0.1, yEm: 0.0, label: 'baseline'),
      GlyphItem(
        glyphId: 97,
        codePoint: 0x0061,
        xEm: 0.75,
        yEm: 0.65,
        advanceEm: 0.5,
        span: SourceSpan(6, 7),
      ),
      GlyphItem(
        glyphId: 43,
        codePoint: 0x002B,
        xEm: 1.55,
        yEm: 0.65,
        advanceEm: 0.78,
        outline: plusOutline,
        colorRole: TexMathColorRole.accent,
        span: SourceSpan(8, 9),
      ),
      GlyphItem(
        glyphId: 98,
        codePoint: 0x0062,
        xEm: 2.65,
        yEm: 0.65,
        advanceEm: 0.5,
        span: SourceSpan(10, 11),
      ),
      RuleItem(
        xEm: 0.55,
        yEm: 0.24,
        widthEm: 2.9,
        heightEm: 0.05,
        colorRole: TexMathColorRole.foreground,
        span: SourceSpan(0, 19),
      ),
      GlyphItem(
        glyphId: 99,
        codePoint: 0x0063,
        xEm: 0.75,
        yEm: -0.65,
        advanceEm: 0.5,
        span: SourceSpan(13, 14),
      ),
      GlyphItem(
        glyphId: 8722,
        codePoint: 0x2212,
        xEm: 1.55,
        yEm: -0.65,
        advanceEm: 0.78,
        outline: minusOutline,
        colorRole: TexMathColorRole.accent,
        span: SourceSpan(15, 16),
      ),
      GlyphItem(
        glyphId: 100,
        codePoint: 0x0064,
        xEm: 2.65,
        yEm: -0.65,
        advanceEm: 0.5,
        span: SourceSpan(17, 18),
      ),
      AnchorItem(id: 'end', xEm: 4.2, yEm: 0.0, label: 'advance'),
    ],
  );

  return displayList.toSvg(
    fontSize: 48.0,
    title: 'tex_math DisplayList Sample',
  );
}

String _buildBoxMetricsDiagramSvg() {
  const GlyphOutline sigmaOutline = GlyphOutline(
    glyphId: 8721,
    advanceWidth: 900,
    commands: <PathCommand>[
      MoveTo(100, 900),
      LineTo(820, 900),
      LineTo(820, 720),
      LineTo(760, 720),
      LineTo(730, 820),
      LineTo(260, 820),
      LineTo(540, 460),
      LineTo(240, 80),
      LineTo(740, 80),
      LineTo(780, 200),
      LineTo(840, 200),
      LineTo(840, 0),
      LineTo(100, 0),
      LineTo(100, 45),
      LineTo(440, 450),
      LineTo(100, 855),
      ClosePath(),
    ],
  );

  const DisplayList displayList = DisplayList(
    source: r'\sum',
    metrics: DisplayMetrics(
      widthEm: 6.0,
      heightEm: 1.6,
      depthEm: 0.9,
      baselineEm: 1.6,
      unitsPerEm: 1000,
    ),
    items: <DisplayItem>[
      RuleItem(
        xEm: 0.4,
        yEm: -0.6,
        widthEm: 5.2,
        heightEm: 0.02,
        colorRole: TexMathColorRole.muted,
      ),
      RuleItem(
        xEm: 0.4,
        yEm: 1.25,
        widthEm: 5.2,
        heightEm: 0.02,
        colorRole: TexMathColorRole.muted,
      ),
      RuleItem(
        xEm: 0.4,
        yEm: -0.6,
        widthEm: 0.02,
        heightEm: 1.85,
        colorRole: TexMathColorRole.muted,
      ),
      RuleItem(
        xEm: 5.58,
        yEm: -0.6,
        widthEm: 0.02,
        heightEm: 1.85,
        colorRole: TexMathColorRole.muted,
      ),
      RuleItem(
        xEm: 0.4,
        yEm: 0.0,
        widthEm: 5.2,
        heightEm: 0.03,
        colorRole: TexMathColorRole.accent,
      ),
      AnchorItem(id: 'baseline-start', xEm: 0.4, yEm: 0.0, label: 'baseline'),
      AnchorItem(id: 'height-top', xEm: 0.4, yEm: 1.25, label: 'heightEm'),
      AnchorItem(id: 'depth-bottom', xEm: 0.4, yEm: -0.6, label: 'depthEm'),
      GlyphItem(
        glyphId: 8721,
        codePoint: 0x2211,
        xEm: 1.0,
        yEm: -0.15,
        advanceEm: 0.9,
        outline: sigmaOutline,
        colorRole: TexMathColorRole.foreground,
      ),
      GlyphItem(
        glyphId: 119,
        codePoint: 0x0077,
        xEm: 2.7,
        yEm: 0.95,
        advanceEm: 0.6,
        colorRole: TexMathColorRole.accent,
      ),
      GlyphItem(
        glyphId: 104,
        codePoint: 0x0068,
        xEm: 2.7,
        yEm: 0.35,
        advanceEm: 0.5,
        colorRole: TexMathColorRole.foreground,
      ),
      GlyphItem(
        glyphId: 100,
        codePoint: 0x0064,
        xEm: 2.7,
        yEm: -0.45,
        advanceEm: 0.5,
        colorRole: TexMathColorRole.muted,
      ),
    ],
  );

  return displayList.toSvg(
    fontSize: 44.0,
    title: 'tex_math DisplayMetrics Box Diagram',
  );
}

void _validateSvgXml(String path, String svg) {
  final String trimmed = svg.trim();
  if (!trimmed.startsWith('<svg ') || !trimmed.endsWith('</svg>')) {
    throw StateError(
      '$path did not produce a valid standalone <svg> document.',
    );
  }
  if (!trimmed.contains('xmlns="http://www.w3.org/2000/svg"')) {
    throw StateError('$path is missing SVG XML namespace attribute.');
  }
  if (!trimmed.contains('viewBox="')) {
    throw StateError('$path is missing viewBox attribute.');
  }
  final int openTags = RegExp(
    r'<(?!/)([A-Za-z][A-Za-z0-9:-]*)(?:[^>"\x27]|"[^"]*"|\x27[^\x27]*\x27)*(?<!/)>',
  ).allMatches(trimmed).length;
  final int closeTags = RegExp(r'</([A-Za-z][A-Za-z0-9:-]*)>')
      .allMatches(trimmed)
      .length;
  if (openTags != closeTags || openTags == 0) {
    throw StateError(
      '$path failed balanced XML tag check (open=$openTags, close=$closeTags).',
    );
  }
}
