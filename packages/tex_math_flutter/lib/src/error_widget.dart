import 'package:flutter/material.dart';
import 'package:tex_math/tex_math.dart';

import 'theme.dart';

/// Default fallback widget displaying the original TeX [source] in a monospace
/// code style alongside the diagnostic error message.
final class TexMathErrorWidget extends StatelessWidget {
  /// Creates a TeX error fallback widget.
  const TexMathErrorWidget({
    super.key,
    required this.source,
    this.error,
    this.errorMessage,
    this.displayMode = TexMathDisplayMode.inline,
    this.selectable = true,
  });

  /// Original TeX math source that failed to parse or lay out.
  final String source;

  /// Optional structured [TexMathError] associated with this failure.
  final TexMathError? error;

  /// Optional explicit error message overriding [error]?.message.
  final String? errorMessage;

  /// Display mode controlling inline vs block padding and layout.
  final TexMathDisplayMode displayMode;

  /// Whether the displayed source and error text can be selected when not
  /// already wrapped in an ancestor [SelectionContainer].
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final TexMathThemeData theme = TexMathTheme.of(context);
    final String resolvedMessage =
        errorMessage ?? error?.message ?? 'Unable to render TeX expression.';
    final bool isDisplay = displayMode == TexMathDisplayMode.display;
    final Color background =
        theme.errorBackground ?? theme.error.withValues(alpha: 0.08);

    final Widget content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDisplay ? 12.0 : 6.0,
        vertical: isDisplay ? 8.0 : 3.0,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: theme.error.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            source,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: isDisplay ? 14.0 : 12.0,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 2.0),
          Text(
            resolvedMessage,
            style: TextStyle(
              fontSize: isDisplay ? 12.0 : 11.0,
              color: theme.error,
            ),
          ),
        ],
      ),
    );

    final Widget maybeSelectable =
        selectable && SelectionContainer.maybeOf(context) == null
        ? SelectionArea(child: content)
        : content;

    return Semantics(
      label: 'TeX error for $source: $resolvedMessage',
      readOnly: true,
      child: maybeSelectable,
    );
  }
}
