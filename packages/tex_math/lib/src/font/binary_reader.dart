import 'dart:typed_data';

import '../error.dart';

/// Bounds-safe big-endian binary reader over an SFNT or subtable byte slice.
///
/// Every offset read and sub-slice checks explicit bounds against [length]
/// before accessing underlying bytes, throwing [TexMathFontError] on any
/// truncation or out-of-range access.
final class FontByteReader {
  /// Wraps [bytes] starting at [baseOffset] for [sliceLength] bytes.
  FontByteReader._(this._bytes, this._data, this._baseOffset, this.length);

  /// Creates a bounds-safe reader over [bytes].
  factory FontByteReader(Uint8List bytes) {
    final ByteData data = ByteData.sublistView(bytes);
    return FontByteReader._(bytes, data, 0, bytes.length);
  }

  final Uint8List _bytes;
  final ByteData _data;
  final int _baseOffset;

  /// Total readable byte length of this view.
  final int length;

  /// Returns a bounded sub-reader covering `[offset, offset + sliceLength)`.
  FontByteReader slice(
    int offset,
    int sliceLength, [
    String context = 'table',
  ]) {
    _checkRange(offset, sliceLength, context);
    return FontByteReader._(_bytes, _data, _baseOffset + offset, sliceLength);
  }

  /// Returns a read-only byte view covering `[offset, offset + viewLength)`.
  Uint8List viewBytes(int offset, int viewLength, [String context = 'bytes']) {
    _checkRange(offset, viewLength, context);
    return Uint8List.sublistView(
      _bytes,
      _baseOffset + offset,
      _baseOffset + offset + viewLength,
    );
  }

  /// Reads an unsigned 8-bit integer at [offset].
  int readUint8(int offset, [String context = 'uint8']) {
    _checkRange(offset, 1, context);
    return _data.getUint8(_baseOffset + offset);
  }

  /// Reads a signed 8-bit integer at [offset].
  int readInt8(int offset, [String context = 'int8']) {
    _checkRange(offset, 1, context);
    return _data.getInt8(_baseOffset + offset);
  }

  /// Reads a big-endian unsigned 16-bit integer at [offset].
  int readUint16(int offset, [String context = 'uint16']) {
    _checkRange(offset, 2, context);
    return _data.getUint16(_baseOffset + offset, Endian.big);
  }

  /// Reads a big-endian signed 16-bit integer at [offset].
  int readInt16(int offset, [String context = 'int16']) {
    _checkRange(offset, 2, context);
    return _data.getInt16(_baseOffset + offset, Endian.big);
  }

  /// Reads a big-endian unsigned 24-bit integer at [offset].
  int readUint24(int offset, [String context = 'uint24']) {
    _checkRange(offset, 3, context);
    final int base = _baseOffset + offset;
    return (_data.getUint8(base) << 16) |
        (_data.getUint8(base + 1) << 8) |
        _data.getUint8(base + 2);
  }

  /// Reads a big-endian unsigned 32-bit integer at [offset].
  int readUint32(int offset, [String context = 'uint32']) {
    _checkRange(offset, 4, context);
    return _data.getUint32(_baseOffset + offset, Endian.big);
  }

  /// Reads a big-endian signed 32-bit integer at [offset].
  int readInt32(int offset, [String context = 'int32']) {
    _checkRange(offset, 4, context);
    return _data.getInt32(_baseOffset + offset, Endian.big);
  }

  /// Reads a 16.16 signed fixed-point number (`Fixed`) at [offset].
  double readFixed(int offset, [String context = 'Fixed']) {
    return readInt32(offset, context) / 65536.0;
  }

  /// Reads a 2.14 signed fixed-point number (`F2Dot14`) at [offset].
  double readF2Dot14(int offset, [String context = 'F2Dot14']) {
    return readInt16(offset, context) / 16384.0;
  }

  /// Reads a 4-byte ASCII SFNT tag at [offset].
  String readTag(int offset, [String context = 'tag']) {
    _checkRange(offset, 4, context);
    final int base = _baseOffset + offset;
    return String.fromCharCodes(<int>[
      _data.getUint8(base),
      _data.getUint8(base + 1),
      _data.getUint8(base + 2),
      _data.getUint8(base + 3),
    ]);
  }

  /// Reads `byteLength` bytes at [offset] as UTF-16BE string.
  String readUtf16Be(int offset, int byteLength, [String context = 'utf16be']) {
    _checkRange(offset, byteLength, context);
    final int unitCount = byteLength ~/ 2;
    final List<int> units = List<int>.filled(unitCount, 0);
    for (int i = 0; i < unitCount; i++) {
      units[i] = _data.getUint16(_baseOffset + offset + i * 2, Endian.big);
    }
    return String.fromCharCodes(units);
  }

  /// Verifies that `[offset, offset + byteCount)` is inside `[0, length]`.
  void checkRange(int offset, int byteCount, [String context = 'range']) {
    _checkRange(offset, byteCount, context);
  }

  /// Reads an unsigned 8-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 1)` via [checkRange] first.
  int readUint8Fast(int offset) => _data.getUint8(_baseOffset + offset);

  /// Reads a big-endian unsigned 16-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 2)` via [checkRange] first.
  int readUint16Fast(int offset) =>
      _data.getUint16(_baseOffset + offset, Endian.big);

  /// Reads a big-endian signed 16-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 2)` via [checkRange] first.
  int readInt16Fast(int offset) =>
      _data.getInt16(_baseOffset + offset, Endian.big);

  /// Reads a big-endian unsigned 24-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 3)` via [checkRange] first.
  int readUint24Fast(int offset) {
    final int base = _baseOffset + offset;
    return (_data.getUint8(base) << 16) |
        (_data.getUint8(base + 1) << 8) |
        _data.getUint8(base + 2);
  }

  /// Reads a big-endian unsigned 32-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 4)` via [checkRange] first.
  int readUint32Fast(int offset) =>
      _data.getUint32(_baseOffset + offset, Endian.big);

  /// Reads a big-endian signed 32-bit integer without rechecking bounds.
  /// Callers must validate `[offset, offset + 4)` via [checkRange] first.
  int readInt32Fast(int offset) =>
      _data.getInt32(_baseOffset + offset, Endian.big);

  void _checkRange(int offset, int byteCount, String context) {
    if (offset < 0 ||
        byteCount < 0 ||
        offset > length ||
        byteCount > length - offset) {
      throw TexMathFontError(
        'Truncated or out-of-bounds OpenType $context read at offset '
        '$offset (length $byteCount, buffer $length).',
      );
    }
  }
}

/// Parsed OpenType Coverage table (Format 1 or Format 2) mapping glyph IDs
/// to contiguous coverage indices.
final class CoverageTable {
  CoverageTable._({
    required this._singleGlyphs,
    required this._rangeStarts,
    required this._rangeEnds,
    required this._rangeStartIndices,
    required this._isFormat2,
  });

  /// Empty coverage matching no glyphs.
  static final CoverageTable empty = CoverageTable._(
    singleGlyphs: Uint16List(0),
    rangeStarts: Uint16List(0),
    rangeEnds: Uint16List(0),
    rangeStartIndices: Uint16List(0),
    isFormat2: false,
  );

  final Uint16List _singleGlyphs;
  final Uint16List _rangeStarts;
  final Uint16List _rangeEnds;
  final Uint16List _rangeStartIndices;
  final bool _isFormat2;

  /// Parses an OpenType Coverage table starting at [offset] within [reader].
  factory CoverageTable.parse(
    FontByteReader reader,
    int offset, [
    String context = 'Coverage',
  ]) {
    final int format = reader.readUint16(offset, '$context.format');
    final int count = reader.readUint16(offset + 2, '$context.count');
    if (format == 1) {
      reader.checkRange(offset + 4, count * 2, '$context.glyphArray');
      final Uint16List glyphs = Uint16List(count);
      for (int i = 0; i < count; i++) {
        glyphs[i] = reader.readUint16Fast(offset + 4 + i * 2);
      }
      return CoverageTable._(
        singleGlyphs: glyphs,
        rangeStarts: Uint16List(0),
        rangeEnds: Uint16List(0),
        rangeStartIndices: Uint16List(0),
        isFormat2: false,
      );
    }
    if (format == 2) {
      reader.checkRange(offset + 4, count * 6, '$context.rangeRecords');
      final Uint16List starts = Uint16List(count);
      final Uint16List ends = Uint16List(count);
      final Uint16List startIndices = Uint16List(count);
      for (int i = 0; i < count; i++) {
        final int pos = offset + 4 + i * 6;
        final int start = reader.readUint16Fast(pos);
        final int end = reader.readUint16Fast(pos + 2);
        final int startIdx = reader.readUint16Fast(pos + 4);
        if (end < start) {
          throw TexMathFontError(
            'Invalid $context Format 2 range: end ($end) < start ($start).',
          );
        }
        starts[i] = start;
        ends[i] = end;
        startIndices[i] = startIdx;
      }
      return CoverageTable._(
        singleGlyphs: Uint16List(0),
        rangeStarts: starts,
        rangeEnds: ends,
        rangeStartIndices: startIndices,
        isFormat2: true,
      );
    }
    throw TexMathFontError('Unsupported $context format: $format.');
  }

  /// Returns the coverage index for [glyphId], or `-1` if not covered.
  int indexOf(int glyphId) {
    if (glyphId < 0 || glyphId > 0xFFFF) {
      return -1;
    }
    if (!_isFormat2) {
      int low = 0;
      int high = _singleGlyphs.length - 1;
      while (low <= high) {
        final int mid = (low + high) >>> 1;
        final int midGlyph = _singleGlyphs[mid];
        if (midGlyph == glyphId) {
          return mid;
        }
        if (midGlyph < glyphId) {
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }
      return -1;
    }
    int low = 0;
    int high = _rangeStarts.length - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final int start = _rangeStarts[mid];
      final int end = _rangeEnds[mid];
      if (glyphId < start) {
        high = mid - 1;
      } else if (glyphId > end) {
        low = mid + 1;
      } else {
        return _rangeStartIndices[mid] + (glyphId - start);
      }
    }
    return -1;
  }

  /// Whether [glyphId] is covered by this table.
  bool contains(int glyphId) => indexOf(glyphId) >= 0;

  /// Expands all covered glyph IDs in coverage-index order.
  List<int> toGlyphList() {
    if (!_isFormat2) {
      return List<int>.from(_singleGlyphs);
    }
    final List<int> result = <int>[];
    for (int i = 0; i < _rangeStarts.length; i++) {
      for (int gid = _rangeStarts[i]; gid <= _rangeEnds[i]; gid++) {
        result.add(gid);
      }
    }
    return result;
  }
}
