import 'dart:math' as math;

import '../error.dart';
import 'binary_reader.dart';
import 'metrics.dart';

/// Parsed `fvar` and optional `avar` coordinate normalizer.
final class VariationSpace {
  const VariationSpace({
    required this.axes,
    required this.normalizedCoords,
    required this.resolvedUserCoords,
  });

  /// Empty non-variable space.
  static const VariationSpace empty = VariationSpace(
    axes: <FontVariationAxis>[],
    normalizedCoords: <double>[],
    resolvedUserCoords: <String, double>{},
  );

  /// Axes declared by `fvar`.
  final List<FontVariationAxis> axes;

  /// Normalized coordinates in `[-1.0, 1.0]` aligned to [axes].
  final List<double> normalizedCoords;

  /// Clamped user-space coordinates keyed by axis tag.
  final Map<String, double> resolvedUserCoords;

  /// Parses `fvar` (and optional `avar`) and normalizes [userAxes].
  factory VariationSpace.parse({
    required FontByteReader? fvarReader,
    required FontByteReader? avarReader,
    required Map<String, double> userAxes,
  }) {
    if (fvarReader == null) {
      return VariationSpace.empty;
    }
    final int majorVersion = fvarReader.readUint16(0, 'fvar.majorVersion');
    final int minorVersion = fvarReader.readUint16(2, 'fvar.minorVersion');
    if (majorVersion != 1 || minorVersion != 0) {
      throw TexMathFontError(
        'Unsupported fvar version $majorVersion.$minorVersion.',
      );
    }
    final int axesArrayOffset = fvarReader.readUint16(
      4,
      'fvar.axesArrayOffset',
    );
    final int axisCount = fvarReader.readUint16(8, 'fvar.axisCount');
    final int axisSize = fvarReader.readUint16(10, 'fvar.axisSize');
    if (axisSize < 20) {
      throw TexMathFontError('Invalid fvar axisSize $axisSize (< 20).');
    }
    fvarReader.checkRange(
      axesArrayOffset,
      axisCount * axisSize,
      'fvar.axisRecords',
    );

    final List<FontVariationAxis> axes = <FontVariationAxis>[];
    final List<double> normalized = List<double>.filled(axisCount, 0.0);
    final Map<String, double> resolved = <String, double>{};

    for (int i = 0; i < axisCount; i++) {
      final int pos = axesArrayOffset + i * axisSize;
      final String tag = fvarReader.readTag(pos, 'fvar.axisTag');
      final double minValue = fvarReader.readFixed(pos + 4, 'fvar.minValue');
      final double defaultValue = fvarReader.readFixed(
        pos + 8,
        'fvar.defaultValue',
      );
      final double maxValue = fvarReader.readFixed(pos + 12, 'fvar.maxValue');
      final int flags = fvarReader.readUint16(pos + 16, 'fvar.flags');
      final int axisNameId = fvarReader.readUint16(pos + 18, 'fvar.axisNameID');

      final FontVariationAxis axis = FontVariationAxis(
        tag: tag,
        minValue: minValue,
        defaultValue: defaultValue,
        maxValue: maxValue,
        flags: flags,
        axisNameId: axisNameId,
      );
      axes.add(axis);

      final double requested = userAxes[tag] ?? defaultValue;
      final double clamped = requested.isFinite
          ? requested.clamp(minValue, maxValue).toDouble()
          : defaultValue;
      resolved[tag] = clamped;
      normalized[i] = _normalizeAxisLinear(clamped, axis);
    }

    if (avarReader != null && axisCount > 0) {
      _applyAvar(avarReader, normalized);
    }

    return VariationSpace(
      axes: List<FontVariationAxis>.unmodifiable(axes),
      normalizedCoords: List<double>.unmodifiable(normalized),
      resolvedUserCoords: Map<String, double>.unmodifiable(resolved),
    );
  }

  static double _normalizeAxisLinear(double value, FontVariationAxis axis) {
    if (value < axis.defaultValue) {
      final double span = axis.defaultValue - axis.minValue;
      return span > 0.0 ? (value - axis.defaultValue) / span : 0.0;
    }
    if (value > axis.defaultValue) {
      final double span = axis.maxValue - axis.defaultValue;
      return span > 0.0 ? (value - axis.defaultValue) / span : 0.0;
    }
    return 0.0;
  }

  static void _applyAvar(FontByteReader avar, List<double> normalized) {
    final int majorVersion = avar.readUint16(0, 'avar.majorVersion');
    final int minorVersion = avar.readUint16(2, 'avar.minorVersion');
    if (majorVersion != 1 || minorVersion != 0) {
      throw TexMathFontError(
        'Unsupported avar version $majorVersion.$minorVersion.',
      );
    }
    final int axisCount = avar.readUint16(6, 'avar.axisCount');
    if (axisCount != normalized.length) {
      throw TexMathFontError(
        'avar axisCount ($axisCount) does not match fvar (${normalized.length}).',
      );
    }
    int offset = 8;
    for (int i = 0; i < axisCount; i++) {
      final int pairCount = avar.readUint16(offset, 'avar.positionMapCount');
      offset += 2;
      avar.checkRange(offset, pairCount * 4, 'avar.axisValueMaps');
      if (pairCount >= 2) {
        final List<double> fromCoords = List<double>.filled(pairCount, 0.0);
        final List<double> toCoords = List<double>.filled(pairCount, 0.0);
        for (int j = 0; j < pairCount; j++) {
          fromCoords[j] = avar.readF2Dot14(offset + j * 4, 'avar.fromCoord');
          toCoords[j] = avar.readF2Dot14(offset + j * 4 + 2, 'avar.toCoord');
        }
        normalized[i] = _remapSegment(normalized[i], fromCoords, toCoords);
      }
      offset += pairCount * 4;
    }
  }

  static double _remapSegment(
    double coord,
    List<double> fromCoords,
    List<double> toCoords,
  ) {
    if (coord <= fromCoords.first) {
      return toCoords.first;
    }
    if (coord >= fromCoords.last) {
      return toCoords.last;
    }
    for (int i = 0; i < fromCoords.length - 1; i++) {
      final double f0 = fromCoords[i];
      final double f1 = fromCoords[i + 1];
      if (coord >= f0 && coord <= f1) {
        final double t0 = toCoords[i];
        final double t1 = toCoords[i + 1];
        if (f1 == f0) {
          return t1;
        }
        return t0 + (t1 - t0) * ((coord - f0) / (f1 - f0));
      }
    }
    return coord;
  }
}

/// Region axis coordinates `(start, peak, end)` in normalized `[-1, 1]` space.
final class _RegionAxis {
  const _RegionAxis(this.start, this.peak, this.end);

  final double start;
  final double peak;
  final double end;

  double scalarFor(double coord) {
    if (peak == 0.0) {
      return 1.0;
    }
    if (start > peak || peak > end || (start < 0.0 && end > 0.0)) {
      return 0.0;
    }
    if (coord < start || coord > end) {
      return 0.0;
    }
    if (coord == peak) {
      return 1.0;
    }
    if (coord < peak) {
      return (coord - start) / (peak - start);
    }
    return (end - coord) / (end - peak);
  }
}

/// Parsed OpenType `ItemVariationData` subtable.
final class ItemVariationDataTable {
  const ItemVariationDataTable({
    required this.itemCount,
    required this.regionIndexes,
    required this.deltas,
  });

  final int itemCount;
  final List<int> regionIndexes;
  final List<List<int>> deltas;

  int get regionCount => regionIndexes.length;
}

/// OpenType `ItemVariationStore` evaluating variation scalars and deltas.
final class ItemVariationStore {
  ItemVariationStore._({
    required this.regionScalars,
    required this.variationData,
    required this._dataRegionScalars,
  });

  /// Precomputed scalar for each region in `VarRegionList`.
  final List<double> regionScalars;

  /// Parsed `ItemVariationData` tables (null entry if offset was `0`).
  final List<ItemVariationDataTable?> variationData;

  final Map<int, List<double>> _dataRegionScalars;

  /// Parses an `ItemVariationStore` starting at [offset] in [reader].
  factory ItemVariationStore.parse(
    FontByteReader reader,
    int offset,
    List<double> normalizedCoords, {
    bool readDeltaSets = true,
  }) {
    final FontByteReader store = reader.slice(
      offset,
      reader.length - offset,
      'ItemVariationStore',
    );
    final int format = store.readUint16(0, 'ItemVariationStore.format');
    if (format != 1) {
      throw TexMathFontError('Unsupported ItemVariationStore format: $format.');
    }
    final int regionListOffset = store.readUint32(
      2,
      'ItemVariationStore.variationRegionListOffset',
    );
    final int dataCount = store.readUint16(
      6,
      'ItemVariationStore.itemVariationDataCount',
    );
    store.checkRange(8, dataCount * 4, 'ItemVariationStore.dataOffsets');

    // Parse VarRegionList
    final int axisCount = store.readUint16(
      regionListOffset,
      'VarRegionList.axisCount',
    );
    final int regionCount = store.readUint16(
      regionListOffset + 2,
      'VarRegionList.regionCount',
    );
    store.checkRange(
      regionListOffset + 4,
      regionCount * axisCount * 6,
      'VarRegionList.regions',
    );

    final List<double> scalars = List<double>.filled(regionCount, 0.0);
    for (int r = 0; r < regionCount; r++) {
      double scalar = 1.0;
      final int regBase = regionListOffset + 4 + r * axisCount * 6;
      for (int a = 0; a < axisCount; a++) {
        final int axisPos = regBase + a * 6;
        final double start = store.readF2Dot14(axisPos, 'VarRegion.startCoord');
        final double peak = store.readF2Dot14(
          axisPos + 2,
          'VarRegion.peakCoord',
        );
        final double end = store.readF2Dot14(axisPos + 4, 'VarRegion.endCoord');
        final double coord = a < normalizedCoords.length
            ? normalizedCoords[a]
            : 0.0;
        scalar *= _RegionAxis(start, peak, end).scalarFor(coord);
        if (scalar == 0.0) {
          break;
        }
      }
      scalars[r] = scalar;
    }

    // Parse ItemVariationData tables with offset deduplication and entry budget.
    const int maxTotalVariationDeltas = 2000000;
    int totalVariationDeltas = 0;
    final List<ItemVariationDataTable?> dataTables =
        List<ItemVariationDataTable?>.filled(dataCount, null);
    final Map<int, List<double>> cachedDataScalars = <int, List<double>>{};
    final Map<int, ({ItemVariationDataTable table, List<double> scalars})>
    parsedByOffset =
        <int, ({ItemVariationDataTable table, List<double> scalars})>{};

    for (int d = 0; d < dataCount; d++) {
      final int dataOffset = store.readUint32(
        8 + d * 4,
        'ItemVariationStore.dataOffset',
      );
      if (dataOffset == 0) {
        continue;
      }
      final ({ItemVariationDataTable table, List<double> scalars})? cached =
          parsedByOffset[dataOffset];
      if (cached != null) {
        dataTables[d] = cached.table;
        cachedDataScalars[d] = cached.scalars;
        continue;
      }
      final int itemCount = store.readUint16(
        dataOffset,
        'ItemVariationData.itemCount',
      );
      final int wordDeltaField = store.readUint16(
        dataOffset + 2,
        'ItemVariationData.wordDeltaCount',
      );
      final bool isLongWords = (wordDeltaField & 0x8000) != 0;
      final int wordDeltaCount = wordDeltaField & 0x7FFF;
      final int regionIndexCount = store.readUint16(
        dataOffset + 4,
        'ItemVariationData.regionIndexCount',
      );
      if (wordDeltaCount > regionIndexCount) {
        throw TexMathFontError(
          'ItemVariationData wordDeltaCount ($wordDeltaCount) exceeds '
          'regionIndexCount ($regionIndexCount).',
        );
      }
      store.checkRange(
        dataOffset + 6,
        regionIndexCount * 2,
        'ItemVariationData.regionIndexes',
      );
      final List<int> regIndexes = List<int>.filled(regionIndexCount, 0);
      final List<double> subScalars = List<double>.filled(
        regionIndexCount,
        0.0,
      );
      for (int i = 0; i < regionIndexCount; i++) {
        final int regIdx = store.readUint16(
          dataOffset + 6 + i * 2,
          'ItemVariationData.regionIndex',
        );
        if (regIdx >= regionCount) {
          throw TexMathFontError(
            'ItemVariationData regionIndex $regIdx out of bounds ($regionCount).',
          );
        }
        regIndexes[i] = regIdx;
        subScalars[i] = scalars[regIdx];
      }

      final int longWordSize = isLongWords ? 4 : 2;
      final int shortWordSize = isLongWords ? 2 : 1;
      final int rowBytes =
          wordDeltaCount * longWordSize +
          (regionIndexCount - wordDeltaCount) * shortWordSize;
      int deltaOffset = dataOffset + 6 + regionIndexCount * 2;
      List<List<int>> rows = const <List<int>>[];
      if (readDeltaSets && itemCount > 0 && regionIndexCount > 0) {
        final int entryCount = itemCount * regionIndexCount;
        totalVariationDeltas += entryCount;
        if (totalVariationDeltas > maxTotalVariationDeltas) {
          throw TexMathFontError(
            'ItemVariationStore decoded delta count ($totalVariationDeltas) '
            'exceeds limit ($maxTotalVariationDeltas).',
          );
        }
        store.checkRange(
          deltaOffset,
          itemCount * rowBytes,
          'ItemVariationData.deltaSets',
        );
        rows = <List<int>>[];
        for (int item = 0; item < itemCount; item++) {
          final List<int> row = List<int>.filled(regionIndexCount, 0);
          int colOff = deltaOffset;
          for (int col = 0; col < regionIndexCount; col++) {
            if (col < wordDeltaCount) {
              if (isLongWords) {
                row[col] = store.readInt32(colOff, 'deltaSet.int32');
                colOff += 4;
              } else {
                row[col] = store.readInt16(colOff, 'deltaSet.int16');
                colOff += 2;
              }
            } else {
              if (isLongWords) {
                row[col] = store.readInt16(colOff, 'deltaSet.int16');
                colOff += 2;
              } else {
                row[col] = store.readInt8(colOff, 'deltaSet.int8');
                colOff += 1;
              }
            }
          }
          rows.add(row);
          deltaOffset += rowBytes;
        }
      }
      final ItemVariationDataTable table = ItemVariationDataTable(
        itemCount: itemCount,
        regionIndexes: List<int>.unmodifiable(regIndexes),
        deltas: rows,
      );
      final List<double> unmodScalars = List<double>.unmodifiable(subScalars);
      parsedByOffset[dataOffset] = (table: table, scalars: unmodScalars);
      dataTables[d] = table;
      cachedDataScalars[d] = unmodScalars;
    }

    return ItemVariationStore._(
      regionScalars: List<double>.unmodifiable(scalars),
      variationData: List<ItemVariationDataTable?>.unmodifiable(dataTables),
      dataRegionScalars: cachedDataScalars,
    );
  }

  /// Returns region scalars for `ItemVariationData` at [vsindex].
  List<double> scalarsForDataIndex(int vsindex) {
    if (vsindex < 0 || vsindex >= variationData.length) {
      throw TexMathFontError(
        'Variation data index $vsindex out of bounds (${variationData.length}).',
      );
    }
    return _dataRegionScalars[vsindex] ?? const <double>[];
  }

  /// Evaluates the delta at `(outerIndex, innerIndex)` using stored `deltaSets`.
  double deltaFor(int outerIndex, int innerIndex) {
    if (outerIndex < 0 || outerIndex >= variationData.length) {
      return 0.0;
    }
    final ItemVariationDataTable? table = variationData[outerIndex];
    if (table == null || innerIndex < 0 || innerIndex >= table.deltas.length) {
      return 0.0;
    }
    final List<int> row = table.deltas[innerIndex];
    final List<double>? scalars = _dataRegionScalars[outerIndex];
    if (scalars == null) {
      return 0.0;
    }
    double total = 0.0;
    final int n = math.min(row.length, scalars.length);
    for (int i = 0; i < n; i++) {
      total += row[i] * scalars[i];
    }
    return total;
  }
}

/// Optional OpenType `HVAR` table providing variable advance width & lsb deltas.
final class HvarTable {
  HvarTable._({
    required this.store,
    required this._advanceMap,
    required this._lsbMap,
  });

  final ItemVariationStore store;
  final List<int>? _advanceMap;
  final List<int>? _lsbMap;

  /// Parses `HVAR` table from [reader] using [normalizedCoords].
  factory HvarTable.parse(
    FontByteReader reader,
    List<double> normalizedCoords,
  ) {
    final int majorVersion = reader.readUint16(0, 'HVAR.majorVersion');
    final int minorVersion = reader.readUint16(2, 'HVAR.minorVersion');
    if (majorVersion != 1 || minorVersion != 0) {
      throw TexMathFontError(
        'Unsupported HVAR version $majorVersion.$minorVersion.',
      );
    }
    final int storeOffset = reader.readUint32(
      4,
      'HVAR.itemVariationStoreOffset',
    );
    final int advOffset = reader.readUint32(
      8,
      'HVAR.advanceWidthMappingOffset',
    );
    final int lsbOffset = reader.readUint32(12, 'HVAR.lsbMappingOffset');
    final ItemVariationStore store = ItemVariationStore.parse(
      reader,
      storeOffset,
      normalizedCoords,
    );
    return HvarTable._(
      store: store,
      advanceMap: advOffset == 0
          ? null
          : _parseDeltaSetIndexMap(reader, advOffset),
      lsbMap: lsbOffset == 0 ? null : _parseDeltaSetIndexMap(reader, lsbOffset),
    );
  }

  /// Returns variable advance width delta for [glyphId].
  double advanceWidthDelta(int glyphId) {
    final List<int>? map = _advanceMap;
    if (map == null) {
      return store.deltaFor(0, glyphId);
    }
    if (map.isEmpty) {
      return 0.0;
    }
    final int idx = glyphId < (map.length ~/ 2)
        ? glyphId
        : (map.length ~/ 2) - 1;
    return store.deltaFor(map[idx * 2], map[idx * 2 + 1]);
  }

  /// Returns variable left-side-bearing delta for [glyphId].
  double lsbDelta(int glyphId) {
    final List<int>? map = _lsbMap;
    if (map == null || map.isEmpty) {
      return 0.0;
    }
    final int idx = glyphId < (map.length ~/ 2)
        ? glyphId
        : (map.length ~/ 2) - 1;
    return store.deltaFor(map[idx * 2], map[idx * 2 + 1]);
  }

  static List<int> _parseDeltaSetIndexMap(FontByteReader reader, int offset) {
    final int format = reader.readUint8(offset, 'DeltaSetIndexMap.format');
    final int entryFormat = reader.readUint8(
      offset + 1,
      'DeltaSetIndexMap.entryFormat',
    );
    final int entrySize = ((entryFormat & 0x30) >> 4) + 1;
    final int innerBits = (entryFormat & 0x0F) + 1;
    final int innerMask = (1 << innerBits) - 1;

    final int mapCount;
    int pos;
    if (format == 0) {
      mapCount = reader.readUint16(offset + 2, 'DeltaSetIndexMap.mapCount');
      pos = offset + 4;
    } else if (format == 1) {
      mapCount = reader.readUint32(offset + 2, 'DeltaSetIndexMap.mapCount');
      pos = offset + 6;
    } else {
      throw TexMathFontError('Unsupported DeltaSetIndexMap format: $format.');
    }

    reader.checkRange(pos, mapCount * entrySize, 'DeltaSetIndexMap.entries');
    final List<int> pairs = List<int>.filled(mapCount * 2, 0);
    for (int i = 0; i < mapCount; i++) {
      int value = 0;
      for (int b = 0; b < entrySize; b++) {
        value = (value << 8) | reader.readUint8(pos + b, 'DeltaSetIndexMap');
      }
      pairs[i * 2] = value >> innerBits;
      pairs[i * 2 + 1] = value & innerMask;
      pos += entrySize;
    }
    return pairs;
  }
}
