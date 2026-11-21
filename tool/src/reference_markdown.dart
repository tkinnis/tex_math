import 'dart:io';

/// Extracts a pinned semver value for [key] from a Markdown table or bullet
/// entry in [content].
String? extractReferenceVersion(String content, String key) {
  final RegExp tableRowPattern = RegExp(
    '^\\|[^|\\n]*`${RegExp.escape(key)}`[^|\\n]*\\|[^|\\n]*`([0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?)`',
    multiLine: true,
  );
  final RegExpMatch? rowMatch = tableRowPattern.firstMatch(content);
  if (rowMatch != null) {
    return rowMatch.group(1);
  }
  final RegExp bulletPattern = RegExp(
    '^[-*]\\s+[^\\n]*`${RegExp.escape(key)}`[^\\n]*`([0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?)`',
    multiLine: true,
  );
  final RegExpMatch? bulletMatch = bulletPattern.firstMatch(content);
  return bulletMatch?.group(1);
}

/// Extracts the SHA-256 hex digest recorded for `package-lock.json` in
/// [content].
String? extractLockfileSha256(String content) {
  final RegExp rowPattern = RegExp(
    r'package-lock\.json[^\n]*`([0-9a-fA-F]{64})`',
  );
  final RegExpMatch? match = rowPattern.firstMatch(content);
  return match?.group(1);
}

/// Reads [path] and extracts a pinned version for [key], or returns `null` if
/// the file does not exist or has no matching entry.
String? readReferenceVersionFromFile(String path, String key) {
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return extractReferenceVersion(file.readAsStringSync(), key);
}
