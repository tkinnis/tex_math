import 'dart:io';

import 'package:tex_math/tex_math.dart';

import 'src/engine_check.dart';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: dart run tool/generate_doc_images.dart [--check]');
    return;
  }

  final bool checkOnly = args.contains('--check');
  final TexMathEngine engine = defaultVerificationEngine();
  final Map<String, String> assets = <String, String>{
    'doc/images/display_list_sample.svg': _buildDisplayListSampleSvg(engine),
    'doc/images/box_metrics_diagram.svg': _buildBoxMetricsDiagramSvg(engine),
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

String _buildDisplayListSampleSvg(TexMathEngine engine) {
  final RenderResult rendered = engine.render(
    r'\frac{a + b}{c - d}',
    options: const TexMathOptions(displayMode: TexMathDisplayMode.display),
  );
  final DisplayMetrics raw = rendered.displayList.metrics;
  const double padX = 0.35;
  const double padY = 0.25;

  final List<DisplayItem> items = <DisplayItem>[
    RuleItem(
      xEm: 0.15,
      yEm: -0.008,
      widthEm: raw.widthEm + (padX - 0.15) * 2,
      heightEm: 0.016,
      colorRole: TexMathColorRole.muted,
    ),
    const AnchorItem(id: 'origin', xEm: padX, yEm: 0.0, label: 'baseline'),
    ..._offsetDisplayItems(rendered.displayList.items, dx: padX),
    AnchorItem(id: 'end', xEm: padX + raw.widthEm, yEm: 0.0, label: 'advance'),
  ];

  final DisplayList displayList = DisplayList(
    source: rendered.source,
    metrics: DisplayMetrics(
      widthEm: raw.widthEm + padX * 2,
      heightEm: raw.heightEm + padY,
      depthEm: raw.depthEm + padY,
      baselineEm: raw.heightEm + padY,
      unitsPerEm: raw.unitsPerEm,
    ),
    items: items,
  );

  return displayList.toSvg(
    fontSize: 48.0,
    title: 'tex_math DisplayList Sample',
  );
}

String _buildBoxMetricsDiagramSvg(TexMathEngine engine) {
  final RenderResult rendered = engine.render(
    r'\sum_{i=1}^{n} x_i',
    options: const TexMathOptions(displayMode: TexMathDisplayMode.display),
  );
  final DisplayMetrics raw = rendered.displayList.metrics;
  const double padLeft = 0.4;
  const double padRight = 1.4;
  const double padY = 0.25;

  final double labelX = padLeft + raw.widthEm + 0.35;
  final List<DisplayItem> wLabel = _recolorAndOffset(
    engine.render('w').displayList.items,
    dx: labelX,
    dy: raw.heightEm * 0.65,
    colorRole: TexMathColorRole.accent,
  );
  final List<DisplayItem> hLabel = _recolorAndOffset(
    engine.render('h').displayList.items,
    dx: labelX,
    dy: raw.heightEm * 0.18,
    colorRole: TexMathColorRole.foreground,
  );
  final List<DisplayItem> dLabel = _recolorAndOffset(
    engine.render('d').displayList.items,
    dx: labelX,
    dy: -raw.depthEm * 0.65,
    colorRole: TexMathColorRole.muted,
  );

  final List<DisplayItem> items = <DisplayItem>[
    RuleItem(
      xEm: padLeft,
      yEm: -raw.depthEm,
      widthEm: raw.widthEm,
      heightEm: raw.heightEm + raw.depthEm,
      strokeWidthEm: 0.02,
      colorRole: TexMathColorRole.muted,
    ),
    RuleItem(
      xEm: padLeft,
      yEm: -0.015,
      widthEm: raw.widthEm,
      heightEm: 0.03,
      colorRole: TexMathColorRole.accent,
    ),
    const AnchorItem(
      id: 'baseline-start',
      xEm: padLeft,
      yEm: 0.0,
      label: 'baseline',
    ),
    AnchorItem(
      id: 'height-top',
      xEm: padLeft,
      yEm: raw.heightEm,
      label: 'heightEm',
    ),
    AnchorItem(
      id: 'depth-bottom',
      xEm: padLeft,
      yEm: -raw.depthEm,
      label: 'depthEm',
    ),
    ..._offsetDisplayItems(rendered.displayList.items, dx: padLeft),
    ...wLabel,
    ...hLabel,
    ...dLabel,
  ];

  final DisplayList displayList = DisplayList(
    source: rendered.source,
    metrics: DisplayMetrics(
      widthEm: padLeft + raw.widthEm + padRight,
      heightEm: raw.heightEm + padY,
      depthEm: raw.depthEm + padY,
      baselineEm: raw.heightEm + padY,
      unitsPerEm: raw.unitsPerEm,
    ),
    items: items,
  );

  return displayList.toSvg(
    fontSize: 44.0,
    title: 'tex_math DisplayMetrics Box Diagram',
  );
}

List<DisplayItem> _offsetDisplayItems(
  List<DisplayItem> items, {
  double dx = 0.0,
  double dy = 0.0,
}) {
  return _recolorAndOffset(items, dx: dx, dy: dy);
}

List<DisplayItem> _recolorAndOffset(
  List<DisplayItem> items, {
  double dx = 0.0,
  double dy = 0.0,
  TexMathColorRole? colorRole,
}) {
  return <DisplayItem>[
    for (final DisplayItem item in items)
      switch (item) {
        GlyphItem() => GlyphItem(
          glyphId: item.glyphId,
          codePoint: item.codePoint,
          xEm: item.xEm + dx,
          yEm: item.yEm + dy,
          scaleX: item.scaleX,
          scaleY: item.scaleY,
          advanceEm: item.advanceEm,
          outline: item.outline,
          span: item.span,
          colorRole: colorRole ?? item.colorRole,
          customColor: colorRole != null ? null : item.customColor,
        ),
        RuleItem() => RuleItem(
          xEm: item.xEm + dx,
          yEm: item.yEm + dy,
          widthEm: item.widthEm,
          heightEm: item.heightEm,
          strokeWidthEm: item.strokeWidthEm,
          span: item.span,
          colorRole: colorRole ?? item.colorRole,
          customColor: colorRole != null ? null : item.customColor,
        ),
        AnchorItem() => AnchorItem(
          id: item.id,
          xEm: item.xEm + dx,
          yEm: item.yEm + dy,
          label: item.label,
          span: item.span,
          colorRole: colorRole ?? item.colorRole,
          customColor: colorRole != null ? null : item.customColor,
        ),
      },
  ];
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
