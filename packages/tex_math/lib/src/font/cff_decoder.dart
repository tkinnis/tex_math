import '../error.dart';
import 'binary_reader.dart';
import 'cff_common.dart';
import 'metrics.dart';
import 'outline.dart';
import 'outline_utils.dart';
import 'type2_charstring.dart';
import 'variation.dart';

/// Parsed Private DICT configuration for a CFF or CFF2 Font DICT.
final class _FontDictInfo {
  const _FontDictInfo({
    required this.localSubrs,
    required this.defaultWidthX,
    required this.nominalWidthX,
    required this.vsindex,
    required this.hintContext,
    required this.fontMatrix,
  });

  final CffIndex localSubrs;
  final double defaultWidthX;
  final double nominalWidthX;
  final int vsindex;
  final HintingContext hintContext;
  final List<double>? fontMatrix;
}

/// Decoded outline plus captured stem hints and FD index prior to optional
/// ppem-dependent hinting.
final class DecodedCffOutline {
  const DecodedCffOutline({
    required this.outline,
    required this.stems,
    required this.hintContext,
  });

  final GlyphOutline outline;
  final List<StemHint> stems;
  final HintingContext hintContext;
}

/// Lazy outline decoder supporting both OpenType `CFF ` (v1) and variable
/// `CFF2` (v2) tables.
final class CffOutlineDecoder {
  CffOutlineDecoder._({
    required this.isCff2,
    required this.unitsPerEm,
    required this._charStrings,
    required this._globalSubrs,
    required this._fontDicts,
    required this._fdSelect,
    required this._variationStore,
    required this._topFontMatrix,
    required this._maxStack,
  });

  final bool isCff2;
  final int unitsPerEm;
  final CffIndex _charStrings;
  final CffIndex _globalSubrs;
  final List<_FontDictInfo> _fontDicts;
  final FdSelectTable _fdSelect;
  final ItemVariationStore? _variationStore;
  final List<double>? _topFontMatrix;
  final int _maxStack;

  /// Number of glyphs inside the CharStrings INDEX.
  int get numGlyphs => _charStrings.length;

  /// Parses a CFF v1 (`CFF `) table.
  factory CffOutlineDecoder.parseCff1({
    required FontByteReader reader,
    required int unitsPerEm,
    required int expectedNumGlyphs,
  }) {
    if (reader.length < 4) {
      throw const TexMathFontError('Truncated CFF table (< 4 bytes).');
    }
    final int major = reader.readUint8(0, 'CFF.major');
    final int hdrSize = reader.readUint8(2, 'CFF.hdrSize');
    if (major != 1 || hdrSize < 4 || hdrSize > reader.length) {
      throw TexMathFontError(
        'Unsupported CFF header (major=$major, hdr=$hdrSize).',
      );
    }

    final CffIndex nameIndex = CffIndex.parse(
      reader,
      hdrSize,
      isCff2: false,
      context: 'CFF.NameINDEX',
    );
    final CffIndex topDictIndex = CffIndex.parse(
      reader,
      nameIndex.endOffset,
      isCff2: false,
      context: 'CFF.TopDICTINDEX',
    );
    if (topDictIndex.length == 0) {
      throw const TexMathFontError('CFF Top DICT INDEX is empty.');
    }
    final CffIndex stringIndex = CffIndex.parse(
      reader,
      topDictIndex.endOffset,
      isCff2: false,
      context: 'CFF.StringINDEX',
    );
    final CffIndex globalSubrs = CffIndex.parse(
      reader,
      stringIndex.endOffset,
      isCff2: false,
      context: 'CFF.GlobalSubrINDEX',
    );

    final Map<CffDictOp, List<double>> topDict = parseCffDict(topDictIndex[0]);
    final List<double>? charStringsVals = topDict[const CffDictOp(17)];
    if (charStringsVals == null || charStringsVals.isEmpty) {
      throw const TexMathFontError('CFF Top DICT missing CharStrings offset.');
    }
    final int csOffset = cffFiniteInt(
      charStringsVals[0],
      'CFF.TopDICT.CharStrings',
    );
    final CffIndex charStrings = CffIndex.parse(
      reader,
      csOffset,
      isCff2: false,
      context: 'CFF.CharStringsINDEX',
    );
    final int glyphCount = charStrings.length > 0
        ? charStrings.length
        : expectedNumGlyphs;

    final List<double>? topMatrix = topDict[const CffDictOp(12, 7)];
    final List<double>? fdArrayVals = topDict[const CffDictOp(12, 36)];
    final List<double>? fdSelectVals = topDict[const CffDictOp(12, 37)];

    final List<_FontDictInfo> fontDicts = <_FontDictInfo>[];
    FdSelectTable fdSelect = FdSelectTable.singleZero;

    if (fdArrayVals != null && fdArrayVals.isNotEmpty) {
      final CffIndex fdIndex = CffIndex.parse(
        reader,
        cffFiniteInt(fdArrayVals[0], 'CFF.TopDICT.FDArray'),
        isCff2: false,
        context: 'CFF.FDArray',
      );
      for (int i = 0; i < fdIndex.length; i++) {
        final Map<CffDictOp, List<double>> fd = parseCffDict(fdIndex[i]);
        fontDicts.add(_parseFontDict(reader, fd, isCff2: false));
      }
      if (fdSelectVals != null && fdSelectVals.isNotEmpty) {
        fdSelect = FdSelectTable.parse(
          reader,
          cffFiniteInt(fdSelectVals[0], 'CFF.TopDICT.FDSelect'),
          glyphCount,
        );
      }
    } else {
      fontDicts.add(_parseFontDict(reader, topDict, isCff2: false));
    }

    if (fontDicts.isEmpty) {
      fontDicts.add(
        _FontDictInfo(
          localSubrs: CffIndex.empty,
          defaultWidthX: 0.0,
          nominalWidthX: 0.0,
          vsindex: 0,
          hintContext: const HintingContext(),
          fontMatrix: null,
        ),
      );
    }

    return CffOutlineDecoder._(
      isCff2: false,
      unitsPerEm: unitsPerEm,
      charStrings: charStrings,
      globalSubrs: globalSubrs,
      fontDicts: fontDicts,
      fdSelect: fdSelect,
      variationStore: null,
      topFontMatrix: topMatrix,
      maxStack: 513,
    );
  }

  /// Parses a CFF2 (`CFF2`) variable font table using [normalizedCoords].
  factory CffOutlineDecoder.parseCff2({
    required FontByteReader reader,
    required int unitsPerEm,
    required List<double> normalizedCoords,
  }) {
    if (reader.length < 5) {
      throw const TexMathFontError('Truncated CFF2 table (< 5 bytes).');
    }
    final int major = reader.readUint8(0, 'CFF2.majorVersion');
    final int hdrSize = reader.readUint8(2, 'CFF2.headerSize');
    final int topDictLen = reader.readUint16(3, 'CFF2.topDictLength');
    if (major != 2 || hdrSize < 5 || hdrSize + topDictLen > reader.length) {
      throw TexMathFontError(
        'Invalid CFF2 header (major=$major, hdrSize=$hdrSize, '
        'topDictLen=$topDictLen).',
      );
    }

    final FontByteReader topDictReader = reader.slice(
      hdrSize,
      topDictLen,
      'CFF2.TopDICT',
    );
    final Map<CffDictOp, List<double>> topDict = parseCffDict(topDictReader);

    final CffIndex globalSubrs = CffIndex.parse(
      reader,
      hdrSize + topDictLen,
      isCff2: true,
      context: 'CFF2.GlobalSubrINDEX',
    );

    ItemVariationStore? varStore;
    final List<double>? vstoreVals = topDict[const CffDictOp(24)];
    if (vstoreVals != null && vstoreVals.isNotEmpty) {
      final int vstoreOff = cffFiniteInt(vstoreVals[0], 'CFF2.TopDICT.vstore');
      final int storeLen = reader.readUint16(vstoreOff, 'CFF2.vstore.length');
      reader.checkRange(vstoreOff + 2, storeLen, 'CFF2.vstore.data');
      final FontByteReader storeSlice = reader.slice(
        vstoreOff + 2,
        storeLen,
        'CFF2.ItemVariationStore',
      );
      varStore = ItemVariationStore.parse(
        storeSlice,
        0,
        normalizedCoords,
        readDeltaSets: false,
      );
    }

    final List<double>? csVals = topDict[const CffDictOp(17)];
    if (csVals == null || csVals.isEmpty) {
      throw const TexMathFontError('CFF2 Top DICT missing CharStrings offset.');
    }
    final CffIndex charStrings = CffIndex.parse(
      reader,
      cffFiniteInt(csVals[0], 'CFF2.TopDICT.CharStrings'),
      isCff2: true,
      context: 'CFF2.CharStringsINDEX',
    );

    final List<double>? maxStackVals = topDict[const CffDictOp(25)];
    final int maxStack = (maxStackVals != null && maxStackVals.isNotEmpty)
        ? cffFiniteInt(
            maxStackVals[0],
            'CFF2.TopDICT.maxstack',
          ).clamp(513, 4096)
        : 513;

    final List<double>? fdArrayVals = topDict[const CffDictOp(12, 36)];
    if (fdArrayVals == null || fdArrayVals.isEmpty) {
      throw const TexMathFontError('CFF2 Top DICT missing FDArray.');
    }
    final CffIndex fdIndex = CffIndex.parse(
      reader,
      cffFiniteInt(fdArrayVals[0], 'CFF2.TopDICT.FDArray'),
      isCff2: true,
      context: 'CFF2.FDArray',
    );
    if (fdIndex.length == 0) {
      throw const TexMathFontError('CFF2 FDArray must not be empty.');
    }
    final List<_FontDictInfo> fontDicts = <_FontDictInfo>[];
    for (int i = 0; i < fdIndex.length; i++) {
      final Map<CffDictOp, List<double>> fd = parseCffDict(fdIndex[i]);
      fontDicts.add(
        _parseFontDict(reader, fd, isCff2: true, variationStore: varStore),
      );
    }

    final List<double>? fdSelectVals = topDict[const CffDictOp(12, 37)];
    final FdSelectTable fdSelect =
        (fdSelectVals != null && fdSelectVals.isNotEmpty)
        ? FdSelectTable.parse(
            reader,
            cffFiniteInt(fdSelectVals[0], 'CFF2.TopDICT.FDSelect'),
            charStrings.length,
          )
        : FdSelectTable.singleZero;

    return CffOutlineDecoder._(
      isCff2: true,
      unitsPerEm: unitsPerEm,
      charStrings: charStrings,
      globalSubrs: globalSubrs,
      fontDicts: fontDicts,
      fdSelect: fdSelect,
      variationStore: varStore,
      topFontMatrix: topDict[const CffDictOp(12, 7)],
      maxStack: maxStack,
    );
  }

  static _FontDictInfo _parseFontDict(
    FontByteReader cffReader,
    Map<CffDictOp, List<double>> dict, {
    required bool isCff2,
    ItemVariationStore? variationStore,
  }) {
    final List<double>? fontMatrix = dict[const CffDictOp(12, 7)];
    final List<double>? privVals = dict[const CffDictOp(18)];
    if (privVals == null || privVals.length < 2) {
      return _FontDictInfo(
        localSubrs: CffIndex.empty,
        defaultWidthX: 0.0,
        nominalWidthX: 0.0,
        vsindex: 0,
        hintContext: const HintingContext(),
        fontMatrix: fontMatrix,
      );
    }

    final int privSize = cffFiniteInt(privVals[0], 'CFF.Private.size');
    final int privOffset = cffFiniteInt(privVals[1], 'CFF.Private.offset');
    if (privSize < 0 || privOffset < 0) {
      throw TexMathFontError(
        'Invalid negative CFF Private DICT range ($privOffset, $privSize).',
      );
    }
    if (privSize == 0) {
      return _FontDictInfo(
        localSubrs: CffIndex.empty,
        defaultWidthX: 0.0,
        nominalWidthX: 0.0,
        vsindex: 0,
        hintContext: const HintingContext(),
        fontMatrix: fontMatrix,
      );
    }
    final FontByteReader privReader = cffReader.slice(
      privOffset,
      privSize,
      'CFF.PrivateDICT',
    );
    final Map<CffDictOp, List<double>> privDict = parseCffDict(
      privReader,
      variationStore: variationStore,
    );

    final double defaultWidthX =
        privDict[const CffDictOp(20)]?.firstOrNull ?? 0.0;
    final double nominalWidthX =
        privDict[const CffDictOp(21)]?.firstOrNull ?? 0.0;
    final double? vsRaw = privDict[const CffDictOp(22)]?.firstOrNull;
    final int vsindex = vsRaw == null
        ? 0
        : cffFiniteInt(vsRaw, 'CFF2.Private.vsindex');

    CffIndex localSubrs = CffIndex.empty;
    final List<double>? subrRel = privDict[const CffDictOp(19)];
    if (subrRel != null && subrRel.isNotEmpty) {
      final int absSubrOff =
          privOffset + cffFiniteInt(subrRel[0], 'CFF.Private.Subrs');
      localSubrs = CffIndex.parse(
        cffReader,
        absSubrOff,
        isCff2: isCff2,
        context: 'CFF.LocalSubrINDEX',
      );
    }

    final HintingContext hintCtx = HintingContext(
      blueValues: decodeDeltaArray(privDict[const CffDictOp(6)]),
      otherBlues: decodeDeltaArray(privDict[const CffDictOp(7)]),
      blueScale: privDict[const CffDictOp(12, 9)]?.firstOrNull ?? 0.039625,
      blueShift: privDict[const CffDictOp(12, 10)]?.firstOrNull ?? 7.0,
      blueFuzz: privDict[const CffDictOp(12, 11)]?.firstOrNull ?? 1.0,
      stdHw: privDict[const CffDictOp(10)]?.firstOrNull,
      stdVw: privDict[const CffDictOp(11)]?.firstOrNull,
    );

    return _FontDictInfo(
      localSubrs: localSubrs,
      defaultWidthX: defaultWidthX,
      nominalWidthX: nominalWidthX,
      vsindex: vsindex,
      hintContext: hintCtx,
      fontMatrix: fontMatrix,
    );
  }

  /// Decodes the unhinted outline and captured stem hints for [glyphId].
  DecodedCffOutline? decodeGlyph(int glyphId, double hmtxAdvanceWidth) {
    if (glyphId < 0 || glyphId >= _charStrings.length) {
      return null;
    }
    final int fdIndex = _fdSelect.fdForGlyph(glyphId);
    final _FontDictInfo fd = (fdIndex >= 0 && fdIndex < _fontDicts.length)
        ? _fontDicts[fdIndex]
        : _fontDicts[0];

    final Type2CharStringInterpreter interp = Type2CharStringInterpreter(
      globalSubrs: _globalSubrs,
      localSubrs: fd.localSubrs,
      isCff2: isCff2,
      defaultWidthX: fd.defaultWidthX,
      nominalWidthX: fd.nominalWidthX,
      variationStore: _variationStore,
      initialVsIndex: fd.vsindex,
      maxStack: _maxStack,
    );

    final DecodedCharString raw = interp.execute(_charStrings[glyphId]);
    List<PathCommand> commands = raw.commands;
    final List<double>? matrix = fd.fontMatrix ?? _topFontMatrix;
    if (matrix != null && matrix.length >= 6) {
      final double a = matrix[0] * unitsPerEm;
      final double b = matrix[1] * unitsPerEm;
      final double c = matrix[2] * unitsPerEm;
      final double d = matrix[3] * unitsPerEm;
      final double tx = matrix[4] * unitsPerEm;
      final double ty = matrix[5] * unitsPerEm;
      if (a != 1.0 ||
          b != 0.0 ||
          c != 0.0 ||
          d != 1.0 ||
          tx != 0.0 ||
          ty != 0.0) {
        commands = transformPathCommands(commands, a, b, c, d, tx, ty);
      }
    }

    return DecodedCffOutline(
      outline: GlyphOutline.cached(
        glyphId: glyphId,
        commands: commands,
        advanceWidth: hmtxAdvanceWidth > 0.0
            ? hmtxAdvanceWidth
            : (raw.width ?? 0.0),
      ),
      stems: raw.stems,
      hintContext: fd.hintContext,
    );
  }
}
