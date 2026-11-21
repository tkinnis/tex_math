import 'package:meta/meta.dart';

/// Semantic classification of a potential line-breaking opportunity in math.
enum MathBreakKind {
  /// No automatic line break opportunity attached to this box.
  none,

  /// Discretionary break opportunity immediately after a binary operator.
  afterBinary,

  /// Discretionary break opportunity immediately after a relation symbol.
  afterRelation,

  /// Explicit numeric break penalty attached to a box.
  penalty,

  /// Explicit forced line break (such as `\\` in multiline structures).
  explicit,
}

/// Line-breaking metadata attached to laid-out boxes for downstream wrapping.
@immutable
final class BreakPoint {
  /// Creates break-hint metadata describing whether and how a line break may
  /// occur at this box boundary.
  const BreakPoint({
    this.kind = MathBreakKind.none,
    this.penalty = 0,
    this.isExplicit = false,
    this.isGood = false,
  });

  /// Sentinel representing the absence of any break hint.
  static const BreakPoint none = BreakPoint();

  /// Category of this break hint.
  final MathBreakKind kind;

  /// TeX-style line-breaking penalty value (`0` for neutral).
  final int penalty;

  /// Whether this break point forces a mandatory line break.
  final bool isExplicit;

  /// Whether this break point represents a preferred break site.
  final bool isGood;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BreakPoint &&
          kind == other.kind &&
          penalty == other.penalty &&
          isExplicit == other.isExplicit &&
          isGood == other.isGood;

  @override
  int get hashCode => Object.hash(kind, penalty, isExplicit, isGood);

  @override
  String toString() =>
      'BreakPoint(kind: $kind, penalty: $penalty, '
      'isExplicit: $isExplicit, isGood: $isGood)';
}
