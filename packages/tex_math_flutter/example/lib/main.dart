import 'package:flutter/material.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

/// Entry point for the `tex_math_flutter` example application.
void main() {
  runApp(const TexMathExampleApp());
}

/// Example application demonstrating display-list painting, inline math spans,
/// error fallback rendering, and bundled math font asset inspection.
final class TexMathExampleApp extends StatelessWidget {
  /// Creates the example application.
  const TexMathExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tex_math_flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

/// Primary screen displaying sample `TexMath` widgets and asset bundle status.
final class ExampleHomePage extends StatefulWidget {
  /// Creates the example home page.
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

final class _ExampleHomePageState extends State<ExampleHomePage> {
  late final Future<TexMathFontAsset> _fontAssetFuture;

  @override
  void initState() {
    super.initState();
    _fontAssetFuture = TexMathFontBundle.load();
  }

  static const DisplayList _sampleDisplayList = DisplayList(
    source: r'\frac{\Delta}{x}',
    metrics: DisplayMetrics(
      widthEm: 2.2,
      heightEm: 1.2,
      depthEm: 0.9,
      unitsPerEm: 1000,
    ),
    items: <DisplayItem>[
      GlyphItem(
        glyphId: 1,
        codePoint: 0x0394,
        xEm: 0.65,
        yEm: 0.42,
        outline: GlyphOutline(
          glyphId: 1,
          commands: <PathCommand>[
            MoveTo(0, 0),
            LineTo(450, 750),
            LineTo(900, 0),
            ClosePath(),
          ],
        ),
      ),
      RuleItem(
        xEm: 0.15,
        yEm: 0.22,
        widthEm: 1.9,
        heightEm: 0.08,
        colorRole: TexMathColorRole.accent,
      ),
      GlyphItem(glyphId: 2, codePoint: 0x0078, xEm: 0.85, yEm: -0.58),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('tex_math_flutter Example')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: TexMathTheme(
          data: TexMathThemeData.fromColorScheme(
            Theme.of(context).colorScheme,
            fontSize: 32.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Pre-laid-out vector DisplayList:'),
              const SizedBox(height: 12.0),
              const TexMath.displayList(
                _sampleDisplayList,
                semanticsLabel: 'Sample fraction display list',
              ),
              const SizedBox(height: 24.0),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    const TextSpan(text: 'Inline TeX fallback span: '),
                    TexMathSpan(r'E = mc^2'),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
              FutureBuilder<TexMathFontAsset>(
                future: _fontAssetFuture,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<TexMathFontAsset> snapshot,
                    ) {
                      if (snapshot.hasData) {
                        final TexMathFontAsset asset = snapshot.data!;
                        return Text(
                          'Bundled font: ${asset.familyName} '
                          '(${asset.byteLength} bytes)',
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Font load failed: ${snapshot.error}');
                      }
                      return const Text('Loading bundled math font...');
                    },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
