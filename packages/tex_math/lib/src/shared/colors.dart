import '../error.dart';
import '../options.dart';

/// Named TeX colors normalized to `#RRGGBB` hex values.
const Map<String, String> standardTexColors = <String, String>{
  'black': '#000000',
  'blue': '#0000FF',
  'brown': '#A52A2A',
  'cyan': '#00FFFF',
  'darkgray': '#A9A9A9',
  'gray': '#808080',
  'green': '#008000',
  'lightblue': '#ADD8E6',
  'lightgray': '#D3D3D3',
  'lime': '#00FF00',
  'magenta': '#FF00FF',
  'olive': '#808000',
  'orange': '#FFA500',
  'pink': '#FFC0CB',
  'purple': '#800080',
  'red': '#FF0000',
  'teal': '#008080',
  'violet': '#EE82EE',
  'white': '#FFFFFF',
  'yellow': '#FFFF00',
  'lavender': '#E6E6FA',
  'crimson': '#DC143C',
  'navy': '#000080',
  'silver': '#C0C0C0',
  'maroon': '#800000',
  'aqua': '#00FFFF',
  'fuchsia': '#FF00FF',
};

final RegExp _hexColorPattern = RegExp(
  r'^#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$',
);
final RegExp _namedColorPattern = RegExp(r'^[a-zA-Z]{1,32}$');
final RegExp _funcColorPattern = RegExp(
  r'^(?:rgb|rgba|hsl|hsla)\(\s*[0-9.+%\s,/]+\)$',
  caseSensitive: false,
);
final RegExp _htmlDigitsPattern = RegExp(
  r'^(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$',
);

/// Default SVG/display fallback hex palette for semantic [TexMathColorRole]s.
String defaultRoleColorHex(TexMathColorRole role) {
  switch (role) {
    case TexMathColorRole.foreground:
    case TexMathColorRole.custom:
      return '#111827';
    case TexMathColorRole.accent:
      return '#2563EB';
    case TexMathColorRole.error:
      return '#DC2626';
    case TexMathColorRole.muted:
      return '#6B7280';
  }
}

/// Resolves a TeX color expression (`name`, `rgb`, `RGB`, `HTML`, `gray`) into
/// a normalized CSS/hex color string.
String resolveTexColor(
  String colorSpec, {
  String model = '',
  Map<String, String> customColors = const <String, String>{},
}) {
  final String normalizedModel = model.trim().toLowerCase();
  final String spec = colorSpec.trim();

  if (normalizedModel == 'rgb') {
    final List<String> parts = spec.split(',');
    if (parts.length == 3) {
      final int r = _floatToChannel(parts[0]);
      final int g = _floatToChannel(parts[1]);
      final int b = _floatToChannel(parts[2]);
      return '#${_hexByte(r)}${_hexByte(g)}${_hexByte(b)}';
    }
  } else if (normalizedModel == 'html') {
    final String cleaned = spec.startsWith('#') ? spec.substring(1) : spec;
    if (!_htmlDigitsPattern.hasMatch(cleaned)) {
      throw TexMathSyntaxError(
        'Invalid HTML hex color specification "$colorSpec".',
        errorClass: TexMathErrorClass.syntaxError,
      );
    }
    return '#${cleaned.toUpperCase()}';
  } else if (normalizedModel == 'gray') {
    final int c = _floatToChannel(spec);
    return '#${_hexByte(c)}${_hexByte(c)}${_hexByte(c)}';
  } else if (model.trim() == 'RGB') {
    final List<String> parts = spec.split(',');
    if (parts.length == 3) {
      final int r = (int.tryParse(parts[0].trim()) ?? 0).clamp(0, 255);
      final int g = (int.tryParse(parts[1].trim()) ?? 0).clamp(0, 255);
      final int b = (int.tryParse(parts[2].trim()) ?? 0).clamp(0, 255);
      return '#${_hexByte(r)}${_hexByte(g)}${_hexByte(b)}';
    }
  }

  final String lower = spec.toLowerCase();
  final String? custom = customColors[lower] ?? customColors[spec];
  if (custom != null) {
    return custom;
  }
  final String? named = standardTexColors[lower];
  if (named != null) {
    return named;
  }
  if (spec.startsWith('#')) {
    return spec.toUpperCase();
  }
  return spec;
}

/// Validates and returns a safe CSS color literal suitable for MathML
/// `mathcolor`/`mathbackground` attributes, or `null` if invalid or unsafe.
String? sanitizeMathMlColor(String? raw) {
  if (raw == null) {
    return null;
  }
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (_hexColorPattern.hasMatch(trimmed) ||
      _namedColorPattern.hasMatch(trimmed) ||
      _funcColorPattern.hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

final RegExp _uriSchemePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');

/// Returns whether [rawUri] uses a safe allowlisted scheme (`http`, `https`,
/// `mailto`, `#` fragment, or relative path without scheme) and contains no
/// control characters.
bool isSafeHrefUri(String rawUri) {
  final String trimmed = rawUri.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  for (int i = 0; i < trimmed.length; i++) {
    final int cu = trimmed.codeUnitAt(i);
    if (cu < 0x20 || cu == 0x7F) {
      return false;
    }
  }
  if (trimmed.startsWith('#')) {
    return true;
  }
  if (trimmed.startsWith('//')) {
    return false;
  }
  final RegExpMatch? match = _uriSchemePattern.firstMatch(trimmed);
  if (match != null) {
    final String scheme = match.group(1)!.toLowerCase();
    return scheme == 'http' || scheme == 'https' || scheme == 'mailto';
  }
  // Reject colon prior to `/`, `?`, `#` in non-scheme-prefix forms like
  // obfuscated `java\tscript:` or unknown scheme syntax.
  for (int i = 0; i < trimmed.length; i++) {
    final int cu = trimmed.codeUnitAt(i);
    if (cu == 0x2F || cu == 0x3F || cu == 0x23) {
      break;
    }
    if (cu == 0x3A) {
      return false;
    }
  }
  return true;
}

/// Resolves a TeX or CSS color specification (such as `red`, `#2563EB`, or
/// `#f00`) into a 32-bit ARGB integer, or `null` when unrecognized.
int? resolveColorSpecArgb(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  final int? direct = _parseHexArgb(raw);
  if (direct != null) {
    return direct;
  }
  final String resolved = resolveTexColor(raw.trim());
  return _parseHexArgb(resolved);
}

int? _parseHexArgb(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  String hex = raw.trim();
  if (hex.startsWith('#')) {
    hex = hex.substring(1);
  }
  if (hex.length == 3) {
    final String r = hex[0];
    final String g = hex[1];
    final String b = hex[2];
    hex = '$r$r$g$g$b$b';
  }
  if (hex.length == 6) {
    final int? rgb = int.tryParse(hex, radix: 16);
    return rgb != null ? (0xFF000000 | rgb) : null;
  }
  if (hex.length == 8) {
    return int.tryParse(hex, radix: 16);
  }
  return null;
}

int _floatToChannel(String raw) {
  final double? value = double.tryParse(raw.trim());
  if (value == null) {
    return 0;
  }
  if (!value.isFinite) {
    throw TexMathSyntaxError(
      'Non-finite color channel value "$raw".',
      errorClass: TexMathErrorClass.syntaxError,
    );
  }
  return (value * 255.0).round().clamp(0, 255);
}

String _hexByte(int value) =>
    value.toRadixString(16).padLeft(2, '0').toUpperCase();
