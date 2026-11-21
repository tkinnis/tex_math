import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

/// Loaded New Computer Modern Math font payload and associated GUST license.
@immutable
final class TexMathFontAsset {
  /// Creates a loaded font asset record.
  const TexMathFontAsset({
    required this.bytes,
    required this.familyName,
    required this.assetPath,
    required this.licenseText,
  });

  /// Raw OpenType SFNT bytes.
  final Uint8List bytes;

  /// OpenType font family identifier.
  final String familyName;

  /// Flutter package asset key from which [bytes] were loaded.
  final String assetPath;

  /// Bundled GUST Font License text.
  final String licenseText;

  /// Number of bytes in [bytes].
  int get byteLength => bytes.length;

  /// Whether [bytes] starts with the `OTTO` OpenType CFF signature.
  bool get hasOttoHeader =>
      bytes.length >= 4 &&
      bytes[0] == 0x4F &&
      bytes[1] == 0x54 &&
      bytes[2] == 0x54 &&
      bytes[3] == 0x4F;

  /// Attempts to decode [bytes] into a pure-Dart [MathFont].
  ///
  /// Throws [TexMathUnsupportedError] in Phase 1 before full OpenType `MATH`
  /// table decoding is enabled.
  MathFont decodeMathFont() => MathFont.fromBytes(bytes);
}

/// Loads and caches the bundled `NewCMMath-Regular.otf` asset once per
/// application lifecycle.
final class TexMathFontBundle {
  TexMathFontBundle._();

  /// Owning Flutter package name for bundled asset keys.
  static const String packageName = 'tex_math_flutter';

  /// Package asset path for `NewCMMath-Regular.otf`.
  static const String fontAssetPath =
      'packages/$packageName/assets/fonts/NewCMMath-Regular.otf';

  /// Package asset path for `GUST-FONT-LICENSE.txt`.
  static const String licenseAssetPath =
      'packages/$packageName/assets/fonts/GUST-FONT-LICENSE.txt';

  /// Package asset path for `MANIFEST-NewCMMath.txt`.
  static const String manifestAssetPath =
      'packages/$packageName/assets/fonts/MANIFEST-NewCMMath.txt';

  static Future<TexMathFontAsset>? _cachedAssetFuture;

  /// Loads `NewCMMath-Regular.otf` and its GUST license from Flutter assets.
  ///
  /// When [bundle] is omitted, the result is cached so the asset is read only
  /// once unless [forceReload] is `true`. Validates that the payload is
  /// non-empty and carries an `OTTO` OpenType header, throwing
  /// [TexMathFontError] otherwise.
  static Future<TexMathFontAsset> load({
    AssetBundle? bundle,
    bool forceReload = false,
  }) {
    if (bundle == null && !forceReload && _cachedAssetFuture != null) {
      return _cachedAssetFuture!;
    }
    final Future<TexMathFontAsset> future = _loadInternal(bundle ?? rootBundle);
    if (bundle == null) {
      _cachedAssetFuture = future;
    }
    return future;
  }

  /// Clears the cached font bundle future. Intended for tests.
  @visibleForTesting
  static void clearCache() {
    _cachedAssetFuture = null;
  }

  static Future<TexMathFontAsset> _loadInternal(AssetBundle bundle) async {
    final ByteData fontData = await bundle.load(fontAssetPath);
    final Uint8List bytes = fontData.buffer.asUint8List(
      fontData.offsetInBytes,
      fontData.lengthInBytes,
    );
    if (bytes.isEmpty ||
        bytes.length < 4 ||
        bytes[0] != 0x4F ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x4F) {
      throw const TexMathFontError(
        'Bundled NewCMMath-Regular.otf is missing a valid OTTO header.',
      );
    }
    final String licenseText = await bundle.loadString(licenseAssetPath);
    return TexMathFontAsset(
      bytes: bytes,
      familyName: 'NewComputerModernMath',
      assetPath: fontAssetPath,
      licenseText: licenseText,
    );
  }
}
