import '../ast.dart';
import '../font.dart';
import '../parser/symbol_map.dart';

/// Resolves both the effective code point and glyph ID for [baseCodePoint]
/// without duplicate `cmap` binary searches when variant mapping succeeds.
(int, int) resolveMathGlyphCodePointAndId({
  required int baseCodePoint,
  required MathFont font,
  TexMathFontVariant? variant,
  bool isTextMode = false,
}) {
  if (isTextMode) {
    if (variant == null ||
        variant == TexMathFontVariant.normal ||
        variant == TexMathFontVariant.italic) {
      return (baseCodePoint, font.glyphIdForCodePoint(baseCodePoint));
    }
    final int mapped = mathUnicodeCodePoint(baseCodePoint, variant);
    if (mapped != baseCodePoint) {
      final int gid = font.glyphIdForCodePoint(mapped);
      if (gid != 0) {
        return (mapped, gid);
      }
    }
    return (baseCodePoint, font.glyphIdForCodePoint(baseCodePoint));
  }

  if (baseCodePoint == 0x002D &&
      (variant == null || variant == TexMathFontVariant.normal)) {
    final int gid = font.glyphIdForCodePoint(0x2212);
    if (gid != 0) {
      return (0x2212, gid);
    }
  }

  final TexMathFontVariant? effectiveVariant =
      variant ?? defaultMathVariantForCodePoint(baseCodePoint);

  if (baseCodePoint == 0x0131 &&
      (effectiveVariant == null ||
          effectiveVariant == TexMathFontVariant.italic)) {
    final int gid = font.glyphIdForCodePoint(0x1D6A4);
    if (gid != 0) {
      return (0x1D6A4, gid);
    }
    return (0x0131, font.glyphIdForCodePoint(0x0131));
  }
  if (baseCodePoint == 0x0237 &&
      (effectiveVariant == null ||
          effectiveVariant == TexMathFontVariant.italic)) {
    final int gid = font.glyphIdForCodePoint(0x1D6A5);
    if (gid != 0) {
      return (0x1D6A5, gid);
    }
    return (0x0237, font.glyphIdForCodePoint(0x0237));
  }

  if (effectiveVariant == null) {
    return (baseCodePoint, font.glyphIdForCodePoint(baseCodePoint));
  }

  final int mapped = mathUnicodeCodePoint(baseCodePoint, effectiveVariant);
  if (mapped != baseCodePoint) {
    final int gid = font.glyphIdForCodePoint(mapped);
    if (gid != 0) {
      return (mapped, gid);
    }
  }
  return (baseCodePoint, font.glyphIdForCodePoint(baseCodePoint));
}

/// Returns the default TeX math font variant for [cp], or `null` when upright.
TexMathFontVariant? defaultMathVariantForCodePoint(int cp) {
  if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) {
    return TexMathFontVariant.italic;
  }
  if ((cp >= 0x03B1 && cp <= 0x03C9) ||
      cp == 0x03D1 ||
      cp == 0x03D5 ||
      cp == 0x03D6 ||
      cp == 0x03F0 ||
      cp == 0x03F1 ||
      cp == 0x03F5 ||
      cp == 0x2202) {
    return TexMathFontVariant.italic;
  }
  return null;
}

/// Decodes a string containing exactly one Unicode scalar code point without
/// allocating a `.runes.toList()` buffer, or returns `null` otherwise.
int? singleCodePointOrNull(String value) {
  final int len = value.length;
  if (len == 1) {
    return value.codeUnitAt(0);
  }
  if (len == 2) {
    final int u0 = value.codeUnitAt(0);
    if (u0 >= 0xD800 && u0 <= 0xDBFF) {
      final int u1 = value.codeUnitAt(1);
      if (u1 >= 0xDC00 && u1 <= 0xDFFF) {
        return 0x10000 + ((u0 - 0xD800) << 10) + (u1 - 0xDC00);
      }
    }
  }
  return null;
}

/// Returns the first Unicode scalar code point of [value], or [fallback] if
/// [value] is empty.
int firstCodePointOr(String value, int fallback) {
  if (value.isEmpty) {
    return fallback;
  }
  final int u0 = value.codeUnitAt(0);
  if (u0 >= 0xD800 && u0 <= 0xDBFF && value.length > 1) {
    final int u1 = value.codeUnitAt(1);
    if (u1 >= 0xDC00 && u1 <= 0xDFFF) {
      return 0x10000 + ((u0 - 0xD800) << 10) + (u1 - 0xDC00);
    }
  }
  return u0;
}
