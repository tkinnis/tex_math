import 'dart:isolate';
import 'dart:typed_data';

import 'package:tex_math/tex_math.dart';

/// Decodes raw OpenType [bytes] in a background [Isolate] on native platforms.
Future<MathFont> decodeMathFontOffThread(Uint8List bytes) =>
    Isolate.run<MathFont>(() => MathFont.fromBytes(bytes));
