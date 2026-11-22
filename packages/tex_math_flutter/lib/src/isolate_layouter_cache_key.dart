import 'package:flutter/foundation.dart';
import 'package:tex_math/tex_math.dart';

/// Deterministic cache key identifying a `(source, options, fontId, fontSignature)`
/// render.
@immutable
final class TexMathLayoutCacheKey {
  /// Creates a layout cache key with precomputed [hashCode].
  TexMathLayoutCacheKey({
    required this.source,
    required this.options,
    required this.fontId,
    this.fontSignature,
  }) : _hashCode = Object.hash(source, options, fontId, fontSignature);

  /// TeX math source expression.
  final String source;

  /// Effective rendering and budget options.
  final TexMathOptions options;

  /// Identifier of the active math font.
  final String fontId;

  /// Optional [MathFont.signature] distinguishing explicit fonts from the
  /// layouter's default configured font.
  final int? fontSignature;

  final int _hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathLayoutCacheKey &&
          _hashCode == other._hashCode &&
          source == other.source &&
          options == other.options &&
          fontId == other.fontId &&
          fontSignature == other.fontSignature;

  @override
  int get hashCode => _hashCode;

  @override
  String toString() =>
      'TexMathLayoutCacheKey(fontId: $fontId, '
      'fontSignature: $fontSignature, sourceLength: ${source.length})';
}
