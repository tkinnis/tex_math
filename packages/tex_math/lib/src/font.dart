import 'dart:collection';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'error.dart';
import 'font/binary_reader.dart';
import 'font/cff_decoder.dart';
import 'font/glyf.dart';
import 'font/math_table.dart';
import 'font/metrics.dart';
import 'font/outline.dart';
import 'font/outline_utils.dart';
import 'font/sfnt.dart';
import 'font/variation.dart';

export 'font/math_table.dart'
    show
        GlyphAssembly,
        GlyphAssemblyPart,
        MathConstants,
        MathGlyphConstruction,
        MathGlyphInfo,
        MathGlyphVariant,
        MathKernCorner,
        MathTableData,
        MathValueRecord,
        MathVariants;
export 'font/metrics.dart'
    show
        FontBoundingBox,
        FontVariationAxis,
        GlyphMetrics,
        StemHint,
        StemOrientation;
export 'font/outline.dart'
    show ClosePath, CubicTo, GlyphOutline, LineTo, MoveTo, PathCommand, QuadTo;

/// Pure-Dart OpenType math font reader backed by in-memory SFNT bytes.
///
/// Decodes SFNT core metric and mapping tables (`head`, `hhea`, `maxp`, `hmtx`,
/// `OS/2`, `name`, `cmap`, `GSUB` `ssty`), the full OpenType `MATH` table,
/// variable-font tables (`fvar`, `avar`, `HVAR`), and lazily caches TrueType
/// (`glyf`/`loca`) and PostScript (`CFF`/`CFF2`) outlines and metrics per
/// glyph ID.
@immutable
final class MathFont {
  const MathFont._({
    required this.familyName,
    required this.unitsPerEm,
    required this._data,
  });

  /// Creates a placeholder font descriptor for unit tests without font table
  /// decoding.
  const MathFont.stub({
    this.familyName = 'NewComputerModernMath',
    this.unitsPerEm = 1000,
  }) : _data = null;

  /// Default maximum font payload accepted by [MathFont.fromBytes] (`16 MiB`).
  static const int defaultMaxFontBytes = 16 * 1024 * 1024;

  /// Parses an OpenType or TrueType font from an in-memory [bytes] buffer.
  ///
  /// Enforces [maxBytes] (`TexMathBudgetError`), validates the SFNT container
  /// and table bounds (`TexMathFontError`), and initializes variable-font
  /// coordinates from [variationAxes] (`fvar`/`avar`).
  factory MathFont.fromBytes(
    Uint8List bytes, {
    int maxBytes = defaultMaxFontBytes,
    Map<String, double> variationAxes = const <String, double>{},
  }) {
    if (bytes.isEmpty) {
      throw const TexMathFontError('Font byte buffer must not be empty.');
    }
    if (bytes.length > maxBytes) {
      throw TexMathBudgetError(
        'Font byte length ${bytes.length} exceeds limit $maxBytes.',
        budgetName: 'maxFontBytes',
        limit: maxBytes,
        actual: bytes.length,
      );
    }

    final FontByteReader rootReader = FontByteReader(bytes);
    final SfntDirectory directory = SfntDirectory.parse(rootReader);

    final HeadTable head = HeadTable.parse(directory.requireTable('head'));
    final MaxpTable maxp = MaxpTable.parse(directory.requireTable('maxp'));
    final HheaTable hhea = HheaTable.parse(
      directory.requireTable('hhea'),
      maxp.numGlyphs,
    );
    final HmtxTable hmtx = HmtxTable.parse(
      directory.requireTable('hmtx'),
      maxp.numGlyphs,
      hhea.numberOfHMetrics,
    );
    final Os2Table os2 = Os2Table.parseOptional(directory['OS/2']);
    final String familyName = parseFamilyName(directory['name']);
    final CmapTable cmap = CmapTable.parseOptional(
      directory['cmap'],
      maxp.numGlyphs,
    );
    final GsubSstyTable gsub = GsubSstyTable.parseOptional(directory['GSUB']);

    final VariationSpace varSpace = VariationSpace.parse(
      fvarReader: directory['fvar'],
      avarReader: directory['avar'],
      userAxes: variationAxes,
    );
    final FontByteReader? hvarReader = directory['HVAR'];
    final HvarTable? hvar = hvarReader == null
        ? null
        : HvarTable.parse(hvarReader, varSpace.normalizedCoords);
    final ItemVariationStore? gdefVarStore = parseGdefVariationStore(
      directory['GDEF'],
      varSpace.normalizedCoords,
    );

    final FontByteReader? mathReader = directory['MATH'];
    final MathTableData? mathTable = mathReader == null
        ? null
        : MathTableData.parse(mathReader, gdefVarStore: gdefVarStore);

    CffOutlineDecoder? cffDecoder;
    final FontByteReader? cff2Reader = directory['CFF2'];
    final FontByteReader? cff1Reader = directory['CFF '];
    if (cff2Reader != null) {
      cffDecoder = CffOutlineDecoder.parseCff2(
        reader: cff2Reader,
        unitsPerEm: head.unitsPerEm,
        normalizedCoords: varSpace.normalizedCoords,
      );
    } else if (cff1Reader != null) {
      cffDecoder = CffOutlineDecoder.parseCff1(
        reader: cff1Reader,
        unitsPerEm: head.unitsPerEm,
        expectedNumGlyphs: maxp.numGlyphs,
      );
    }

    GlyfDecoder? glyfDecoder;
    final FontByteReader? glyfReader = directory['glyf'];
    final FontByteReader? locaReader = directory['loca'];
    if (glyfReader != null && locaReader != null) {
      glyfDecoder = GlyfDecoder.parse(
        glyfReader: glyfReader,
        locaReader: locaReader,
        numGlyphs: maxp.numGlyphs,
        indexToLocFormat: head.indexToLocFormat,
      );
    }

    final _LoadedFontData loaded = _LoadedFontData(
      sfntSignature: _computeSfntSignature(bytes),
      sfntLength: bytes.length,
      head: head,
      maxp: maxp,
      hhea: hhea,
      hmtx: hmtx,
      os2: os2,
      cmap: cmap,
      gsub: gsub,
      variationSpace: varSpace,
      hvar: hvar,
      mathTable: mathTable,
      cffDecoder: cffDecoder,
      glyfDecoder: glyfDecoder,
    );

    return MathFont._(
      familyName: familyName,
      unitsPerEm: head.unitsPerEm,
      data: loaded,
    );
  }

  /// Font family name from `name` table (or stub default).
  final String familyName;

  /// Design units per em square from `head`.
  final int unitsPerEm;

  final _LoadedFontData? _data;

  /// Total number of glyphs declared in `maxp` (`0` on stub fonts).
  int get numGlyphs => _data?.maxp.numGlyphs ?? 0;

  /// Typographic ascender from `hhea` in font design units.
  int get ascender => _data?.hhea.ascender ?? 800;

  /// Typographic descender from `hhea` in font design units.
  int get descender => _data?.hhea.descender ?? -200;

  /// Line gap from `hhea` in font design units.
  int get lineGap => _data?.hhea.lineGap ?? 0;

  /// Count of full horizontal metric entries in `hmtx`.
  int get numberOfHMetrics => _data?.hhea.numberOfHMetrics ?? 0;

  /// TrueType `loca` index format (`0` = short, `1` = long).
  int get indexToLocFormat => _data?.head.indexToLocFormat ?? 0;

  /// Global font bounding box from `head`.
  FontBoundingBox get boundingBox =>
      _data?.head.boundingBox ?? FontBoundingBox.zero;

  /// Optional x-height from `OS/2` (`sxHeight`).
  int? get xHeight => _data?.os2.xHeight;

  /// Optional cap height from `OS/2` (`sCapHeight`).
  int? get capHeight => _data?.os2.capHeight;

  /// Optional typographic ascender from `OS/2` (`sTypoAscender`).
  int? get typoAscender => _data?.os2.typoAscender;

  /// Optional typographic descender from `OS/2` (`sTypoDescender`).
  int? get typoDescender => _data?.os2.typoDescender;

  /// Declared variation axes from `fvar` (empty for static fonts).
  List<FontVariationAxis> get axes {
    final List<FontVariationAxis>? list = _data?.variationSpace.axes;
    return (list == null || list.isEmpty)
        ? const <FontVariationAxis>[]
        : UnmodifiableListView<FontVariationAxis>(list);
  }

  /// Active clamped user-space variation axis coordinates keyed by tag.
  Map<String, double> get variationAxes {
    final Map<String, double>? map = _data?.variationSpace.resolvedUserCoords;
    return (map == null || map.isEmpty)
        ? const <String, double>{}
        : UnmodifiableMapView<String, double>(map);
  }

  /// Active normalized variation coordinates in `[-1.0, 1.0]`.
  List<double> get normalizedVariationCoordinates {
    final List<double>? list = _data?.variationSpace.normalizedCoords;
    return (list == null || list.isEmpty)
        ? const <double>[]
        : UnmodifiableListView<double>(list);
  }

  /// Fast deterministic payload-and-variation signature distinguishing distinct
  /// fonts even when typographic header fields match.
  int get signature =>
      _data?.fontSignature ?? Object.hash(0, familyName, unitsPerEm);

  /// Parsed OpenType `MATH` table, or `null` if absent (or on stub fonts).
  MathTableData? get mathTable => _data?.mathTable;

  /// Maps Unicode scalar [codePoint] via `cmap` (Format 12 / Format 4) to an
  /// OpenType glyph ID, returning `0` if unmapped.
  int glyphIdForCodePoint(int codePoint) {
    return _data?.cmap.glyphIdForCodePoint(codePoint) ?? 0;
  }

  /// Resolves the `GSUB` `ssty` script variant glyph ID for [glyphId] at
  /// [level] (`0` = script, `1` = scriptscript), returning `null` if none.
  int? scriptVariantGlyph(int glyphId, int level) {
    return _data?.gsub.scriptVariantGlyph(glyphId, level);
  }

  /// Returns horizontal advance width for [glyphId] in font design units.
  double advanceWidthForGlyph(int glyphId) {
    final _LoadedFontData? data = _data;
    if (data == null || glyphId < 0 || glyphId >= data.maxp.numGlyphs) {
      return 0.0;
    }
    return data.advanceWidthFor(glyphId);
  }

  /// Returns left side bearing for [glyphId] in font design units.
  double lsbForGlyph(int glyphId) {
    final _LoadedFontData? data = _data;
    if (data == null || glyphId < 0 || glyphId >= data.maxp.numGlyphs) {
      return 0.0;
    }
    return data.lsbFor(glyphId);
  }

  /// Lazily decodes and caches the vector outline for [glyphId], returning
  /// `null` if [glyphId] is missing or out of bounds.
  ///
  /// When [enableHinting] is `true`, captured horizontal and vertical stem
  /// hints from `CFF`/`CFF2` are grid-aligned at [ppem] (defaulting to `16.0`
  /// when omitted) while keeping coordinates in font design units.
  GlyphOutline? outlineForGlyph(
    int glyphId, {
    double? ppem,
    bool enableHinting = false,
  }) {
    final _LoadedFontData? data = _data;
    if (data == null) {
      return null;
    }
    return data.outlineForGlyph(
      glyphId,
      ppem: ppem,
      enableHinting: enableHinting,
    );
  }

  /// Returns horizontal and vertical stem hints captured for [glyphId].
  List<StemHint> stemHintsForGlyph(int glyphId) {
    return _data?.stemHintsForGlyph(glyphId) ?? const <StemHint>[];
  }

  /// Lazily computes and caches complete metrics and tight outline bounding
  /// box for [glyphId].
  GlyphMetrics metricsForGlyph(int glyphId) {
    final _LoadedFontData? data = _data;
    if (data == null || glyphId < 0 || glyphId >= data.maxp.numGlyphs) {
      return GlyphMetrics.empty(glyphId);
    }
    return data.metricsForGlyph(glyphId);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! MathFont) {
      return false;
    }
    if ((_data == null) != (other._data == null)) {
      return false;
    }
    return signature == other.signature &&
        _data?.sfntSignature == other._data?.sfntSignature &&
        _data?.sfntLength == other._data?.sfntLength &&
        familyName == other.familyName &&
        unitsPerEm == other.unitsPerEm &&
        numGlyphs == other.numGlyphs &&
        ascender == other.ascender &&
        descender == other.descender &&
        _doubleMapEquals(variationAxes, other.variationAxes);
  }

  @override
  int get hashCode =>
      _data?.fontHashCode ?? Object.hash(0, familyName, unitsPerEm);

  @override
  String toString() =>
      'MathFont(familyName: $familyName, unitsPerEm: $unitsPerEm, '
      'numGlyphs: $numGlyphs)';
}

final class _LoadedFontData {
  _LoadedFontData({
    required this.sfntSignature,
    required this.sfntLength,
    required this.head,
    required this.maxp,
    required this.hhea,
    required this.hmtx,
    required this.os2,
    required this.cmap,
    required this.gsub,
    required this.variationSpace,
    required this.hvar,
    required this.mathTable,
    required this.cffDecoder,
    required this.glyfDecoder,
  }) : _outlineDecoded = Uint8List(maxp.numGlyphs),
       _outlineCache = List<GlyphOutline?>.filled(maxp.numGlyphs, null),
       _cffCache = List<DecodedCffOutline?>.filled(maxp.numGlyphs, null),
       _metricsCache = List<GlyphMetrics?>.filled(maxp.numGlyphs, null),
       fontSignature = _mixSignature(
         sfntSignature,
         sfntLength,
         variationSpace.normalizedCoords,
       ),
       fontHashCode = Object.hash(
         sfntSignature,
         sfntLength,
         head.unitsPerEm,
         maxp.numGlyphs,
         hhea.ascender,
         hhea.descender,
         Object.hashAll(variationSpace.normalizedCoords),
       );

  final int sfntSignature;
  final int sfntLength;
  final int fontSignature;
  final int fontHashCode;
  final HeadTable head;
  final MaxpTable maxp;
  final HheaTable hhea;
  final HmtxTable hmtx;
  final Os2Table os2;
  final CmapTable cmap;
  final GsubSstyTable gsub;
  final VariationSpace variationSpace;
  final HvarTable? hvar;
  final MathTableData? mathTable;
  final CffOutlineDecoder? cffDecoder;
  final GlyfDecoder? glyfDecoder;

  final Uint8List _outlineDecoded;
  final List<GlyphOutline?> _outlineCache;
  final List<DecodedCffOutline?> _cffCache;
  final List<GlyphMetrics?> _metricsCache;
  final Map<(int, double), GlyphOutline> _hintedOutlineCache =
      <(int, double), GlyphOutline>{};

  double advanceWidthFor(int glyphId) {
    final double base = hmtx.advanceWidthFor(glyphId).toDouble();
    final double delta = hvar?.advanceWidthDelta(glyphId) ?? 0.0;
    return base + delta;
  }

  double lsbFor(int glyphId) {
    final double base = hmtx.lsbFor(glyphId).toDouble();
    final double delta = hvar?.lsbDelta(glyphId) ?? 0.0;
    return base + delta;
  }

  GlyphOutline? outlineForGlyph(
    int glyphId, {
    double? ppem,
    bool enableHinting = false,
  }) {
    if (glyphId < 0 || glyphId >= maxp.numGlyphs) {
      return null;
    }
    _ensureDecoded(glyphId);
    final GlyphOutline? base = _outlineCache[glyphId];
    if (base == null || !enableHinting) {
      return base;
    }
    final DecodedCffOutline? cff = _cffCache[glyphId];
    if (cff == null || cff.stems.isEmpty) {
      return base;
    }
    final double effectivePpem = (ppem != null && ppem.isFinite && ppem > 0.0)
        ? ppem
        : 16.0;
    final (int, double) hintKey = (glyphId, effectivePpem);
    final GlyphOutline? cachedHinted = _hintedOutlineCache[hintKey];
    if (cachedHinted != null) {
      return cachedHinted;
    }
    final List<PathCommand> hintedCommands = applyStemHinting(
      commands: base.commands,
      stems: cff.stems,
      unitsPerEm: head.unitsPerEm,
      ppem: effectivePpem,
      context: cff.hintContext,
    );
    final GlyphOutline hinted = GlyphOutline.cached(
      glyphId: glyphId,
      commands: hintedCommands,
      advanceWidth: base.advanceWidth,
    );
    _hintedOutlineCache[hintKey] = hinted;
    return hinted;
  }

  List<StemHint> stemHintsForGlyph(int glyphId) {
    if (glyphId < 0 || glyphId >= maxp.numGlyphs) {
      return const <StemHint>[];
    }
    _ensureDecoded(glyphId);
    return _cffCache[glyphId]?.stems ?? const <StemHint>[];
  }

  GlyphMetrics metricsForGlyph(int glyphId) {
    final GlyphMetrics? cached = _metricsCache[glyphId];
    if (cached != null) {
      return cached;
    }
    final GlyphOutline? outline = outlineForGlyph(glyphId);
    final FontBoundingBox bbox = outline == null
        ? FontBoundingBox.zero
        : computeOutlineBoundingBox(outline.commands);
    final double adv = advanceWidthFor(glyphId);
    final double lsb = lsbFor(glyphId);
    final double? ital = mathTable?.glyphInfo.italicsCorrection(glyphId);
    final double? topAccent = mathTable?.glyphInfo.topAccentAttachment(glyphId);

    final GlyphMetrics metrics = GlyphMetrics(
      glyphId: glyphId,
      advanceWidth: adv,
      lsb: lsb,
      xMin: bbox.xMin,
      yMin: bbox.yMin,
      xMax: bbox.xMax,
      yMax: bbox.yMax,
      height: bbox.height,
      depth: bbox.depth,
      italicsCorrection: ital,
      topAccentAttachment: topAccent,
    );
    _metricsCache[glyphId] = metrics;
    return metrics;
  }

  void _ensureDecoded(int glyphId) {
    if (_outlineDecoded[glyphId] != 0) {
      return;
    }
    _outlineDecoded[glyphId] = 1;
    final double adv = advanceWidthFor(glyphId);
    if (cffDecoder != null) {
      final DecodedCffOutline? cff = cffDecoder!.decodeGlyph(glyphId, adv);
      _cffCache[glyphId] = cff;
      _outlineCache[glyphId] = cff?.outline;
      return;
    }
    if (glyfDecoder != null) {
      _outlineCache[glyphId] = glyfDecoder!.decodeGlyph(glyphId, adv);
    }
  }
}

bool _doubleMapEquals(Map<String, double> a, Map<String, double> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final MapEntry<String, double> entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _computeSfntSignature(Uint8List bytes) {
  int h1 = 0x811C9DC5 ^ bytes.length;
  int h2 = 0x9E3779B9 ^ bytes.length;

  void mix(int value) {
    h1 = ((h1 ^ value) * 0x01000193) & 0x7FFFFFFF;
    h2 = ((h2 + value + 0x9E3779B9) * 0x85EBCA6B) & 0x7FFFFFFF;
  }

  // Mix SFNT header and full table directory (tag, checksum, offset, length).
  final int numTables = bytes.length >= 6 ? ((bytes[4] << 8) | bytes[5]) : 0;
  final int directoryEnd = 12 + numTables * 16;
  final int headerScanEnd = directoryEnd <= bytes.length
      ? directoryEnd
      : (bytes.length < 256 ? bytes.length : 256);
  for (int i = 0; i < headerScanEnd; i++) {
    mix(bytes[i]);
  }

  // Mix full payload for small test fonts or strided samples + tail for large
  // fonts to catch un-checksummed single-byte mutations quickly.
  if (bytes.length <= 8192) {
    for (int i = headerScanEnd; i < bytes.length; i++) {
      mix(bytes[i]);
    }
  } else {
    final int step = bytes.length ~/ 256;
    for (int i = 0; i < bytes.length; i += step) {
      mix(bytes[i]);
    }
    final int tailStart = bytes.length - 32;
    for (int i = tailStart; i < bytes.length; i++) {
      mix(bytes[i]);
    }
  }
  return (h1 << 21) ^ h2;
}

int _mixSignature(int sfntSig, int len, List<double> normalizedCoords) {
  if (normalizedCoords.isEmpty) {
    return sfntSig;
  }
  return Object.hash(sfntSig, len, Object.hashAll(normalizedCoords)) &
      0x1FFFFFFFFFFFFF;
}
