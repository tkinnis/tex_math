import 'dart:typed_data';

import 'package:tex_math/tex_math.dart';

/// Decodes raw OpenType [bytes] on Web and Wasm targets where `dart:isolate` is
/// unavailable.
Future<MathFont> decodeMathFontOffThread(Uint8List bytes) =>
    Future<MathFont>(() => MathFont.fromBytes(bytes));
