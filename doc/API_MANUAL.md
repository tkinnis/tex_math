# API Manual

This manual documents the public API exported by [**`package:tex_math/tex_math.dart`**](https://pub.dev/packages/tex_math) ([API reference](https://pub.dev/documentation/tex_math/latest/), pure Dart) and [**`package:tex_math_flutter/tex_math_flutter.dart`**](https://pub.dev/packages/tex_math_flutter) ([API reference](https://pub.dev/documentation/tex_math_flutter/latest/), Flutter widgets, path caching, theming, font loading, selection utilities, and background isolate layout).

## Installation

Add `tex_math` for pure-Dart rendering or `tex_math_flutter` for Flutter widgets and the bundled `NewCMMath-Regular.otf` font asset:

```bash
# Pure Dart (requires Dart ^3.8.0)
dart pub add tex_math

# Flutter (requires Dart ^3.8.0 and Flutter >=3.32.0)
flutter pub add tex_math_flutter
```

---

## 1. Core Package (`package:tex_math/tex_math.dart`)

`package:tex_math/tex_math.dart` exports the engine, options, syntax tree, break-point, display-list, error, exporter, font, and source-span types alongside package-registry and tokenizer utilities. Internal parser and Stage 4 layout files (`src/layout/*`) remain private to `src/`.

### Engine & Top-Level Entry Points (`TexMathEngine`, `RenderResult`)

`TexMathEngine` is an immutable, value-comparable entry point that runs the five-stage TeX pipeline synchronously on in-memory strings and fonts with zero filesystem I/O or global mutable state:

| Symbol | Signature / Role | Behavior |
| :--- | :--- | :--- |
| `TexMathEngine` | `const TexMathEngine({TexMathOptions defaultOptions = const TexMathOptions(), MathFont? font})` | Constructs a stateless engine with default options and an optional default font. |
| `parse` | `MathNode parse(String source, {TexMathOptions? options})` | Tokenizes and expands macros within input/token budgets, returning a `MathNode` tree within `maxNestingDepth`. |
| `layout` | `DisplayList layout(MathNode syntaxTree, {TexMathOptions? options, MathFont? font})` | Enforces `maxNestingDepth` and applies TeX Appendix G OpenType math layout, throwing `TexMathFontError` if no font is supplied. |
| `render` | `RenderResult render(String source, {TexMathOptions? options, MathFont? font})` | Composes `parse` and `layout` into an immutable `RenderResult` carrying `displayList`, `syntaxTree`, and `source`. |
| `renderToSvg` | `String renderToSvg(String source, {TexMathOptions? options, MathFont? font, double fontSize = 16.0})` | Composes `render` and SVG serialization while enforcing `maxOutputItems` and `maxSvgLength`. |
| `toMathMl` | `String toMathMl(String source, {TexMathOptions? options})` | Parses `source` within budgets and emits Presentation MathML XML. |
| `toSpokenText` | `String toSpokenText(String source, {TexMathOptions? options})` | Parses `source` within budgets and emits natural-language spoken math text. |
| `parseTex` | `MathNode parseTex(String source, {TexMathOptions options = const TexMathOptions()})` | Top-level convenience wrapper calling `const TexMathEngine().parse(...)`. |
| `renderTex` | `RenderResult renderTex(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font})` | Top-level convenience wrapper calling `const TexMathEngine().render(...)`. |
| `renderTexToSvg` | `String renderTexToSvg(String source, {TexMathOptions options = const TexMathOptions(), MathFont? font, double fontSize = 16.0})` | Top-level convenience wrapper calling `const TexMathEngine().renderToSvg(...)`. |
| `mathNodeToMathMl` | `String mathNodeToMathMl(MathNode node, {bool includeXmlNamespace = true})` | Top-level Presentation MathML serializer for a parsed syntax tree. |
| `mathNodeToSpokenText` | `String mathNodeToSpokenText(MathNode node)` | Top-level spoken-text serializer for a parsed syntax tree. |

A `RenderResult` pairs the laid-out display list, syntax tree, and source string, exposing `toSvg()`, `toMathMl()`, and `toSpokenText()`.

### Configuration (`TexMathOptions`, `TexMathBudgets`, `TexPackageRegistry`)

`TexMathOptions` is an immutable configuration class exposing unmodifiable list/map views and `copyWith(...)`:

| Option Field | Type & Default | Description |
| :--- | :--- | :--- |
| `displayMode` | `TexMathDisplayMode` (`display`) | Selects inline (`$...$`) vs. block display (`$$...$$`) typesetting rules. |
| `packages` | `List<String>` (`TexMathOptions.defaultPackages`) | Active TeX packages (29 JupyterLab default extensions excluding `noerrors` and `noundefined`). |
| `requireAllowlist` | `List<String>` (`TexMathOptions.defaultRequireAllowlist`) | Packages permitted for synchronous `\require{pkg}` loading (36 extensions matching MathJax defaults). |
| `macros` | `Map<String, String>` (empty) | Preconfigured macros mapping command names (without leading `\`) to TeX replacement bodies. |
| `budgets` | `TexMathBudgets` (`const TexMathBudgets()`) | Resource limits enforced during parsing, expansion, layout, and SVG serialization. |
| `strictErrors` | `bool` (`true`) | When `false`, non-budget syntax and macro errors emit `ErrorNode` instead of throwing. |
| `useOpticalScriptVariants` | `bool` (`false`) | When `true`, script layout substitutes OpenType `GSUB` `ssty` optical glyphs alongside `MATH` scale factors. |
| `multlineWidthEm` | `double?` (`null`) | Positive finite target width in ems for `multline` / `multline*` environments; defaults to a compact `12em` minimum width when `null`. |
| `tagMode` | `TexMathTagMode` (`TexMathTagMode.none`) | Automatic equation numbering policy (`none`, `ams`, or `all`). |

`TexMathBudgets` exposes immutable safety limits with `copyWith(...)`:

| Budget Field | Default Constant | Default Value |
| :--- | :--- | ---: |
| `maxInputLength` | `defaultMaxInputLength` | `50000` |
| `maxMacroDepth` | `defaultMaxMacroDepth` | `64` |
| `maxMacroExpansions` | `defaultMaxMacroExpansions` | `10000` |
| `maxTokens` | `defaultMaxTokens` | `100000` |
| `maxNestingDepth` | `defaultMaxNestingDepth` | `64` |
| `maxOutputItems` | `defaultMaxOutputItems` | `50000` |
| `maxSvgLength` | `defaultMaxSvgLength` | `4000000` |

Core layout and typography enums exported by `tex_math`:

| Enum | Values | Role |
| :--- | :--- | :--- |
| `TexMathDisplayMode` | `inline`, `display` | Controls inline vs. display-style operator limits and fractions. |
| `TexMathTagMode` | `none`, `ams`, `all` | Controls automatic equation numbering (`none`: explicit `\tag`/`\tag*` only; `ams`: numbered AMS/LaTeX environments; `all`: numbered environments plus untagged top-level display math). |
| `TexMathColorRole` | `foreground`, `accent`, `error`, `muted`, `custom` | Semantic color role resolved during Flutter painting or SVG export. |
| `TexMathStyle` | `display`, `text`, `script`, `scriptScript`, `crampedDisplay`, `crampedText`, `crampedScript`, `crampedScriptScript` | TeX Appendix G layout styles controlling size and cramped behavior. |
| `TexMathAtomClass` | `ord`, `op`, `bin`, `rel`, `open`, `close`, `punct`, `inner` | TeX atom categories governing inter-atom horizontal spacing. |
| `TexMathFontVariant` | `normal`, `bold`, `italic`, `boldItalic`, `script`, `boldScript`, `fraktur`, `boldFraktur`, `sansSerif`, `boldSansSerif`, `sansSerifItalic`, `sansSerifBoldItalic`, `monospace`, `doubleStruck`, `doubleStruckBold`, `doubleStruckSans`, `doubleStruckMonospace` | Unicode math alphabet style variants. |

The package also exposes registry and symbol metadata utilities for inspecting supported TeX extensions, colors, and Unicode math alphabets:

| Symbol | Role & Key Members |
| :--- | :--- |
| `TexPackageRegistry` | Catalogs all 42 MathJax `4.1.3` packages (`all`, `byName`, `allNames`, `contains`, `autoloadCommands`, `autoloadEnvironments`) as `TexPackageDescriptor` entries grouped by `TexPackageTier` (`tier1`, `tier2`, `tier3`). |
| `TexSymbolSpec` | Metadata record describing built-in TeX math commands and symbol classes. |
| `resolveTexColor` | Resolves named, hex, and CSS color specifications into normalized CSS/hex color strings (such as `'#FF0000'`). |
| `mathUnicodeCodePoint` | Maps a base Unicode code point and `TexMathFontVariant` to the corresponding Unicode Mathematical Alphanumeric scalar. |

### Source Spans, Tokens, & Errors (`SourceSpan`, `TexToken`, `TexMathError`)

`SourceSpan` represents a half-open UTF-16 code-unit range within TeX source text, while `tokenizeTex` converts raw TeX into catcode-annotated tokens without backtracking regular expressions.

| Type | Key Members & Methods |
| :--- | :--- |
| `SourceSpan` | Constructors `SourceSpan(start, end)`, `SourceSpan.empty`, and `SourceSpan.zero`; getters `length` and `isEmpty`; helpers `slice(source)` and `merge(other)`. |
| `TexToken` | Exposes `kind` (`TexTokenKind`), `text`, `span` (`SourceSpan`), `catCode` (`TexCatCode`), `isControlWord`, `isIgnorableInMath`, and `rawText`. |

`TexMathError` is a sealed `Exception` carrying `message`, `errorClass`, and an optional source `span`, plus 1-based UTF-16 `position`, `formattedMessage`, and `formatWithSource(String source)` caret/snippet formatting. Its five subclasses enable exhaustive Dart 3 `switch` handling:

| Exception Class | Default `errorClass` | Trigger Condition & Extra Fields |
| :--- | :--- | :--- |
| `TexMathSyntaxError` | `syntaxError` | Tokenization, delimiter, environment, `\require`, unsafe `\href` URI, and parser grammar errors. |
| `TexMathMacroError` | `invalidMacroDefinition` | Malformed macro definitions and macro expansion errors. |
| `TexMathBudgetError` | `budgetExceeded` | Resource limit violations; adds `budgetName`, `limit`, and `actual`. |
| `TexMathFontError` | `invalidFont` | Empty, corrupt, or non-SFNT font payloads or missing font instances. |
| `TexMathUnsupportedError` | `unsupportedFeature` | Explicitly unsupported TeX features or pipeline capabilities. |

`TexMathErrorClass` defines 16 machine-readable error categories aligned with MathJax TeX error classes:

| Category | Error Class Values |
| :--- | :--- |
| **Syntax & Delimiters** | `missingBrace`, `extraBrace`, `misplacedAlignmentTab`, `misplacedNewline`, `missingDelimiter`, `extraDelimiter`, `doubleScript`, `missingArgument`, `syntaxError` |
| **Macros & Environments** | `undefinedControlSequence`, `invalidMacroDefinition`, `mismatchedEnvironment`, `unknownEnvironment` |
| **Engine, Budgets & Fonts** | `budgetExceeded`, `invalidFont`, `unsupportedFeature` |

### Syntax Tree (`sealed class MathNode`)

Every `MathNode` subclass is `@immutable` with unmodifiable child/attribute views and a `SourceSpan span`:

| Node Type | Key Properties | TeX Role |
| :--- | :--- | :--- |
| `MathRootNode` | `children`, `displayMode`, `labels` | Top-level expression container and `\label`/`\tag` bindings. |
| `MathGroupNode` | `children`, `isExplicitGroup`, `atomClass`, `fontVariant`, `role`, `attributes` | Brace-delimited `{...}` or implicit sub-group, phantom, boxed, cancel, enclose, sideset, prooftree, or HTML/action wrapper. |
| `SymbolNode` | `value`, `command`, `atomClass`, `fontVariant`, `isNegated`, `isStretchy` | Identifiers, numerals, relations, negated symbols, and stretchy delimiter glyphs. |
| `OperatorNode` | `operatorName`, `hasLimits`, `isLarge`, `command`, `isDeclared`, `isExtensible` | Large, declared (`\operatorname`), named, or extensible arrow operators. |
| `FractionNode` | `numerator`, `denominator`, `ruleThicknessEm`, `leftDelimiter`, `rightDelimiter`, `styleOverride`, `isBevelled` | Fractions, `\dfrac`, `\tfrac`, `\cfrac`, `\nicefrac` bevelled fractions, and binomials. |
| `ScriptNode` | `base`, `subscript`, `superscript`, `limitsAboveBelow`, `presubscript`, `presuperscript` | Subscripts, superscripts, stacked limits, and `\prescript` attachments. |
| `RadicalNode` | `radicand`, `index` | Square and nth roots (`\sqrt[n]{x}`). |
| `AccentNode` | `base`, `accent`, `isWide`, `isUnder` | Over/under accents, wide accents, `\overbrace`, `\underbrace`, `\overbracket`, and `\underbracket`. |
| `DelimiterNode` | `children`, `leftDelimiter`, `rightDelimiter`, `fixedSizeEm` | Stretchy `\left...\middle...\right` or fixed-size delimiter groups. |
| `MatrixNode` | `rows`, `environment`, `columnAlignments`, `verticalAlignment`, `explicitWidthEm`, `leftDelimiter`, `rightDelimiter`, `isNumbered`, `rowLines`, `columnLines`, `columnSeparators`, `rowTags` | Grids, matrices, arrays, commutative diagrams, proof trees, cases, and AMS alignments with pre-parsed column separators. |
| `TextNode` | `text`, `styleCommand`, `children` | Embedded text-mode runs (`\text`, `\mathrm`, `\textbf`) with inline math fragments. |
| `SpaceNode` | `widthEm`, `command` | Explicit horizontal skips (`\,`, `\quad`, `\hspace`, `\mspace`). |
| `StyleNode` | `style`, `children`, `scaleEm` | Explicit math style scopes and font size scales (`\tiny`–`\Huge`). |
| `ColorNode` | `role`, `children`, `colorValue`, `backgroundColor`, `borderColor` | Semantic or explicit color, `\colorbox`, `\fcolorbox`, and `\cellcolor` scopes. |
| `TagNode` | `label`, `targetId`, `isStarred`, `body`, `isReference`, `isLabelDefinition` | Equation tags, labels, and cross-references (`\tag`, `\label`, `\ref`, `\eqref`). |
| `ErrorNode` | `error`, `rawSource` | Non-fatal diagnostic placeholder when `strictErrors` is `false` or `noerrors` is active. |

### OpenType Font, Variations, Hinting & `MATH` Table

`MathFont` decodes SFNT font containers purely from in-memory bytes via `MathFont.fromBytes`, enforcing a 16 MiB default cap and optional variation-axis overrides. Table-free unit tests can construct `const MathFont.stub()` instead.

| Symbol | Role & Key Members |
| :--- | :--- |
| `MathFont` | Metadata (`familyName`, `unitsPerEm`, `numGlyphs`, `ascender`, `descender`, `lineGap`, `numberOfHMetrics`, `indexToLocFormat`, `boundingBox`, `xHeight`, `capHeight`, `typoAscender`, `typoDescender`, `axes`, `variationAxes`, `normalizedVariationCoordinates`, `mathTable`, `signature`) and queries (`glyphIdForCodePoint`, `scriptVariantGlyph`, `advanceWidthForGlyph`, `lsbForGlyph`, `metricsForGlyph`, `outlineForGlyph`, `stemHintsForGlyph`). |
| `MathTableData` | Exposes `MathConstants` (all 56 OpenType constants and `MathValueRecord` values), `MathGlyphInfo` (italics corrections, top accents, extended-shape flags, four-corner `mathKern`), and `MathVariants` (`minConnectorOverlap`, vertical/horizontal `MathGlyphConstruction`, `MathGlyphVariant`, and `GlyphAssembly`). |
| `GlyphOutline` & `PathCommand` | Immutable contour record (`GlyphOutline` / `GlyphOutline.cached` with `toSvgPathData()`) backed by sealed `MoveTo`, `LineTo`, `QuadTo`, `CubicTo`, and `ClosePath` commands. |
| `GlyphMetrics` & `FontBoundingBox` | Stores advance width, left side bearing, analytical Bezier bounds, optional italics correction, and top accent attachment. |
| `FontVariationAxis` & `StemHint` | `FontVariationAxis` describes `fvar` axes (`tag`, `minValue`, `defaultValue`, `maxValue`, `flags`, `axisNameId`); `StemHint` (`StemOrientation`) stores Type 2 CharString stem hints. |

When calling `outlineForGlyph`, passing `enableHinting: true` grid-aligns Type 2 stem hints at the requested `ppem` (defaulting to `16.0`) and caches hinted outlines per glyph.

### Display List, Break Hints & SVG Export (`DisplayList`, `DisplayBreakHint`)

`DisplayList` stores bounding metrics, positioned primitives, top-level break hints, an optional source string, and an optional font signature. It exports standalone XML 1.0 SVG via:

```dart
String toSvg({
  double fontSize = 16.0,
  int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
  int maxSvgLength = TexMathBudgets.defaultMaxSvgLength,
  Map<TexMathColorRole, String>? colors,
  String? title,
})
```

| Symbol | Key Fields | Role |
| :--- | :--- | :--- |
| `DisplayMetrics` | `widthEm`, `heightEm`, `depthEm`, `baselineEm`, `unitsPerEm`, `totalHeightEm`, `widthUnits`, `heightUnits`, `depthUnits` | Em-space and design-unit layout dimensions relative to the baseline. |
| `DisplayBreakHint` & `BreakPoint` | `xEm`, `afterItemIndex`, `breakPoint`, `span`, `kind` (`MathBreakKind`: `none`, `afterBinary`, `afterRelation`, `penalty`, `explicit`), `penalty`, `isExplicit`, `isGood` | Top-level discretionary and forced line-break metadata for wrapping downstream consumers. |
| `DisplayItem` | `GlyphItem`, `RuleItem`, `AnchorItem` (each carrying `span`, `colorRole`, `customColor`) | Positioned glyph IDs with optional cached outlines, filled/stroked rules, and semantic anchors. |
| `AnchorItem` | `id`, `xEm`, `yEm`, `widthEm`, `heightEm`, `depthEm`, `label`, `href` (getter) | Non-inked anchor marker carrying optional hitbox bounds (`widthEm`, `heightEm` above `yEm`, `depthEm` below `yEm`, defaulting to `0.0`); the `href` getter returns the validated safe URI for `href:` anchors (`null` otherwise), and `DisplayList.toSvg()` appends `<a href="..." data-href="..."><rect ... fill="none" pointer-events="all"/></a>` overlays when `href != null` and `widthEm > 0`. |

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

`package:tex_math_flutter/tex_math_flutter.dart` gives Flutter callers a single import by re-exporting 24 core types alongside the Flutter widget, theme, caching, selection, and background-isolate APIs:

```dart
export 'package:tex_math/tex_math.dart'
    show
        AnchorItem,
        DisplayItem,
        DisplayList,
        DisplayMetrics,
        GlyphOutline,
        MathFont,
        MathNode,
        MathRootNode,
        PathCommand,
        RenderResult,
        SourceSpan,
        TexMathBudgetError,
        TexMathBudgets,
        TexMathColorRole,
        TexMathDisplayMode,
        TexMathEngine,
        TexMathError,
        TexMathErrorClass,
        TexMathFontError,
        TexMathMacroError,
        TexMathOptions,
        TexMathSyntaxError,
        TexMathTagMode,
        TexMathUnsupportedError;
```

### Widgets & Overflow (`TexMath`, `TexMathSpan`, `TexMathOverflow`, `TexMathErrorWidget`)

| Type / Constructor | Summary & Defaults |
| :--- | :--- |
| `TexMath(source, ...)` | Default `StatefulWidget` (`displayMode = TexMathDisplayMode.display`), resolving font size from `textStyle`, `TexMathTheme`, `DefaultTextStyle`, or theme fallback scaled by `MediaQuery.textScalerOf(context)`. |
| `TexMath.inline(source, ...)` | Inline preset (`displayMode = TexMathDisplayMode.inline`, `overflow = TexMathOverflow.visible`). |
| `TexMath.display(source, ...)` | Display preset (`displayMode = TexMathDisplayMode.display`, `overflow = TexMathOverflow.scroll`). |
| `TexMath.displayList(displayList, ...)` | Renders a pre-computed display list directly without running parsing or layout again. |
| `TexMathSpan(source, ...)` | `WidgetSpan` aligned with `PlaceholderAlignment.baseline` and `TextBaseline.alphabetic` for `Text.rich` and `RichText`, scaling baselines proportionally under `scaleToFit`. |
| `TexMathOverflow` | Horizontal overflow policy: `scroll`, `scaleToFit`, `clip`, or `visible` (expanding hit-test bounds cleanly). |
| `TexMathErrorWidget` & `TexMathErrorBuilder` | Monospace diagnostic fallback taking `source`, optional `error`, `errorMessage`, `displayMode`, and `selectable`; highlights offending UTF-16 error spans or caret positions (`error?.formattedMessage`), respects `selectable: false` inside ancestor selection areas, and sets `Semantics(excludeSemantics: true)`. `TexMathErrorBuilder` allows custom error UI. |

Both `TexMath` and `TexMathSpan` accept the shared widget parameters below:

| Parameter | Purpose |
| :--- | :--- |
| `options` / `engine` | Override default TeX options or supply a custom `TexMathEngine` instance. |
| `font` | Provide an explicit `MathFont` instead of auto-loading the bundled font. |
| `overflow` | Override the default horizontal overflow policy (`TexMathOverflow`). |
| `pathCache` | Supply a custom `TexMathPathCache` instead of `TexMathPathCache.shared`. |
| `layouter` | Offload parsing and layout to a `TexMathIsolateLayouter` background worker. |
| `textStyle` / `style` | Override font size and foreground color (`style` on `TexMathSpan`, `textStyle` on `TexMath`). |
| `errorBuilder` | Build a custom fallback widget when parsing or layout throws a `TexMathError`. |
| `semanticsLabel` | Override the generated spoken-text accessibility label. |
| `selectable` | Enable or disable `"copy as LaTeX"` selection handling. |
| `onLinkTap` | Optional `ValueChanged<String>?` callback invoked with the target URI when a user taps a safe `\href` link hitbox inside the rendered expression (`TexMath`, `TexMath.inline`, `TexMath.display`, `TexMath.displayList`, and `TexMathSpan`). |

When `onLinkTap` is non-null, `RenderTexMath` builds interactive hit regions from `AnchorItem` records with non-null `href` and positive `widthEm`, displaying `SystemMouseCursors.click` while hovering over a link hitbox and reverting to `MouseCursor.defer` outside it. Taps trigger `onLinkTap(uri)` only when the primary pointer presses and releases within `kTouchSlop` inside the same link region, preserving `SelectionArea` drag selection across `\href` spans painted in `TexMathThemeData.accent`.

### Sub-Expression Selection (`TexMathSelectionUtils`)

Inside a `SelectionArea`, `TexMath` builds hit boxes lazily only when registered for selection and uses `TexMathSelectionUtils` so partial drags copy syntactically valid LaTeX:

* **`expandSpanToMinimalNode(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Expands `targetSpan` to the smallest enclosing `MathNode.span` (or contiguous top-level children), balancing braces and environment delimiters.
* **`sliceMinimalLatex(MathNode? syntaxTree, SourceSpan targetSpan, String source)`**: Convenience wrapper returning the expanded source slice for clipboard copy actions.

### Theming, Path Cache & Painting (`TexMathTheme`, `TexMathPathCache`, `TexMathDisplayPainter`)

| Type | Role & Key Members |
| :--- | :--- |
| `TexMathPathCache` | Bounded LRU `Path` cache (`defaultMaxEntries = 4096`, `maxTextPainterEntries` defaulting to `min(maxEntries, 256)`, singleton `TexMathPathCache.shared`) keyed by font signature, glyph ID, and optional `ppemBucket` for real glyphs while isolating synthetic `glyphId == 0` procedural outlines (e.g. `\enclose`, `\cancel`) by outline identity. Exposes `length`, `hitCount`, `buildCount`, `pathForGlyph`, `resolvePath`, and `clear`. |
| `TexMathDisplayPainter` | `CustomPainter` drawing glyphs, filled or stroked rules, and selection highlights onto a `Canvas` using cached `Paint` objects; exposes static `paintDisplayList` and `buildPathFromCommands`. |
| `TexMathThemeData` & `TexMathTheme` | `InheritedTheme` propagating `foreground`, `accent`, `error`, `muted`, `errorBackground`, and `fontSize = 18.0`, with `fromColorScheme`, `fallback`, `colorForRole`, `copyWith`, `lerp`, `of`, and `maybeOf`. |

### Bundled Math Font & Persistent Isolate Layouter (`TexMathFontBundle`, `TexMathIsolateLayouter`)

`TexMathFontBundle` loads and caches the bundled `NewCMMath-Regular.otf`, `GUST-FONT-LICENSE.txt`, and `MANIFEST-NewCMMath.txt` assets once per app lifecycle:

| Method / Property | Behavior |
| :--- | :--- |
| `TexMathFontBundle.load` | Validates non-empty bytes and the `OTTO` OpenType header, returning `Future<TexMathFontAsset>`. |
| `TexMathFontBundle.loadMathFont` | Loads and decodes `NewCMMath-Regular.otf` off the UI thread via `Isolate.run` on native platforms and seamless conditional-import fallback on Web/Wasm, returning `Future<MathFont>`. |
| `cachedAsset` / `cachedMathFont` | Synchronous getters returning already-loaded bundle assets or decoded fonts, plus `@visibleForTesting` `clearCache()`. |
| `TexMathFontAsset` | Exposes `bytes`, `familyName`, `assetPath`, `licenseText`, `byteLength`, `hasOttoHeader`, and `decodeMathFont()`. |

`TexMathIsolateLayouter` runs parsing and layout in a persistent background worker isolate on native platforms (`Android`, `iOS`, `Linux`, `macOS`, `Windows`) with seamless asynchronous conditional-import fallback on Web/Wasm, backed by an LRU cache keyed by `TexMathLayoutCacheKey(source, options, fontId, fontSignature)`:

| Member | Behavior |
| :--- | :--- |
| Constructors | `TexMathIsolateLayouter({maxCacheEntries = 256, fontId = 'NewCMMath-Regular', fontBytes, shutdownTimeout = Duration(milliseconds: 500)})` and `TexMathIsolateLayouter.withBundledFont(...)`. |
| Lifecycle & Status | `warmUp()`, `dispose()` (killing unresponsive native workers after `shutdownTimeout`), `hasFontBytes`, `isWorkerRunning`, and `isDisposed`. |
| Rendering & Cache | `renderInBackground`, `layoutInBackground`, `getCached`, `putCached`, `clearCache`, `cacheLength`, `hitCount`, and `missCount`. Transfers font bytes once on native isolates, deduplicates in-flight renders, recovers automatically from native worker crashes, and preserves `TexMathError` diagnostics and stack traces. |

### Example Usage (Flutter Theme, Inline Span, & Persistent Isolate Layouter)

```dart
import 'dart:async';

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
    unawaited(_initLayouter());
  }

  Future<void> _initLayouter() async {
    final TexMathIsolateLayouter layouter =
        await TexMathIsolateLayouter.withBundledFont();
    if (!mounted) {
      await layouter.dispose();
      return;
    }
    setState(() => _layouter = layouter);
  }

  @override
  void dispose() {
    final TexMathIsolateLayouter? active = _layouter;
    if (active != null) {
      unawaited(active.dispose());
    }
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
