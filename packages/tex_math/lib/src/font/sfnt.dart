import 'dart:typed_data';

import '../error.dart';
import 'binary_reader.dart';
import 'metrics.dart';
import 'variation.dart';

/// Parsed SFNT container directory mapping 4-character table tags to bounded
/// [FontByteReader] slices.
final class SfntDirectory {
  SfntDirectory._(this.sfntTag, this.tables);

  /// SFNT magic header tag (`'OTTO'`, `'0x00010000'`, `'true'`, or `'typ1'`).
  final int sfntTag;

  /// Table readers keyed by 4-character ASCII SFNT tag.
  final Map<String, FontByteReader> tables;

  /// Returns the table reader for [tag], or `null` if absent.
  FontByteReader? operator [](String tag) => tables[tag];

  /// Returns the required table reader for [tag], throwing [TexMathFontError]
  /// if absent.
  FontByteReader requireTable(String tag) {
    final FontByteReader? table = tables[tag];
    if (table == null) {
      throw TexMathFontError('Missing required SFNT table "$tag".');
    }
    return table;
  }

  /// Validates and parses the SFNT offset table and directory records.
  factory SfntDirectory.parse(FontByteReader reader) {
    if (reader.length < 12) {
      throw const TexMathFontError(
        'Invalid SFNT header; expected at least 12 bytes.',
      );
    }
    final int tag = reader.readUint32(0, 'sfnt.tag');
    if (!_isSupportedSfntTag(tag)) {
      throw const TexMathFontError(
        'Invalid SFNT header; expected OTTO or TrueType magic bytes.',
      );
    }
    final int numTables = reader.readUint16(4, 'sfnt.numTables');
    if (numTables == 0) {
      throw const TexMathFontError('SFNT directory contains no tables.');
    }
    final int directoryBytes = 12 + numTables * 16;
    if (directoryBytes > reader.length) {
      throw TexMathFontError(
        'SFNT table directory truncated (needs $directoryBytes bytes, '
        'buffer has ${reader.length}).',
      );
    }

    final Map<String, FontByteReader> tables = <String, FontByteReader>{};
    for (int i = 0; i < numTables; i++) {
      final int entryOffset = 12 + i * 16;
      final String tableTag = reader.readTag(entryOffset, 'sfnt.tableTag');
      final int offset = reader.readUint32(entryOffset + 8, 'sfnt.tableOffset');
      final int length = reader.readUint32(entryOffset + 12, 'sfnt.tableLen');
      final FontByteReader slice = reader.slice(
        offset,
        length,
        'table "$tableTag"',
      );
      tables.putIfAbsent(tableTag, () => slice);
    }
    return SfntDirectory._(tag, tables);
  }

  static bool _isSupportedSfntTag(int tag) {
    return tag == 0x4F54544F || // 'OTTO'
        tag == 0x00010000 || // TrueType 1.0
        tag == 0x74727565 || // 'true'
        tag == 0x74797031; // 'typ1'
  }
}

/// Parsed `head` table metrics.
final class HeadTable {
  const HeadTable({
    required this.unitsPerEm,
    required this.boundingBox,
    required this.indexToLocFormat,
  });

  final int unitsPerEm;
  final FontBoundingBox boundingBox;
  final int indexToLocFormat;

  factory HeadTable.parse(FontByteReader reader) {
    if (reader.length < 54) {
      throw const TexMathFontError('Invalid head table (< 54 bytes).');
    }
    final int unitsPerEm = reader.readUint16(18, 'head.unitsPerEm');
    if (unitsPerEm < 16 || unitsPerEm > 16384) {
      throw TexMathFontError('Invalid head unitsPerEm: $unitsPerEm.');
    }
    final int xMin = reader.readInt16(36, 'head.xMin');
    final int yMin = reader.readInt16(38, 'head.yMin');
    final int xMax = reader.readInt16(40, 'head.xMax');
    final int yMax = reader.readInt16(42, 'head.yMax');
    final int indexToLocFormat = reader.readInt16(50, 'head.indexToLocFormat');
    return HeadTable(
      unitsPerEm: unitsPerEm,
      boundingBox: FontBoundingBox(
        xMin: xMin.toDouble(),
        yMin: yMin.toDouble(),
        xMax: xMax.toDouble(),
        yMax: yMax.toDouble(),
      ),
      indexToLocFormat: indexToLocFormat,
    );
  }
}

/// Parsed `maxp` table metrics.
final class MaxpTable {
  const MaxpTable({required this.numGlyphs});

  final int numGlyphs;

  factory MaxpTable.parse(FontByteReader reader) {
    if (reader.length < 6) {
      throw const TexMathFontError('Invalid maxp table (< 6 bytes).');
    }
    final int numGlyphs = reader.readUint16(4, 'maxp.numGlyphs');
    return MaxpTable(numGlyphs: numGlyphs);
  }
}

/// Parsed `hhea` table metrics.
final class HheaTable {
  const HheaTable({
    required this.ascender,
    required this.descender,
    required this.lineGap,
    required this.advanceWidthMax,
    required this.numberOfHMetrics,
  });

  final int ascender;
  final int descender;
  final int lineGap;
  final int advanceWidthMax;
  final int numberOfHMetrics;

  factory HheaTable.parse(FontByteReader reader, int numGlyphs) {
    if (reader.length < 36) {
      throw const TexMathFontError('Invalid hhea table (< 36 bytes).');
    }
    final int ascender = reader.readInt16(4, 'hhea.ascender');
    final int descender = reader.readInt16(6, 'hhea.descender');
    final int lineGap = reader.readInt16(8, 'hhea.lineGap');
    final int advanceWidthMax = reader.readUint16(10, 'hhea.advanceWidthMax');
    final int numberOfHMetrics = reader.readUint16(34, 'hhea.numberOfHMetrics');
    if (numGlyphs > 0 &&
        (numberOfHMetrics == 0 || numberOfHMetrics > numGlyphs)) {
      throw TexMathFontError(
        'Invalid hhea numberOfHMetrics $numberOfHMetrics for '
        'numGlyphs $numGlyphs.',
      );
    }
    return HheaTable(
      ascender: ascender,
      descender: descender,
      lineGap: lineGap,
      advanceWidthMax: advanceWidthMax,
      numberOfHMetrics: numberOfHMetrics,
    );
  }
}

/// Parsed `hmtx` horizontal glyph metrics array.
final class HmtxTable {
  HmtxTable._(this._advanceWidths, this._lsbs);

  final Uint16List _advanceWidths;
  final Int32List _lsbs;

  /// Number of glyph entries in this table.
  int get numGlyphs => _advanceWidths.length;

  /// Returns raw advance width for [glyphId], or `0` if out of range.
  int advanceWidthFor(int glyphId) {
    if (glyphId < 0 || glyphId >= _advanceWidths.length) {
      return 0;
    }
    return _advanceWidths[glyphId];
  }

  /// Returns raw left side bearing for [glyphId], or `0` if out of range.
  int lsbFor(int glyphId) {
    if (glyphId < 0 || glyphId >= _lsbs.length) {
      return 0;
    }
    return _lsbs[glyphId];
  }

  factory HmtxTable.parse(
    FontByteReader reader,
    int numGlyphs,
    int numberOfHMetrics,
  ) {
    if (numGlyphs == 0) {
      return HmtxTable._(Uint16List(0), Int32List(0));
    }
    final int extraLsbs = numGlyphs - numberOfHMetrics;
    final int requiredBytes = numberOfHMetrics * 4 + extraLsbs * 2;
    reader.checkRange(0, requiredBytes, 'hmtx.entries');

    final Uint16List advs = Uint16List(numGlyphs);
    final Int32List lsbs = Int32List(numGlyphs);

    int lastAdv = 0;
    if (extraLsbs >= 0) {
      for (int i = 0; i < numberOfHMetrics; i++) {
        final int pos = i * 4;
        lastAdv = reader.readUint16Fast(pos);
        advs[i] = lastAdv;
        lsbs[i] = reader.readInt16Fast(pos + 2);
      }
      final int lsbBase = numberOfHMetrics * 4;
      for (int i = 0; i < extraLsbs; i++) {
        final int gid = numberOfHMetrics + i;
        advs[gid] = lastAdv;
        lsbs[gid] = reader.readInt16Fast(lsbBase + i * 2);
      }
    } else {
      for (int i = 0; i < numberOfHMetrics; i++) {
        final int pos = i * 4;
        lastAdv = reader.readUint16(pos, 'hmtx.advanceWidth');
        advs[i] = lastAdv;
        lsbs[i] = reader.readInt16(pos + 2, 'hmtx.lsb');
      }
    }
    return HmtxTable._(advs, lsbs);
  }
}

/// Parsed optional `OS/2` metrics.
final class Os2Table {
  const Os2Table({
    this.typoAscender,
    this.typoDescender,
    this.xHeight,
    this.capHeight,
  });

  final int? typoAscender;
  final int? typoDescender;
  final int? xHeight;
  final int? capHeight;

  static Os2Table parseOptional(FontByteReader? reader) {
    if (reader == null) {
      return const Os2Table();
    }
    if (reader.length < 2) {
      throw const TexMathFontError('Truncated OS/2 table (< 2 bytes).');
    }
    final int version = reader.readUint16(0, 'OS/2.version');
    int? typoAsc;
    int? typoDesc;
    int? xHeight;
    int? capHeight;
    if (reader.length >= 72) {
      typoAsc = reader.readInt16(68, 'OS/2.sTypoAscender');
      typoDesc = reader.readInt16(70, 'OS/2.sTypoDescender');
    }
    if (version >= 2 && reader.length >= 90) {
      xHeight = reader.readInt16(86, 'OS/2.sxHeight');
      capHeight = reader.readInt16(88, 'OS/2.sCapHeight');
    }
    return Os2Table(
      typoAscender: typoAsc,
      typoDescender: typoDesc,
      xHeight: xHeight,
      capHeight: capHeight,
    );
  }
}

/// Parses font family name from the optional `name` table.
String parseFamilyName(FontByteReader? reader) {
  if (reader == null) {
    return 'Unknown';
  }
  if (reader.length < 6) {
    throw const TexMathFontError('Truncated name table (< 6 bytes).');
  }
  final int count = reader.readUint16(2, 'name.count');
  final int stringOffset = reader.readUint16(4, 'name.stringOffset');
  reader.checkRange(6, count * 12, 'name.records');

  String? decodeRecord(int pos) {
    final int pid = reader.readUint16(pos, 'name.platformID');
    final int length = reader.readUint16(pos + 8, 'name.length');
    final int off = reader.readUint16(pos + 10, 'name.offset');
    final int absOffset = stringOffset + off;
    if (length == 0) {
      return null;
    }
    if (pid == 3 || pid == 0) {
      return reader.readUtf16Be(absOffset, length, 'name.utf16');
    }
    final Uint8List raw = reader.viewBytes(absOffset, length, 'name.mac');
    return String.fromCharCodes(raw);
  }

  // Prefer nameID 1 (Font Family), then nameID 16 (Typographic Family), then 4.
  for (final int targetNameId in <int>[1, 16, 4]) {
    String? bestFallback;
    for (int i = 0; i < count; i++) {
      final int pos = 6 + i * 12;
      final int pid = reader.readUint16(pos, 'name.platformID');
      final int eid = reader.readUint16(pos + 2, 'name.encodingID');
      final int lid = reader.readUint16(pos + 4, 'name.languageID');
      final int nid = reader.readUint16(pos + 6, 'name.nameID');
      if (nid != targetNameId) {
        continue;
      }
      final String? decoded = decodeRecord(pos);
      if (decoded == null || decoded.isEmpty) {
        continue;
      }
      if (pid == 3 && (eid == 1 || eid == 10) && lid == 0x0409) {
        return decoded;
      }
      if (pid == 3 || pid == 0) {
        bestFallback ??= decoded;
      } else {
        bestFallback ??= decoded;
      }
    }
    if (bestFallback != null) {
      return bestFallback;
    }
  }
  return 'Unknown';
}

/// Parsed `cmap` Format 4 and Format 12 Unicode-to-glyph mapper.
final class CmapTable {
  const CmapTable._(this._format12, this._format4, this._asciiGlyphs);

  /// Empty `cmap` returning `0` for all code points.
  static const CmapTable empty = CmapTable._(null, null, null);

  final _CmapFormat12? _format12;
  final _CmapFormat4? _format4;
  final Uint32List? _asciiGlyphs;

  /// Maps Unicode scalar [codePoint] to OpenType glyph ID, or `0` if unmapped.
  int glyphIdForCodePoint(int codePoint) {
    if (codePoint < 0 || codePoint > 0x10FFFF) {
      return 0;
    }
    final Uint32List? ascii = _asciiGlyphs;
    if (ascii != null && codePoint < 128) {
      return ascii[codePoint];
    }
    return _lookupUncached(codePoint);
  }

  int _lookupUncached(int codePoint) {
    final _CmapFormat12? f12 = _format12;
    if (f12 != null) {
      final int gid = f12.lookup(codePoint);
      if (gid != 0) {
        return gid;
      }
    }
    final _CmapFormat4? f4 = _format4;
    if (f4 != null && codePoint <= 0xFFFF) {
      return f4.lookup(codePoint);
    }
    return 0;
  }

  /// Parses an optional `cmap` table supporting Format 4 and Format 12.
  static CmapTable parseOptional(FontByteReader? reader, int numGlyphs) {
    if (reader == null) {
      return empty;
    }
    if (reader.length < 4) {
      throw const TexMathFontError('Truncated cmap table (< 4 bytes).');
    }
    final int numTables = reader.readUint16(2, 'cmap.numTables');
    reader.checkRange(4, numTables * 8, 'cmap.encodingRecords');

    int bestFmt12Offset = -1;
    int bestFmt12Score = -1;
    int bestFmt4Offset = -1;
    int bestFmt4Score = -1;

    for (int i = 0; i < numTables; i++) {
      final int recPos = 4 + i * 8;
      final int pid = reader.readUint16(recPos, 'cmap.platformID');
      final int eid = reader.readUint16(recPos + 2, 'cmap.encodingID');
      final int subOff = reader.readUint32(recPos + 4, 'cmap.offset');
      final int format = reader.readUint16(subOff, 'cmap.subtable.format');

      if (format == 12) {
        final int score = (pid == 3 && eid == 10)
            ? 3
            : (pid == 0 && eid == 4)
            ? 2
            : 1;
        if (score > bestFmt12Score) {
          bestFmt12Score = score;
          bestFmt12Offset = subOff;
        }
      } else if (format == 4) {
        final int score = (pid == 3 && eid == 1)
            ? 3
            : (pid == 0 && eid == 3)
            ? 2
            : 1;
        if (score > bestFmt4Score) {
          bestFmt4Score = score;
          bestFmt4Offset = subOff;
        }
      }
    }

    final _CmapFormat12? f12 = bestFmt12Offset >= 0
        ? _CmapFormat12.parse(reader, bestFmt12Offset, numGlyphs)
        : null;
    final _CmapFormat4? f4 = bestFmt4Offset >= 0
        ? _CmapFormat4.parse(reader, bestFmt4Offset, numGlyphs)
        : null;
    if (f12 == null && f4 == null) {
      return empty;
    }
    final CmapTable uncached = CmapTable._(f12, f4, null);
    final Uint32List ascii = Uint32List(128);
    for (int cp = 0; cp < 128; cp++) {
      ascii[cp] = uncached._lookupUncached(cp);
    }
    return CmapTable._(f12, f4, ascii);
  }
}

final class _CmapFormat4 {
  _CmapFormat4({
    required this.reader,
    required this.subtableOffset,
    required this.segCount,
    required this.endCodes,
    required this.startCodes,
    required this.idDeltas,
    required this.idRangeOffsets,
    required this.idRangeOffsetBase,
    required this.numGlyphs,
  });

  final FontByteReader reader;
  final int subtableOffset;
  final int segCount;
  final Uint16List endCodes;
  final Uint16List startCodes;
  final Int16List idDeltas;
  final Uint16List idRangeOffsets;
  final int idRangeOffsetBase;
  final int numGlyphs;

  static _CmapFormat4 parse(FontByteReader reader, int offset, int numGlyphs) {
    final int length = reader.readUint16(offset + 2, 'cmap4.length');
    reader.checkRange(offset, length, 'cmap4.subtable');
    if (length < 16) {
      throw const TexMathFontError('Invalid cmap Format 4 length.');
    }
    final int segCountX2 = reader.readUint16(offset + 6, 'cmap4.segCountX2');
    if (segCountX2 == 0 || (segCountX2 & 1) != 0) {
      throw TexMathFontError('Invalid cmap Format 4 segCountX2: $segCountX2.');
    }
    final int segCount = segCountX2 >> 1;
    final int minLen = 16 + segCount * 8;
    if (length < minLen || offset + minLen > reader.length) {
      throw const TexMathFontError('Truncated cmap Format 4 segments.');
    }

    final int endBase = offset + 14;
    final int startBase = endBase + segCountX2 + 2;
    final int deltaBase = startBase + segCountX2;
    final int rangeBase = deltaBase + segCountX2;

    final Uint16List endCodes = Uint16List(segCount);
    final Uint16List startCodes = Uint16List(segCount);
    final Int16List idDeltas = Int16List(segCount);
    final Uint16List idRangeOffsets = Uint16List(segCount);

    for (int i = 0; i < segCount; i++) {
      final int pos = i * 2;
      endCodes[i] = reader.readUint16Fast(endBase + pos);
      startCodes[i] = reader.readUint16Fast(startBase + pos);
      idDeltas[i] = reader.readInt16Fast(deltaBase + pos);
      idRangeOffsets[i] = reader.readUint16Fast(rangeBase + pos);
    }

    return _CmapFormat4(
      reader: reader,
      subtableOffset: offset,
      segCount: segCount,
      endCodes: endCodes,
      startCodes: startCodes,
      idDeltas: idDeltas,
      idRangeOffsets: idRangeOffsets,
      idRangeOffsetBase: rangeBase,
      numGlyphs: numGlyphs,
    );
  }

  int lookup(int codePoint) {
    int low = 0;
    int high = segCount - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final int endCode = endCodes[mid];
      if (codePoint > endCode) {
        low = mid + 1;
      } else if (codePoint < startCodes[mid]) {
        high = mid - 1;
      } else {
        final int rangeOff = idRangeOffsets[mid];
        int gid;
        if (rangeOff == 0) {
          gid = (codePoint + idDeltas[mid]) & 0xFFFF;
        } else {
          final int fieldPos = idRangeOffsetBase + mid * 2;
          final int glyphOff =
              fieldPos + rangeOff + 2 * (codePoint - startCodes[mid]);
          if (glyphOff < 0 || glyphOff + 2 > reader.length) {
            return 0;
          }
          gid = reader.readUint16Fast(glyphOff);
          if (gid != 0) {
            gid = (gid + idDeltas[mid]) & 0xFFFF;
          }
        }
        return (numGlyphs == 0 || gid < numGlyphs) ? gid : 0;
      }
    }
    return 0;
  }
}

final class _CmapFormat12 {
  _CmapFormat12({
    required this.starts,
    required this.ends,
    required this.startGlyphs,
    required this.numGlyphs,
  });

  final Uint32List starts;
  final Uint32List ends;
  final Uint32List startGlyphs;
  final int numGlyphs;

  static _CmapFormat12 parse(FontByteReader reader, int offset, int numGlyphs) {
    reader.checkRange(offset, 16, 'cmap12.header');
    final int length = reader.readUint32(offset + 4, 'cmap12.length');
    reader.checkRange(offset, length, 'cmap12.subtable');
    final int numGroups = reader.readUint32(offset + 12, 'cmap12.numGroups');
    reader.checkRange(offset + 16, numGroups * 12, 'cmap12.groups');

    final Uint32List starts = Uint32List(numGroups);
    final Uint32List ends = Uint32List(numGroups);
    final Uint32List startGlyphs = Uint32List(numGroups);

    for (int i = 0; i < numGroups; i++) {
      final int pos = offset + 16 + i * 12;
      starts[i] = reader.readUint32Fast(pos);
      ends[i] = reader.readUint32Fast(pos + 4);
      startGlyphs[i] = reader.readUint32Fast(pos + 8);
    }

    return _CmapFormat12(
      starts: starts,
      ends: ends,
      startGlyphs: startGlyphs,
      numGlyphs: numGlyphs,
    );
  }

  int lookup(int codePoint) {
    int low = 0;
    int high = starts.length - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final int start = starts[mid];
      final int end = ends[mid];
      if (codePoint < start) {
        high = mid - 1;
      } else if (codePoint > end) {
        low = mid + 1;
      } else {
        final int gid = startGlyphs[mid] + (codePoint - start);
        return (numGlyphs == 0 || gid < numGlyphs) ? gid : 0;
      }
    }
    return 0;
  }
}

/// Parsed `GSUB` `ssty` feature lookups (`LookupType 1` & `LookupType 3`).
final class GsubSstyTable {
  const GsubSstyTable._(this._alternates, this._singleSubstMaps);

  /// Empty table with no script variant substitutions.
  static const GsubSstyTable empty = GsubSstyTable._(
    <int, List<int>>{},
    <Map<int, int>>[],
  );

  final Map<int, List<int>> _alternates;
  final List<Map<int, int>> _singleSubstMaps;

  /// Returns the `ssty` script variant glyph ID for [glyphId] at [level]
  /// (`0` = script, `1` = scriptscript), or `null` if none exists.
  int? scriptVariantGlyph(int glyphId, int level) {
    if (level < 0 || glyphId < 0) {
      return null;
    }
    final List<int>? alts = _alternates[glyphId];
    if (alts != null && level < alts.length) {
      return alts[level];
    }
    if (_singleSubstMaps.isEmpty) {
      return null;
    }
    if (level == 0) {
      for (final Map<int, int> map in _singleSubstMaps) {
        final int? sub = map[glyphId];
        if (sub != null) {
          return sub;
        }
      }
      return null;
    }
    if (level == 1) {
      // Support chained single substitution (`g -> g1 -> g2`) or a second
      // `SingleSubst` lookup dedicated to scriptscript.
      final int? first = scriptVariantGlyph(glyphId, 0);
      if (first != null) {
        for (final Map<int, int> map in _singleSubstMaps) {
          final int? second = map[first];
          if (second != null && second != first) {
            return second;
          }
        }
      }
      if (_singleSubstMaps.length > 1) {
        final int? direct = _singleSubstMaps[1][glyphId];
        if (direct != null) {
          return direct;
        }
      }
    }
    return null;
  }

  /// Parses `ssty` feature lookups from an optional `GSUB` table.
  static GsubSstyTable parseOptional(FontByteReader? reader) {
    if (reader == null) {
      return empty;
    }
    if (reader.length < 10) {
      throw const TexMathFontError('Truncated GSUB table (< 10 bytes).');
    }
    final int scriptListOffset = reader.readUint16(4, 'GSUB.scriptListOffset');
    final int featureListOffset = reader.readUint16(
      6,
      'GSUB.featureListOffset',
    );
    final int lookupListOffset = reader.readUint16(8, 'GSUB.lookupListOffset');

    final List<int> sstyFeatureIndices = _findSstyFeatureIndices(
      reader,
      scriptListOffset,
      featureListOffset,
    );
    if (sstyFeatureIndices.isEmpty) {
      return empty;
    }

    final int featureCount = reader.readUint16(
      featureListOffset,
      'GSUB.featureCount',
    );
    final Set<int> lookupIndices = <int>{};
    for (final int fIdx in sstyFeatureIndices) {
      if (fIdx >= featureCount) {
        continue;
      }
      final int fRecOff = featureListOffset + 2 + fIdx * 6;
      final int fOff = reader.readUint16(fRecOff + 4, 'GSUB.featureOffset');
      final int fBase = featureListOffset + fOff;
      final int lCount = reader.readUint16(fBase + 2, 'GSUB.lookupIndexCount');
      reader.checkRange(fBase + 4, lCount * 2, 'GSUB.featureLookups');
      for (int i = 0; i < lCount; i++) {
        lookupIndices.add(
          reader.readUint16(fBase + 4 + i * 2, 'GSUB.lookupListIndex'),
        );
      }
    }

    if (lookupIndices.isEmpty) {
      return empty;
    }

    final int totalLookups = reader.readUint16(
      lookupListOffset,
      'GSUB.lookupCount',
    );
    reader.checkRange(lookupListOffset + 2, totalLookups * 2, 'GSUB.lookups');

    final Map<int, List<int>> alternates = <int, List<int>>{};
    final List<Map<int, int>> singleSubstMaps = <Map<int, int>>[];

    final List<int> sortedLookups = lookupIndices.toList()..sort();
    for (final int lookupIdx in sortedLookups) {
      if (lookupIdx >= totalLookups) {
        continue;
      }
      final int lRel = reader.readUint16(
        lookupListOffset + 2 + lookupIdx * 2,
        'GSUB.lookupOffset',
      );
      final int lBase = lookupListOffset + lRel;
      final int lookupType = reader.readUint16(lBase, 'GSUB.lookupType');
      final int subCount = reader.readUint16(lBase + 4, 'GSUB.subTableCount');
      reader.checkRange(lBase + 6, subCount * 2, 'GSUB.subTableOffsets');

      Map<int, int>? singleMap;
      for (int s = 0; s < subCount; s++) {
        final int subRel = reader.readUint16(
          lBase + 6 + s * 2,
          'GSUB.subtableOffset',
        );
        int subOff = lBase + subRel;
        int effType = lookupType;
        if (effType == 7) {
          final int extFmt = reader.readUint16(subOff, 'GSUB.ext.format');
          if (extFmt != 1) {
            continue;
          }
          effType = reader.readUint16(subOff + 2, 'GSUB.ext.lookupType');
          final int extOff = reader.readUint32(subOff + 4, 'GSUB.ext.offset');
          subOff += extOff;
        }

        if (effType == 1) {
          _parseSingleSubst(reader, subOff, singleMap ??= <int, int>{});
        } else if (effType == 3) {
          _parseAlternateSubst(reader, subOff, alternates);
        }
      }
      if (singleMap != null && singleMap.isNotEmpty) {
        singleSubstMaps.add(singleMap);
      }
    }

    return GsubSstyTable._(alternates, singleSubstMaps);
  }

  static const int _sstyTag32 = 0x73737479; // 'ssty'
  static const int _mathTag32 = 0x6D617468; // 'math'
  static const int _dfltTag32 = 0x44464C54; // 'DFLT'

  static List<int> _findSstyFeatureIndices(
    FontByteReader reader,
    int scriptListOffset,
    int featureListOffset,
  ) {
    final int featureCount = reader.readUint16(
      featureListOffset,
      'GSUB.featureCount',
    );
    reader.checkRange(
      featureListOffset + 2,
      featureCount * 6,
      'GSUB.featureRecords',
    );

    bool isSstyFeature(int featureIdx) {
      if (featureIdx < 0 || featureIdx >= featureCount) {
        return false;
      }
      return reader.readUint32Fast(featureListOffset + 2 + featureIdx * 6) ==
          _sstyTag32;
    }

    List<int> collectForScript(int targetTag32) {
      final int scriptCount = reader.readUint16(
        scriptListOffset,
        'GSUB.scriptCount',
      );
      reader.checkRange(
        scriptListOffset + 2,
        scriptCount * 6,
        'GSUB.scriptRecords',
      );
      for (int i = 0; i < scriptCount; i++) {
        final int rec = scriptListOffset + 2 + i * 6;
        if (reader.readUint32Fast(rec) != targetTag32) {
          continue;
        }
        final int sBase = scriptListOffset + reader.readUint16Fast(rec + 4);
        final int dfltOff = reader.readUint16(sBase, 'GSUB.defaultLangSysOff');
        if (dfltOff == 0) {
          continue;
        }
        final int langBase = sBase + dfltOff;
        final int fCount = reader.readUint16(langBase + 4, 'GSUB.langFeatCnt');
        reader.checkRange(langBase + 6, fCount * 2, 'GSUB.langFeatures');
        final List<int> found = <int>[];
        for (int j = 0; j < fCount; j++) {
          final int idx = reader.readUint16Fast(langBase + 6 + j * 2);
          if (isSstyFeature(idx)) {
            found.add(idx);
          }
        }
        if (found.isNotEmpty) {
          return found;
        }
      }
      return const <int>[];
    }

    final List<int> mathFeatures = collectForScript(_mathTag32);
    if (mathFeatures.isNotEmpty) {
      return mathFeatures;
    }
    final List<int> dfltFeatures = collectForScript(_dfltTag32);
    if (dfltFeatures.isNotEmpty) {
      return dfltFeatures;
    }

    final List<int> fallback = <int>[];
    for (int i = 0; i < featureCount; i++) {
      if (isSstyFeature(i)) {
        fallback.add(i);
      }
    }
    return fallback;
  }

  static void _parseSingleSubst(
    FontByteReader reader,
    int subOff,
    Map<int, int> out,
  ) {
    final int fmt = reader.readUint16(subOff, 'GSUB.SingleSubst.format');
    final int covOff = reader.readUint16(
      subOff + 2,
      'GSUB.SingleSubst.coverage',
    );
    final CoverageTable cov = CoverageTable.parse(
      reader,
      subOff + covOff,
      'GSUB.SingleSubst.Coverage',
    );
    final List<int> glyphs = cov.toGlyphList();
    if (fmt == 1) {
      final int delta = reader.readInt16(
        subOff + 4,
        'GSUB.SingleSubst.deltaGlyphID',
      );
      for (final int gid in glyphs) {
        out[gid] = (gid + delta) & 0xFFFF;
      }
    } else if (fmt == 2) {
      final int glyphCount = reader.readUint16(
        subOff + 4,
        'GSUB.SingleSubst.glyphCount',
      );
      reader.checkRange(
        subOff + 6,
        glyphCount * 2,
        'GSUB.SingleSubst.substituteGlyphIDs',
      );
      final int n = glyphs.length < glyphCount ? glyphs.length : glyphCount;
      for (int i = 0; i < n; i++) {
        out[glyphs[i]] = reader.readUint16Fast(subOff + 6 + i * 2);
      }
    }
  }

  static void _parseAlternateSubst(
    FontByteReader reader,
    int subOff,
    Map<int, List<int>> out,
  ) {
    final int fmt = reader.readUint16(subOff, 'GSUB.AlternateSubst.format');
    if (fmt != 1) {
      return;
    }
    final int covOff = reader.readUint16(
      subOff + 2,
      'GSUB.AlternateSubst.coverage',
    );
    final int altSetCount = reader.readUint16(
      subOff + 4,
      'GSUB.AlternateSubst.alternateSetCount',
    );
    reader.checkRange(
      subOff + 6,
      altSetCount * 2,
      'GSUB.AlternateSubst.alternateSetOffsets',
    );

    final CoverageTable cov = CoverageTable.parse(
      reader,
      subOff + covOff,
      'GSUB.AlternateSubst.Coverage',
    );
    final List<int> glyphs = cov.toGlyphList();
    final int n = glyphs.length < altSetCount ? glyphs.length : altSetCount;
    for (int i = 0; i < n; i++) {
      final int altSetOff = subOff + reader.readUint16Fast(subOff + 6 + i * 2);
      final int count = reader.readUint16(altSetOff, 'GSUB.AlternateSet.count');
      reader.checkRange(altSetOff + 2, count * 2, 'GSUB.AlternateSet.glyphIDs');
      final Uint16List alts = Uint16List(count);
      for (int j = 0; j < count; j++) {
        alts[j] = reader.readUint16Fast(altSetOff + 2 + j * 2);
      }
      out.putIfAbsent(glyphs[i], () => alts);
    }
  }
}

/// Extracts optional `ItemVariationStore` from `GDEF` v1.3+.
ItemVariationStore? parseGdefVariationStore(
  FontByteReader? reader,
  List<double> normalizedCoords,
) {
  if (reader == null || reader.length < 12) {
    return null;
  }
  final int major = reader.readUint16(0, 'GDEF.majorVersion');
  final int minor = reader.readUint16(2, 'GDEF.minorVersion');
  if (major != 1 || minor < 3 || reader.length < 18) {
    return null;
  }
  final int varStoreOffset = reader.readUint32(
    14,
    'GDEF.itemVariationStoreOffset',
  );
  if (varStoreOffset == 0) {
    return null;
  }
  return ItemVariationStore.parse(reader, varStoreOffset, normalizedCoords);
}
