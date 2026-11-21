import 'package:flutter/material.dart';
import 'package:tex_math/tex_math.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

/// Entry point for the `tex_math` macOS comparison studio application.
void main() {
  runApp(const TexMathStudioApp());
}

/// Root widget for the three-way TeX math comparison workbench.
final class TexMathStudioApp extends StatelessWidget {
  /// Creates the studio workbench application.
  const TexMathStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'tex_math Studio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
        useMaterial3: true,
      ),
      home: const StudioWorkbenchPage(),
    );
  }
}

/// Interactive workbench allowing TeX input editing, display-mode toggling,
/// and side-by-side comparison across `tex_math`, MathJax, and KaTeX panes.
final class StudioWorkbenchPage extends StatefulWidget {
  /// Creates the studio workbench page.
  const StudioWorkbenchPage({super.key});

  @override
  State<StudioWorkbenchPage> createState() => _StudioWorkbenchPageState();
}

final class _StudioWorkbenchPageState extends State<StudioWorkbenchPage> {
  static const List<String> _presets = <String>[
    r'\frac{a + b}{c - d}',
    r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
    r'\begin{pmatrix} 1 & 0 \\ 0 & 1 \end{pmatrix}',
  ];

  late final TextEditingController _controller;
  TexMathDisplayMode _displayMode = TexMathDisplayMode.display;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _presets.first);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String source = _controller.text;

    return Scaffold(
      appBar: AppBar(
        title: const Text('tex_math Comparison Studio'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: SegmentedButton<TexMathDisplayMode>(
              segments: const <ButtonSegment<TexMathDisplayMode>>[
                ButtonSegment<TexMathDisplayMode>(
                  value: TexMathDisplayMode.display,
                  label: Text('Display'),
                ),
                ButtonSegment<TexMathDisplayMode>(
                  value: TexMathDisplayMode.inline,
                  label: Text('Inline'),
                ),
              ],
              selected: <TexMathDisplayMode>{_displayMode},
              onSelectionChanged: (Set<TexMathDisplayMode> next) {
                setState(() {
                  _displayMode = next.first;
                });
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: _presets.map((String preset) {
                return ActionChip(
                  label: Text(preset),
                  onPressed: () {
                    setState(() {
                      _controller.text = preset;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 12.0),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'TeX Source',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16.0),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _ComparisonPane(
                      title: 'tex_math (Pure Dart)',
                      child: Center(
                        child: TexMath(source, displayMode: _displayMode),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: _ComparisonPane(
                      title: 'MathJax 4.1.3 Oracle',
                      child: _OraclePlaceholder(
                        engineName: 'MathJax 4.1.3 SVG Oracle',
                        source: source,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: _ComparisonPane(
                      title: 'KaTeX 0.19.1 Comparison',
                      child: _OraclePlaceholder(
                        engineName: 'KaTeX 0.19.1 Reference',
                        source: source,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ComparisonPane extends StatelessWidget {
  const _ComparisonPane({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

final class _OraclePlaceholder extends StatelessWidget {
  const _OraclePlaceholder({required this.engineName, required this.source});

  final String engineName;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(engineName, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8.0),
          Text(
            source,
            style: const TextStyle(fontFamily: 'monospace'),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
