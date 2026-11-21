import 'dart:typed_data';

import '../error.dart';
import 'binary_reader.dart';
import 'outline.dart';
import 'outline_utils.dart';

/// Lazy TrueType `loca` + `glyf` outline decoder supporting simple and
/// composite glyphs with cycle and recursion depth guards.
final class GlyfDecoder {
  GlyfDecoder._({
    required FontByteReader glyfReader,
    required this._offsets,
    required this._numGlyphs,
  }) : _glyf = glyfReader;

  static const int _maxCompositeDepth = 32;
  static const int _maxCompositeVisits = 4096;
  static const int _maxPathCommands = 16384;

  final FontByteReader _glyf;
  final Uint32List _offsets;
  final int _numGlyphs;

  /// Parses `loca` offsets and validates bounds against `glyf`.
  factory GlyfDecoder.parse({
    required FontByteReader glyfReader,
    required FontByteReader locaReader,
    required int numGlyphs,
    required int indexToLocFormat,
  }) {
    if (indexToLocFormat != 0 && indexToLocFormat != 1) {
      throw TexMathFontError(
        'Invalid head indexToLocFormat ($indexToLocFormat) for TrueType glyf.',
      );
    }
    final int entryCount = numGlyphs + 1;
    final int requiredBytes = indexToLocFormat == 0
        ? entryCount * 2
        : entryCount * 4;
    locaReader.checkRange(0, requiredBytes, 'loca.offsets');

    final Uint32List offsets = Uint32List(entryCount);
    for (int i = 0; i < entryCount; i++) {
      final int off = indexToLocFormat == 0
          ? locaReader.readUint16(i * 2, 'loca.short') * 2
          : locaReader.readUint32(i * 4, 'loca.long');
      if (off > glyfReader.length) {
        throw TexMathFontError(
          'loca offset $off exceeds glyf length (${glyfReader.length}).',
        );
      }
      if (i > 0 && off < offsets[i - 1]) {
        throw TexMathFontError(
          'Unsorted loca offsets at glyph $i ($off < ${offsets[i - 1]}).',
        );
      }
      offsets[i] = off;
    }

    return GlyfDecoder._(
      glyfReader: glyfReader,
      offsets: offsets,
      numGlyphs: numGlyphs,
    );
  }

  /// Decodes the vector outline for [glyphId], returning `null` if out of
  /// range.
  GlyphOutline? decodeGlyph(int glyphId, double advanceWidth) {
    if (glyphId < 0 || glyphId >= _numGlyphs) {
      return null;
    }
    final _GlyfDecodeBudget budget = _GlyfDecodeBudget(
      maxVisits: _maxCompositeVisits,
      maxCommands: _maxPathCommands,
    );
    final _DecodedTrueType result = _decodeInternal(
      glyphId,
      <int>{},
      0,
      <int, _DecodedTrueType>{},
      budget,
    );
    return GlyphOutline.cached(
      glyphId: glyphId,
      commands: result.commands,
      advanceWidth: advanceWidth,
    );
  }

  _DecodedTrueType _decodeInternal(
    int glyphId,
    Set<int> visiting,
    int depth,
    Map<int, _DecodedTrueType> memo,
    _GlyfDecodeBudget budget,
  ) {
    if (depth > _maxCompositeDepth) {
      throw TexMathFontError(
        'TrueType composite glyph recursion exceeded $_maxCompositeDepth.',
      );
    }
    if (++budget.visits > budget.maxVisits) {
      throw TexMathFontError(
        'TrueType composite glyph visit count exceeded ${budget.maxVisits}.',
      );
    }
    final _DecodedTrueType? cached = memo[glyphId];
    if (cached != null) {
      return cached;
    }
    if (!visiting.add(glyphId)) {
      throw TexMathFontError(
        'Cycle detected in TrueType composite glyph $glyphId.',
      );
    }

    try {
      final int start = _offsets[glyphId];
      final int end = _offsets[glyphId + 1];
      if (start == end) {
        return const _DecodedTrueType(<PathCommand>[], <_Point2D>[]);
      }
      if (end - start < 10) {
        throw TexMathFontError(
          'Truncated TrueType glyph $glyphId header (${end - start} bytes).',
        );
      }

      final FontByteReader glyphSlice = _glyf.slice(
        start,
        end - start,
        'glyf[$glyphId]',
      );
      final int numberOfContours = glyphSlice.readInt16(0, 'glyf.contours');
      final _DecodedTrueType decoded;
      if (numberOfContours >= 0) {
        decoded = _decodeSimple(glyphSlice, numberOfContours);
        if (decoded.commands.length > budget.maxCommands) {
          throw TexMathFontError(
            'TrueType glyph path commands (${decoded.commands.length}) '
            'exceed limit (${budget.maxCommands}).',
          );
        }
      } else {
        decoded = _decodeComposite(glyphSlice, visiting, depth, memo, budget);
      }
      memo[glyphId] = decoded;
      return decoded;
    } finally {
      visiting.remove(glyphId);
    }
  }

  _DecodedTrueType _decodeSimple(FontByteReader slice, int numberOfContours) {
    if (numberOfContours == 0) {
      return const _DecodedTrueType(<PathCommand>[], <_Point2D>[]);
    }
    int pos = 10;
    slice.checkRange(pos, numberOfContours * 2, 'glyf.endPtsOfContours');
    final List<int> endPts = List<int>.filled(numberOfContours, 0);
    int prevEnd = -1;
    for (int i = 0; i < numberOfContours; i++) {
      final int endPt = slice.readUint16(pos + i * 2, 'glyf.endPt');
      if (endPt < prevEnd) {
        throw const TexMathFontError('Invalid decreasing endPtsOfContours.');
      }
      endPts[i] = endPt;
      prevEnd = endPt;
    }
    pos += numberOfContours * 2;

    final int numPoints = endPts.last + 1;
    final int instructionLength = slice.readUint16(
      pos,
      'glyf.instructionLength',
    );
    pos += 2;
    slice.checkRange(pos, instructionLength, 'glyf.instructions');
    pos += instructionLength;

    final Uint8List flags = Uint8List(numPoints);
    int flagIndex = 0;
    while (flagIndex < numPoints) {
      final int flag = slice.readUint8(pos++, 'glyf.flag');
      flags[flagIndex++] = flag;
      if ((flag & 0x08) != 0) {
        final int repeat = slice.readUint8(pos++, 'glyf.repeatCount');
        if (flagIndex + repeat > numPoints) {
          throw const TexMathFontError(
            'TrueType flag repeat count exceeds glyph point count.',
          );
        }
        for (int r = 0; r < repeat; r++) {
          flags[flagIndex++] = flag;
        }
      }
    }

    final Int32List xs = Int32List(numPoints);
    int curX = 0;
    for (int i = 0; i < numPoints; i++) {
      final int flag = flags[i];
      final bool isShort = (flag & 0x02) != 0;
      final bool sameOrPos = (flag & 0x10) != 0;
      if (isShort) {
        final int dx = slice.readUint8(pos++, 'glyf.dxShort');
        curX += sameOrPos ? dx : -dx;
      } else if (!sameOrPos) {
        curX += slice.readInt16(pos, 'glyf.dxLong');
        pos += 2;
      }
      xs[i] = curX;
    }

    final Int32List ys = Int32List(numPoints);
    int curY = 0;
    for (int i = 0; i < numPoints; i++) {
      final int flag = flags[i];
      final bool isShort = (flag & 0x04) != 0;
      final bool sameOrPos = (flag & 0x20) != 0;
      if (isShort) {
        final int dy = slice.readUint8(pos++, 'glyf.dyShort');
        curY += sameOrPos ? dy : -dy;
      } else if (!sameOrPos) {
        curY += slice.readInt16(pos, 'glyf.dyLong');
        pos += 2;
      }
      ys[i] = curY;
    }

    final List<PathCommand> commands = <PathCommand>[];
    final List<_Point2D> points = <_Point2D>[
      for (int i = 0; i < numPoints; i++)
        _Point2D(xs[i].toDouble(), ys[i].toDouble()),
    ];

    int contourStart = 0;
    for (final int contourEnd in endPts) {
      final int count = contourEnd - contourStart + 1;
      if (count <= 0) {
        contourStart = contourEnd + 1;
        continue;
      }
      _emitContour(commands, xs, ys, flags, contourStart, contourEnd);
      contourStart = contourEnd + 1;
    }

    return _DecodedTrueType(commands, points);
  }

  void _emitContour(
    List<PathCommand> commands,
    Int32List xs,
    Int32List ys,
    Uint8List flags,
    int start,
    int end,
  ) {
    final int count = end - start + 1;
    if (count == 1) {
      commands
        ..add(MoveTo(xs[start].toDouble(), ys[start].toDouble()))
        ..add(const ClosePath());
      return;
    }

    bool onCurve(int offset) => (flags[start + (offset % count)] & 0x01) != 0;
    double px(int offset) => xs[start + (offset % count)].toDouble();
    double py(int offset) => ys[start + (offset % count)].toDouble();

    int firstOnCurve = -1;
    for (int i = 0; i < count; i++) {
      if (onCurve(i)) {
        firstOnCurve = i;
        break;
      }
    }

    if (firstOnCurve == -1) {
      // Every point in the contour is off-curve; start at midpoint of last and
      // first points.
      final double startX = (px(count - 1) + px(0)) * 0.5;
      final double startY = (py(count - 1) + py(0)) * 0.5;
      commands.add(MoveTo(startX, startY));
      for (int i = 0; i < count; i++) {
        final double cx = px(i);
        final double cy = py(i);
        final double nx = (cx + px(i + 1)) * 0.5;
        final double ny = (cy + py(i + 1)) * 0.5;
        commands.add(QuadTo(cx, cy, nx, ny));
      }
      commands.add(const ClosePath());
      return;
    }

    commands.add(MoveTo(px(firstOnCurve), py(firstOnCurve)));
    int i = firstOnCurve + 1;
    final int limit = firstOnCurve + count;
    while (i <= limit) {
      if (onCurve(i)) {
        commands.add(LineTo(px(i), py(i)));
        i++;
      } else {
        final double cx = px(i);
        final double cy = py(i);
        if (i + 1 <= limit && onCurve(i + 1)) {
          commands.add(QuadTo(cx, cy, px(i + 1), py(i + 1)));
          i += 2;
        } else {
          final double nx = (cx + px(i + 1)) * 0.5;
          final double ny = (cy + py(i + 1)) * 0.5;
          commands.add(QuadTo(cx, cy, nx, ny));
          i += 1;
        }
      }
    }
    commands.add(const ClosePath());
  }

  _DecodedTrueType _decodeComposite(
    FontByteReader slice,
    Set<int> visiting,
    int depth,
    Map<int, _DecodedTrueType> memo,
    _GlyfDecodeBudget budget,
  ) {
    final List<PathCommand> allCommands = <PathCommand>[];
    final List<_Point2D> allPoints = <_Point2D>[];
    int pos = 10;

    while (true) {
      final int flags = slice.readUint16(pos, 'glyf.comp.flags');
      final int compGid = slice.readUint16(pos + 2, 'glyf.comp.glyphIndex');
      pos += 4;
      if (compGid >= _numGlyphs) {
        throw TexMathFontError(
          'Composite glyph component index $compGid out of bounds '
          '($_numGlyphs).',
        );
      }

      final bool argsAreWords = (flags & 0x0001) != 0;
      final bool argsAreXy = (flags & 0x0002) != 0;

      final int arg1;
      final int arg2;
      if (argsAreWords) {
        arg1 = argsAreXy
            ? slice.readInt16(pos, 'glyf.comp.arg1')
            : slice.readUint16(pos, 'glyf.comp.pt1');
        arg2 = argsAreXy
            ? slice.readInt16(pos + 2, 'glyf.comp.arg2')
            : slice.readUint16(pos + 2, 'glyf.comp.pt2');
        pos += 4;
      } else {
        arg1 = argsAreXy
            ? slice.readInt8(pos, 'glyf.comp.arg1')
            : slice.readUint8(pos, 'glyf.comp.pt1');
        arg2 = argsAreXy
            ? slice.readInt8(pos + 1, 'glyf.comp.arg2')
            : slice.readUint8(pos + 1, 'glyf.comp.pt2');
        pos += 2;
      }

      double a = 1.0;
      double b = 0.0;
      double c = 0.0;
      double d = 1.0;

      if ((flags & 0x0008) != 0) {
        final double scale = slice.readF2Dot14(pos, 'glyf.comp.scale');
        pos += 2;
        a = scale;
        d = scale;
      } else if ((flags & 0x0040) != 0) {
        a = slice.readF2Dot14(pos, 'glyf.comp.xscale');
        d = slice.readF2Dot14(pos + 2, 'glyf.comp.yscale');
        pos += 4;
      } else if ((flags & 0x0080) != 0) {
        a = slice.readF2Dot14(pos, 'glyf.comp.xscale');
        b = slice.readF2Dot14(pos + 2, 'glyf.comp.scale01');
        c = slice.readF2Dot14(pos + 4, 'glyf.comp.scale10');
        d = slice.readF2Dot14(pos + 6, 'glyf.comp.yscale');
        pos += 8;
      }

      final _DecodedTrueType child = _decodeInternal(
        compGid,
        visiting,
        depth + 1,
        memo,
        budget,
      );

      double tx = 0.0;
      double ty = 0.0;
      if (argsAreXy) {
        final bool scaledOffset =
            (flags & 0x0800) != 0 && (flags & 0x1000) == 0;
        if (scaledOffset) {
          tx = a * arg1 + c * arg2;
          ty = b * arg1 + d * arg2;
        } else {
          tx = arg1.toDouble();
          ty = arg2.toDouble();
        }
      } else if (arg1 < allPoints.length && arg2 < child.points.length) {
        final _Point2D parentPt = allPoints[arg1];
        final _Point2D childPt = child.points[arg2];
        final double childX = a * childPt.x + c * childPt.y;
        final double childY = b * childPt.x + d * childPt.y;
        tx = parentPt.x - childX;
        ty = parentPt.y - childY;
      }

      if (allCommands.length + child.commands.length > budget.maxCommands) {
        throw TexMathFontError(
          'TrueType composite glyph path command count exceeds limit '
          '(${budget.maxCommands}).',
        );
      }
      if (allPoints.length + child.points.length > 65536) {
        throw const TexMathFontError(
          'TrueType composite glyph point count exceeds limit (65536).',
        );
      }
      allCommands.addAll(
        transformPathCommands(child.commands, a, b, c, d, tx, ty),
      );
      for (final _Point2D pt in child.points) {
        allPoints.add(
          _Point2D(a * pt.x + c * pt.y + tx, b * pt.x + d * pt.y + ty),
        );
      }

      if ((flags & 0x0020) == 0) {
        break;
      }
    }

    return _DecodedTrueType(allCommands, allPoints);
  }
}

final class _GlyfDecodeBudget {
  _GlyfDecodeBudget({required this.maxVisits, required this.maxCommands});

  final int maxVisits;
  final int maxCommands;
  int visits = 0;
}

final class _Point2D {
  const _Point2D(this.x, this.y);

  final double x;
  final double y;
}

final class _DecodedTrueType {
  const _DecodedTrueType(this.commands, this.points);

  final List<PathCommand> commands;
  final List<_Point2D> points;
}
