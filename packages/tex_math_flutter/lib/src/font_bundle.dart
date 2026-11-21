import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tex_math/tex_math.dart';

import 'async_zone.dart';

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

  /// Decodes [bytes] into a pure-Dart [MathFont] via [MathFont.fromBytes].
  MathFont decodeMathFont() => MathFont.fromBytes(bytes);
}

/// Loads and caches the bundled `NewCMMath-Regular.otf` asset and decoded
/// [MathFont] once per application lifecycle.
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
  static TexMathFontAsset? _cachedAsset;
  static Future<MathFont>? _cachedMathFontFuture;
  static MathFont? _cachedMathFont;

  /// Synchronously returns the cached [TexMathFontAsset] if [load] has
  /// already completed for the default asset bundle, or `null` otherwise.
  static TexMathFontAsset? get cachedAsset => _cachedAsset;

  /// Synchronously returns the cached decoded [MathFont] if [loadMathFont] has
  /// already completed for the default asset bundle, or `null` otherwise.
  static MathFont? get cachedMathFont => _cachedMathFont;

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
    if (bundle == null && !forceReload) {
      final TexMathFontAsset? asset = _cachedAsset;
      if (asset != null) {
        return SynchronousFuture<TexMathFontAsset>(asset);
      }
      if (_cachedAssetFuture != null) {
        return _cachedAssetFuture!;
      }
    }
    late final Future<TexMathFontAsset> future;
    future = _loadInternal(bundle ?? rootBundle).then(
      (TexMathFontAsset asset) {
        if (bundle == null && identical(_cachedAssetFuture, future)) {
          _cachedAsset = asset;
        }
        return asset;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (bundle == null && identical(_cachedAssetFuture, future)) {
          _cachedAssetFuture = null;
          _cachedAsset = null;
        }
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    if (bundle == null) {
      _cachedAssetFuture = future;
    }
    return future;
  }

  /// Loads and decodes the bundled `NewCMMath-Regular.otf` into a cached
  /// [MathFont] once per application lifecycle.
  ///
  /// When [bundle] is omitted, both the future and the resulting [MathFont] are
  /// cached and exposed via [cachedMathFont] unless [forceReload] is `true`.
  static Future<MathFont> loadMathFont({
    AssetBundle? bundle,
    bool forceReload = false,
  }) {
    if (bundle == null && !forceReload) {
      final MathFont? font = _cachedMathFont;
      if (font != null) {
        return SynchronousFuture<MathFont>(font);
      }
      if (_cachedMathFontFuture != null) {
        return _cachedMathFontFuture!;
      }
    }
    final Future<TexMathFontAsset> assetFuture = load(
      bundle: bundle,
      forceReload: forceReload,
    );
    late final Future<MathFont> future;
    future = runInRealAsyncZone<Future<MathFont>>(() {
      return assetFuture
          .then<MathFont>((TexMathFontAsset asset) {
            final Uint8List bytes = asset.bytes;
            return Isolate.run<MathFont>(() => MathFont.fromBytes(bytes));
          })
          .then<MathFont>(
            (MathFont font) {
              if (bundle == null && identical(_cachedMathFontFuture, future)) {
                _cachedMathFont = font;
              }
              return font;
            },
            onError: (Object error, StackTrace stackTrace) {
              if (bundle == null && identical(_cachedMathFontFuture, future)) {
                _cachedMathFontFuture = null;
                _cachedMathFont = null;
              }
              Error.throwWithStackTrace(error, stackTrace);
            },
          );
    });
    if (bundle == null) {
      _cachedMathFontFuture = future;
    }
    return future;
  }

  /// Clears all cached font asset and [MathFont] state. Intended for tests.
  @visibleForTesting
  static void clearCache() {
    _cachedAssetFuture = null;
    _cachedAsset = null;
    _cachedMathFontFuture = null;
    _cachedMathFont = null;
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
    final String licenseText = await bundle.loadString(
      licenseAssetPath,
      cache: false,
    );
    return TexMathFontAsset(
      bytes: bytes,
      familyName: 'NewComputerModernMath',
      assetPath: fontAssetPath,
      licenseText: licenseText,
    );
  }
}
