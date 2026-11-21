import 'dart:io';
import 'dart:typed_data';

import 'package:tex_math/tex_math.dart';

import 'corpus.dart';

/// Repository-relative path to the bundled default OpenType math font.
const String defaultMathFontPath =
    'packages/tex_math_flutter/assets/fonts/NewCMMath-Regular.otf';

TexMathEngine? _cachedDefaultEngine;

/// Reads the raw SFNT bytes for the bundled `NewCMMath-Regular.otf` font.
Uint8List loadDefaultMathFontBytes() {
  final File fontFile = File(defaultMathFontPath);
  if (!fontFile.existsSync()) {
    throw StateError('Missing default math font: $defaultMathFontPath');
  }
  return fontFile.readAsBytesSync();
}

/// Decodes the bundled `NewCMMath-Regular.otf` font via [MathFont.fromBytes].
MathFont loadDefaultMathFont() =>
    MathFont.fromBytes(loadDefaultMathFontBytes());

/// Loads the bundled `NewCMMath-Regular.otf` font once and returns a cached
/// [TexMathEngine] configured with it.
TexMathEngine defaultVerificationEngine() {
  final TexMathEngine? cached = _cachedDefaultEngine;
  if (cached != null) {
    return cached;
  }
  final TexMathEngine engine = TexMathEngine(font: loadDefaultMathFont());
  _cachedDefaultEngine = engine;
  return engine;
}

/// Outcome of running [TexMathEngine] on a single corpus test case.
enum EngineOutcome {
  /// Accepted by both oracle and engine with matching metrics and glyphs.
  pass('pass'),

  /// Output, acceptance, or error class disagrees with expectation.
  differs('differs'),

  /// Engine deterministically threw [TexMathUnsupportedError].
  unsupported('unsupported'),

  /// Refused by both oracle and engine with compatible error classification.
  refusedMatch('refused_match'),

  /// Engine threw [TexMathBudgetError] where budget enforcement applies.
  budgetError('budget_error');

  const EngineOutcome(this.wireName);

  /// Wire identifier written into `corpus/expectations.json`.
  final String wireName;

  /// Resolves an [EngineOutcome] from its serialized wire string.
  static EngineOutcome? fromWireName(String? raw) {
    for (final EngineOutcome value in values) {
      if (value.wireName == raw) {
        return value;
      }
    }
    return null;
  }
}

/// Result of evaluating [TexMathEngine] on one [CorpusCase].
final class EngineEvaluation {
  /// Creates an engine evaluation record.
  const EngineEvaluation({required this.outcome, this.errorClass, this.detail});

  /// High-level evaluation outcome.
  final EngineOutcome outcome;

  /// Actual [TexMathErrorClass.name] thrown by the engine, if any.
  final String? errorClass;

  /// Diagnostic mismatch or error message when relevant.
  final String? detail;
}

/// Evaluates [TexMathEngine] against a corpus case and its oracle reference.
EngineEvaluation evaluateEngineAgainstOracle({
  required CorpusCase corpusCase,
  required bool oracleAccepted,
  String? oracleErrorClass,
  Map<String, Object?>? oracleBox,
  List<Object?>? oracleGlyphs,
  List<Object?>? oracleRules,
  double toleranceEm = 0.02,
  TexMathEngine? engine,
}) {
  final TexMathEngine resolvedEngine = engine ?? defaultVerificationEngine();
  final TexMathOptions options = TexMathOptions(
    displayMode: corpusCase.display
        ? TexMathDisplayMode.display
        : TexMathDisplayMode.inline,
    packages: corpusCase.packages ?? TexMathOptions.defaultPackages,
  );

  try {
    final RenderResult result = resolvedEngine.render(
      corpusCase.tex,
      options: options,
    );
    if (!oracleAccepted) {
      return EngineEvaluation(
        outcome: EngineOutcome.differs,
        detail:
            'Engine accepted input that oracle refused '
            '(${oracleErrorClass ?? 'unknown'}).',
      );
    }
    final String? mismatch = _compareDisplayList(
      displayList: result.displayList,
      oracleBox: oracleBox,
      oracleGlyphs: oracleGlyphs,
      oracleRules: oracleRules,
      toleranceEm: toleranceEm,
    );
    if (mismatch != null) {
      return EngineEvaluation(outcome: EngineOutcome.differs, detail: mismatch);
    }
    return const EngineEvaluation(outcome: EngineOutcome.pass);
  } on TexMathUnsupportedError catch (err) {
    return EngineEvaluation(
      outcome: EngineOutcome.unsupported,
      errorClass: err.errorClass.name,
      detail: err.message,
    );
  } on TexMathBudgetError catch (err) {
    if (!oracleAccepted &&
        _errorClassesCompatible(err.errorClass.name, oracleErrorClass)) {
      return EngineEvaluation(
        outcome: EngineOutcome.refusedMatch,
        errorClass: err.errorClass.name,
        detail: err.message,
      );
    }
    return EngineEvaluation(
      outcome: EngineOutcome.budgetError,
      errorClass: err.errorClass.name,
      detail: err.message,
    );
  } on TexMathError catch (err) {
    if (!oracleAccepted &&
        _errorClassesCompatible(err.errorClass.name, oracleErrorClass)) {
      return EngineEvaluation(
        outcome: EngineOutcome.refusedMatch,
        errorClass: err.errorClass.name,
        detail: err.message,
      );
    }
    return EngineEvaluation(
      outcome: EngineOutcome.differs,
      errorClass: err.errorClass.name,
      detail: oracleAccepted
          ? 'Engine rejected valid input with ${err.errorClass.name}: ${err.message}'
          : 'Error class mismatch: engine=${err.errorClass.name}, '
                'oracle=${oracleErrorClass ?? 'unspecified'}',
    );
  }
}

bool _errorClassesCompatible(String actual, String? expected) {
  if (expected == null || expected.isEmpty) {
    return true;
  }
  return actual.toLowerCase() == expected.toLowerCase();
}

String? _compareDisplayList({
  required DisplayList displayList,
  required Map<String, Object?>? oracleBox,
  required List<Object?>? oracleGlyphs,
  required List<Object?>? oracleRules,
  required double toleranceEm,
}) {
  if (oracleBox != null) {
    final double expectedWidth = (oracleBox['width'] as num).toDouble();
    final double expectedHeight = (oracleBox['height'] as num).toDouble();
    final double expectedDepth = (oracleBox['depth'] as num).toDouble();

    final DisplayMetrics m = displayList.metrics;
    if ((m.widthEm - expectedWidth).abs() > toleranceEm) {
      return 'widthEm mismatch: engine=${m.widthEm}, oracle=$expectedWidth';
    }
    if ((m.heightEm - expectedHeight).abs() > toleranceEm) {
      return 'heightEm mismatch: engine=${m.heightEm}, oracle=$expectedHeight';
    }
    if ((m.depthEm - expectedDepth).abs() > toleranceEm) {
      return 'depthEm mismatch: engine=${m.depthEm}, oracle=$expectedDepth';
    }
  }

  final List<GlyphItem> actualGlyphs = displayList.items
      .whereType<GlyphItem>()
      .toList();
  if (oracleGlyphs != null) {
    if (actualGlyphs.length != oracleGlyphs.length) {
      return 'Glyph count mismatch: engine=${actualGlyphs.length}, '
          'oracle=${oracleGlyphs.length}';
    }
    for (int i = 0; i < oracleGlyphs.length; i++) {
      final Map<String, Object?> og = oracleGlyphs[i] as Map<String, Object?>;
      final GlyphItem ag = actualGlyphs[i];
      final int? expectedCp = parseCodePoint(og['codePoint']);
      if (expectedCp != null && ag.codePoint != expectedCp) {
        return 'Glyph[$i] codePoint mismatch: engine=${ag.codePoint}, '
            'oracle=$expectedCp';
      }
      final double ox = (og['x'] as num).toDouble();
      final double oy = (og['y'] as num).toDouble();
      final double osx = (og['scaleX'] as num?)?.toDouble() ?? 1.0;
      final double osy = (og['scaleY'] as num?)?.toDouble() ?? 1.0;
      if ((ag.xEm - ox).abs() > toleranceEm ||
          (ag.yEm - oy).abs() > toleranceEm) {
        return 'Glyph[$i] position mismatch: engine=(${ag.xEm}, ${ag.yEm}), '
            'oracle=($ox, $oy)';
      }
      if ((ag.scaleX - osx).abs() > toleranceEm ||
          (ag.scaleY - osy).abs() > toleranceEm) {
        return 'Glyph[$i] scale mismatch: engine=(${ag.scaleX}, ${ag.scaleY}), '
            'oracle=($osx, $osy)';
      }
    }
  }

  final List<RuleItem> actualRules = displayList.items
      .whereType<RuleItem>()
      .toList();
  if (oracleRules != null) {
    if (actualRules.length != oracleRules.length) {
      return 'Rule count mismatch: engine=${actualRules.length}, '
          'oracle=${oracleRules.length}';
    }
    for (int i = 0; i < oracleRules.length; i++) {
      final Map<String, Object?> orule = oracleRules[i] as Map<String, Object?>;
      final RuleItem ar = actualRules[i];
      final double ox = (orule['x'] as num).toDouble();
      final double oy = (orule['y'] as num).toDouble();
      final double ow = (orule['width'] as num).toDouble();
      final double oh = (orule['height'] as num).toDouble();
      if ((ar.xEm - ox).abs() > toleranceEm ||
          (ar.yEm - oy).abs() > toleranceEm ||
          (ar.widthEm - ow).abs() > toleranceEm ||
          (ar.heightEm - oh).abs() > toleranceEm) {
        return 'Rule[$i] geometry mismatch';
      }
    }
  }

  return null;
}

/// Parses an integer or hexadecimal Unicode scalar value from oracle JSON.
int? parseCodePoint(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  if (raw is String) {
    String cleaned = raw.trim();
    if (cleaned.startsWith('U+') || cleaned.startsWith('u+')) {
      cleaned = cleaned.substring(2);
    } else if (cleaned.startsWith('0x') || cleaned.startsWith('0X')) {
      cleaned = cleaned.substring(2);
    }
    final int? parsedHex = int.tryParse(cleaned, radix: 16);
    if (parsedHex != null) {
      return parsedHex;
    }
    return int.tryParse(cleaned);
  }
  return null;
}
