import 'dart:math' as math;

import '../error.dart';
import 'binary_reader.dart';
import 'cff_common.dart';
import 'metrics.dart';
import 'outline.dart';
import 'variation.dart';

/// Result of executing a single Type 2 CharString program.
final class DecodedCharString {
  const DecodedCharString({
    required this.commands,
    required this.stems,
    this.width,
  });

  final List<PathCommand> commands;
  final List<StemHint> stems;
  final double? width;
}

/// Executes Type 2 CharString bytecode for both `CFF` (v1) and `CFF2`.
final class Type2CharStringInterpreter {
  Type2CharStringInterpreter({
    required this.globalSubrs,
    required this.localSubrs,
    required this.isCff2,
    required this.defaultWidthX,
    required this.nominalWidthX,
    required this.variationStore,
    required this.initialVsIndex,
    this.maxStack = 513,
  }) : _vsindex = initialVsIndex;

  static const int _maxCallDepth = 64;
  static const int _maxSubrCalls = 4096;
  static const int _maxOpcodes = 65536;
  static const int _maxCommands = 16384;
  static const int _maxStems = 1024;

  final CffIndex globalSubrs;
  final CffIndex localSubrs;
  final bool isCff2;
  final double defaultWidthX;
  final double nominalWidthX;
  final ItemVariationStore? variationStore;
  final int initialVsIndex;
  final int maxStack;

  final List<double> _stack = <double>[];
  final List<double> _transient = List<double>.filled(32, 0.0);
  final List<PathCommand> _commands = <PathCommand>[];
  final List<StemHint> _stems = <StemHint>[];

  double _curX = 0.0;
  double _curY = 0.0;
  double _hStemPos = 0.0;
  double _vStemPos = 0.0;
  bool _hasWidth = false;
  double? _parsedWidth;
  bool _subpathOpen = false;
  bool _subpathHasSegments = false;
  bool _finished = false;
  int _vsindex;
  int _rngState = 0x12345678;
  int _subrCallCount = 0;
  int _opcodeCount = 0;

  /// Runs [charString] and returns the decoded vector commands and stem hints.
  DecodedCharString execute(FontByteReader charString) {
    _executeSubroutine(charString, 0);
    _closeActiveSubpath();
    return DecodedCharString(
      commands: List<PathCommand>.unmodifiable(_commands),
      stems: List<StemHint>.unmodifiable(_stems),
      width: isCff2 ? null : (_parsedWidth ?? defaultWidthX),
    );
  }

  void _executeSubroutine(FontByteReader code, int depth) {
    if (depth > _maxCallDepth) {
      throw const TexMathFontError(
        'Type 2 CharString subroutine recursion depth exceeded limit.',
      );
    }
    int pos = 0;
    while (pos < code.length && !_finished) {
      if (++_opcodeCount > _maxOpcodes) {
        throw const TexMathFontError(
          'Type 2 CharString opcode count exceeded limit.',
        );
      }
      final int b0 = code.readUint8(pos++, 'CharString.op');
      if (b0 >= 32) {
        if (b0 <= 246) {
          _push((b0 - 139).toDouble());
        } else if (b0 <= 250) {
          final int b1 = code.readUint8(pos++, 'CharString.num+');
          _push(((b0 - 247) * 256 + b1 + 108).toDouble());
        } else if (b0 <= 254) {
          final int b1 = code.readUint8(pos++, 'CharString.num-');
          _push((-(b0 - 251) * 256 - b1 - 108).toDouble());
        } else {
          // 255: 16.16 signed Fixed
          _push(code.readFixed(pos, 'CharString.fixed'));
          pos += 4;
        }
        continue;
      }
      if (b0 == 28) {
        final int val = code.readInt16(pos, 'CharString.int16');
        pos += 2;
        _push(val.toDouble());
        continue;
      }

      switch (b0) {
        case 1: // hstem
        case 18: // hstemhm
          _consumeWidthIfOdd(isCff2 ? false : true);
          _consumeStems(StemOrientation.horizontal);
        case 3: // vstem
        case 23: // vstemhm
          _consumeWidthIfOdd(isCff2 ? false : true);
          _consumeStems(StemOrientation.vertical);
        case 19: // hintmask
        case 20: // cntrmask
          _consumeWidthIfOdd(isCff2 ? false : true);
          _consumeStems(StemOrientation.vertical);
          final int maskBytes = (_stems.length + 7) >> 3;
          code.checkRange(pos, maskBytes, 'CharString.hintmask');
          pos += maskBytes;
        case 4: // vmoveto
          _consumeWidthForSingleArgMove();
          _vMoveTo();
        case 5: // rlineto
          _rLineTo();
        case 6: // hlineto
          _hLineTo();
        case 7: // vlineto
          _vLineTo();
        case 8: // rrcurveto
          _rrCurveTo();
        case 10: // callsubr
          if (++_subrCallCount > _maxSubrCalls) {
            throw const TexMathFontError(
              'Type 2 CharString subroutine call count exceeded limit.',
            );
          }
          final int subIdx = _popSubrIndex(localSubrs.length);
          _executeSubroutine(localSubrs[subIdx], depth + 1);
        case 29: // callgsubr
          if (++_subrCallCount > _maxSubrCalls) {
            throw const TexMathFontError(
              'Type 2 CharString subroutine call count exceeded limit.',
            );
          }
          final int gsubIdx = _popSubrIndex(globalSubrs.length);
          _executeSubroutine(globalSubrs[gsubIdx], depth + 1);
        case 11: // return
          return;
        case 14: // endchar
          if (!isCff2 && !_hasWidth && _stack.isNotEmpty) {
            _parsedWidth = nominalWidthX + _stack.removeAt(0);
            _hasWidth = true;
          }
          _stack.clear();
          _finished = true;
          return;
        case 15: // CFF2 vsindex
          if (!isCff2) {
            throw const TexMathFontError(
              'CharString operator 15 (vsindex) is only valid in CFF2.',
            );
          }
          if (_stack.isEmpty) {
            throw const TexMathFontError('CFF2 vsindex operand underflow.');
          }
          _vsindex = cffFiniteInt(_stack.removeLast(), 'CharString.vsindex');
          _stack.clear();
        case 16: // CFF2 blend
          if (!isCff2) {
            throw const TexMathFontError(
              'CharString operator 16 (blend) is only valid in CFF2.',
            );
          }
          _execBlend();
        case 21: // rmoveto
          _consumeWidthForTwoArgMove();
          _rMoveTo();
        case 22: // hmoveto
          _consumeWidthForSingleArgMove();
          _hMoveTo();
        case 24: // rcurveline
          _rCurveLine();
        case 25: // rlinecurve
          _rLineCurve();
        case 26: // vvcurveto
          _vvCurveTo();
        case 27: // hhcurveto
          _hhCurveTo();
        case 30: // vhcurveto
          _vhCurveTo();
        case 31: // hvcurveto
          _hvCurveTo();
        case 12: // two-byte operator
          final int b1 = code.readUint8(pos++, 'CharString.escOp');
          _execEscapeOp(b1);
        default:
          throw TexMathFontError('Unsupported Type 2 CharString opcode $b0.');
      }
    }
  }

  void _push(double value) {
    if (!value.isFinite) {
      throw const TexMathFontError(
        'Non-finite numeric value in Type 2 CharString stack.',
      );
    }
    if (_stack.length >= maxStack) {
      throw TexMathFontError(
        'Type 2 CharString stack exceeded limit ($maxStack).',
      );
    }
    _stack.add(value);
  }

  int _popSubrIndex(int count) {
    if (_stack.isEmpty) {
      throw const TexMathFontError('CharString subroutine index underflow.');
    }
    final int biased = cffFiniteInt(_stack.removeLast(), 'CharString.subr');
    final int bias = count < 1240
        ? 107
        : count < 33900
        ? 1131
        : 32768;
    final int index = biased + bias;
    if (index < 0 || index >= count) {
      throw TexMathFontError(
        'CharString subroutine index $index out of bounds ($count).',
      );
    }
    return index;
  }

  void _consumeWidthIfOdd(bool checkWidth) {
    if (!checkWidth || _hasWidth) {
      _hasWidth = true;
      return;
    }
    if (_stack.length.isOdd) {
      _parsedWidth = nominalWidthX + _stack.removeAt(0);
    }
    _hasWidth = true;
  }

  void _consumeWidthForSingleArgMove() {
    if (isCff2 || _hasWidth) {
      _hasWidth = true;
      return;
    }
    if (_stack.length > 1) {
      _parsedWidth = nominalWidthX + _stack.removeAt(0);
    }
    _hasWidth = true;
  }

  void _consumeWidthForTwoArgMove() {
    if (isCff2 || _hasWidth) {
      _hasWidth = true;
      return;
    }
    if (_stack.length > 2) {
      _parsedWidth = nominalWidthX + _stack.removeAt(0);
    }
    _hasWidth = true;
  }

  void _consumeStems(StemOrientation orientation) {
    int i = 0;
    while (i + 1 < _stack.length) {
      if (_stems.length >= _maxStems) {
        throw const TexMathFontError(
          'Type 2 CharString stem hint count exceeded limit.',
        );
      }
      final double dPos = _stack[i];
      final double dWidth = _stack[i + 1];
      if (orientation == StemOrientation.horizontal) {
        final double pos = _hStemPos + dPos;
        _stems.add(
          StemHint(orientation: orientation, position: pos, width: dWidth),
        );
        _hStemPos = pos + dWidth;
      } else {
        final double pos = _vStemPos + dPos;
        _stems.add(
          StemHint(orientation: orientation, position: pos, width: dWidth),
        );
        _vStemPos = pos + dWidth;
      }
      i += 2;
    }
    _stack.clear();
  }

  void _execBlend() {
    final ItemVariationStore? store = variationStore;
    if (store == null) {
      throw const TexMathFontError(
        'CFF2 CharString blend encountered without vstore.',
      );
    }
    if (_stack.isEmpty) {
      throw const TexMathFontError('CFF2 CharString blend operand underflow.');
    }
    final int n = cffFiniteInt(_stack.removeLast(), 'CharString.blend');
    final List<double> scalars = store.scalarsForDataIndex(_vsindex);
    final int k = scalars.length;
    final int needed = n + n * k;
    if (n < 0 || _stack.length < needed) {
      throw TexMathFontError(
        'CFF2 CharString blend underflow: need $needed, have ${_stack.length}.',
      );
    }
    final int baseStart = _stack.length - needed;
    final List<double> blended = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      double val = _stack[baseStart + i];
      final int deltaStart = baseStart + n + i * k;
      for (int r = 0; r < k; r++) {
        val += _stack[deltaStart + r] * scalars[r];
      }
      if (!val.isFinite) {
        throw const TexMathFontError(
          'Non-finite value produced by Type 2 CharString blend.',
        );
      }
      blended[i] = val;
    }
    _stack.removeRange(baseStart, _stack.length);
    _stack.addAll(blended);
  }

  void _addCommand(PathCommand command) {
    if (_commands.length >= _maxCommands) {
      throw const TexMathFontError(
        'Type 2 CharString path command count exceeded limit.',
      );
    }
    _commands.add(command);
  }

  void _closeActiveSubpath() {
    if (_subpathOpen && _subpathHasSegments) {
      _addCommand(const ClosePath());
    }
    _subpathOpen = false;
    _subpathHasSegments = false;
  }

  void _emitMove(double dx, double dy) {
    _closeActiveSubpath();
    _curX += dx;
    _curY += dy;
    if (!_curX.isFinite || !_curY.isFinite) {
      throw const TexMathFontError(
        'Non-finite coordinate in Type 2 CharString move.',
      );
    }
    _addCommand(MoveTo(_curX, _curY));
    _subpathOpen = true;
    _subpathHasSegments = false;
  }

  void _emitLine(double dx, double dy) {
    if (!_subpathOpen) {
      _addCommand(MoveTo(_curX, _curY));
      _subpathOpen = true;
    }
    _curX += dx;
    _curY += dy;
    if (!_curX.isFinite || !_curY.isFinite) {
      throw const TexMathFontError(
        'Non-finite coordinate in Type 2 CharString line.',
      );
    }
    _addCommand(LineTo(_curX, _curY));
    _subpathHasSegments = true;
  }

  void _emitCubic(
    double dx1,
    double dy1,
    double dx2,
    double dy2,
    double dx3,
    double dy3,
  ) {
    if (!_subpathOpen) {
      _addCommand(MoveTo(_curX, _curY));
      _subpathOpen = true;
    }
    final double c1x = _curX + dx1;
    final double c1y = _curY + dy1;
    final double c2x = c1x + dx2;
    final double c2y = c1y + dy2;
    _curX = c2x + dx3;
    _curY = c2y + dy3;
    if (!c1x.isFinite ||
        !c1y.isFinite ||
        !c2x.isFinite ||
        !c2y.isFinite ||
        !_curX.isFinite ||
        !_curY.isFinite) {
      throw const TexMathFontError(
        'Non-finite coordinate in Type 2 CharString curve.',
      );
    }
    _addCommand(CubicTo(c1x, c1y, c2x, c2y, _curX, _curY));
    _subpathHasSegments = true;
  }

  void _rMoveTo() {
    if (_stack.length >= 2) {
      _emitMove(_stack[0], _stack[1]);
    }
    _stack.clear();
  }

  void _hMoveTo() {
    if (_stack.isNotEmpty) {
      _emitMove(_stack[0], 0.0);
    }
    _stack.clear();
  }

  void _vMoveTo() {
    if (_stack.isNotEmpty) {
      _emitMove(0.0, _stack[0]);
    }
    _stack.clear();
  }

  void _rLineTo() {
    for (int i = 0; i + 1 < _stack.length; i += 2) {
      _emitLine(_stack[i], _stack[i + 1]);
    }
    _stack.clear();
  }

  void _hLineTo() {
    bool horiz = true;
    for (int i = 0; i < _stack.length; i++) {
      if (horiz) {
        _emitLine(_stack[i], 0.0);
      } else {
        _emitLine(0.0, _stack[i]);
      }
      horiz = !horiz;
    }
    _stack.clear();
  }

  void _vLineTo() {
    bool horiz = false;
    for (int i = 0; i < _stack.length; i++) {
      if (horiz) {
        _emitLine(_stack[i], 0.0);
      } else {
        _emitLine(0.0, _stack[i]);
      }
      horiz = !horiz;
    }
    _stack.clear();
  }

  void _rrCurveTo() {
    for (int i = 0; i + 5 < _stack.length; i += 6) {
      _emitCubic(
        _stack[i],
        _stack[i + 1],
        _stack[i + 2],
        _stack[i + 3],
        _stack[i + 4],
        _stack[i + 5],
      );
    }
    _stack.clear();
  }

  void _rCurveLine() {
    int i = 0;
    while (i + 7 < _stack.length) {
      _emitCubic(
        _stack[i],
        _stack[i + 1],
        _stack[i + 2],
        _stack[i + 3],
        _stack[i + 4],
        _stack[i + 5],
      );
      i += 6;
    }
    if (i + 1 < _stack.length) {
      _emitLine(_stack[i], _stack[i + 1]);
    }
    _stack.clear();
  }

  void _rLineCurve() {
    int i = 0;
    while (i + 7 < _stack.length) {
      _emitLine(_stack[i], _stack[i + 1]);
      i += 2;
    }
    if (i + 5 < _stack.length) {
      _emitCubic(
        _stack[i],
        _stack[i + 1],
        _stack[i + 2],
        _stack[i + 3],
        _stack[i + 4],
        _stack[i + 5],
      );
    }
    _stack.clear();
  }

  void _vvCurveTo() {
    int i = 0;
    double dx1 = 0.0;
    if (_stack.length % 4 == 1 && _stack.isNotEmpty) {
      dx1 = _stack[0];
      i = 1;
    }
    while (i + 3 < _stack.length) {
      _emitCubic(
        dx1,
        _stack[i],
        _stack[i + 1],
        _stack[i + 2],
        0.0,
        _stack[i + 3],
      );
      dx1 = 0.0;
      i += 4;
    }
    _stack.clear();
  }

  void _hhCurveTo() {
    int i = 0;
    double dy1 = 0.0;
    if (_stack.length % 4 == 1 && _stack.isNotEmpty) {
      dy1 = _stack[0];
      i = 1;
    }
    while (i + 3 < _stack.length) {
      _emitCubic(
        _stack[i],
        dy1,
        _stack[i + 1],
        _stack[i + 2],
        _stack[i + 3],
        0.0,
      );
      dy1 = 0.0;
      i += 4;
    }
    _stack.clear();
  }

  void _hvCurveTo() {
    int i = 0;
    bool horizFirst = true;
    while (i + 3 < _stack.length) {
      final bool isLast = i + 5 >= _stack.length;
      final bool hasExtra = isLast && i + 4 < _stack.length;
      final double extra = hasExtra ? _stack[i + 4] : 0.0;
      if (horizFirst) {
        _emitCubic(
          _stack[i],
          0.0,
          _stack[i + 1],
          _stack[i + 2],
          extra,
          _stack[i + 3],
        );
      } else {
        _emitCubic(
          0.0,
          _stack[i],
          _stack[i + 1],
          _stack[i + 2],
          _stack[i + 3],
          extra,
        );
      }
      i += hasExtra ? 5 : 4;
      horizFirst = !horizFirst;
    }
    _stack.clear();
  }

  void _vhCurveTo() {
    int i = 0;
    bool vertFirst = true;
    while (i + 3 < _stack.length) {
      final bool isLast = i + 5 >= _stack.length;
      final bool hasExtra = isLast && i + 4 < _stack.length;
      final double extra = hasExtra ? _stack[i + 4] : 0.0;
      if (vertFirst) {
        _emitCubic(
          0.0,
          _stack[i],
          _stack[i + 1],
          _stack[i + 2],
          _stack[i + 3],
          extra,
        );
      } else {
        _emitCubic(
          _stack[i],
          0.0,
          _stack[i + 1],
          _stack[i + 2],
          extra,
          _stack[i + 3],
        );
      }
      i += hasExtra ? 5 : 4;
      vertFirst = !vertFirst;
    }
    _stack.clear();
  }

  void _execEscapeOp(int op) {
    switch (op) {
      case 3: // and
        final double b = _pop();
        final double a = _pop();
        _push((a != 0.0 && b != 0.0) ? 1.0 : 0.0);
      case 4: // or
        final double b = _pop();
        final double a = _pop();
        _push((a != 0.0 || b != 0.0) ? 1.0 : 0.0);
      case 5: // not
        final double a = _pop();
        _push(a == 0.0 ? 1.0 : 0.0);
      case 9: // abs
        _push(_pop().abs());
      case 10: // add
        final double b = _pop();
        final double a = _pop();
        _push(a + b);
      case 11: // sub
        final double b = _pop();
        final double a = _pop();
        _push(a - b);
      case 12: // div
        final double b = _pop();
        final double a = _pop();
        _push(b == 0.0 ? 0.0 : a / b);
      case 14: // neg
        _push(-_pop());
      case 15: // eq
        final double b = _pop();
        final double a = _pop();
        _push(a == b ? 1.0 : 0.0);
      case 18: // drop
        if (_stack.isNotEmpty) {
          _stack.removeLast();
        }
      case 20: // put
        final int i = cffFiniteInt(_pop(), 'CharString.put');
        final double val = _pop();
        if (i >= 0 && i < _transient.length) {
          _transient[i] = val;
        }
      case 21: // get
        final int i = cffFiniteInt(_pop(), 'CharString.get');
        _push((i >= 0 && i < _transient.length) ? _transient[i] : 0.0);
      case 22: // ifelse
        final double v2 = _pop();
        final double v1 = _pop();
        final double s2 = _pop();
        final double s1 = _pop();
        _push(v1 <= v2 ? s1 : s2);
      case 23: // random (deterministic per-glyph LCG)
        _rngState = (_rngState * 1664525 + 1013904223) & 0xFFFFFFFF;
        final int low = _rngState == 0 ? 1 : _rngState;
        _push(low / 4294967296.0);
      case 24: // mul
        final double b = _pop();
        final double a = _pop();
        _push(a * b);
      case 26: // sqrt
        final double a = _pop();
        _push(a <= 0.0 ? 0.0 : math.sqrt(a));
      case 27: // dup
        final double a = _pop();
        _push(a);
        _push(a);
      case 28: // exch
        final double b = _pop();
        final double a = _pop();
        _push(b);
        _push(a);
      case 29: // index
        int idx = cffFiniteInt(_pop(), 'CharString.index');
        if (idx < 0) {
          idx = 0;
        }
        if (idx >= _stack.length) {
          throw const TexMathFontError(
            'CharString index operator out of range.',
          );
        }
        _push(_stack[_stack.length - 1 - idx]);
      case 30: // roll
        final int j = cffFiniteInt(_pop(), 'CharString.roll.shift');
        final int n = cffFiniteInt(_pop(), 'CharString.roll.count');
        if (n < 0 || n > _stack.length) {
          throw const TexMathFontError('CharString roll count out of range.');
        }
        if (n > 1) {
          final int shift = ((j % n) + n) % n;
          final int start = _stack.length - n;
          final List<double> slice = _stack.sublist(start);
          for (int i = 0; i < n; i++) {
            _stack[start + i] = slice[(i - shift + n) % n];
          }
        }
      case 34: // hflex
        if (_stack.length < 7) {
          throw const TexMathFontError('CharString hflex underflow.');
        }
        _emitCubic(_stack[0], 0.0, _stack[1], _stack[2], _stack[3], 0.0);
        _emitCubic(_stack[4], 0.0, _stack[5], -_stack[2], _stack[6], 0.0);
        _stack.clear();
      case 35: // flex
        if (_stack.length < 13) {
          throw const TexMathFontError('CharString flex underflow.');
        }
        _emitCubic(
          _stack[0],
          _stack[1],
          _stack[2],
          _stack[3],
          _stack[4],
          _stack[5],
        );
        _emitCubic(
          _stack[6],
          _stack[7],
          _stack[8],
          _stack[9],
          _stack[10],
          _stack[11],
        );
        _stack.clear();
      case 36: // hflex1
        if (_stack.length < 9) {
          throw const TexMathFontError('CharString hflex1 underflow.');
        }
        final double dy6 = -(_stack[1] + _stack[3] + _stack[7]);
        _emitCubic(_stack[0], _stack[1], _stack[2], _stack[3], _stack[4], 0.0);
        _emitCubic(_stack[5], 0.0, _stack[6], _stack[7], _stack[8], dy6);
        _stack.clear();
      case 37: // flex1
        if (_stack.length < 11) {
          throw const TexMathFontError('CharString flex1 underflow.');
        }
        final double sumDx =
            _stack[0] + _stack[2] + _stack[4] + _stack[6] + _stack[8];
        final double sumDy =
            _stack[1] + _stack[3] + _stack[5] + _stack[7] + _stack[9];
        final double dx6;
        final double dy6;
        if (sumDx.abs() > sumDy.abs()) {
          dx6 = _stack[10];
          dy6 = -sumDy;
        } else {
          dx6 = -sumDx;
          dy6 = _stack[10];
        }
        _emitCubic(
          _stack[0],
          _stack[1],
          _stack[2],
          _stack[3],
          _stack[4],
          _stack[5],
        );
        _emitCubic(_stack[6], _stack[7], _stack[8], _stack[9], dx6, dy6);
        _stack.clear();
      default:
        throw TexMathFontError(
          'Unsupported Type 2 CharString escape operator (12, $op).',
        );
    }
  }

  double _pop() {
    if (_stack.isEmpty) {
      throw const TexMathFontError(
        'Type 2 CharString operand stack underflow.',
      );
    }
    return _stack.removeLast();
  }
}
