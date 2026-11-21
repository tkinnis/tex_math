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
    'doc/images/showcase_gaussian_integral.svg': _buildShowcaseSvg(
      engine,
      tex: r'\int_{-\infty}^{\infty} e^{-\alpha x^2}\,dx = \sqrt{\frac{\pi}{\alpha}} \quad (\alpha > 0)',
      title: 'tex_math Showcase: Gaussian Integral',
    ),
    'doc/images/showcase_piecewise_cases.svg': _buildShowcaseSvg(
      engine,
      tex: r'|x| = \begin{cases} x & \text{if } x \ge 0 \\ -x & \text{if } x < 0 \end{cases}',
      title: 'tex_math Showcase: Piecewise Cases',
    ),
    'doc/images/showcase_matrix_rotation.svg': _buildShowcaseSvg(
      engine,
      tex: r'R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}',
      title: 'tex_math Showcase: Rotation Matrix',
    ),
    'doc/images/showcase_nested_radical.svg': _buildShowcaseSvg(
      engine,
      tex:
          r'\sqrt{\frac{\frac{a}{b} + \frac{c}{d}}{\frac{e}{f} - \frac{g}{h}}}',
      title: 'tex_math Showcase: Nested Radical',
    ),
    'doc/images/showcase_chemistry.svg': _buildShowcaseSvg(
      engine,
      tex: r'\ce{N2 + 3H2 <=> 2NH3}',
      title: 'tex_math Showcase: Chemistry (mhchem)',
    ),
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
    options: const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      packages: TexMathOptions.defaultPackages,
    ),
  );
  final DisplayMetrics raw = rendered.displayList.metrics;
  const double padX = 0.50;
  const double padY = 0.40;
  const double baselineOverhangX = 0.22;

  final List<DisplayItem> items = <DisplayItem>[
    RuleItem(
      xEm: padX - baselineOverhangX,
      yEm: -0.008,
      widthEm: raw.widthEm + baselineOverhangX * 2,
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

  return _wrapWithCardBackdrop(
    displayList.toSvg(fontSize: 48.0, title: 'tex_math DisplayList Sample'),
  );
}

String _buildBoxMetricsDiagramSvg(TexMathEngine engine) {
  final RenderResult rendered = engine.render(
    r'\sum_{i=1}^{n} x_i',
    options: const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      packages: TexMathOptions.defaultPackages,
    ),
  );
  final DisplayMetrics raw = rendered.displayList.metrics;

  const double padLeft = 0.60;
  const double padRight = 1.55;
  const double padTop = 1.28;
  const double padBottom = 0.42;
  const double boxStrokeEm = 0.025;
  const double lineThicknessEm = 0.026;
  const double tickHalfEm = 0.09;
  const double baselineLeftTickEm = 0.16;

  final double boxRight = padLeft + raw.widthEm;
  final double wLineY = raw.heightEm + 0.28;
  final double dimX = boxRight + 0.34;
  final double labelRightX = dimX + tickHalfEm + 0.16;

  final DisplayList wList = engine.render('w').displayList;
  final DisplayList hList = engine.render('h').displayList;
  final DisplayList dList = engine.render('d').displayList;

  final double wDx = padLeft + (raw.widthEm - wList.metrics.widthEm) / 2;
  final double wDy = wLineY + tickHalfEm + 0.10;

  final double hVisualCenterEm =
      (hList.metrics.heightEm - hList.metrics.depthEm) / 2;
  final double dVisualCenterEm =
      (dList.metrics.heightEm - dList.metrics.depthEm) / 2;
  final double hDy = raw.heightEm / 2 - hVisualCenterEm;
  final double dDy = -raw.depthEm / 2 - dVisualCenterEm;

  final List<DisplayItem> wLabel = _recolorAndOffset(
    wList.items,
    dx: wDx,
    dy: wDy,
    colorRole: TexMathColorRole.accent,
  );
  final List<DisplayItem> hLabel = _recolorAndOffset(
    hList.items,
    dx: labelRightX,
    dy: hDy,
    colorRole: TexMathColorRole.foreground,
  );
  final List<DisplayItem> dLabel = _recolorAndOffset(
    dList.items,
    dx: labelRightX,
    dy: dDy,
    colorRole: TexMathColorRole.muted,
  );

  final List<DisplayItem> items = <DisplayItem>[
    // Muted bounding box (#9CA3AF).
    RuleItem(
      xEm: padLeft,
      yEm: -raw.depthEm,
      widthEm: raw.widthEm,
      heightEm: raw.heightEm + raw.depthEm,
      strokeWidthEm: boxStrokeEm,
      colorRole: TexMathColorRole.custom,
      customColor: 0xFF9CA3AF,
    ),
    // Solid accent blue (#2563EB) baseline across box + left-edge tick.
    RuleItem(
      xEm: padLeft - baselineLeftTickEm,
      yEm: -lineThicknessEm / 2,
      widthEm: raw.widthEm + baselineLeftTickEm,
      heightEm: lineThicknessEm,
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
    // Width dimension span line + end ticks above the box.
    RuleItem(
      xEm: padLeft - lineThicknessEm / 2,
      yEm: wLineY - lineThicknessEm / 2,
      widthEm: raw.widthEm + lineThicknessEm,
      heightEm: lineThicknessEm,
      colorRole: TexMathColorRole.accent,
    ),
    RuleItem(
      xEm: padLeft - lineThicknessEm / 2,
      yEm: wLineY - tickHalfEm,
      widthEm: lineThicknessEm,
      heightEm: tickHalfEm * 2,
      colorRole: TexMathColorRole.accent,
    ),
    RuleItem(
      xEm: boxRight - lineThicknessEm / 2,
      yEm: wLineY - tickHalfEm,
      widthEm: lineThicknessEm,
      heightEm: tickHalfEm * 2,
      colorRole: TexMathColorRole.accent,
    ),
    ...wLabel,
    // Depth dimension span line + baseline/bottom ticks to the right.
    RuleItem(
      xEm: dimX - lineThicknessEm / 2,
      yEm: -raw.depthEm - lineThicknessEm / 2,
      widthEm: lineThicknessEm,
      heightEm: raw.depthEm + lineThicknessEm,
      colorRole: TexMathColorRole.muted,
    ),
    RuleItem(
      xEm: dimX - tickHalfEm,
      yEm: -raw.depthEm - lineThicknessEm / 2,
      widthEm: tickHalfEm * 2,
      heightEm: lineThicknessEm,
      colorRole: TexMathColorRole.muted,
    ),
    RuleItem(
      xEm: dimX - tickHalfEm,
      yEm: -lineThicknessEm / 2,
      widthEm: tickHalfEm * 2,
      heightEm: lineThicknessEm,
      colorRole: TexMathColorRole.muted,
    ),
    ...dLabel,
    // Height dimension span line + top/baseline ticks to the right.
    RuleItem(
      xEm: dimX - lineThicknessEm / 2,
      yEm: -lineThicknessEm / 2,
      widthEm: lineThicknessEm,
      heightEm: raw.heightEm + lineThicknessEm,
      colorRole: TexMathColorRole.foreground,
    ),
    RuleItem(
      xEm: dimX - tickHalfEm,
      yEm: raw.heightEm - lineThicknessEm / 2,
      widthEm: tickHalfEm * 2,
      heightEm: lineThicknessEm,
      colorRole: TexMathColorRole.foreground,
    ),
    RuleItem(
      xEm: dimX - tickHalfEm,
      yEm: -lineThicknessEm / 2,
      widthEm: tickHalfEm * 2,
      heightEm: lineThicknessEm,
      colorRole: TexMathColorRole.foreground,
    ),
    ...hLabel,
  ];

  final DisplayList displayList = DisplayList(
    source: rendered.source,
    metrics: DisplayMetrics(
      widthEm: padLeft + raw.widthEm + padRight,
      heightEm: raw.heightEm + padTop,
      depthEm: raw.depthEm + padBottom,
      baselineEm: raw.heightEm + padTop,
      unitsPerEm: raw.unitsPerEm,
    ),
    items: items,
  );

  return _wrapWithCardBackdrop(
    displayList.toSvg(
      fontSize: 44.0,
      title: 'tex_math DisplayMetrics Box Diagram',
    ),
  );
}

String _buildShowcaseSvg(
  TexMathEngine engine, {
  required String tex,
  required String title,
  double fontSize = 36.0,
  double padX = 0.55,
  double padY = 0.42,
}) {
  final RenderResult rendered = engine.render(
    tex,
    options: const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      packages: TexMathOptions.defaultPackages,
    ),
  );
  final DisplayMetrics raw = rendered.displayList.metrics;

  final DisplayList displayList = DisplayList(
    source: rendered.source,
    metrics: DisplayMetrics(
      widthEm: raw.widthEm + padX * 2,
      heightEm: raw.heightEm + padY,
      depthEm: raw.depthEm + padY,
      baselineEm: raw.heightEm + padY,
      unitsPerEm: raw.unitsPerEm,
    ),
    items: _offsetDisplayItems(rendered.displayList.items, dx: padX),
  );

  return _wrapWithCardBackdrop(
    displayList.toSvg(fontSize: fontSize, title: title),
  );
}

String _wrapWithCardBackdrop(String svg) {
  const String cardRect =
      '<rect width="100%" height="100%" rx="8" fill="#FFFFFF" stroke="#E2E8F0"/>';
  const String titleClose = '</title>';
  final int titleEnd = svg.indexOf(titleClose);
  if (titleEnd != -1) {
    final int insertAt = titleEnd + titleClose.length;
    return '${svg.substring(0, insertAt)}$cardRect${svg.substring(insertAt)}';
  }
  final int svgTagEnd = svg.indexOf('>');
  if (svgTagEnd != -1) {
    final int insertAt = svgTagEnd + 1;
    return '${svg.substring(0, insertAt)}$cardRect${svg.substring(insertAt)}';
  }
  return svg;
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
