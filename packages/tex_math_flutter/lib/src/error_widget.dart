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

  /// Optional explicit error message overriding [error]?.formattedMessage.
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
        errorMessage ??
        error?.formattedMessage ??
        'Unable to render TeX expression.';
    final bool isDisplay = displayMode == TexMathDisplayMode.display;
    final Color background =
        theme.errorBackground ?? theme.error.withValues(alpha: 0.08);
    final TextStyle baseSourceStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: isDisplay ? 14.0 : 12.0,
      color: theme.foreground,
    );

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
          _buildSourceWidget(theme: theme, baseSourceStyle: baseSourceStyle),
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

    final bool hasAncestorSelection =
        SelectionContainer.maybeOf(context) != null;
    final Widget maybeSelectable;
    if (selectable) {
      maybeSelectable = hasAncestorSelection
          ? content
          : SelectionArea(child: content);
    } else {
      maybeSelectable = hasAncestorSelection
          ? SelectionContainer.disabled(child: content)
          : content;
    }

    return Semantics(
      label: 'TeX error for $source: $resolvedMessage',
      readOnly: true,
      excludeSemantics: true,
      child: maybeSelectable,
    );
  }

  Widget _buildSourceWidget({
    required TexMathThemeData theme,
    required TextStyle baseSourceStyle,
  }) {
    final SourceSpan? span = error?.span;
    if (span == null || source.isEmpty) {
      return Text(source, style: baseSourceStyle);
    }

    final int start = span.start.clamp(0, source.length);
    final int end = span.end.clamp(start, source.length);
    final TextStyle highlightStyle = TextStyle(
      color: theme.error,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationColor: theme.error,
      backgroundColor: theme.error.withValues(alpha: 0.16),
    );

    final List<InlineSpan> spans = <InlineSpan>[
      if (start > 0) TextSpan(text: source.substring(0, start)),
      if (end > start)
        TextSpan(text: source.substring(start, end), style: highlightStyle)
      else
        TextSpan(
          text: '‸',
          style: TextStyle(
            color: theme.error,
            fontWeight: FontWeight.w700,
            backgroundColor: theme.error.withValues(alpha: 0.16),
          ),
        ),
      if (end < source.length) TextSpan(text: source.substring(end)),
    ];

    return Text.rich(
      TextSpan(style: baseSourceStyle, children: spans),
      style: baseSourceStyle,
    );
  }
}
