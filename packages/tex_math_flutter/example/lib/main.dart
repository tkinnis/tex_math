import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

/// Entry point for the `tex_math_flutter` example application.
void main() {
  runApp(const TexMathExampleApp());
}

/// Example application demonstrating OpenType `MATH` display equations, inline
/// `TexMathSpan` prose alignment, zero-relayout dark/light theme toggling,
/// `SelectionArea` copy-as-LaTeX, `TexMathErrorWidget` fallback rendering, and
/// a 50-equation notebook list backed by `TexMathIsolateLayouter`.
final class TexMathExampleApp extends StatefulWidget {
  /// Creates the example application.
  const TexMathExampleApp({super.key});

  @override
  State<TexMathExampleApp> createState() => _TexMathExampleAppState();
}

final class _TexMathExampleAppState extends State<TexMathExampleApp> {
  bool _isDark = false;

  void _toggleTheme() {
    setState(() {
      _isDark = !_isDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    final ThemeData darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF60A5FA),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'tex_math_flutter Example',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: ExampleHomePage(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

/// Primary screen hosting the showcase and 50-equation notebook tabs.
final class ExampleHomePage extends StatefulWidget {
  /// Creates the example home page.
  const ExampleHomePage({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  /// Whether dark mode is active.
  final bool isDark;

  /// Callback toggling between light and dark themes.
  final VoidCallback onToggleTheme;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

final class _ExampleHomePageState extends State<ExampleHomePage> {
  late final Future<TexMathFontAsset> _fontAssetFuture;
  TexMathIsolateLayouter? _notebookLayouter;
  String? _notebookError;
  int _showcaseLayoutCount = 0;
  bool _showcaseRefreshScheduled = false;

  static final List<String> _notebookEquations = List<String>.generate(
    50,
    (int index) => _buildNotebookEquation(index),
  );

  static String _buildNotebookEquation(int index) {
    final int n = index + 1;
    switch (index % 5) {
      case 0:
        return 'f_{$n}(x) = \\frac{x^{$n} + $n}{\\sqrt{x^2 + $n}}';
      case 1:
        return '\\sum_{k=1}^{$n} k^2 = \\frac{$n($n+1)(2\\cdot$n+1)}{6}';
      case 2:
        return '\\int_{0}^{$n} e^{-t/$n}\\,dt = $n(1 - e^{-1})';
      case 3:
        return 'A_{$n} = \\begin{pmatrix} $n & -1 \\\\ 1 & $n \\end{pmatrix}';
      default:
        return '\\binom{$n + 2}{2} = \\frac{($n + 2)($n + 1)}{2}';
    }
  }

  @override
  void initState() {
    super.initState();
    _fontAssetFuture = TexMathFontBundle.load();
    unawaited(_initNotebookLayouter());
  }

  Future<void> _initNotebookLayouter() async {
    try {
      final TexMathIsolateLayouter layouter =
          await TexMathIsolateLayouter.withBundledFont(maxCacheEntries: 128);
      if (!mounted) {
        await layouter.dispose();
        return;
      }
      setState(() {
        _notebookLayouter = layouter;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notebookError = '$error';
      });
    }
  }

  @override
  void dispose() {
    final TexMathIsolateLayouter? layouter = _notebookLayouter;
    _notebookLayouter = null;
    if (layouter != null) {
      unawaited(layouter.dispose());
    }
    super.dispose();
  }

  void _recordShowcaseLayout() {
    _showcaseLayoutCount++;
    if (!mounted || _showcaseRefreshScheduled) {
      return;
    }
    _showcaseRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showcaseRefreshScheduled = false;
      if (mounted) {
        setState(() {});
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TexMathThemeData mathTheme = TexMathThemeData.fromColorScheme(
      scheme,
      fontSize: 24.0,
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('tex_math_flutter Example'),
          actions: <Widget>[
            IconButton(
              key: const Key('theme-toggle-button'),
              tooltip: widget.isDark
                  ? 'Switch to light theme'
                  : 'Switch to dark theme',
              onPressed: widget.onToggleTheme,
              icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(text: 'Showcase'),
              Tab(text: 'Notebook (50)'),
            ],
          ),
        ),
        body: TexMathTheme(
          data: mathTheme,
          child: TabBarView(
            children: <Widget>[
              _buildShowcaseTab(context),
              _buildNotebookTab(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShowcaseTab(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    const TextStyle displayStyle = TextStyle(fontSize: 22.0);
    const TextStyle proseStyle = TextStyle(fontSize: 16.0, height: 1.5);

    return ListView(
      key: const Key('showcase-list'),
      padding: const EdgeInsets.all(20.0),
      children: <Widget>[
        _ShowcaseCard(
          title: 'Display Equations (Cached OpenType MATH Paths)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TexMath(
                r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
                textStyle: displayStyle,
                debugOnLayout: _recordShowcaseLayout,
              ),
              const SizedBox(height: 16.0),
              const TexMath(
                r'\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}',
                textStyle: displayStyle,
              ),
              const SizedBox(height: 16.0),
              const TexMath(
                r'R(\theta) = \begin{pmatrix} \cos\theta & -\sin\theta \\ \sin\theta & \cos\theta \end{pmatrix}',
                textStyle: displayStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16.0),
        _ShowcaseCard(
          title: 'Inline TexMathSpan Baseline Alignment',
          child: Text.rich(
            TextSpan(
              style: proseStyle.copyWith(color: textTheme.bodyLarge?.color),
              children: <InlineSpan>[
                const TextSpan(text: 'Relativistic energy '),
                TexMathSpan(r'E = mc^2', style: proseStyle),
                const TextSpan(text: ' reduces at low velocity to '),
                TexMathSpan(r'\frac{1}{2}mv^2', style: proseStyle),
                const TextSpan(text: ' with phase '),
                TexMathSpan(r'\alpha + \beta = \gamma', style: proseStyle),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        _ShowcaseCard(
          title: 'SelectionArea Copy-as-LaTeX',
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Drag across any term or select all to copy valid LaTeX:',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 8.0),
                const TexMath(
                  r'f(x) = \frac{a + b}{c - d} + \sqrt{x^2 + 1}',
                  textStyle: displayStyle,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16.0),
        const _ShowcaseCard(
          title: 'TexMathErrorWidget Diagnostic Fallback',
          child: TexMath(r'\undefinedcmd + \frac{1}{2}'),
        ),
        const SizedBox(height: 16.0),
        _ShowcaseCard(
          title: 'Asset & Cache Status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
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
              const SizedBox(height: 4.0),
              Text(
                'Quadratic layout runs: $_showcaseLayoutCount | '
                'Cached glyph paths: ${TexMathPathCache.shared.length}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotebookTab(BuildContext context) {
    if (_notebookError != null) {
      return Center(child: Text('Isolate layouter error: $_notebookError'));
    }
    final TexMathIsolateLayouter? layouter = _notebookLayouter;
    if (layouter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: <Widget>[
              Text(
                '50 Notebook Equations (Persistent Isolate)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Text('LRU Cache: ${layouter.cacheLength}'),
            ],
          ),
        ),
        const Divider(height: 1.0),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: _notebookEquations.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12.0),
            itemBuilder: (BuildContext context, int index) {
              final String tex = _notebookEquations[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 44.0,
                        child: Text(
                          '[${index + 1}]',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                      Expanded(
                        child: TexMath(
                          tex,
                          layouter: layouter,
                          textStyle: const TextStyle(fontSize: 18.0),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            const SizedBox(height: 4.0),
            child,
          ],
        ),
      ),
    );
  }
}
