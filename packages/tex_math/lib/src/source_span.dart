import 'package:meta/meta.dart';

/// Half-open UTF-16 code-unit range `[start, end)` within a TeX source string.
@immutable
final class SourceSpan {
  /// Creates a source span covering `[start, end)`.
  const SourceSpan(this.start, this.end)
    : assert(start >= 0, 'start must be non-negative'),
      assert(end >= start, 'end must be >= start');

  /// Creates a zero-length span at [offset].
  const SourceSpan.empty([int offset = 0])
    : assert(offset >= 0, 'offset must be non-negative'),
      start = offset,
      end = offset;

  /// Canonical empty span at index `0`.
  static const SourceSpan zero = SourceSpan(0, 0);

  /// Inclusive start index in UTF-16 code units.
  final int start;

  /// Exclusive end index in UTF-16 code units.
  final int end;

  /// Number of UTF-16 code units covered by this span.
  int get length => end - start;

  /// Whether this span covers zero code units.
  bool get isEmpty => start == end;

  /// Extracts the substring covered by this span from [source].
  String slice(String source) {
    RangeError.checkValidRange(start, end, source.length);
    return source.substring(start, end);
  }

  /// Returns the smallest span enclosing both `this` and [other].
  SourceSpan merge(SourceSpan other) {
    final int mergedStart = start < other.start ? start : other.start;
    final int mergedEnd = end > other.end ? end : other.end;
    return SourceSpan(mergedStart, mergedEnd);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceSpan && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SourceSpan($start, $end)';
}
