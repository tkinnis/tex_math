import 'package:flutter/material.dart';
import 'package:tex_math/tex_math.dart';

/// Immutable theme values governing math glyph colors, accent rules, error
/// presentation, and base font sizing in Flutter widgets.
@immutable
final class TexMathThemeData {
  /// Creates a math theme configuration.
  const TexMathThemeData({
    required this.foreground,
    required this.accent,
    required this.error,
    required this.muted,
    this.errorBackground,
    this.fontSize = 18.0,
  });

  /// Derives a [TexMathThemeData] from a Material [ColorScheme].
  factory TexMathThemeData.fromColorScheme(
    ColorScheme scheme, {
    double fontSize = 18.0,
  }) {
    return TexMathThemeData(
      foreground: scheme.onSurface,
      accent: scheme.primary,
      error: scheme.error,
      muted: scheme.onSurfaceVariant,
      errorBackground: scheme.errorContainer.withValues(alpha: 0.25),
      fontSize: fontSize,
    );
  }

  /// Default fallback theme used when no ancestor theme is provided.
  static const TexMathThemeData fallback = TexMathThemeData(
    foreground: Color(0xFF111827),
    accent: Color(0xFF2563EB),
    error: Color(0xFFDC2626),
    muted: Color(0xFF6B7280),
    errorBackground: Color(0xFFFEF2F2),
    fontSize: 18.0,
  );

  /// Primary foreground color for glyphs and rules.
  final Color foreground;

  /// Accent color for [TexMathColorRole.accent].
  final Color accent;

  /// Diagnostic color for [TexMathColorRole.error] and error borders.
  final Color error;

  /// Secondary muted color for [TexMathColorRole.muted].
  final Color muted;

  /// Optional container background tint for `TexMathErrorWidget`.
  final Color? errorBackground;

  /// Default logical font size when not overridden by an ambient [TextStyle].
  final double fontSize;

  /// Resolves the Flutter [Color] corresponding to [role] and an optional
  /// 32-bit ARGB [customColorValue].
  Color colorForRole(TexMathColorRole role, {int? customColorValue}) {
    if (role == TexMathColorRole.custom && customColorValue != null) {
      return Color(customColorValue);
    }
    switch (role) {
      case TexMathColorRole.foreground:
        return foreground;
      case TexMathColorRole.accent:
        return accent;
      case TexMathColorRole.error:
        return error;
      case TexMathColorRole.muted:
        return muted;
      case TexMathColorRole.custom:
        return foreground;
    }
  }

  /// Returns a copy of this theme data with selected fields replaced.
  TexMathThemeData copyWith({
    Color? foreground,
    Color? accent,
    Color? error,
    Color? muted,
    Color? errorBackground,
    double? fontSize,
  }) {
    return TexMathThemeData(
      foreground: foreground ?? this.foreground,
      accent: accent ?? this.accent,
      error: error ?? this.error,
      muted: muted ?? this.muted,
      errorBackground: errorBackground ?? this.errorBackground,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  /// Linearly interpolates between two [TexMathThemeData] instances.
  static TexMathThemeData lerp(
    TexMathThemeData a,
    TexMathThemeData b,
    double t,
  ) {
    return TexMathThemeData(
      foreground: Color.lerp(a.foreground, b.foreground, t) ?? b.foreground,
      accent: Color.lerp(a.accent, b.accent, t) ?? b.accent,
      error: Color.lerp(a.error, b.error, t) ?? b.error,
      muted: Color.lerp(a.muted, b.muted, t) ?? b.muted,
      errorBackground: Color.lerp(a.errorBackground, b.errorBackground, t),
      fontSize: a.fontSize + (b.fontSize - a.fontSize) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TexMathThemeData &&
          foreground == other.foreground &&
          accent == other.accent &&
          error == other.error &&
          muted == other.muted &&
          errorBackground == other.errorBackground &&
          fontSize == other.fontSize;

  @override
  int get hashCode =>
      Object.hash(foreground, accent, error, muted, errorBackground, fontSize);
}

/// Inherited theme supplying [TexMathThemeData] to descendant math widgets.
final class TexMathTheme extends InheritedTheme {
  /// Creates an inherited math theme wrapping [child].
  const TexMathTheme({super.key, required this.data, required super.child});

  /// Theme colors and typography settings propagated to descendants.
  final TexMathThemeData data;

  /// Returns the closest [TexMathThemeData] ancestor, falling back to the
  /// active Material [ColorScheme].
  static TexMathThemeData of(BuildContext context) {
    final TexMathTheme? inherited = context
        .dependOnInheritedWidgetOfExactType<TexMathTheme>();
    if (inherited != null) {
      return inherited.data;
    }
    return TexMathThemeData.fromColorScheme(Theme.of(context).colorScheme);
  }

  /// Returns the closest [TexMathThemeData] ancestor, or `null` if absent.
  static TexMathThemeData? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TexMathTheme>()?.data;
  }

  @override
  Widget wrap(BuildContext context, Widget child) {
    return TexMathTheme(data: data, child: child);
  }

  @override
  bool updateShouldNotify(TexMathTheme oldWidget) => data != oldWidget.data;
}

/// Validates [fontSize] as a positive finite logical pixel size, falling back
/// to [theme]'s font size and finally [TexMathThemeData.fallback].
double resolveSafeTexMathFontSize(double? fontSize, {TexMathThemeData? theme}) {
  if (fontSize != null && fontSize.isFinite && fontSize > 0.0) {
    return fontSize;
  }
  final double? themeSize = theme?.fontSize;
  if (themeSize != null && themeSize.isFinite && themeSize > 0.0) {
    return themeSize;
  }
  return TexMathThemeData.fallback.fontSize;
}
