import 'dart:typed_data';

import '../error.dart';
import 'binary_reader.dart';
import 'variation.dart';

/// Lazy CFF / CFF2 INDEX storing absolute byte offset spans inside the owning
/// table buffer.
final class CffIndex {
  CffIndex._(this._reader, this._offsets, this.endOffset);

  /// Empty index with zero entries.
  static final CffIndex empty = CffIndex._(
    FontByteReader(Uint8List(0)),
    Uint32List(1),
    0,
  );

  final FontByteReader _reader;
  final Uint32List _offsets;

  /// Byte offset immediately following this INDEX in the CFF/CFF2 table.
  final int endOffset;

  /// Number of entries in this INDEX.
  int get length => _offsets.length - 1;

  /// Returns a bounded [FontByteReader] for entry [index].
  FontByteReader operator [](int index) {
    if (index < 0 || index >= length) {
      throw TexMathFontError('CFF INDEX entry $index out of bounds ($length).');
    }
    final int start = _offsets[index];
    final int end = _offsets[index + 1];
    return _reader.slice(start, end - start, 'CFF.INDEX[$index]');
  }

  /// Parses a CFF v1 (`uint16` count) or CFF2 (`uint32` count) INDEX starting
  /// at [offset] in [reader].
  factory CffIndex.parse(
    FontByteReader reader,
    int offset, {
    required bool isCff2,
    String context = 'CFF.INDEX',
  }) {
    final int count;
    int pos = offset;
    if (isCff2) {
      count = reader.readUint32(pos, '$context.count');
      pos += 4;
    } else {
      count = reader.readUint16(pos, '$context.count');
      pos += 2;
    }
    if (count == 0) {
      return CffIndex._(reader, Uint32List(1), pos);
    }

    final int offSize = reader.readUint8(pos++, '$context.offSize');
    if (offSize < 1 || offSize > 4) {
      throw TexMathFontError('Invalid $context offSize: $offSize.');
    }

    final int offTableBytes = (count + 1) * offSize;
    reader.checkRange(pos, offTableBytes, '$context.offsets');
    final int dataOrigin = pos + offTableBytes - 1;

    final Uint32List absOffsets = Uint32List(count + 1);
    int prevAbs = 0;
    for (int i = 0; i <= count; i++) {
      final int offPos = pos + i * offSize;
      final int relOff = switch (offSize) {
        1 => reader.readUint8Fast(offPos),
        2 => reader.readUint16Fast(offPos),
        3 => reader.readUint24Fast(offPos),
        _ => reader.readUint32Fast(offPos),
      };
      if (relOff < 1) {
        throw TexMathFontError('Invalid $context offset $relOff (< 1).');
      }
      final int abs = dataOrigin + relOff;
      if (abs > reader.length) {
        throw TexMathFontError(
          '$context entry offset $abs exceeds table length (${reader.length}).',
        );
      }
      if (i > 0 && abs < prevAbs) {
        throw TexMathFontError(
          'Unsorted $context offsets at index $i ($abs < $prevAbs).',
        );
      }
      absOffsets[i] = abs;
      prevAbs = abs;
    }

    return CffIndex._(reader, absOffsets, prevAbs);
  }
}

/// DICT operator key (single-byte `0..25` or two-byte `12, op`).
final class CffDictOp {
  const CffDictOp(this.op, [this.subOp = -1]);

  final int op;
  final int subOp;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CffDictOp && op == other.op && subOp == other.subOp;

  @override
  int get hashCode => Object.hash(op, subOp);
}

/// Maximum number of operands allowed on a CFF DICT stack.
const int maxCffDictStack = 513;

/// Converts a finite CFF DICT / CharString [value] into a safe integer, throwing
/// [TexMathFontError] if [value] is `NaN` or infinite.
int cffFiniteInt(double value, String context) {
  if (!value.isFinite) {
    throw TexMathFontError('Non-finite numeric value in $context.');
  }
  return value.round();
}

/// Parses CFF / CFF2 DICT byte slices with optional `vsindex`/`blend`
/// evaluation.
Map<CffDictOp, List<double>> parseCffDict(
  FontByteReader dictReader, {
  ItemVariationStore? variationStore,
  int initialVsIndex = 0,
}) {
  final Map<CffDictOp, List<double>> result = <CffDictOp, List<double>>{};
  final List<double> stack = <double>[];
  int vsindex = initialVsIndex;
  int pos = 0;

  while (pos < dictReader.length) {
    final int b0 = dictReader.readUint8(pos, 'CFF.DICT.byte');
    if (b0 <= 27 && b0 != 26) {
      if (b0 == 12) {
        final int b1 = dictReader.readUint8(pos + 1, 'CFF.DICT.op2');
        pos += 2;
        result[CffDictOp(12, b1)] = List<double>.from(stack);
        stack.clear();
      } else if (b0 == 22) {
        // CFF2 Private DICT `vsindex`
        pos++;
        if (stack.isEmpty) {
          throw const TexMathFontError('CFF2 DICT vsindex underflow.');
        }
        vsindex = cffFiniteInt(stack.removeLast(), 'CFF2.DICT.vsindex');
        result[const CffDictOp(22)] = <double>[vsindex.toDouble()];
        stack.clear();
      } else if (b0 == 23) {
        // CFF2 Private DICT `blend`
        pos++;
        _evalDictBlend(stack, variationStore, vsindex);
      } else {
        pos++;
        result[CffDictOp(b0)] = List<double>.from(stack);
        stack.clear();
      }
      continue;
    }

    if (stack.length >= maxCffDictStack) {
      throw const TexMathFontError('CFF DICT operand stack exceeded limit.');
    }
    if (b0 == 28) {
      stack.add(dictReader.readInt16(pos + 1, 'CFF.DICT.int16').toDouble());
      pos += 3;
    } else if (b0 == 29) {
      stack.add(dictReader.readInt32(pos + 1, 'CFF.DICT.int32').toDouble());
      pos += 5;
    } else if (b0 == 30) {
      final _ParsedNibbleFloat parsed = _parseNibbleFloat(dictReader, pos + 1);
      stack.add(parsed.value);
      pos = parsed.nextOffset;
    } else if (b0 >= 32 && b0 <= 246) {
      stack.add((b0 - 139).toDouble());
      pos += 1;
    } else if (b0 >= 247 && b0 <= 250) {
      final int b1 = dictReader.readUint8(pos + 1, 'CFF.DICT.num+');
      stack.add(((b0 - 247) * 256 + b1 + 108).toDouble());
      pos += 2;
    } else if (b0 >= 251 && b0 <= 254) {
      final int b1 = dictReader.readUint8(pos + 1, 'CFF.DICT.num-');
      stack.add((-(b0 - 251) * 256 - b1 - 108).toDouble());
      pos += 2;
    } else {
      throw TexMathFontError('Invalid byte $b0 in CFF DICT.');
    }
  }

  return result;
}

void _evalDictBlend(
  List<double> stack,
  ItemVariationStore? store,
  int vsindex,
) {
  if (store == null) {
    throw const TexMathFontError('CFF2 DICT blend encountered without vstore.');
  }
  if (stack.isEmpty) {
    throw const TexMathFontError('CFF2 DICT blend operand underflow.');
  }
  final int n = cffFiniteInt(stack.removeLast(), 'CFF2.DICT.blend');
  final List<double> scalars = store.scalarsForDataIndex(vsindex);
  final int k = scalars.length;
  final int needed = n + n * k;
  if (n < 0 || stack.length < needed) {
    throw TexMathFontError(
      'CFF2 DICT blend underflow: need $needed operands, have ${stack.length}.',
    );
  }
  final int baseStart = stack.length - needed;
  final List<double> blended = List<double>.filled(n, 0.0);
  for (int i = 0; i < n; i++) {
    double val = stack[baseStart + i];
    final int deltaStart = baseStart + n + i * k;
    for (int r = 0; r < k; r++) {
      val += stack[deltaStart + r] * scalars[r];
    }
    if (!val.isFinite) {
      throw const TexMathFontError('Non-finite value produced by CFF2 blend.');
    }
    blended[i] = val;
  }
  stack.removeRange(baseStart, stack.length);
  stack.addAll(blended);
}

final class _ParsedNibbleFloat {
  const _ParsedNibbleFloat(this.value, this.nextOffset);

  final double value;
  final int nextOffset;
}

_ParsedNibbleFloat _parseNibbleFloat(FontByteReader reader, int startPos) {
  final StringBuffer sb = StringBuffer();
  int pos = startPos;
  while (true) {
    final int byte = reader.readUint8(pos++, 'CFF.DICT.float');
    final int hi = (byte >> 4) & 0x0F;
    final int lo = byte & 0x0F;
    if (_appendFloatNibble(sb, hi)) {
      break;
    }
    if (_appendFloatNibble(sb, lo)) {
      break;
    }
  }
  final double value = double.tryParse(sb.toString()) ?? 0.0;
  if (!value.isFinite) {
    throw const TexMathFontError('Non-finite floating-point operand in CFF.');
  }
  return _ParsedNibbleFloat(value, pos);
}

bool _appendFloatNibble(StringBuffer sb, int nibble) {
  switch (nibble) {
    case 0x0:
    case 0x1:
    case 0x2:
    case 0x3:
    case 0x4:
    case 0x5:
    case 0x6:
    case 0x7:
    case 0x8:
    case 0x9:
      sb.write(nibble);
      return false;
    case 0xA:
      sb.write('.');
      return false;
    case 0xB:
      sb.write('E');
      return false;
    case 0xC:
      sb.write('E-');
      return false;
    case 0xE:
      sb.write('-');
      return false;
    case 0xF:
      return true;
    default:
      return false;
  }
}

/// Decodes CFF delta-encoded number arrays (`BlueValues`, `StemSnapH`, etc.).
List<double> decodeDeltaArray(List<double>? deltas) {
  if (deltas == null || deltas.isEmpty) {
    return const <double>[];
  }
  final List<double> out = List<double>.filled(deltas.length, 0.0);
  double running = 0.0;
  for (int i = 0; i < deltas.length; i++) {
    running += deltas[i];
    out[i] = running;
  }
  return out;
}

/// Maps glyph IDs to Font DICT (`FDArray`) indices supporting Formats 0, 3,
/// and 4.
final class FdSelectTable {
  FdSelectTable._(this._format, this._direct, this._starts, this._fds);

  /// Constant FD index `0` when a single Font DICT applies to every glyph.
  static final FdSelectTable singleZero = FdSelectTable._(
    -1,
    Uint8List(0),
    Uint32List(0),
    Uint16List(0),
  );

  final int _format;
  final Uint8List _direct;
  final Uint32List _starts;
  final Uint16List _fds;

  /// Returns the Font DICT index for [glyphId].
  int fdForGlyph(int glyphId) {
    if (_format == -1) {
      return 0;
    }
    if (_format == 0) {
      return (glyphId >= 0 && glyphId < _direct.length) ? _direct[glyphId] : 0;
    }
    if (_starts.isEmpty || glyphId < _starts[0]) {
      return 0;
    }
    int low = 0;
    int high = _fds.length - 1;
    while (low <= high) {
      final int mid = (low + high) >>> 1;
      final int start = _starts[mid];
      final int end = _starts[mid + 1];
      if (glyphId < start) {
        high = mid - 1;
      } else if (glyphId >= end) {
        low = mid + 1;
      } else {
        return _fds[mid];
      }
    }
    return 0;
  }

  /// Parses an `FDSelect` structure at [offset] inside [reader].
  factory FdSelectTable.parse(
    FontByteReader reader,
    int offset,
    int numGlyphs,
  ) {
    final int fmt = reader.readUint8(offset, 'FDSelect.format');
    if (fmt == 0) {
      final Uint8List fds = Uint8List.fromList(
        reader.viewBytes(offset + 1, numGlyphs, 'FDSelect.fmt0'),
      );
      return FdSelectTable._(0, fds, Uint32List(0), Uint16List(0));
    }
    if (fmt == 3) {
      final int nRanges = reader.readUint16(offset + 1, 'FDSelect.nRanges');
      reader.checkRange(offset + 3, nRanges * 3 + 2, 'FDSelect.fmt3');
      final Uint32List starts = Uint32List(nRanges + 1);
      final Uint16List fds = Uint16List(nRanges);
      int pos = offset + 3;
      for (int i = 0; i < nRanges; i++) {
        starts[i] = reader.readUint16Fast(pos);
        fds[i] = reader.readUint8Fast(pos + 2);
        pos += 3;
      }
      starts[nRanges] = reader.readUint16Fast(pos);
      return FdSelectTable._(3, Uint8List(0), starts, fds);
    }
    if (fmt == 4) {
      final int nRanges = reader.readUint32(offset + 1, 'FDSelect.nRanges');
      reader.checkRange(offset + 5, nRanges * 6 + 4, 'FDSelect.fmt4');
      final Uint32List starts = Uint32List(nRanges + 1);
      final Uint16List fds = Uint16List(nRanges);
      int pos = offset + 5;
      for (int i = 0; i < nRanges; i++) {
        starts[i] = reader.readUint32Fast(pos);
        fds[i] = reader.readUint16Fast(pos + 4);
        pos += 6;
      }
      starts[nRanges] = reader.readUint32Fast(pos);
      return FdSelectTable._(4, Uint8List(0), starts, fds);
    }
    throw TexMathFontError('Unsupported CFF FDSelect format: $fmt.');
  }
}
