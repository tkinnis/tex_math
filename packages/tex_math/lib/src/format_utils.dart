/// Internal pure-Dart number, hex, and XML formatting utilities avoiding
/// intermediate string and `RegExp` allocations on hot export paths.
library;

const String _upperHexDigits = '0123456789ABCDEF';

/// Writes [value] formatted with up to 4 decimal places (stripping trailing
/// fractional zeros, normalizing non-finite values and `-0` to `0`) directly
/// into [buffer].
void writeFormattedNumber(StringBuffer buffer, double value) {
  if (!value.isFinite || value == 0.0) {
    buffer.write('0');
    return;
  }
  final double absVal = value < 0 ? -value : value;
  if (absVal < 9007199254740992.0 && value == value.truncateToDouble()) {
    buffer.write(value.toInt());
    return;
  }
  if (absVal < 1e7) {
    final double scaled = value * 10000.0;
    final double frac = scaled - scaled.floorToDouble();
    // Stay away from 0.5 rounding boundaries where 10000x scaling could differ
    // by 0.5 ULP from double.toStringAsFixed(4).
    if ((frac - 0.5).abs() > 1e-3) {
      int fixed10k = scaled.round();
      if (fixed10k == 0) {
        buffer.write('0');
        return;
      }
      if (fixed10k < 0) {
        buffer.writeCharCode(0x2D); // '-'
        fixed10k = -fixed10k;
      }
      final int intPart = fixed10k ~/ 10000;
      final int fracPart = fixed10k % 10000;
      buffer.write(intPart);
      if (fracPart != 0) {
        buffer.writeCharCode(0x2E); // '.'
        final int d1 = fracPart ~/ 1000;
        final int r1 = fracPart % 1000;
        buffer.writeCharCode(0x30 + d1);
        if (r1 != 0) {
          final int d2 = r1 ~/ 100;
          final int r2 = r1 % 100;
          buffer.writeCharCode(0x30 + d2);
          if (r2 != 0) {
            final int d3 = r2 ~/ 10;
            final int d4 = r2 % 10;
            buffer.writeCharCode(0x30 + d3);
            if (d4 != 0) {
              buffer.writeCharCode(0x30 + d4);
            }
          }
        }
      }
      return;
    }
  }

  final String fixed = value.toStringAsFixed(4);
  final int dotIndex = fixed.indexOf('.');
  if (dotIndex < 0) {
    buffer.write(fixed);
    return;
  }
  int end = fixed.length;
  while (end > dotIndex + 1 && fixed.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  if (end == dotIndex + 1) {
    end = dotIndex;
  }
  if (end == 2 && fixed.codeUnitAt(0) == 0x2D && fixed.codeUnitAt(1) == 0x30) {
    buffer.write('0');
    return;
  }
  if (end == fixed.length) {
    buffer.write(fixed);
  } else {
    buffer.write(fixed.substring(0, end));
  }
}

/// Formats [value] with up to 4 decimal places using [writeFormattedNumber].
String formatTrimmedNumber(double value) {
  final StringBuffer buffer = StringBuffer();
  writeFormattedNumber(buffer, value);
  return buffer.toString();
}

/// Writes `0x<HEX>` for [codePoint] directly into [buffer].
void writeUpperHexCodePoint(StringBuffer buffer, int codePoint) {
  buffer.write('0x');
  if (codePoint == 0) {
    buffer.writeCharCode(0x30);
    return;
  }
  if (codePoint < 0 || codePoint > 0xFFFFFFFF) {
    buffer.write(codePoint.toRadixString(16).toUpperCase());
    return;
  }
  int shift = 28;
  while (shift > 0 && ((codePoint >> shift) & 0xF) == 0) {
    shift -= 4;
  }
  while (shift >= 0) {
    buffer.writeCharCode(
      _upperHexDigits.codeUnitAt((codePoint >> shift) & 0xF),
    );
    shift -= 4;
  }
}

/// Writes `#RRGGBB` uppercase hex for [argb] directly into [buffer].
void writeCssHexRgb(StringBuffer buffer, int argb) {
  buffer
    ..writeCharCode(0x23) // '#'
    ..writeCharCode(_upperHexDigits.codeUnitAt((argb >> 20) & 0xF))
    ..writeCharCode(_upperHexDigits.codeUnitAt((argb >> 16) & 0xF))
    ..writeCharCode(_upperHexDigits.codeUnitAt((argb >> 12) & 0xF))
    ..writeCharCode(_upperHexDigits.codeUnitAt((argb >> 8) & 0xF))
    ..writeCharCode(_upperHexDigits.codeUnitAt((argb >> 4) & 0xF))
    ..writeCharCode(_upperHexDigits.codeUnitAt(argb & 0xF));
}

/// Writes XML-escaped text (`&`, `<`, `>`) directly into [buffer].
void writeEscapedXmlText(StringBuffer buffer, String value) {
  int start = 0;
  final int len = value.length;
  for (int i = 0; i < len; i++) {
    final String? entity = switch (value.codeUnitAt(i)) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      _ => null,
    };
    if (entity != null) {
      if (i > start) {
        buffer.write(value.substring(start, i));
      }
      buffer.write(entity);
      start = i + 1;
    }
  }
  if (start == 0) {
    buffer.write(value);
  } else if (start < len) {
    buffer.write(value.substring(start));
  }
}

/// Writes XML-escaped attribute text (`&`, `<`, `>`, `"`, `'`) into [buffer].
void writeEscapedXmlAttr(StringBuffer buffer, String value) {
  int start = 0;
  final int len = value.length;
  for (int i = 0; i < len; i++) {
    final String? entity = switch (value.codeUnitAt(i)) {
      0x26 => '&amp;',
      0x3C => '&lt;',
      0x3E => '&gt;',
      0x22 => '&quot;',
      0x27 => '&#39;',
      _ => null,
    };
    if (entity != null) {
      if (i > start) {
        buffer.write(value.substring(start, i));
      }
      buffer.write(entity);
      start = i + 1;
    }
  }
  if (start == 0) {
    buffer.write(value);
  } else if (start < len) {
    buffer.write(value.substring(start));
  }
}

/// Returns [value] escaped for XML text or attributes, returning [value]
/// directly with zero allocations when no special characters appear.
String escapeXmlAttr(String value) {
  final int len = value.length;
  for (int i = 0; i < len; i++) {
    final int cu = value.codeUnitAt(i);
    if (cu == 0x26 || cu == 0x3C || cu == 0x3E || cu == 0x22 || cu == 0x27) {
      final StringBuffer buffer = StringBuffer();
      writeEscapedXmlAttr(buffer, value);
      return buffer.toString();
    }
  }
  return value;
}
