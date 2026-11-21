# API Manual

This manual documents the public API exported by **`package:tex_math/tex_math.dart`** (pure Dart) and **`package:tex_math_flutter/tex_math_flutter.dart`** (Flutter widgets, glyph path caching, theming, font asset bundle, selection utilities, and persistent background isolate layouter).

---

## 1. Core Package (`package:tex_math/tex_math.dart`)

### Entry Points & Engine (`TexMathEngine`)

`TexMathEngine` is an immutable, stateless entry point executing the five-stage TeX math-mode pipeline synchronously from in-memory strings and `MathFont` instances with zero filesystem access or global mutable state.

| Symbol | Signature / Role | Behavior |
| :--- | :--- | :--- |
| `TexMathEngine` | `const TexMathEngine({TexMathOptions defaultOptions = const TexMathOptions(), MathFont? font})` | Constructs a stateless engine with default options and an optional default font. |
| `parse` | `MathNode parse(String source, {TexMathOptions? options})` | Tokenizes, expands macros within budgets, and parses `source` into a `MathNode` syntax tree. |
| `layout` | `DisplayList layout(MathNode syntaxTree, {TexMathOptions? options, MathFont? font})` | Enforces `maxNestingDepth` and applies TeX Appendix G OpenType `MATH` layout using `font` (or `TexMathEngine.font`), throwing `TexMathFontError` if neither provides a font with a `MATH` table. |
| `render` | `RenderResult render(String source, {TexMathOptions? options, MathFont? font})` | Composes `parse` and `layout` into an immutable `RenderResult` carrying `displayList`, `syntaxTree`, and `source`. |
| `renderToSvg` | `String renderToSvg(String source, {TexMathOptions? options, MathFont? font, double fontSize = 16.0})` | Composes `render` and `RenderResult.toSvg(...)`, enforcing `maxOutputItems` and `maxSvgLength`. |
| `toMathMl` | `String toMathMl(String source, {TexMathOptions? options})` | Parses `source` and emits Presentation MathML XML. |
| `toSpokenText` | `String toSpokenText(String source, {TexMathOptions? options})` | Parses `source` and emits natural-language spoken math text for assistive technologies. |
| `parseTex` | `MathNode parseTex(String source, {TexMathOptions options = const TexMathOptions()})` | Top-level convenience wrapper calling `const TexMathEngine().parse(...)`. |
| `renderTex` | `RenderResult renderTex(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font})` | Top-level convenience wrapper calling `const TexMathEngine().render(...)`. |
| `renderTexToSvg` | `String renderTexToSvg(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font, double fontSize = 16.0})` | Top-level convenience wrapper calling `const TexMathEngine().renderToSvg(...)`. |

### Configuration (`TexMathOptions`, `TexMathBudgets`, `TexPackageRegistry`)

* **`TexMathDisplayMode`**: Enum with `inline` (`$...$`) and `display` (`$$...$$`).
* **`TexMathColorRole`**: Semantic paint roles (`foreground`, `accent`, `error`, `muted`, `custom`).
* **`TexMathStyle`**: Appendix G layout styles (`display`, `text`, `script`, `scriptScript`, `crampedDisplay`, `crampedText`, `crampedScript`, `crampedScriptScript`).
* **`TexMathAtomClass`**: Appendix G atom spacing categories (`ord`, `op`, `bin`, `rel`, `open`, `close`, `punct`, `inner`).
* **`TexMathFontVariant`**: Math alphabet and style variants (`normal`, `bold`, `italic`, `boldItalic`, `script`, `boldScript`, `fraktur`, `boldFraktur`, `sansSerif`, `boldSansSerif`, `sansSerifItalic`, `sansSerifBoldItalic`, `monospace`, `doubleStruck`, `doubleStruckBold`, `doubleStruckSans`, `doubleStruckMonospace`).
* **`TexMathBudgets`**: Immutable safety limit configuration with `copyWith(...)` and defensive defaults (`defaultMaxInputLength = 50000`, `defaultMaxMacroDepth = 64`, `defaultMaxMacroExpansions = 10000`, `defaultMaxNestingDepth = 64`, `defaultMaxOutputItems = 50000`, `defaultMaxSvgLength = 4000000`).
* **`TexMathOptions`**: Immutable options configuring parsing, macro expansion, package loading, and OpenType script behavior:
  * `displayMode`: `TexMathDisplayMode` (defaults to `TexMathDisplayMode.display`).
  * `packages`: `List<String>` (defaults to `TexMathOptions.defaultPackages`, the 29 active JupyterLab default TeX packages excluding `noerrors` and `noundefined`).
  * `requireAllowlist`: `List<String>` (defaults to `TexMathOptions.defaultRequireAllowlist`, 36 packages permitted for synchronous `\require{pkg}`, matching MathJax `require.allow` defaults while disallowing `base`, `autoload`, `configmacros`, `tagformat`, `setoptions`, and `texhtml`).
  * `macros`: `Map<String, String>` preconfigured macro definitions mapping command names (without `\`) to TeX replacement bodies.
  * `budgets`: `TexMathBudgets` safety limits.
  * `strictErrors`: `bool` (defaults to `true`; when `false`, parser/macro errors emit non-fatal `ErrorNode` entries instead of throwing).
  * `useOpticalScriptVariants`: `bool` (defaults to `false`; when `true`, script layout substitutes OpenType `GSUB` `ssty` optical glyph alternates via `MathFont.scriptVariantGlyph` alongside `MATH` scale-down factors).
* **`TexPackageRegistry`**: Compile-time immutable registry of all 42 MathJax `4.1.3` TeX packages (`TexPackageRegistry.all`, `byName`, `allNames`, `contains(String name)`, `autoloadCommands`, `autoloadEnvironments`), returning `TexPackageDescriptor` records classified by `TexPackageTier` (`tier1`, `tier2`, `tier3`).

### Source Spans, Tokens, & Errors (`SourceSpan`, `TexToken`, `TexMathError`)

`SourceSpan` represents a half-open UTF-16 code-unit range `[start, end)` within TeX source text, providing `SourceSpan.empty([int offset = 0])`, `SourceSpan.zero`, `length`, `isEmpty`, `slice(String source)`, and `merge(SourceSpan other)`.

`tokenizeTex(String source)` scans UTF-16 TeX source without regex backtracking into `List<TexToken>` records carrying `kind` (`TexTokenKind`), `text`, `span` (`SourceSpan`), `catCode` (`TexCatCode`), `isControlWord`, `isIgnorableInMath`, and `rawText`.

`TexMathError` is a `sealed class TexMathError implements Exception` carrying `message` (`String`), `errorClass` (`TexMathErrorClass`), and optional `span` (`SourceSpan?`). Its five `final` subclasses enable exhaustive Dart 3 `switch` handling:

* **`TexMathSyntaxError`**: Tokenization, delimiter, environment, `\require`, and parser grammar errors (`errorClass` defaults to `TexMathErrorClass.syntaxError`).
* **`TexMathMacroError`**: Macro definition and expansion errors (`errorClass` defaults to `TexMathErrorClass.invalidMacroDefinition`).
* **`TexMathBudgetError`**: Resource budget violations (`errorClass` fixed to `TexMathErrorClass.budgetExceeded`), adding `budgetName`, `limit`, and `actual`.
* **`TexMathFontError`**: Invalid, empty, missing `MATH` table, or malformed font payload errors (`errorClass` defaults to `TexMathErrorClass.invalidFont`).
* **`TexMathUnsupportedError`**: Unsupported feature errors (`errorClass` defaults to `TexMathErrorClass.unsupportedFeature`).

`TexMathErrorClass` defines 16 machine-readable error categories aligned to MathJax TeX error classes: `undefinedControlSequence`, `missingBrace`, `extraBrace`, `misplacedAlignmentTab`, `misplacedNewline`, `missingDelimiter`, `extraDelimiter`, `mismatchedEnvironment`, `doubleScript`, `missingArgument`, `invalidMacroDefinition`, `unknownEnvironment`, `budgetExceeded`, `invalidFont`, `unsupportedFeature`, and `syntaxError`.

### Syntax Tree (`sealed class MathNode`)

Every `MathNode` subclass is `@immutable` and preserves `SourceSpan span`:

| Node Type | Key Properties | TeX Role |
| :--- | :--- | :--- |
| `MathRootNode` | `children`, `displayMode`, `labels` | Top-level expression container and `\label`/`\tag` bindings. |
| `MathGroupNode` | `children`, `isExplicitGroup`, `atomClass`, `fontVariant`, `role`, `attributes` | Brace-delimited `{...}` or implicit sub-group, phantom, boxed, cancel, enclose, sideset, prooftree, or HTML/action wrapper. |
| `SymbolNode` | `value`, `command`, `atomClass`, `fontVariant`, `isNegated`, `isStretchy` | Identifiers, numerals, relations, negated symbols, and stretchy delimiter glyphs. |
| `OperatorNode` | `operatorName`, `hasLimits`, `isLarge`, `command`, `isDeclared`, `isExtensible` | Large, declared (`\operatorname`), named, or extensible arrow operators (`\sum`, `\int`, `\lim`, `\xrightarrow`). |
| `FractionNode` | `numerator`, `denominator`, `ruleThicknessEm`, `leftDelimiter`, `rightDelimiter`, `styleOverride`, `isBevelled` | Fractions, `\dfrac`, `\tfrac`, `\cfrac`, `\nicefrac` bevelled fractions, and binomials (`\binom`, `\genfrac`). |
| `ScriptNode` | `base`, `subscript`, `superscript`, `limitsAboveBelow`, `presubscript`, `presuperscript` | Subscripts, superscripts, stacked limits, and `\prescript` attachments. |
| `RadicalNode` | `radicand`, `index` | Square and nth roots (`\sqrt[n]{x}`). |
| `AccentNode` | `base`, `accent`, `isWide`, `isUnder` | Over/under accents, wide accents, `\overbrace`, `\underbrace`, `\overbracket`, `\underbracket`. |
| `DelimiterNode` | `children`, `leftDelimiter`, `rightDelimiter`, `fixedSizeEm` | Stretchy `\left...\middle...\right` or fixed-size `\big`–`\Bigg` groups. |
| `MatrixNode` | `rows`, `environment`, `columnAlignments`, `verticalAlignment`, `leftDelimiter`, `rightDelimiter`, `isNumbered`, `rowLines`, `columnSeparators`, `rowTags` | Grids, matrices, arrays, `CD` diagrams, `prooftree`, `cases`/`numcases`, and AMS alignment environments with `\hline`, column rules, and row tags. |
| `TextNode` | `text`, `styleCommand`, `children` | Embedded text-mode runs (`\text`, `\mathrm`, `\textbf`) with inline `$...$` fragments. |
| `SpaceNode` | `widthEm`, `command` | Explicit horizontal skips (`\,`, `\quad`, `\hspace`, `\mspace`). |
| `StyleNode` | `style`, `children`, `scaleEm` | Explicit math style scopes (`TexMathStyle`) and font size scales (`\tiny`–`\Huge`). |
| `ColorNode` | `role`, `children`, `colorValue`, `backgroundColor`, `borderColor` | Semantic or explicit color, `\colorbox`, `\fcolorbox`, and `\cellcolor` scopes. |
| `TagNode` | `label`, `isStarred`, `body`, `isReference`, `isLabelDefinition` | Equation tags, labels, and cross-references (`\tag`, `\tag*`, `\label`, `\ref`, `\eqref`). |
| `ErrorNode` | `error`, `rawSource` | Non-fatal diagnostic placeholder when `strictErrors` is `false` or `noerrors` is active. |

### OpenType Font, Variations, Hinting & `MATH` Table (`MathFont`, `MathTableData`, `GlyphOutline`)

* **`PathCommand`**: Sealed vector outline command hierarchy (`MoveTo(x, y)`, `LineTo(x, y)`, `QuadTo(controlX, controlY, x, y)`, `CubicTo(control1X, control1Y, control2X, control2Y, x, y)`, `ClosePath()`).
* **`GlyphOutline`**: Immutable contour record for a `glyphId` storing `commands` (`List<PathCommand>`), `advanceWidth` (`double`), `isEmpty`, and `toSvgPathData()` (emitting SVG path `d` commands).
* **`FontBoundingBox` & `GlyphMetrics`**: `GlyphMetrics` stores `glyphId`, `advanceWidth`, `lsb`, exact analytical Bezier-extrema bounds (`xMin`, `yMin`, `xMax`, `yMax`, `height`, `depth`), optional `italicsCorrection`, and optional `topAccentAttachment`.
* **`FontVariationAxis`, `StemHint`, & `StemOrientation`**: `FontVariationAxis` describes `fvar` axes (`tag`, `minValue`, `defaultValue`, `maxValue`, `flags`, `axisNameId`); `StemHint` stores horizontal or vertical Type 2 CharString stem hints (`orientation`, `position`, `width`, `min`, `max`).
* **`MathTableData` (`MathConstants`, `MathGlyphInfo`, `MathVariants`)**: Exposes all 56 OpenType `MathConstants` fields and `MathValueRecord`s, `MathGlyphInfo` queries (`italicsCorrection`, `topAccentAttachment`, `isExtendedShape`, `mathKern(glyphId, MathKernCorner, correctionHeight)`), and `MathVariants` constructions (`minConnectorOverlap`, `verticalConstruction`, `horizontalConstruction` returning `MathGlyphConstruction` with discrete `MathGlyphVariant` steps and `GlyphAssembly` / `GlyphAssemblyPart` recipes).
* **`MathFont`**: Pure-Dart OpenType/TrueType reader constructed from in-memory bytes via `MathFont.fromBytes(Uint8List bytes, {int maxBytes = MathFont.defaultMaxFontBytes, Map<String, double> variationAxes = const <String, double>{}})` (`defaultMaxFontBytes = 16 * 1024 * 1024`), validating SFNT headers (`OTTO`, `0x00010000`, `true`, `typ1`) and decoding `head`, `maxp`, `hhea`, `hmtx`, `OS/2`, `name`, `cmap` (Format 4 and Format 12), `GSUB` (`ssty`), `MATH`, `fvar`/`avar`/`HVAR`/`GDEF` variations, `glyf`/`loca`, and `CFF`/`CFF2`.
  * Table & variation metadata: `familyName`, `unitsPerEm`, `numGlyphs`, `ascender`, `descender`, `lineGap`, `numberOfHMetrics`, `indexToLocFormat`, `boundingBox`, `xHeight`, `capHeight`, `typoAscender`, `typoDescender`, `axes`, `variationAxes`, `normalizedVariationCoordinates`, and `mathTable`.
  * Mapping & metrics methods: `glyphIdForCodePoint(int codePoint)`, `scriptVariantGlyph(int glyphId, int level)` (`0` = script, `1` = scriptscript), `advanceWidthForGlyph(int glyphId)`, `lsbForGlyph(int glyphId)`, and `metricsForGlyph(int glyphId)`.
  * Outline & hinting methods: `outlineForGlyph(int glyphId, {double? ppem, bool enableHinting = false})` (when `enableHinting` is `true`, snaps captured `CFF`/`CFF2` stem hints to the pixel grid at `ppem`, defaulting to `16.0`, in design units) and `stemHintsForGlyph(int glyphId)`.

### Display List, Break Hints & Exporters (`DisplayList`, `DisplayBreakHint`, `RenderResult`)

`DisplayList` stores `DisplayMetrics metrics`, `List<DisplayItem> items`, optional `String? source`, and `List<DisplayBreakHint> breakHints`, and implements standalone XML SVG serialization via:

```dart
String toSvg({
  double fontSize = 16.0,
  int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
  int maxSvgLength = TexMathBudgets.defaultMaxSvgLength,
  Map<TexMathColorRole, String>? colors,
  String? title,
})
```

* **`DisplayMetrics`**: Bounding box (`widthEm`, `heightEm`, `depthEm`, `baselineEm` defaulting to `heightEm`, `unitsPerEm` defaulting to `1000`) plus `totalHeightEm`, `widthUnits`, `heightUnits`, and `depthUnits`.
* **`DisplayBreakHint`, `BreakPoint`, & `MathBreakKind`**: Top-level line-breaking metadata attached to `DisplayList.breakHints`. Each `DisplayBreakHint` carries `xEm`, `afterItemIndex`, `breakPoint` (`BreakPoint` with `kind`, `penalty`, `isExplicit`, `isGood`), optional `span`, and convenience getters `kind` (`MathBreakKind`: `none`, `afterBinary`, `afterRelation`, `penalty`, `explicit`) and `penalty`.
* **`DisplayItem`** (`sealed class` with `span`, `colorRole`, `customColor`):
  * **`GlyphItem`**: `glyphId`, `codePoint`, `xEm`, `yEm`, `scaleX = 1.0`, `scaleY = 1.0`, `advanceEm = 0.5`, and optional `GlyphOutline? outline`.
  * **`RuleItem`**: `xEm`, `yEm`, `widthEm`, `heightEm`, and optional `strokeWidthEm` for stroked borders (`\boxed`, `\fcolorbox`).
  * **`AnchorItem`**: `id`, `xEm`, `yEm`, and optional `label` for non-inked structural coordinates.
* **`RenderResult`**: Combines `displayList`, `syntaxTree`, and `source`, exposing `toSvg(...)`, `toMathMl()`, and `toSpokenText()`. Top-level functions `mathNodeToMathMl(MathNode node, {bool includeXmlNamespace = true})` and `mathNodeToSpokenText(MathNode node)` are also exported directly.

### Example Usage (Pure-Dart OpenType `MATH` Pipeline)

```dart
import 'dart:typed_data';
import 'package:tex_math/tex_math.dart';

String renderIntegralToSvg(Uint8List otfBytes) {
  final MathFont font = MathFont.fromBytes(otfBytes);
  final TexMathEngine engine = TexMathEngine(
    font: font,
    defaultOptions: const TexMathOptions(
      displayMode: TexMathDisplayMode.display,
      useOpticalScriptVariants: true,
    ),
  );
  final RenderResult result = engine.render(
    r'\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}',
  );
  final String mathMl = result.toMathMl();
  final String spoken = result.toSpokenText();
  assert(mathMl.contains('<math') && spoken.isNotEmpty);
  return result.toSvg(fontSize: 24.0, title: 'Gaussian integral');
}
```

---

## 2. Flutter Package (`package:tex_math_flutter/tex_math_flutter.dart`)

### Widgets & Overflow (`TexMath`, `TexMathSpan`, `TexMathOverflow`, `TexMathErrorWidget`)

* **`TexMathOverflow`**: Enum defining horizontal overflow handling when rendered width exceeds layout constraints: `scroll` (horizontal `SingleChildScrollView`), `scaleToFit` (`FittedBox` `BoxFit.scaleDown`), `clip` (`ClipRect`), and `visible` (unclipped inline flow).
* **`TexMath`**: `StatefulWidget` supporting `const TexMath(source, ...)` (default `TexMathDisplayMode.display`), `const TexMath.inline(...)`, `const TexMath.display(...)`, and `const TexMath.displayList(displayList, ...)`. When neither `font` nor `engine.font` is supplied, `TexMath` renders synchronously if `TexMathFontBundle.cachedMathFont` is already decoded or automatically triggers `TexMathFontBundle.loadMathFont()` once per application lifecycle. Applies `DefaultTextStyle`, widget `textStyle`, `TexMathTheme.of(context).fontSize`, `MediaQuery.textScalerOf(context)`, `Baseline` / `TexMathBaselineProxy` alphabetic baseline forwarding, `TexMathOverflow` (`scroll` default for display mode, `visible` default for inline mode), spoken-text `Semantics` (`semanticsLabel` -> `RenderResult.toSpokenText()` -> `source`), and automatic `SelectionArea` wrapping when `selectable` is `true` and no ancestor `SelectionContainer` is present.
* **`TexMathSpan`**: `WidgetSpan` subclass aligned with `PlaceholderAlignment.baseline` and `TextBaseline.alphabetic` for embedding inline TeX math inside `Text.rich` or `RichText` (accepting `options`, `engine`, `font`, `overflow`, `pathCache`, `layouter`, `style`, `errorBuilder`, `semanticsLabel`, and `selectable`).
* **`TexMathErrorWidget` & `TexMathErrorBuilder`**: `TexMathErrorWidget` renders `source` in monospace alongside `errorMessage ?? error?.message` using `TexMathThemeData.error` and `errorBackground`. `TexMathErrorBuilder` (`Widget Function(BuildContext context, String source, TexMathError error)`) allows custom error widgets on `TexMath` and `TexMathSpan`.

### Sub-Expression Selection (`TexMathSelectionUtils` & `RenderTexMath`)

Inside a `SelectionArea`, `TexMath` uses internal `RenderTexMath` (`Selectable` with `SelectionRegistrant`, in `src/selection_adapter.dart`) and `TexMathSelectionUtils` so dragging across part of an equation expands partial selections to syntactically valid LaTeX slices via `DisplayItem.span` and the enclosing `MathNode`:

* **`TexMathSelectionUtils.expandSpanToMinimalNode(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Walks `syntaxTree` to find the smallest enclosing `MathNode.span` containing `targetSpan` (or contiguous top-level `MathRootNode` children), normalizes trailing `\end{...}` / `\right...` tokens and balanced braces, and returns `SourceSpan(0, source.length)` when selecting across the full expression.
* **`TexMathSelectionUtils.sliceMinimalLatex(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Convenience wrapper returning `expandSpanToMinimalNode(...).slice(source)` for `"copy as LaTeX"` clipboard actions.

### Theming, Path Cache & Painting (`TexMathTheme`, `TexMathPathCache`, `TexMathDisplayPainter`)

* **`TexMathPathCache`**: LRU cache (`TexMathPathCache({int maxEntries = defaultMaxEntries})` with `defaultMaxEntries = 4096` and shared singleton `TexMathPathCache.shared`) keyed by `(MathFont, glyphId)` (falling back to `GlyphOutline` when no `MathFont` is attached). Exposes `length`, `hitCount`, `buildCount`, `pathForGlyph(MathFont font, int glyphId, {GlyphOutline? outline})`, `resolvePath({required int glyphId, MathFont? font, GlyphOutline? outline})`, and `clear()`. Sharing `Path` geometry per `(font, glyphId)` lets theme color updates repaint without re-running `TexMathEngine.render` or rebuilding paths.
* **`TexMathDisplayPainter`**: `CustomPainter` rendering `DisplayList` items (`GlyphItem`, filled or `strokeWidthEm`-stroked `RuleItem`, and optional selection highlight `selectionRects`) onto a Flutter `Canvas` using `TexMathPathCache` and `TexMathDisplayPainter.buildPathFromCommands(List<PathCommand> commands)`.
* **`TexMathThemeData` & `TexMathTheme`**: Immutable theme (`foreground`, `accent`, `error`, `muted`, optional `errorBackground`, `fontSize = 18.0`, `TexMathThemeData.fromColorScheme`, `TexMathThemeData.fallback`, `colorForRole`, `copyWith`, `lerp`) propagated via `InheritedTheme` (`TexMathTheme.of(context)` and `TexMathTheme.maybeOf(context)`).

### Bundled Math Font & Persistent Isolate Layouter (`TexMathFontBundle`, `TexMathIsolateLayouter`)

* **`TexMathFontBundle`**: Loads and caches `packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf`, `GUST-FONT-LICENSE.txt`, and `MANIFEST-NewCMMath.txt` once per application lifecycle via:
  * `TexMathFontBundle.load({AssetBundle? bundle, bool forceReload = false}) -> Future<TexMathFontAsset>`: Validates non-empty bytes and the `OTTO` OpenType header; cached asset available synchronously via `TexMathFontBundle.cachedAsset`.
  * `TexMathFontBundle.loadMathFont({AssetBundle? bundle, bool forceReload = false}) -> Future<MathFont>`: Loads and decodes `NewCMMath-Regular.otf` once; cached font available synchronously via `TexMathFontBundle.cachedMathFont`.
  * `@visibleForTesting static void clearCache()`: Resets cached asset and decoded font state in tests.
* **`TexMathFontAsset`**: Immutable payload exposing `bytes`, `familyName`, `assetPath`, `licenseText`, `byteLength`, `hasOttoHeader`, and `decodeMathFont()`.
* **`TexMathLayoutCacheKey`**: Immutable `(source, options, fontId)` key with structural value equality.
* **`TexMathIsolateLayouter`**: Persistent background `Isolate` layouter backed by a bounded LRU cache (`maxCacheEntries = 256`, `fontId = 'NewCMMath-Regular'`) and in-flight request deduplication:
  * `TexMathIsolateLayouter({int maxCacheEntries = 256, String fontId = 'NewCMMath-Regular', Uint8List? fontBytes})` and `static Future<TexMathIsolateLayouter> withBundledFont({int maxCacheEntries = 256, String fontId = 'NewCMMath-Regular', AssetBundle? bundle})`: Transfers `fontBytes` once via `TransferableTypedData` and decodes `MathFont.fromBytes` once on worker startup.
  * Lifecycle & status: `warmUp()`, `dispose()`, `hasFontBytes`, `isWorkerRunning`, `isDisposed`.
  * Rendering & cache API: `renderInBackground(String source, {TexMathOptions options, TexMathEngine engine})`, `layoutInBackground(...)`, `getCached`, `putCached`, `clearCache`, `cacheLength`, `hitCount`, `missCount`. Propagates `TexMathError` exceptions across the isolate boundary.

### Example Usage (Flutter Theme, Inline Span, & Persistent Isolate Layouter)

```dart
import 'package:flutter/material.dart';
import 'package:tex_math_flutter/tex_math_flutter.dart';

class MathNotebookSection extends StatefulWidget {
  const MathNotebookSection({super.key});

  @override
  State<MathNotebookSection> createState() => _MathNotebookSectionState();
}

class _MathNotebookSectionState extends State<MathNotebookSection> {
  TexMathIsolateLayouter? _layouter;

  @override
  void initState() {
    super.initState();
    TexMathIsolateLayouter.withBundledFont().then((TexMathIsolateLayouter l) {
      if (!mounted) {
        l.dispose();
        return;
      }
      setState(() => _layouter = l);
    });
  }

  @override
  void dispose() {
    _layouter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TexMathTheme(
      data: TexMathThemeData.fromColorScheme(Theme.of(context).colorScheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TexMath(
            r'x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}',
            overflow: TexMathOverflow.scroll,
            layouter: _layouter,
          ),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Pythagorean identity: '),
                TexMathSpan(r'a^2 + b^2 = c^2', layouter: _layouter),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```
