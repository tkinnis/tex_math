import '../ast.dart';
import '../font.dart';
import '../shared/math_symbols.dart';

export '../shared/math_symbols.dart'
    show
        defaultMathVariantForCodePoint,
        firstCodePointOr,
        singleCodePointOrNull;

/// Resolves both the effective code point and glyph ID for [baseCodePoint]
/// without duplicate `cmap` binary searches when variant mapping succeeds.
(int, int) resolveMathGlyphCodePointAndId({
  required int baseCodePoint,
  required MathFont font,
  TexMathFontVariant? variant,
  bool isTextMode = false,
}) {
  if (isTextMode) {
    if (variant == null || variant == TexMathFontVariant.normal) {
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
