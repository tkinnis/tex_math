# API Manual

This manual documents the public API exported by **`package:tex_math/tex_math.dart`** (pure Dart) and **`package:tex_math_flutter/tex_math_flutter.dart`** (Flutter widgets, glyph path caching, theming, font asset bundle, selection utilities, and persistent background isolate layouter).

---

## 1. Core Package (`package:tex_math/tex_math.dart`)

`package:tex_math/tex_math.dart` exports the engine, options, AST, break-point, display-list, error, exporter, font, and source-span libraries alongside `show`-scoped `TexPackageDescriptor`, `TexPackageRegistry`, `TexPackageTier`, `TexSymbolSpec`, `TexCatCode`, `TexToken`, `TexTokenKind`, `tokenizeTex`, `resolveTexColor`, and `mathUnicodeCodePoint`. Internal Stage 3 parser internals and Stage 4 layout internals (`src/layout/*`) remain private to `src/`.

### Entry Points & Engine (`TexMathEngine`, `RenderResult`)

`TexMathEngine` is an immutable, value-comparable (`==` / `hashCode`) entry point executing the TeX math-mode pipeline synchronously from in-memory strings and `MathFont` instances with zero filesystem access or global mutable state:

| Symbol | Signature / Role | Behavior |
| :--- | :--- | :--- |
| `TexMathEngine` | `const TexMathEngine({TexMathOptions defaultOptions = const TexMathOptions(), MathFont? font})` | Constructs a stateless engine with default options and an optional default font. |
| `parse` | `MathNode parse(String source, {TexMathOptions? options})` | Tokenizes, expands macros within `maxInputLength`, `maxMacroDepth`, `maxMacroExpansions`, `maxTokens`, and parses `source` into a `MathNode` tree enforcing `maxNestingDepth`. |
| `layout` | `DisplayList layout(MathNode syntaxTree, {TexMathOptions? options, MathFont? font})` | Enforces `maxNestingDepth` and applies TeX Appendix G OpenType `MATH` layout using `font` (or `TexMathEngine.font`), throwing `TexMathFontError` when neither supplies a valid font. |
| `render` | `RenderResult render(String source, {TexMathOptions? options, MathFont? font})` | Composes `parse` and `layout` into an immutable `RenderResult` carrying `displayList`, `syntaxTree`, and `source`. |
| `renderToSvg` | `String renderToSvg(String source, {TexMathOptions? options, MathFont? font, double fontSize = 16.0})` | Composes `render` and `RenderResult.toSvg(...)`, enforcing `maxOutputItems` and `maxSvgLength`. |
| `toMathMl` | `String toMathMl(String source, {TexMathOptions? options})` | Parses `source` within budgets and emits Presentation MathML XML. |
| `toSpokenText` | `String toSpokenText(String source, {TexMathOptions? options})` | Parses `source` within budgets and emits natural-language spoken math text. |
| `parseTex` | `MathNode parseTex(String source, {TexMathOptions options = const TexMathOptions()})` | Top-level convenience wrapper calling `const TexMathEngine().parse(...)`. |
| `renderTex` | `RenderResult renderTex(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font})` | Top-level convenience wrapper calling `const TexMathEngine().render(...)`. |
| `renderTexToSvg` | `String renderTexToSvg(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font, double fontSize = 16.0})` | Top-level convenience wrapper calling `const TexMathEngine().renderToSvg(...)`. |

`RenderResult` (`src/engine.dart`) binds `displayList`, `syntaxTree`, and `source`, exposing `toSvg(...)`, `toMathMl()`, and `toSpokenText()`. Top-level `mathNodeToMathMl(MathNode node, {bool includeXmlNamespace = true})` and `mathNodeToSpokenText(MathNode node)` are also exported.

### Configuration (`TexMathOptions`, `TexMathBudgets`, `TexPackageRegistry`)

* **`TexMathDisplayMode`**: Enum with `inline` (`$...$`) and `display` (`$$...$$`).
* **`TexMathColorRole`**: Semantic paint roles (`foreground`, `accent`, `error`, `muted`, `custom`).
* **`TexMathStyle`**: Appendix G layout styles (`display`, `text`, `script`, `scriptScript`, `crampedDisplay`, `crampedText`, `crampedScript`, `crampedScriptScript`).
* **`TexMathAtomClass`**: Appendix G atom spacing categories (`ord`, `op`, `bin`, `rel`, `open`, `close`, `punct`, `inner`).
* **`TexMathFontVariant`**: Math alphabet and style variants (`normal`, `bold`, `italic`, `boldItalic`, `script`, `boldScript`, `fraktur`, `boldFraktur`, `sansSerif`, `boldSansSerif`, `sansSerifItalic`, `sansSerifBoldItalic`, `monospace`, `doubleStruck`, `doubleStruckBold`, `doubleStruckSans`, `doubleStruckMonospace`).
* **`TexMathBudgets`**: Immutable safety limit configuration with `copyWith(...)` and defensive defaults (`defaultMaxInputLength = 50000`, `defaultMaxMacroDepth = 64`, `defaultMaxMacroExpansions = 10000`, `defaultMaxTokens = 100000`, `defaultMaxNestingDepth = 64`, `defaultMaxOutputItems = 50000`, `defaultMaxSvgLength = 4000000`).
* **`TexMathOptions`**: Immutable options exposing unmodifiable views of `packages`, `requireAllowlist`, and `macros`, alongside `displayMode`, `budgets`, `strictErrors`, and `useOpticalScriptVariants`:
  * `displayMode`: `TexMathDisplayMode` (defaults to `TexMathDisplayMode.display`).
  * `packages`: `List<String>` (defaults to `TexMathOptions.defaultPackages`, the 29 active JupyterLab default TeX packages excluding `noerrors` and `noundefined`).
  * `requireAllowlist`: `List<String>` (defaults to `TexMathOptions.defaultRequireAllowlist`, 36 packages permitted for synchronous `\require{pkg}`, matching MathJax `require.allow` defaults while disallowing `base`, `autoload`, `configmacros`, `tagformat`, `setoptions`, and `texhtml`).
  * `macros`: `Map<String, String>` preconfigured macro definitions mapping command names (without `\`) to TeX replacement bodies.
  * `budgets`: `TexMathBudgets` safety limits.
  * `strictErrors`: `bool` (defaults to `true`; when `false`, non-budget parser/macro errors emit `ErrorNode` instead of throwing).
  * `useOpticalScriptVariants`: `bool` (defaults to `false`; when `true`, script layout substitutes OpenType `GSUB` `ssty` optical glyph alternates via `MathFont.scriptVariantGlyph` alongside `MATH` scale-down factors).
* **`TexPackageRegistry` & `TexSymbolSpec`**: `TexPackageRegistry` compiles all 42 MathJax `4.1.3` packages (`all`, `byName`, `allNames`, `contains(String name)`, `autoloadCommands`, `autoloadEnvironments`), returning `TexPackageDescriptor` values classified by `TexPackageTier` (`tier1`, `tier2`, `tier3`). `TexSymbolSpec`, `resolveTexColor(String colorSpec, {String model = '', Map<String, String> customColors = const <String, String>{}})`, and `mathUnicodeCodePoint(int baseCodePoint, TexMathFontVariant? variant)` expose canonical symbol, color, and math-alphabet metadata.

### Source Spans, Tokens, & Errors (`SourceSpan`, `TexToken`, `TexMathError`)

`SourceSpan` represents a half-open UTF-16 code-unit range `[start, end)` within TeX source text, providing `SourceSpan.empty([int offset = 0])`, `SourceSpan.zero`, `length`, `isEmpty`, `slice(String source)`, and `merge(SourceSpan other)`.

`tokenizeTex(String source)` scans UTF-16 TeX source without regex backtracking into `List<TexToken>` records carrying `kind` (`TexTokenKind`), `text`, `span` (`SourceSpan`), `catCode` (`TexCatCode`), `isControlWord`, `isIgnorableInMath`, and `rawText`.

`TexMathError` is a `sealed class TexMathError implements Exception` carrying `message` (`String`), `errorClass` (`TexMathErrorClass`), and optional `span` (`SourceSpan?`). Its five `final` subclasses enable exhaustive Dart 3 `switch` handling:

* **`TexMathSyntaxError`**: Tokenization, delimiter, environment, `\require`, unsafe `\href` URI, and parser grammar errors (`errorClass` defaults to `TexMathErrorClass.syntaxError`).
* **`TexMathMacroError`**: Macro definition and expansion errors (`errorClass` defaults to `TexMathErrorClass.invalidMacroDefinition`).
* **`TexMathBudgetError`**: Resource budget violations (`errorClass` fixed to `TexMathErrorClass.budgetExceeded`), adding `budgetName`, `limit`, and `actual`.
* **`TexMathFontError`**: Invalid, empty, missing `MATH` table, or malformed font payload errors (`errorClass` defaults to `TexMathErrorClass.invalidFont`).
* **`TexMathUnsupportedError`**: Unsupported feature errors (`errorClass` defaults to `TexMathErrorClass.unsupportedFeature`).

`TexMathErrorClass` defines 16 machine-readable error categories aligned to MathJax TeX error classes: `undefinedControlSequence`, `missingBrace`, `extraBrace`, `misplacedAlignmentTab`, `misplacedNewline`, `missingDelimiter`, `extraDelimiter`, `mismatchedEnvironment`, `doubleScript`, `missingArgument`, `invalidMacroDefinition`, `unknownEnvironment`, `budgetExceeded`, `invalidFont`, `unsupportedFeature`, and `syntaxError`.

### Syntax Tree (`sealed class MathNode`)

Every `MathNode` subclass is `@immutable` (with unmodifiable child/attribute views) and preserves `SourceSpan span`:

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
| `MatrixNode` | `rows`, `environment`, `columnAlignments`, `verticalAlignment`, `leftDelimiter`, `rightDelimiter`, `isNumbered`, `rowLines`, `columnLines`, `columnSeparators`, `rowTags` | Grids, matrices, arrays, `CD` diagrams, `prooftree`, `cases`/`numcases`, and AMS alignments with row/column rules, pre-parsed `Map<int, MathNode>` `columnSeparators` (`@{...}`/`!{...}`), and row tags. |
| `TextNode` | `text`, `styleCommand`, `children` | Embedded text-mode runs (`\text`, `\mathrm`, `\textbf`) with inline `$...$` fragments. |
| `SpaceNode` | `widthEm`, `command` | Explicit horizontal skips (`\,`, `\quad`, `\hspace`, `\mspace`). |
| `StyleNode` | `style`, `children`, `scaleEm` | Explicit math style scopes (`TexMathStyle`) and font size scales (`\tiny`–`\Huge`). |
| `ColorNode` | `role`, `children`, `colorValue`, `backgroundColor`, `borderColor` | Semantic or explicit color, `\colorbox`, `\fcolorbox`, and `\cellcolor` scopes. |
| `TagNode` | `label`, `isStarred`, `body`, `isReference`, `isLabelDefinition` | Equation tags, labels, and cross-references (`\tag`, `\tag*`, `\label`, `\ref`, `\eqref`). |
| `ErrorNode` | `error`, `rawSource` | Non-fatal diagnostic placeholder when `strictErrors` is `false` or `noerrors` is active. |

### OpenType Font, Variations, Hinting & `MATH` Table (`MathFont`, `MathTableData`, `GlyphOutline`)

* **`PathCommand`**: Sealed outline command hierarchy (`MoveTo(x, y)`, `LineTo(x, y)`, `QuadTo(controlX, controlY, x, y)`, `CubicTo(control1X, control1Y, control2X, control2Y, x, y)`, `ClosePath()`).
* **`GlyphOutline`**: Immutable contour record (`GlyphOutline(...)` and `GlyphOutline.cached(...)` with memoized `hashCode`) storing `glyphId`, unmodifiable `commands` (`List<PathCommand>`), `advanceWidth` (`double`), `isEmpty`, and `toSvgPathData()`.
* **`FontBoundingBox` & `GlyphMetrics`**: `GlyphMetrics` stores `glyphId`, `advanceWidth`, `lsb`, exact analytical Bezier-extrema bounds (`xMin`, `yMin`, `xMax`, `yMax`, `height`, `depth`), optional `italicsCorrection`, and optional `topAccentAttachment`.
* **`FontVariationAxis`, `StemHint`, & `StemOrientation`**: `FontVariationAxis` describes `fvar` axes (`tag`, `minValue`, `defaultValue`, `maxValue`, `flags`, `axisNameId`); `StemHint` stores horizontal or vertical Type 2 CharString stem hints (`orientation`, `position`, `width`, `min`, `max`).
* **`MathTableData` (`MathConstants`, `MathGlyphInfo`, `MathVariants`)**: Exposes all 56 OpenType `MathConstants` fields and `MathValueRecord`s, `MathGlyphInfo` queries (`italicsCorrection`, `topAccentAttachment`, `isExtendedShape`, `mathKern(glyphId, MathKernCorner, correctionHeight)`), and `MathVariants` constructions (`minConnectorOverlap`, `verticalConstruction`, `horizontalConstruction` returning `MathGlyphConstruction` with `MathGlyphVariant` steps and `GlyphAssembly` / `GlyphAssemblyPart` recipes).
* **`MathFont`**: Pure-Dart OpenType/TrueType reader constructed via `MathFont.fromBytes(Uint8List bytes, {int maxBytes = MathFont.defaultMaxFontBytes, Map<String, double> variationAxes = const <String, double>{}})` (`defaultMaxFontBytes = 16 * 1024 * 1024`), plus `const MathFont.stub({String familyName = 'NewComputerModernMath', int unitsPerEm = 1000})` for table-free unit tests. Validates SFNT headers and decodes `head`, `maxp`, `hhea`, `hmtx`, `OS/2`, `name`, `cmap` (Format 4/12), `GSUB` (`ssty`), `MATH`, `fvar`/`avar`/`HVAR`/`GDEF`, `glyf`/`loca`, and `CFF`/`CFF2`.
  * Metadata & identity: `familyName`, `unitsPerEm`, `numGlyphs`, `ascender`, `descender`, `lineGap`, `numberOfHMetrics`, `indexToLocFormat`, `boundingBox`, `xHeight`, `capHeight`, `typoAscender`, `typoDescender`, `axes`, `variationAxes`, `normalizedVariationCoordinates`, `mathTable`, and `signature` (fast payload-and-variation digest distinguishing distinct fonts in `==` and `TexMathPathCache`).
  * Mapping & metrics methods: `glyphIdForCodePoint(int codePoint)`, `scriptVariantGlyph(int glyphId, int level)`, `advanceWidthForGlyph(int glyphId)`, `lsbForGlyph(int glyphId)`, and `metricsForGlyph(int glyphId)`.
  * Outline & hinting methods: `outlineForGlyph(int glyphId, {double? ppem, bool enableHinting = false})` (when `enableHinting` is `true`, grid-aligns `CFF`/`CFF2` stem hints at `ppem`, defaulting to `16.0`, cached per `(glyphId, ppem)`) and `stemHintsForGlyph(int glyphId)`.

### Display List, Break Hints & SVG Export (`DisplayList`, `DisplayBreakHint`)

`DisplayList` stores `DisplayMetrics metrics`, `List<DisplayItem> items`, optional `String? source`, `List<DisplayBreakHint> breakHints`, and optional `int? fontSignature` (populated with `MathFont.signature` by `layoutMathTree`), implementing standalone XML 1.0 SVG serialization via:

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
* **`DisplayBreakHint`, `BreakPoint`, & `MathBreakKind`**: Top-level line-breaking metadata attached to `DisplayList.breakHints`, carrying `xEm`, `afterItemIndex`, `breakPoint` (`BreakPoint` with `kind`, `penalty`, `isExplicit`, `isGood`), optional `span`, and getters `kind` (`MathBreakKind`: `none`, `afterBinary`, `afterRelation`, `penalty`, `explicit`) and `penalty`.
* **`DisplayItem`** (`sealed class` with `span`, `colorRole`, `customColor`): `GlyphItem` (`glyphId`, `codePoint`, `xEm`, `yEm`, `scaleX`, `scaleY`, `advanceEm`, optional `GlyphOutline? outline`), `RuleItem` (`xEm`, `yEm`, `widthEm`, `heightEm`, optional `strokeWidthEm`), and `AnchorItem` (`id`, `xEm`, `yEm`, optional `label`).

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

`package:tex_math_flutter/tex_math_flutter.dart` re-exports the 22 core `package:tex_math/tex_math.dart` public symbols used by Flutter callers (`DisplayItem`, `DisplayList`, `DisplayMetrics`, `GlyphOutline`, `MathFont`, `MathNode`, `MathRootNode`, `PathCommand`, `RenderResult`, `SourceSpan`, `TexMathBudgetError`, `TexMathBudgets`, `TexMathColorRole`, `TexMathDisplayMode`, `TexMathEngine`, `TexMathError`, `TexMathErrorClass`, `TexMathFontError`, `TexMathMacroError`, `TexMathOptions`, `TexMathSyntaxError`, `TexMathUnsupportedError`) alongside the Flutter widgets, caching, and isolate types below so Flutter apps need only a single import.

### Widgets & Overflow (`TexMath`, `TexMathSpan`, `TexMathOverflow`, `TexMathErrorWidget`)

* **`TexMathOverflow`**: Horizontal overflow policy enum: `scroll` (horizontal `SingleChildScrollView`), `scaleToFit` (`FittedBox` `BoxFit.scaleDown`), `clip` (`ClipRect`), and `visible` (unclipped visual overflow with matching expanded hit-test and selection `boundingBoxes`).
* **`TexMath`**: `StatefulWidget` offering `const TexMath(source, ...)` (default `TexMathDisplayMode.display`), `const TexMath.inline(...)`, `const TexMath.display(...)`, and `const TexMath.displayList(displayList, ...)`. Resolves font size via `widget.textStyle?.fontSize ?? TexMathTheme.maybeOf(context)?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? theme.fontSize` (validated via positive finite fallback and scaled by `MediaQuery.textScalerOf(context)`), applies `widget.textStyle?.color`, auto-loads `TexMathFontBundle.loadMathFont()` once per lifecycle without double-parsing (`engine.layout()` on the pre-parsed `MathNode`), forwards proportional `TextBaseline.alphabetic` and `TextBaseline.ideographic` metrics via `Baseline` / `TexMathBaselineProxy`, exposes cached spoken-text `Semantics`, and wraps standalone selectable output in `SelectionArea`.
* **`TexMathSpan`**: `WidgetSpan` subclass aligned with `PlaceholderAlignment.baseline` and `TextBaseline.alphabetic` for embedding inline math inside `Text.rich` / `RichText` (accepting `options`, `engine`, `font`, `overflow`, `pathCache`, `layouter`, `style`, `errorBuilder`, `semanticsLabel`, and `selectable`).
* **`TexMathErrorWidget` & `TexMathErrorBuilder`**: `TexMathErrorWidget` renders `source` in monospace alongside `errorMessage ?? error?.message` using `TexMathThemeData.error` and `errorBackground`, sets `Semantics(excludeSemantics: true)`, and respects `selectable: false` inside ancestor `SelectionArea`s via `SelectionContainer.disabled`. `TexMathErrorBuilder` (`Widget Function(BuildContext context, String source, TexMathError error)`) allows custom error widgets.

### Sub-Expression Selection (`TexMathSelectionUtils`)

Inside a `SelectionArea`, `TexMath` mounts internal `RenderTexMath` (`Selectable` with `SelectionRegistrant`, lazily building atom hit boxes only when registered for selection) and `TexMathSelectionUtils` so partial drags expand to syntactically valid LaTeX slices:

* **`TexMathSelectionUtils.expandSpanToMinimalNode(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Finds the smallest enclosing `MathNode.span` containing `targetSpan` (or contiguous top-level `MathRootNode` children), normalizes trailing `\end{...}` / `\right...` tokens and balanced braces, and returns `SourceSpan(0, source.length)` for full-expression selections.
* **`TexMathSelectionUtils.sliceMinimalLatex(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Returns `expandSpanToMinimalNode(...).slice(source)` for `"copy as LaTeX"` clipboard actions.

### Theming, Path Cache & Painting (`TexMathTheme`, `TexMathPathCache`, `TexMathDisplayPainter`)

* **`TexMathPathCache`**: Bounded LRU cache (`TexMathPathCache({int maxEntries = defaultMaxEntries, int? maxTextPainterEntries})` with `defaultMaxEntries = 4096`, `maxTextPainterEntries` defaulting to `min(maxEntries, 256)`, and singleton `TexMathPathCache.shared`) keyed by `(font?.signature ?? displayList.fontSignature, glyphId, ppemBucket?)` (falling back to `GlyphOutline` when no font or signature is present), plus an LRU cache of fallback `TextPainter`s disposed on eviction or `clear()`. Exposes `length`, `hitCount`, `buildCount`, `pathForGlyph(MathFont font, int glyphId, {GlyphOutline? outline, int? ppemBucket})`, `resolvePath({required int glyphId, MathFont? font, GlyphOutline? outline, int? fontSignature, int? ppemBucket})`, and `clear()`.
* **`TexMathDisplayPainter`**: `CustomPainter` rendering `DisplayList` items (`GlyphItem`, filled or `strokeWidthEm`-stroked `RuleItem`, and `selectionRects`) onto a `Canvas` using `TexMathPathCache`, reusing cached `Paint` objects, and exposing static `paintDisplayList(...)` and `buildPathFromCommands(List<PathCommand> commands)`.
* **`TexMathThemeData` & `TexMathTheme`**: Immutable theme (`foreground`, `accent`, `error`, `muted`, optional `errorBackground`, `fontSize = 18.0`, `TexMathThemeData.fromColorScheme`, `TexMathThemeData.fallback`, `colorForRole`, `copyWith`, `lerp`) propagated via `InheritedTheme` (`TexMathTheme.of(context)` and `TexMathTheme.maybeOf(context)`).

### Bundled Math Font & Persistent Isolate Layouter (`TexMathFontBundle`, `TexMathIsolateLayouter`)

* **`TexMathFontBundle`**: Loads and caches `packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf`, `GUST-FONT-LICENSE.txt`, and `MANIFEST-NewCMMath.txt` once per application lifecycle:
  * `TexMathFontBundle.load({AssetBundle? bundle, bool forceReload = false}) -> Future<TexMathFontAsset>`: Validates non-empty bytes and the `OTTO` OpenType header; cached asset exposed synchronously via `TexMathFontBundle.cachedAsset`.
  * `TexMathFontBundle.loadMathFont({AssetBundle? bundle, bool forceReload = false}) -> Future<MathFont>`: Loads and decodes `NewCMMath-Regular.otf` off the UI thread via `Isolate.run`; cached font exposed synchronously via `TexMathFontBundle.cachedMathFont`.
  * `@visibleForTesting static void clearCache()`: Resets cached asset and decoded font state in tests.
* **`TexMathFontAsset`**: Immutable payload exposing `bytes`, `familyName`, `assetPath`, `licenseText`, `byteLength`, `hasOttoHeader`, and `decodeMathFont()`.
* **`TexMathLayoutCacheKey`**: Immutable `(source, options, fontId, fontSignature)` key with precomputed `hashCode` and structural equality.
* **`TexMathIsolateLayouter`**: Persistent background `Isolate` layouter backed by a bounded LRU cache (`maxCacheEntries = 256`, `fontId = 'NewCMMath-Regular'`), worker-side font caching by `signature`, in-flight deduplication (including custom fonts), and `onExit`/`onError` crash recovery:
  * `TexMathIsolateLayouter({int maxCacheEntries = 256, String fontId = 'NewCMMath-Regular', Uint8List? fontBytes, Duration shutdownTimeout = const Duration(milliseconds: 500)})` and `static Future<TexMathIsolateLayouter> withBundledFont({int maxCacheEntries = 256, String fontId = 'NewCMMath-Regular', AssetBundle? bundle})`: Transfers `fontBytes` once via `TransferableTypedData` and decodes `MathFont.fromBytes` once on worker startup.
  * Lifecycle & status: `warmUp()`, `dispose()` (killing unresponsive workers after `shutdownTimeout`), `hasFontBytes`, `isWorkerRunning`, `isDisposed`.
  * Rendering & cache API: `renderInBackground(String source, {TexMathOptions options, TexMathEngine engine, MathFont? font})`, `layoutInBackground(...)`, `getCached(..., {MathFont? font})`, `putCached(..., {MathFont? font})`, `clearCache`, `cacheLength`, `hitCount`, `missCount`. Propagates `TexMathError` instances and stack traces across the isolate boundary.

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
