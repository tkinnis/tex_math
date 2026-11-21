# API Manual

This manual documents the Phase 1 public API exported by **`package:tex_math/tex_math.dart`** (pure Dart) and **`package:tex_math_flutter/tex_math_flutter.dart`** (Flutter widgets, theming, font asset bundle, and background isolate layouter).

---

## 1. Core Package (`package:tex_math/tex_math.dart`)

### Entry Points & Engine (`TexMathEngine`)

`TexMathEngine` is an immutable, stateless entry point executing the TeX math-mode pipeline synchronously from in-memory strings and `MathFont` instances.

| Symbol | Signature / Role | Phase 1 Behavior |
| :--- | :--- | :--- |
| `TexMathEngine` | `const TexMathEngine({TexMathOptions defaultOptions = const TexMathOptions(), MathFont? font})` | Constructs a stateless engine with default options and an optional font. |
| `parse` | `MathNode parse(String source, {TexMathOptions? options})` | Checks `maxInputLength` (`TexMathBudgetError`), then throws `TexMathUnsupportedError`. |
| `layout` | `DisplayList layout(MathNode syntaxTree, {TexMathOptions? options, MathFont? font})` | Checks `maxNestingDepth` (`TexMathBudgetError`), then throws `TexMathUnsupportedError`. |
| `render` | `RenderResult render(String source, {TexMathOptions? options, MathFont? font})` | Composes `parse` and `layout` into a `RenderResult`. |
| `renderToSvg` | `String renderToSvg(String source, {TexMathOptions? options, MathFont? font, double fontSize = 16.0})` | Composes `render` and `RenderResult.toSvg`. |
| `toMathMl` | `String toMathMl(String source, {TexMathOptions? options})` | Checks `maxInputLength`, then throws `TexMathUnsupportedError`. |
| `toSpokenText` | `String toSpokenText(String source, {TexMathOptions? options})` | Checks `maxInputLength`, then throws `TexMathUnsupportedError`. |
| `parseTex` | `MathNode parseTex(String source, {TexMathOptions options = const TexMathOptions()})` | Top-level convenience wrapper calling `const TexMathEngine().parse(...)`. |
| `renderTex` | `RenderResult renderTex(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font})` | Top-level convenience wrapper calling `const TexMathEngine().render(...)`. |
| `renderTexToSvg` | `String renderTexToSvg(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font, double fontSize = 16.0})` | Top-level convenience wrapper calling `const TexMathEngine().renderToSvg(...)`. |

### Configuration (`TexMathOptions`, `TexMathBudgets`, Enums)

* **`TexMathDisplayMode`**: Enum with `inline` (`$...$`) and `display` (`$$...$$`).
* **`TexMathColorRole`**: Semantic paint roles (`foreground`, `accent`, `error`, `muted`, `custom`).
* **`TexMathStyle`**: Appendix G layout styles (`display`, `text`, `script`, `scriptScript`, `crampedDisplay`, `crampedText`, `crampedScript`, `crampedScriptScript`).
* **`TexMathBudgets`**: Immutable safety limit configuration with `copyWith(...)` and defensive defaults (`defaultMaxInputLength = 50000`, `defaultMaxMacroDepth = 64`, `defaultMaxMacroExpansions = 10000`, `defaultMaxNestingDepth = 64`, `defaultMaxOutputItems = 50000`, `defaultMaxSvgLength = 4000000`).
* **`TexMathOptions`**: Immutable options (`displayMode = TexMathDisplayMode.display`, `packages = TexMathOptions.defaultPackages`, `macros = const <String, String>{}`, `budgets = const TexMathBudgets()`, `strictErrors = true`, plus `copyWith(...)`). `TexMathOptions.defaultPackages` contains the 29 active JupyterLab default TeX packages excluding `noerrors` and `noundefined`.

### Source Spans & Errors (`SourceSpan`, `TexMathError`, `TexMathErrorClass`)

`SourceSpan` represents a half-open UTF-16 code-unit range `[start, end)` within TeX source text, providing `SourceSpan.empty([int offset = 0])`, `SourceSpan.zero`, `length`, `isEmpty`, `slice(String source)`, and `merge(SourceSpan other)`.

`TexMathError` is a `sealed class TexMathError implements Exception` carrying `message` (`String`), `errorClass` (`TexMathErrorClass`), and optional `span` (`SourceSpan?`). Its five `final` subclasses enable exhaustive Dart 3 `switch` handling:

* **`TexMathSyntaxError`**: Tokenization and parser grammar errors (`errorClass` defaults to `TexMathErrorClass.syntaxError`).
* **`TexMathMacroError`**: Macro definition and expansion errors (`errorClass` defaults to `TexMathErrorClass.invalidMacroDefinition`).
* **`TexMathBudgetError`**: Resource budget violations (`errorClass` fixed to `TexMathErrorClass.budgetExceeded`), adding `budgetName`, `limit`, and `actual`.
* **`TexMathFontError`**: Invalid, empty, or malformed font payload errors (`errorClass` defaults to `TexMathErrorClass.invalidFont`).
* **`TexMathUnsupportedError`**: Unimplemented TeX features or pipeline stages (`errorClass` defaults to `TexMathErrorClass.unsupportedFeature`).

`TexMathErrorClass` defines 16 machine-readable error categories aligned to MathJax TeX error classes: `undefinedControlSequence`, `missingBrace`, `extraBrace`, `misplacedAlignmentTab`, `misplacedNewline`, `missingDelimiter`, `extraDelimiter`, `mismatchedEnvironment`, `doubleScript`, `missingArgument`, `invalidMacroDefinition`, `unknownEnvironment`, `budgetExceeded`, `invalidFont`, `unsupportedFeature`, and `syntaxError`.

### Syntax Tree (`sealed class MathNode`)

Every `MathNode` subclass is `@immutable` and stores `SourceSpan span`:

| Node Type | Key Properties | TeX Role |
| :--- | :--- | :--- |
| `MathRootNode` | `children`, `displayMode` | Top-level expression container. |
| `MathGroupNode` | `children`, `isExplicitGroup` | Brace-delimited `{...}` or implicit sub-group. |
| `SymbolNode` | `value`, `command` | Identifiers, numerals, relations, and named symbols. |
| `OperatorNode` | `operatorName`, `hasLimits`, `isLarge` | Large or named operators such as `\sum`, `\int`, and `\lim`. |
| `FractionNode` | `numerator`, `denominator`, `ruleThicknessEm`, `leftDelimiter`, `rightDelimiter` | Fractions, `\dfrac`, `\tfrac`, and binomials (`\binom`). |
| `ScriptNode` | `base`, `subscript`, `superscript`, `limitsAboveBelow` | Subscripts, superscripts, and stacked limits. |
| `RadicalNode` | `radicand`, `index` | Square and nth roots (`\sqrt[n]{x}`). |
| `AccentNode` | `base`, `accent`, `isWide`, `isUnder` | Over/under accents and wide accents. |
| `DelimiterNode` | `children`, `leftDelimiter`, `rightDelimiter`, `fixedSizeEm` | Stretchy `\left...\right` or fixed-size `\big` groups. |
| `MatrixNode` | `rows`, `environment`, `columnAlignments` | Grids, matrices, arrays, and alignment environments. |
| `TextNode` | `text`, `styleCommand` | Embedded text-mode runs (`\text`, `\mathrm`, `\textbf`). |
| `SpaceNode` | `widthEm`, `command` | Explicit horizontal skips (`\,`, `\quad`, `\hspace`). |
| `StyleNode` | `style`, `children` | Explicit math style scopes (`TexMathStyle`). |
| `ColorNode` | `role`, `children`, `colorValue` | Semantic or explicit color scopes. |
| `TagNode` | `label`, `isStarred`, `body` | Equation tags and labels (`\tag`, `\tag*`, `\label`). |
| `ErrorNode` | `error`, `rawSource` | Non-fatal diagnostic placeholder when `strictErrors` is `false`. |

### OpenType Font & Outlines (`MathFont`, `GlyphOutline`, `PathCommand`)

* **`PathCommand`**: Sealed vector outline command hierarchy (`MoveTo(x, y)`, `LineTo(x, y)`, `QuadTo(controlX, controlY, x, y)`, `CubicTo(control1X, control1Y, control2X, control2Y, x, y)`, `ClosePath()`).
* **`GlyphOutline`**: Immutable contour record for a `glyphId` storing `commands` (`List<PathCommand>`), `advanceWidth` (`double`), `isEmpty`, and `toSvgPathData()` (emitting SVG path `d` commands).
* **`MathFont`**: Pure-Dart OpenType math font constructed exclusively from in-memory bytes via `MathFont.fromBytes(Uint8List bytes, {int maxBytes = MathFont.defaultMaxFontBytes})`, where `defaultMaxFontBytes` is `16 * 1024 * 1024` (16 MiB). In Phase 1, `fromBytes` rejects empty buffers (`TexMathFontError`), oversized buffers (`TexMathBudgetError`), and unrecognized SFNT signatures (`TexMathFontError`), then throws `TexMathUnsupportedError` after validating `OTTO`, `0x00010000`, `true`, or `typ1` headers. Exposes `familyName`, `unitsPerEm`, and `outlineForGlyph(int glyphId)`.

### Display List & Exporters (`DisplayList`, `DisplayItem`, `DisplayMetrics`, `RenderResult`)

`DisplayList` stores `DisplayMetrics metrics`, `List<DisplayItem> items`, and optional `String? source`, and implements standalone XML SVG serialization via:

```dart
String toSvg({
  double fontSize = 16.0,
  int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
  int maxSvgLength = TexMathBudgets.defaultMaxSvgLength,
  Map<TexMathColorRole, String>? colors,
  String? title,
})
```

* **`DisplayMetrics`**: Bounding box (`widthEm`, `heightEm`, `depthEm`, `baselineEm` defaulting to `heightEm`, `unitsPerEm` defaulting to `1000`) plus computed getters `totalHeightEm`, `widthUnits`, `heightUnits`, and `depthUnits`.
* **`DisplayItem`** (`sealed class` with `span`, `colorRole`, `customColor`):
  * **`GlyphItem`**: `glyphId`, `codePoint`, `xEm`, `yEm`, `scaleX = 1.0`, `scaleY = 1.0`, `advanceEm = 0.5`, and optional `GlyphOutline? outline`.
  * **`RuleItem`**: `xEm`, `yEm`, `widthEm`, `heightEm` for fraction bars, vincula, and rules.
  * **`AnchorItem`**: `id`, `xEm`, `yEm`, and optional `label` for non-inked structural coordinates.
* **`RenderResult`**: Combines `displayList`, `syntaxTree`, and `source`, exposing `toSvg(...)`, `toMathMl()`, and `toSpokenText()`.

### Example Usage (Standalone `DisplayList` SVG Export)

```dart
import 'package:tex_math/tex_math.dart';

String renderSampleFraction() {
  const DisplayList displayList = DisplayList(
    source: r'\frac{a + b}{c}',
    metrics: DisplayMetrics(
      widthEm: 2.8,
      heightEm: 1.15,
      depthEm: 0.75,
      unitsPerEm: 1000,
    ),
    items: <DisplayItem>[
      RuleItem(xEm: 0.1, yEm: 0.24, widthEm: 2.4, heightEm: 0.05),
      AnchorItem(id: 'eq-1', xEm: 2.7, yEm: 0.0, label: 'fraction'),
    ],
  );
  return displayList.toSvg(fontSize: 24.0, title: 'Sample fraction');
}
```

---

## 2. Flutter Package (`package:tex_math_flutter/tex_math_flutter.dart`)

### Widgets (`TexMath`, `TexMathSpan`, `TexMathErrorWidget`, `TexMathErrorBuilder`)

* **`TexMath`**: `StatelessWidget` supporting `const TexMath(source, ...)` (default `TexMathDisplayMode.display`), `const TexMath.inline(...)`, `const TexMath.display(...)`, and `const TexMath.displayList(displayList, ...)`. Applies ambient `DefaultTextStyle`, `MediaQuery.textScalerOf(context)`, `Baseline(baselineType: TextBaseline.alphabetic)`, `Semantics`, and automatic `SelectionArea` wrapping when `selectable` is `true` and no ancestor `SelectionContainer` is present.
* **`TexMathSpan`**: `WidgetSpan` subclass aligned with `PlaceholderAlignment.baseline` and `TextBaseline.alphabetic` for embedding inline TeX math inside `Text.rich` or `RichText` (`selectable` defaults to `false`).
* **`TexMathErrorWidget`**: Default error fallback widget displaying `source` in monospace alongside `errorMessage ?? error?.message` tinted by `TexMathThemeData.error` and `TexMathThemeData.errorBackground`.
* **`TexMathErrorBuilder`**: Signature `Widget Function(BuildContext context, String source, TexMathError error)` for custom `TexMath` error widgets.

### Theming & Painting (`TexMathTheme`, `TexMathThemeData`, `TexMathDisplayPainter`)

* **`TexMathThemeData`**: Immutable theme configuration carrying `foreground`, `accent`, `error`, `muted`, optional `errorBackground`, and `fontSize = 18.0`, with `TexMathThemeData.fromColorScheme(ColorScheme scheme, {double fontSize = 18.0})`, `TexMathThemeData.fallback`, `colorForRole(...)`, `copyWith(...)`, and `lerp(...)`.
* **`TexMathTheme`**: `InheritedTheme` supplying `TexMathThemeData` via `TexMathTheme.of(context)` (falling back to `Theme.of(context).colorScheme`) and `TexMathTheme.maybeOf(context)`.
* **`TexMathDisplayPainter`**: `CustomPainter` rendering `DisplayList` items onto a Flutter `Canvas`, converting `GlyphOutline.commands` via `TexMathDisplayPainter.buildPathFromCommands(List<PathCommand> commands)` and repainting on theme color changes without re-layout.

### Bundled Math Font & Isolate Layouter (`TexMathFontBundle`, `TexMathFontAsset`, `TexMathIsolateLayouter`, `TexMathLayoutCacheKey`)

* **`TexMathFontBundle`**: Loads and caches `packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf`, `GUST-FONT-LICENSE.txt`, and `MANIFEST-NewCMMath.txt` via `TexMathFontBundle.load({AssetBundle? bundle, bool forceReload = false})`, validating non-empty bytes and the `OTTO` OpenType signature. Provides `@visibleForTesting static void clearCache()`.
* **`TexMathFontAsset`**: Immutable payload returned by `TexMathFontBundle.load()`, exposing `bytes`, `familyName`, `assetPath`, `licenseText`, `byteLength`, `hasOttoHeader`, and `decodeMathFont()`.
* **`TexMathLayoutCacheKey`**: Immutable `(source, options, fontId)` key with structural value equality.
* **`TexMathIsolateLayouter`**: Runs `TexMathEngine.render` off the UI thread via `Isolate.run` (`renderInBackground(...)`, `layoutInBackground(...)`) backed by an in-memory bounded cache (`maxCacheEntries = 256`, `fontId = 'NewCMMath-Regular'`, `cacheLength`, `getCached`, `putCached`, `clearCache`).

### Example Usage (Flutter Theme & Inline Span)

```dart
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

Widget buildMathParagraph(DisplayList precomputed) {
  return TexMathTheme(
    data: TexMathThemeData.fallback.copyWith(fontSize: 20.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TexMath.displayList(precomputed, semanticsLabel: 'Precomputed formula'),
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              const TextSpan(text: 'Inline relation: '),
              TexMathSpan(r'a^2 + b^2 = c^2'),
            ],
          ),
        ),
      ],
    ),
  );
}
```
