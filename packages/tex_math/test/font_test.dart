import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tex_math/tex_math.dart';

void main() {
  group('NewCMMath-Regular.otf integration', () {
    late MathFont font;

    setUpAll(() {
      final File otfFile = File(
        '../tex_math_flutter/assets/fonts/NewCMMath-Regular.otf',
      );
      expect(otfFile.existsSync(), isTrue);
      font = MathFont.fromBytes(otfFile.readAsBytesSync());
    });

    test('parses SFNT header, core metrics, OS/2, and family name', () {
      expect(font.familyName, 'NewComputerModernMath');
      expect(font.unitsPerEm, 1000);
      expect(font.numGlyphs, 8603);
      expect(font.ascender, 806);
      expect(font.descender, -194);
      expect(font.lineGap, 200);
      expect(font.numberOfHMetrics, 8603);
      expect(font.xHeight, 431);
      expect(font.capHeight, 683);
      expect(font.typoAscender, 806);
      expect(font.typoDescender, -194);
      expect(
        font.boundingBox,
        const FontBoundingBox(xMin: -1042, yMin: -3060, xMax: 4082, yMax: 3560),
      );
      expect(font.axes, isEmpty);
    });

    test('resolves BMP and SMP Unicode code points via cmap', () {
      expect(font.glyphIdForCodePoint(0x0028), 9); // '('
      expect(font.glyphIdForCodePoint(0x0061), 66); // 'a'
      expect(font.glyphIdForCodePoint(0x1D44E), 3550); // Mathematical italic a
      expect(font.glyphIdForCodePoint(0x2211), 992); // Summation
      expect(font.glyphIdForCodePoint(0x222B), 1018); // Integral
      expect(font.glyphIdForCodePoint(0x221A), 1001); // Radical
      expect(font.glyphIdForCodePoint(0x10FFFD), 0); // Unmapped PUA
      expect(font.glyphIdForCodePoint(-1), 0);
    });

    test('exposes all 56 MATH table constants, glyph info, and variants', () {
      final MathTableData? math = font.mathTable;
      expect(math, isNotNull);
      final MathConstants c = math!.constants;

      expect(c.scriptPercentScaleDown, 70);
      expect(c.scriptScriptPercentScaleDown, 50);
      expect(c.delimitedSubFormulaMinHeight, 1300);
      expect(c.displayOperatorMinHeight, 1300);
      expect(c.mathLeading, 154.0);
      expect(c.axisHeight, 250.0);
      expect(c.accentBaseHeight, 450.0);
      expect(c.flattenedAccentBaseHeight, 664.0);
      expect(c.subscriptShiftDown, 247.0);
      expect(c.subscriptTopMax, 344.0);
      expect(c.subscriptBaselineDropMin, 200.0);
      expect(c.superscriptShiftUp, 363.0);
      expect(c.superscriptShiftUpCramped, 289.0);
      expect(c.superscriptBottomMin, 108.0);
      expect(c.superscriptBaselineDropMax, 250.0);
      expect(c.subSuperscriptGapMin, 160.0);
      expect(c.superscriptBottomMaxWithSubscript, 344.0);
      expect(c.spaceAfterScript, 56.0);
      expect(c.upperLimitGapMin, 200.0);
      expect(c.upperLimitBaselineRiseMin, 111.0);
      expect(c.lowerLimitGapMin, 167.0);
      expect(c.lowerLimitBaselineDropMin, 600.0);
      expect(c.stackTopShiftUp, 444.0);
      expect(c.stackTopDisplayStyleShiftUp, 677.0);
      expect(c.stackBottomShiftDown, 345.0);
      expect(c.stackBottomDisplayStyleShiftDown, 686.0);
      expect(c.stackGapMin, 120.0);
      expect(c.stackDisplayStyleGapMin, 280.0);
      expect(c.stretchStackTopShiftUp, 111.0);
      expect(c.stretchStackBottomShiftDown, 600.0);
      expect(c.stretchStackGapAboveMin, 200.0);
      expect(c.stretchStackGapBelowMin, 167.0);
      expect(c.fractionNumeratorShiftUp, 394.0);
      expect(c.fractionNumeratorDisplayStyleShiftUp, 677.0);
      expect(c.fractionDenominatorShiftDown, 345.0);
      expect(c.fractionDenominatorDisplayStyleShiftDown, 686.0);
      expect(c.fractionNumeratorGapMin, 40.0);
      expect(c.fractionNumDisplayStyleGapMin, 120.0);
      expect(c.fractionNumeratorDisplayStyleGapMin, 120.0);
      expect(c.fractionRuleThickness, 40.0);
      expect(c.fractionDenominatorGapMin, 40.0);
      expect(c.fractionDenomDisplayStyleGapMin, 120.0);
      expect(c.fractionDenominatorDisplayStyleGapMin, 120.0);
      expect(c.skewedFractionHorizontalGap, 350.0);
      expect(c.skewedFractionVerticalGap, 96.0);
      expect(c.overbarVerticalGap, 120.0);
      expect(c.overbarRuleThickness, 40.0);
      expect(c.overbarExtraAscender, 40.0);
      expect(c.underbarVerticalGap, 120.0);
      expect(c.underbarRuleThickness, 40.0);
      expect(c.underbarExtraDescender, 40.0);
      expect(c.radicalVerticalGap, 50.0);
      expect(c.radicalDisplayStyleVerticalGap, 148.0);
      expect(c.radicalRuleThickness, 40.0);
      expect(c.radicalExtraAscender, 40.0);
      expect(c.radicalKernBeforeDegree, 278.0);
      expect(c.radicalKernAfterDegree, -556.0);
      expect(c.radicalDegreeBottomRaisePercent, 60);
      expect(
        c.axisHeightRecord,
        const MathValueRecord(value: 250.0, deviceOffset: 0),
      );

      // Italics correction, top accent attachment, extended shapes, mathKern
      final int integralGid = font.glyphIdForCodePoint(0x222B);
      final int mathItalicAGid = font.glyphIdForCodePoint(0x1D44E);
      expect(math.glyphInfo.italicsCorrection(integralGid), isNotNull);
      expect(math.glyphInfo.italicsCorrection(integralGid)!, greaterThan(0.0));
      expect(math.glyphInfo.topAccentAttachment(mathItalicAGid), isNotNull);
      expect(math.glyphInfo.isExtendedShape(integralGid), isTrue);
      expect(
        math.glyphInfo.mathKern(374, MathKernCorner.bottomRight, 0.0),
        -180.0,
      );

      // Vertical & horizontal variants and extensible assemblies
      expect(math.variants.minConnectorOverlap, 20);
      final int lparenGid = font.glyphIdForCodePoint(0x0028);
      final MathGlyphConstruction? lparenVert = math.variants
          .verticalConstruction(lparenGid);
      expect(lparenVert, isNotNull);
      expect(lparenVert!.variants.length, 8);
      expect(lparenVert.assembly, isNotNull);
      expect(lparenVert.assembly!.parts, hasLength(3));
      expect(lparenVert.assembly!.parts[1].isExtender, isTrue);

      final int overbraceGid = font.glyphIdForCodePoint(0x23DE);
      final MathGlyphConstruction? overbraceHoriz = math.variants
          .horizontalConstruction(overbraceGid);
      expect(overbraceHoriz, isNotNull);
      expect(overbraceHoriz!.assembly, isNotNull);
      expect(overbraceHoriz.assembly!.parts.length, greaterThanOrEqualTo(3));
    });

    test('resolves GSUB ssty script and scriptscript glyph variants', () {
      expect(font.scriptVariantGlyph(2, 0), 5431);
      expect(font.scriptVariantGlyph(2, 1), 5024);
      expect(font.scriptVariantGlyph(2, 2), isNull);
      expect(font.scriptVariantGlyph(0, 0), isNull);
    });

    test(
      'extracts CFF outlines, metrics, SVG paths, and decodes all glyphs',
      () {
        final int sumGid = font.glyphIdForCodePoint(0x2211);
        final GlyphOutline? sumOutline = font.outlineForGlyph(sumGid);
        expect(sumOutline, isNotNull);
        expect(sumOutline!.isEmpty, isFalse);
        expect(sumOutline.commands.first, isA<MoveTo>());
        expect(sumOutline.commands.last, const ClosePath());
        final String svgPath = sumOutline.toSvgPathData();
        expect(svgPath, startsWith('M'));
        expect(svgPath, endsWith('Z'));

        // Lazy cache returns identical instance on repeated queries.
        expect(identical(font.outlineForGlyph(sumGid), sumOutline), isTrue);

        final GlyphMetrics sumMetrics = font.metricsForGlyph(sumGid);
        expect(sumMetrics.advanceWidth, greaterThan(500.0));
        expect(sumMetrics.height, greaterThan(500.0));
        expect(sumMetrics.depth, greaterThan(0.0));
        expect(identical(font.metricsForGlyph(sumGid), sumMetrics), isTrue);

        // Decode every glyph in NewCMMath-Regular.otf without errors.
        int nonEmptyCount = 0;
        for (int gid = 0; gid < font.numGlyphs; gid++) {
          final GlyphOutline? outline = font.outlineForGlyph(gid);
          expect(outline, isNotNull);
          if (!outline!.isEmpty) {
            nonEmptyCount++;
          }
        }
        expect(nonEmptyCount, greaterThan(8000));

        // Verify exact CFF outline coordinates and hinting on NewCMMath glyphs.
        final GlyphOutline? lparen = font.outlineForGlyph(9);
        expect(lparen, isNotNull);
        expect(lparen!.advanceWidth, 389.0);
        expect(lparen.commands.first, const MoveTo(332.0, -238.0));

        final int aGid = font.glyphIdForCodePoint(0x0061);
        final GlyphOutline? aUnhinted = font.outlineForGlyph(aGid);
        final GlyphOutline? aHinted = font.outlineForGlyph(
          aGid,
          ppem: 12.0,
          enableHinting: true,
        );
        expect(aUnhinted, isNotNull);
        expect(aHinted, isNotNull);
        expect(font.stemHintsForGlyph(aGid), isNotEmpty);
        expect(aHinted!.commands.length, aUnhinted!.commands.length);
      },
    );
  });

  group('Extended CFF1 Type 2, CID FDSelect, cmap, and glyf edge cases', () {
    test('decodes CFF1 CID font with FDArray/FDSelect, subrs, flex, curves, and arithmetic', () {
      final Uint8List cff1Font = _buildSyntheticCff1CidFont();
      final MathFont font = MathFont.fromBytes(cff1Font);

      expect(font.glyphIdForCodePoint(0x1D44E), 1); // Format 12 SMP
      expect(font.glyphIdForCodePoint(0x03B1), 2); // Format 4 idRangeOffset
      expect(font.xHeight, 440);
      expect(font.capHeight, 690);

      // Glyph 1 exercises callgsubr, callsubr, hflex, flex, hflex1, flex1,
      // hhcurveto, vvcurveto, hvcurveto, vhcurveto, rcurveline, rlinecurve,
      // cntrmask, and arithmetic ops.
      final GlyphOutline? g1 = font.outlineForGlyph(1);
      expect(g1, isNotNull);
      expect(g1!.commands, contains(isA<CubicTo>()));
      expect(g1.commands, contains(isA<LineTo>()));
      expect(g1.commands.last, const ClosePath());

      // Glyph 2 uses FD index 1 via FDSelect Format 3
      final GlyphOutline? g2 = font.outlineForGlyph(2);
      expect(g2, isNotNull);
      expect(g2!.advanceWidth, 650.0);
      final GlyphMetrics m2 = font.metricsForGlyph(2);
      expect(m2.xMax, closeTo(300.0, 1e-6));
      expect(m2.yMax, closeTo(400.0, 1e-6));
    });

    test('decodes all-off-curve TrueType contour and 2x2/point-matched composite', () {
      final Uint8List ttf = _buildExtendedTrueTypeFont();
      final MathFont font = MathFont.fromBytes(ttf);

      // Glyph 1: all-off-curve 4-point contour produces 4 QuadTo segments
      final GlyphOutline? g1 = font.outlineForGlyph(1);
      expect(g1, isNotNull);
      expect(g1!.commands.whereType<QuadTo>(), hasLength(4));
      expect(g1.commands.first, const MoveTo(100.0, 0.0));

      // Glyph 2: composite with 2x2 transform (90 deg CCW) + point-matched part
      final GlyphOutline? g2 = font.outlineForGlyph(2);
      expect(g2, isNotNull);
      expect(g2!.commands.whereType<QuadTo>(), hasLength(8));
    });
  });

  group('TrueType glyf/loca simple & composite outlines', () {
    test(
      'decodes simple implicit-midpoint QuadTo and composite transforms',
      () {
        final Uint8List ttfBytes = _buildSyntheticTrueTypeFont(longLoca: false);
        final MathFont font = MathFont.fromBytes(ttfBytes);

        expect(font.familyName, 'SynthTT');
        expect(font.unitsPerEm, 1000);
        expect(font.indexToLocFormat, 0);
        expect(font.glyphIdForCodePoint(0x0041), 1); // 'A'
        expect(font.glyphIdForCodePoint(0x00C0), 2); // Composite glyph

        // Simple glyph 1: triangle + off-curve midpoint quadratic spline
        final GlyphOutline? g1 = font.outlineForGlyph(1);
        expect(g1, isNotNull);
        expect(g1!.commands, contains(isA<QuadTo>()));
        // Two consecutive off-curve points (100,200) & (200,200) -> midpoint (150,200)
        expect(g1.commands, contains(const QuadTo(100.0, 200.0, 150.0, 200.0)));
        final GlyphMetrics m1 = font.metricsForGlyph(1);
        expect(m1.xMin, 0.0);
        expect(m1.yMin, 0.0);
        expect(m1.xMax, 300.0);
        expect(m1.yMax, 200.0);

        // Composite glyph 2: component 1 scaled 0.5x and shifted (+50, +100)
        final GlyphOutline? g2 = font.outlineForGlyph(2);
        expect(g2, isNotNull);
        final GlyphMetrics m2 = font.metricsForGlyph(2);
        expect(m2.xMin, closeTo(50.0, 1e-6));
        expect(m2.yMin, closeTo(100.0, 1e-6));
        expect(m2.xMax, closeTo(200.0, 1e-6));
        expect(m2.yMax, closeTo(200.0, 1e-6));
      },
    );

    test('supports long loca offsets and rejects composite glyph cycles', () {
      final Uint8List longTtf = _buildSyntheticTrueTypeFont(longLoca: true);
      final MathFont longFont = MathFont.fromBytes(longTtf);
      expect(longFont.indexToLocFormat, 1);
      expect(longFont.outlineForGlyph(1)!.isEmpty, isFalse);

      final Uint8List cyclicTtf = _buildSyntheticTrueTypeFont(
        longLoca: true,
        createCompositeCycle: true,
      );
      final MathFont cyclicFont = MathFont.fromBytes(cyclicTtf);
      expect(
        () => cyclicFont.outlineForGlyph(2),
        throwsA(isA<TexMathFontError>()),
      );
    });
  });

  group('CFF2 variable font, stem hinting, GSUB, and MathKern', () {
    test('evaluates fvar/avar, ItemVariationStore, blend, HVAR, and hinting', () {
      final Uint8List vfBytes = _buildSyntheticCff2VariableFont();

      // Default axis value (wght = 400 -> norm = 0.0)
      final MathFont defaultFont = MathFont.fromBytes(vfBytes);
      expect(defaultFont.familyName, 'SynthVarCFF2');
      expect(defaultFont.axes, hasLength(1));
      expect(defaultFont.axes.first.tag, 'wght');
      expect(defaultFont.variationAxes['wght'], 400.0);
      expect(
        defaultFont.normalizedVariationCoordinates.first,
        closeTo(0.0, 1e-9),
      );

      // Check GSUB LookupType 1 SingleSubst (glyph 1 -> 2, chained 2 -> 3)
      expect(defaultFont.scriptVariantGlyph(1, 0), 2);
      expect(defaultFont.scriptVariantGlyph(1, 1), 3);

      // Check MathKern 4-corner staircase evaluation + GDEF VariationIndex
      final MathTableData math = defaultFont.mathTable!;
      expect(math.constants.axisHeight, 250.0);
      expect(math.glyphInfo.mathKern(1, MathKernCorner.topRight, 50.0), -10.0);
      expect(math.glyphInfo.mathKern(1, MathKernCorner.topRight, 100.0), -30.0);
      expect(math.glyphInfo.mathKern(1, MathKernCorner.topRight, 250.0), -60.0);
      expect(
        math.glyphInfo.mathKern(1, MathKernCorner.bottomLeft, 150.0),
        15.0,
      );

      final GlyphOutline baseOutline = defaultFont.outlineForGlyph(1)!;
      final GlyphMetrics baseMetrics = defaultFont.metricsForGlyph(1);
      expect(baseMetrics.advanceWidth, 500.0);
      expect(baseMetrics.xMax, closeTo(200.0, 1e-6));
      expect(baseMetrics.yMax, closeTo(700.0, 1e-6));
      expect(defaultFont.stemHintsForGlyph(1), hasLength(2));

      // Midpoint axis (wght = 650 -> linear 0.5 -> avar remapped to 0.25)
      final MathFont midFont = MathFont.fromBytes(
        vfBytes,
        variationAxes: const <String, double>{'wght': 650.0},
      );
      expect(midFont.normalizedVariationCoordinates.first, closeTo(0.25, 1e-4));
      final GlyphMetrics midMetrics = midFont.metricsForGlyph(1);
      // HVAR advance delta is +200 at peak 1.0 -> +50 at 0.25
      expect(midMetrics.advanceWidth, closeTo(550.0, 0.5));
      // Blend on x width: base 200 + delta 200 * 0.25 = 250
      expect(midMetrics.xMax, closeTo(250.0, 0.5));
      // MATH axisHeight has GDEF VariationIndex delta +40 at peak -> +10 at 0.25
      expect(midFont.mathTable!.constants.axisHeight, closeTo(260.0, 0.5));

      // Max axis (clamped wght = 1200 -> 900 -> norm 1.0)
      final MathFont boldFont = MathFont.fromBytes(
        vfBytes,
        variationAxes: const <String, double>{'wght': 1200.0},
      );
      expect(boldFont.variationAxes['wght'], 900.0);
      final GlyphMetrics boldMetrics = boldFont.metricsForGlyph(1);
      expect(boldMetrics.advanceWidth, closeTo(700.0, 0.5));
      expect(boldMetrics.xMax, closeTo(400.0, 0.5));
      expect(baseOutline, isNot(equals(boldFont.outlineForGlyph(1))));

      // Stem hinting at small ppem (12 px) snaps stem coordinates to pixel grid
      final GlyphOutline? hinted = defaultFont.outlineForGlyph(
        1,
        ppem: 12.0,
        enableHinting: true,
      );
      expect(hinted, isNotNull);
      final FontBoundingBox hintedBox = _bboxFromCommands(hinted!.commands);
      final double scale = 12.0 / 1000.0;
      // Snapped vertical stem width in pixels should be an exact integer >= 1
      final double snappedWidthPx = hintedBox.width * scale;
      expect(snappedWidthPx, closeTo(snappedWidthPx.roundToDouble(), 1e-6));
      expect(snappedWidthPx, greaterThanOrEqualTo(1.0));
    });
  });

  group('Error, budget, header, and stub validation', () {
    test(
      'rejects invalid inputs with TexMathFontError and TexMathBudgetError',
      () {
        expect(
          () => MathFont.fromBytes(Uint8List(0)),
          throwsA(
            isA<TexMathFontError>().having(
              (TexMathFontError e) => e.errorClass,
              'errorClass',
              TexMathErrorClass.invalidFont,
            ),
          ),
        );

        expect(
          () => MathFont.fromBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
          throwsA(isA<TexMathFontError>()),
        );

        expect(
          () => MathFont.fromBytes(
            Uint8List.fromList(<int>[
              0x4F,
              0x54,
              0x54,
              0x4F,
              0,
              1,
              0,
              0,
              0,
              0,
              0,
              0,
            ]),
            maxBytes: 8,
          ),
          throwsA(
            isA<TexMathBudgetError>().having(
              (TexMathBudgetError e) => e.budgetName,
              'budgetName',
              'maxFontBytes',
            ),
          ),
        );

        // 12-byte OTTO header with numTables = 0
        expect(
          () => MathFont.fromBytes(
            Uint8List.fromList(<int>[
              0x4F,
              0x54,
              0x54,
              0x4F,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
            ]),
          ),
          throwsA(isA<TexMathFontError>()),
        );

        // Truncated table directory claiming 5 tables in 20 bytes
        expect(
          () => MathFont.fromBytes(
            Uint8List.fromList(<int>[
              0x4F,
              0x54,
              0x54,
              0x4F,
              0,
              5,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
              0,
            ]),
          ),
          throwsA(isA<TexMathFontError>()),
        );

        // Corrupt unitsPerEm == 0 in head
        final Uint8List badHead = _buildSyntheticTrueTypeFont(
          longLoca: false,
          sfntTag: 0x74727565, // 'true'
        );
        // Corrupt SFNT table directory offset out-of-bounds
        badHead[12 + 8] = 0x7F;
        expect(
          () => MathFont.fromBytes(badHead),
          throwsA(isA<TexMathFontError>()),
        );

        // Supports 'true' and 'typ1' SFNT tags cleanly
        final MathFont appleTrue = MathFont.fromBytes(
          _buildSyntheticTrueTypeFont(longLoca: false, sfntTag: 0x74727565),
        );
        expect(appleTrue.unitsPerEm, 1000);

        final MathFont typ1 = MathFont.fromBytes(
          _buildSyntheticTrueTypeFont(longLoca: false, sfntTag: 0x74797031),
        );
        expect(typ1.unitsPerEm, 1000);

        // Stub compatibility
        const MathFont stub = MathFont.stub();
        expect(stub.familyName, 'NewComputerModernMath');
        expect(stub.unitsPerEm, 1000);
        expect(stub.outlineForGlyph(0), isNull);
        expect(stub.glyphIdForCodePoint(0x0061), 0);
        expect(stub.scriptVariantGlyph(1, 0), isNull);
        expect(stub.metricsForGlyph(0), const GlyphMetrics.empty(0));
      },
    );
  });
}

FontBoundingBox _bboxFromCommands(List<PathCommand> commands) {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = -double.infinity;
  double maxY = -double.infinity;
  for (final PathCommand cmd in commands) {
    void add(double x, double y) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    switch (cmd) {
      case MoveTo(:final double x, :final double y):
      case LineTo(:final double x, :final double y):
        add(x, y);
      case QuadTo(:final double x, :final double y):
        add(x, y);
      case CubicTo(:final double x, :final double y):
        add(x, y);
      case ClosePath():
        break;
    }
  }
  return FontBoundingBox(xMin: minX, yMin: minY, xMax: maxX, yMax: maxY);
}

// ---------------------------------------------------------------------------
// Synthetic Binary SFNT Test Builders
// ---------------------------------------------------------------------------

final class _ByteWriter {
  final BytesBuilder _b = BytesBuilder();

  int get length => _b.length;

  void u8(int v) => _b.addByte(v & 0xFF);

  void i8(int v) => _b.addByte(v & 0xFF);

  void u16(int v) {
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void i16(int v) => u16(v & 0xFFFF);

  void u24(int v) {
    _b.addByte((v >> 16) & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void u32(int v) {
    _b.addByte((v >> 24) & 0xFF);
    _b.addByte((v >> 16) & 0xFF);
    _b.addByte((v >> 8) & 0xFF);
    _b.addByte(v & 0xFF);
  }

  void i32(int v) => u32(v & 0xFFFFFFFF);

  void fixed(double v) => i32((v * 65536.0).round());

  void f2dot14(double v) => i16((v * 16384.0).round());

  void tag(String s) {
    for (int i = 0; i < 4; i++) {
      _b.addByte(s.codeUnitAt(i));
    }
  }

  void bytes(List<int> raw) => _b.add(raw);

  void zeros(int count) {
    for (int i = 0; i < count; i++) {
      _b.addByte(0);
    }
  }

  Uint8List toBytes() => _b.toBytes();
}

Uint8List _assembleSfnt(int sfntTag, Map<String, Uint8List> tables) {
  final List<String> tags = tables.keys.toList()..sort();
  final _ByteWriter out = _ByteWriter()
    ..u32(sfntTag)
    ..u16(tags.length)
    ..u16(16)
    ..u16(0)
    ..u16(0);

  int currentOffset = 12 + tags.length * 16;
  final Map<String, int> offsets = <String, int>{};
  for (final String t in tags) {
    final Uint8List data = tables[t]!;
    offsets[t] = currentOffset;
    out
      ..tag(t)
      ..u32(0)
      ..u32(currentOffset)
      ..u32(data.length);
    final int padded = (data.length + 3) & ~3;
    currentOffset += padded;
  }

  for (final String t in tags) {
    final Uint8List data = tables[t]!;
    out.bytes(data);
    final int pad = ((data.length + 3) & ~3) - data.length;
    out.zeros(pad);
  }
  return out.toBytes();
}

Uint8List _buildHeadTable({required int unitsPerEm, required int locaFormat}) {
  final _ByteWriter w = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u32(0x00010000)
    ..u32(0)
    ..u32(0x5F0F3CF5)
    ..u16(0)
    ..u16(unitsPerEm)
    ..zeros(16) // created/modified
    ..i16(0)
    ..i16(0)
    ..i16(500)
    ..i16(700)
    ..u16(0)
    ..u16(8)
    ..i16(2)
    ..i16(locaFormat)
    ..i16(0);
  return w.toBytes();
}

Uint8List _buildMaxpTable(int numGlyphs, {required bool isTrueType}) {
  final _ByteWriter w = _ByteWriter();
  if (isTrueType) {
    w
      ..u32(0x00010000)
      ..u16(numGlyphs)
      ..zeros(26);
  } else {
    w
      ..u32(0x00005000)
      ..u16(numGlyphs);
  }
  return w.toBytes();
}

Uint8List _buildHheaTable(int numHMetrics) {
  final _ByteWriter w = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..i16(800)
    ..i16(-200)
    ..i16(0)
    ..u16(700)
    ..zeros(22)
    ..u16(numHMetrics);
  return w.toBytes();
}

Uint8List _buildHmtxTable(List<int> advWidths, List<int> lsbs) {
  final _ByteWriter w = _ByteWriter();
  for (int i = 0; i < advWidths.length; i++) {
    w
      ..u16(advWidths[i])
      ..i16(lsbs[i]);
  }
  return w.toBytes();
}

Uint8List _buildNameTable(String familyName) {
  final _ByteWriter strBytes = _ByteWriter();
  for (final int unit in familyName.codeUnits) {
    strBytes.u16(unit);
  }
  final Uint8List strData = strBytes.toBytes();
  final _ByteWriter w = _ByteWriter()
    ..u16(0)
    ..u16(1)
    ..u16(6 + 12)
    ..u16(3)
    ..u16(1)
    ..u16(0x0409)
    ..u16(1)
    ..u16(strData.length)
    ..u16(0)
    ..bytes(strData);
  return w.toBytes();
}

Uint8List _buildCmapFormat4(Map<int, int> bmpMap) {
  final List<int> codes = bmpMap.keys.toList()..sort();
  final int segCount = codes.length + 1;
  final int length = 16 + segCount * 8;
  final _ByteWriter sub = _ByteWriter()
    ..u16(4)
    ..u16(length)
    ..u16(0)
    ..u16(segCount * 2)
    ..u16(2)
    ..u16(0)
    ..u16(0);

  for (final int c in codes) {
    sub.u16(c);
  }
  sub
    ..u16(0xFFFF) // endCode sentinel
    ..u16(0); // reservedPad
  for (final int c in codes) {
    sub.u16(c);
  }
  sub.u16(0xFFFF); // startCode sentinel
  for (final int c in codes) {
    sub.i16(bmpMap[c]! - c);
  }
  sub.i16(1); // idDelta sentinel
  for (int i = 0; i < segCount; i++) {
    sub.u16(0); // idRangeOffset
  }
  final Uint8List subBytes = sub.toBytes();
  final _ByteWriter w = _ByteWriter()
    ..u16(0)
    ..u16(1)
    ..u16(3)
    ..u16(1)
    ..u32(12)
    ..bytes(subBytes);
  return w.toBytes();
}

Uint8List _buildSyntheticTrueTypeFont({
  required bool longLoca,
  int sfntTag = 0x00010000,
  bool createCompositeCycle = false,
}) {
  // Glyph 0: empty
  // Glyph 1: simple 4-point contour: (0,0) on, (300,0) on, (100,200) off, (200,200) off
  final _ByteWriter g1 = _ByteWriter()
    ..i16(1) // numberOfContours
    ..i16(0)
    ..i16(0)
    ..i16(300)
    ..i16(200)
    ..u16(3) // endPtsOfContours[0]
    ..u16(0) // instructionLength
    // flags: on, on, off, off (use long x/y deltas for simplicity)
    ..u8(0x01)
    ..u8(0x01)
    ..u8(0x00)
    ..u8(0x00)
    // dx: 0, +300, -200, +100
    ..i16(0)
    ..i16(300)
    ..i16(-200)
    ..i16(100)
    // dy: 0, 0, +200, 0
    ..i16(0)
    ..i16(0)
    ..i16(200)
    ..i16(0);
  final Uint8List g1Bytes = g1.toBytes();
  final int g1Pad = g1Bytes.length.isOdd ? 1 : 0;

  // Glyph 2: composite referencing glyph 1 (or self-cycle if createCompositeCycle)
  final _ByteWriter g2 = _ByteWriter()
    ..i16(-1)
    ..i16(0)
    ..i16(0)
    ..i16(250)
    ..i16(250)
    // flags: ARG_1_AND_2_ARE_WORDS (0x01) | ARGS_ARE_XY_VALUES (0x02) |
    // WE_HAVE_A_SCALE (0x08)
    ..u16(0x000B)
    ..u16(createCompositeCycle ? 2 : 1)
    ..i16(50) // dx
    ..i16(100) // dy
    ..f2dot14(0.5); // scale
  final Uint8List g2Bytes = g2.toBytes();
  final int g2Pad = g2Bytes.length.isOdd ? 1 : 0;

  final _ByteWriter glyf = _ByteWriter()
    ..bytes(g1Bytes)
    ..zeros(g1Pad)
    ..bytes(g2Bytes)
    ..zeros(g2Pad);

  final int off0 = 0;
  final int off1 = 0;
  final int off2 = g1Bytes.length + g1Pad;
  final int off3 = off2 + g2Bytes.length + g2Pad;

  final _ByteWriter loca = _ByteWriter();
  for (final int off in <int>[off0, off1, off2, off3]) {
    if (longLoca) {
      loca.u32(off);
    } else {
      loca.u16(off ~/ 2);
    }
  }

  return _assembleSfnt(sfntTag, <String, Uint8List>{
    'head': _buildHeadTable(unitsPerEm: 1000, locaFormat: longLoca ? 1 : 0),
    'maxp': _buildMaxpTable(3, isTrueType: true),
    'hhea': _buildHheaTable(3),
    'hmtx': _buildHmtxTable(<int>[500, 400, 300], <int>[0, 0, 50]),
    'name': _buildNameTable('SynthTT'),
    'cmap': _buildCmapFormat4(<int, int>{0x0041: 1, 0x00C0: 2}),
    'loca': loca.toBytes(),
    'glyf': glyf.toBytes(),
  });
}

Uint8List _buildSyntheticCff2VariableFont() {
  // Build ItemVariationStore bytes shared by CFF2 vstore and GDEF
  final _ByteWriter ivs = _ByteWriter()
    ..u16(1) // format
    ..u32(12) // variationRegionListOffset
    ..u16(1) // itemVariationDataCount
    ..u32(22) // itemVariationDataOffsets[0]
    // VarRegionList @ 12 (1 axis, 1 region: 0.0 -> 1.0 -> 1.0)
    ..u16(1) // axisCount
    ..u16(1) // regionCount
    ..f2dot14(0.0) // startCoord
    ..f2dot14(1.0) // peakCoord
    ..f2dot14(1.0) // endCoord
    // ItemVariationData @ 22 (3 items: gid 0 = 0, gid 1 = 200, MATH axis = 40)
    ..u16(3) // itemCount
    ..u16(1) // wordDeltaCount = 1 (16-bit signed)
    ..u16(1) // regionIndexCount = 1
    ..u16(0) // regionIndexes[0] = 0
    ..i16(0) // deltaSets[0] (.notdef)
    ..i16(200) // deltaSets[1] (HVAR advanceWidth for gid 1)
    ..i16(40); // deltaSets[2] (MATH axisHeight VariationIndex)
  final Uint8List ivsBytes = ivs.toBytes();

  // fvar: 1 axis 'wght' (100, 400, 900)
  final _ByteWriter fvar = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(16) // axesArrayOffset
    ..u16(2)
    ..u16(1) // axisCount
    ..u16(20) // axisSize
    ..u16(0)
    ..u16(0)
    ..tag('wght')
    ..fixed(100.0)
    ..fixed(400.0)
    ..fixed(900.0)
    ..u16(0)
    ..u16(256);

  // avar: 1 axis with 5 segment maps (-1->-1, 0->0, 0.5->0.25, 1->1)
  final _ByteWriter avar = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(0)
    ..u16(1) // axisCount
    ..u16(4) // positionMapCount
    ..f2dot14(-1.0)
    ..f2dot14(-1.0)
    ..f2dot14(0.0)
    ..f2dot14(0.0)
    ..f2dot14(0.5)
    ..f2dot14(0.25)
    ..f2dot14(1.0)
    ..f2dot14(1.0);

  // HVAR: itemVariationStore @ 20, advanceWidthMapping @ 0 (implicit 0, gid)
  final _ByteWriter hvar = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u32(20)
    ..u32(0) // implicit outer=0, inner=gid
    ..u32(0)
    ..u32(0)
    ..bytes(ivsBytes);

  // GDEF v1.3 with ItemVariationStore @ 18
  final _ByteWriter gdef = _ByteWriter()
    ..u16(1)
    ..u16(3)
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u16(0)
    ..u32(18)
    ..bytes(ivsBytes);

  // GSUB: LookupType 1 SingleSubst Format 1 (delta +1) and Format 2 (gid 2 -> 3)
  final Uint8List gsubBytes = _buildGsubSingleSubst();

  // MATH table: constants (axisHeight=250 + VariationIndex(0,1) -> +40 at peak),
  // MathGlyphInfo with 4-corner MathKern staircase for gid 1
  final Uint8List mathBytes = _buildMathTableWithKernAndVar();

  // CFF2 table with Top DICT, Global Subr, FDArray, Private DICT (blend),
  // CharStrings (hstem, vstem, hintmask, blend, rmoveto, hlineto, vlineto)
  final Uint8List cff2Bytes = _buildCff2Table(ivsBytes);

  return _assembleSfnt(0x4F54544F, <String, Uint8List>{
    'head': _buildHeadTable(unitsPerEm: 1000, locaFormat: 0),
    'maxp': _buildMaxpTable(4, isTrueType: false),
    'hhea': _buildHheaTable(4),
    'hmtx': _buildHmtxTable(<int>[500, 500, 400, 300], <int>[0, 0, 0, 0]),
    'name': _buildNameTable('SynthVarCFF2'),
    'cmap': _buildCmapFormat4(<int, int>{0x0041: 1}),
    'fvar': fvar.toBytes(),
    'avar': avar.toBytes(),
    'HVAR': hvar.toBytes(),
    'GDEF': gdef.toBytes(),
    'GSUB': gsubBytes,
    'MATH': mathBytes,
    'CFF2': cff2Bytes,
  });
}

Uint8List _buildGsubSingleSubst() {
  // ScriptList (24 bytes): count=1, 'math'@8, Script@8: dflt@4, langCnt=0, LangSys@12: 0, 0xFFFF, 1, 0
  final _ByteWriter scriptList = _ByteWriter()
    ..u16(1)
    ..tag('math')
    ..u16(8)
    ..u16(4)
    ..u16(0)
    ..u16(0)
    ..u16(0xFFFF)
    ..u16(1)
    ..u16(0);

  // FeatureList (18 bytes): count=1, 'ssty'@8 -> params=0, cnt=2, [0, 1]
  final _ByteWriter featureList = _ByteWriter()
    ..u16(1)
    ..tag('ssty')
    ..u16(8)
    ..u16(0)
    ..u16(2)
    ..u16(0)
    ..u16(1);

  // Lookup 0 (SingleSubst Format 1: gid 1 -> +1 = 2)
  // Header(8) + subtable(6 + Coverage(6) = 12) = 20 bytes
  final _ByteWriter l0 = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(1)
    ..u16(8)
    ..u16(1) // fmt 1
    ..u16(6) // cov offset rel to subtable
    ..i16(1) // deltaGlyphID = +1
    ..u16(1) // cov fmt 1
    ..u16(1) // cov count 1
    ..u16(1); // gid 1

  // Lookup 1 (SingleSubst Format 2: gid 2 -> 3)
  // Header(8) + subtable(8 + Coverage(6) = 14) = 22 bytes
  final _ByteWriter l1 = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(1)
    ..u16(8)
    ..u16(2) // fmt 2
    ..u16(8) // cov offset rel to subtable
    ..u16(1) // glyphCount
    ..u16(3) // substituteGlyphIDs[0] = 3
    ..u16(1) // cov fmt 1
    ..u16(1) // cov count 1
    ..u16(2); // gid 2

  final int slOff = 10;
  final int flOff = slOff + scriptList.length;
  final int llOff = flOff + featureList.length;
  final int l0Off = 6; // rel to LookupList
  final int l1Off = l0Off + l0.length;

  final _ByteWriter out = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(slOff)
    ..u16(flOff)
    ..u16(llOff)
    ..bytes(scriptList.toBytes())
    ..bytes(featureList.toBytes())
    ..u16(2)
    ..u16(l0Off)
    ..u16(l1Off)
    ..bytes(l0.toBytes())
    ..bytes(l1.toBytes());
  return out.toBytes();
}

Uint8List _buildMathTableWithKernAndVar() {
  // MathConstants: 214 bytes + 6-byte VariationIndex(0, 1) at offset 214!
  final _ByteWriter mc = _ByteWriter()
    ..i16(70)
    ..i16(50)
    ..u16(1200)
    ..u16(1200);
  for (int i = 0; i < 51; i++) {
    if (i == 1) {
      // axisHeight = 250 + VariationIndex at offset 214
      mc
        ..i16(250)
        ..u16(214);
    } else {
      mc
        ..i16(100)
        ..u16(0);
    }
  }
  mc
    ..i16(60) // radicalDegreeBottomRaisePercent
    // VariationIndex @ 214
    ..u16(0) // deltaSetOuterIndex = 0
    ..u16(2) // deltaSetInnerIndex = 2 (delta +40)
    ..u16(0x8000); // deltaFormat = VARIATION_INDEX

  // MathGlyphInfo: only mathKernInfoOffset populated
  // Header(8) -> MathKernInfo @ 8:
  // covOffset=12, kernCount=1, MathKernInfoRecord(8): tr=18, tl=0, br=0, bl=36
  // Coverage @ 12: fmt=1, cnt=1, gid=1 (6 bytes -> ends 18)
  // MathKern tr @ 18: heightCount=2, heights=[100, 200], kerns=[-10, -30, -60]
  //   size = 2 + (2 + 3)*4 = 22 bytes? Wait: 18 + 22 = 40, so bl @ 40!
  // MathKern bl @ 40: heightCount=0, kerns=[15] (size = 6 bytes)
  final _ByteWriter mgi = _ByteWriter()
    ..u16(0) // italics
    ..u16(0) // topAccent
    ..u16(0) // extShape
    ..u16(8) // mathKernInfoOffset
    // MathKernInfo @ 8 (rel to MathGlyphInfo -> base 0 inside MathKernInfo)
    ..u16(12) // covOff (rel to MathKernInfo)
    ..u16(1) // count
    ..u16(18) // tr
    ..u16(0) // tl
    ..u16(0) // br
    ..u16(40) // bl
    // Coverage @ 12 (6 bytes)
    ..u16(1)
    ..u16(1)
    ..u16(1)
    // MathKern tr @ 18 (22 bytes)
    ..u16(2) // heightCount
    ..i16(100)
    ..u16(0)
    ..i16(200)
    ..u16(0)
    ..i16(-10)
    ..u16(0)
    ..i16(-30)
    ..u16(0)
    ..i16(-60)
    ..u16(0)
    // MathKern bl @ 40 (6 bytes)
    ..u16(0)
    ..i16(15)
    ..u16(0);

  final int mcOff = 10;
  final int giOff = mcOff + mc.length;
  final _ByteWriter out = _ByteWriter()
    ..u16(1)
    ..u16(0)
    ..u16(mcOff)
    ..u16(giOff)
    ..u16(0) // variantsOffset = 0
    ..bytes(mc.toBytes())
    ..bytes(mgi.toBytes());
  return out.toBytes();
}

void _encodeCffInt(_ByteWriter w, int value) {
  if (value >= -107 && value <= 107) {
    w.u8(value + 139);
  } else if (value >= 108 && value <= 1131) {
    final int adj = value - 108;
    w.u8((adj >> 8) + 247);
    w.u8(adj & 0xFF);
  } else if (value >= -1131 && value <= -108) {
    final int adj = -value - 108;
    w.u8((adj >> 8) + 251);
    w.u8(adj & 0xFF);
  } else {
    w
      ..u8(29)
      ..i32(value);
  }
}

Uint8List _buildCff2Index(List<Uint8List> items) {
  final _ByteWriter w = _ByteWriter()..u32(items.length);
  if (items.isEmpty) {
    return w.toBytes();
  }
  w.u8(4); // offSize = 4
  int off = 1;
  w.u32(off);
  for (final Uint8List item in items) {
    off += item.length;
    w.u32(off);
  }
  for (final Uint8List item in items) {
    w.bytes(item);
  }
  return w.toBytes();
}

Uint8List _buildCff2Table(Uint8List ivsBytes) {
  // Build CharStrings:
  // gid 0 (.notdef): empty
  // gid 1:
  //   0 700 hstem (1)
  //   0 200 200 1 blend vstem (wait: test blend on vstem/path!)
  //   Actually:
  //     0 700 hstem
  //     0 200 vstem
  //     0xC0 hintmask (2 stems -> 1 byte mask!)
  //     0 0 rmoveto
  //     200 200 1 blend hlineto  (width = 200 + 200*coord!)
  //     700 vlineto
  //     -200 -200 1 blend hlineto
  //     -700 vlineto
  final _ByteWriter cs1 = _ByteWriter();
  _encodeCffInt(cs1, 0);
  _encodeCffInt(cs1, 700);
  cs1.u8(1); // hstem
  _encodeCffInt(cs1, 0);
  _encodeCffInt(cs1, 200);
  cs1.u8(3); // vstem
  cs1.u8(19); // hintmask
  cs1.u8(0xC0); // mask byte for 2 stems
  _encodeCffInt(cs1, 0);
  _encodeCffInt(cs1, 0);
  cs1.u8(21); // rmoveto
  _encodeCffInt(cs1, 200);
  _encodeCffInt(cs1, 200);
  _encodeCffInt(cs1, 1);
  cs1.u8(16); // blend
  cs1.u8(6); // hlineto
  _encodeCffInt(cs1, 700);
  cs1.u8(7); // vlineto
  _encodeCffInt(cs1, -200);
  _encodeCffInt(cs1, -200);
  _encodeCffInt(cs1, 1);
  cs1.u8(16); // blend
  cs1.u8(6); // hlineto
  _encodeCffInt(cs1, -700);
  cs1.u8(7); // vlineto

  final Uint8List csIndex = _buildCff2Index(<Uint8List>[
    Uint8List(0),
    cs1.toBytes(),
    Uint8List(0),
    Uint8List(0),
  ]);

  // Private DICT: BlueValues [-10, 10, 700, 720] (deltas: -10, 20, 690, 20)
  // plus StdVW with blend!
  final _ByteWriter priv = _ByteWriter();
  _encodeCffInt(priv, -10);
  _encodeCffInt(priv, 20);
  _encodeCffInt(priv, 690);
  _encodeCffInt(priv, 20);
  priv.u8(6); // BlueValues
  _encodeCffInt(priv, 200);
  _encodeCffInt(priv, 200);
  _encodeCffInt(priv, 1);
  priv.u8(23); // Private DICT blend
  priv.u8(11); // StdVW
  final Uint8List privBytes = priv.toBytes();

  final Uint8List gsubrs = _buildCff2Index(<Uint8List>[]);

  // Fixed-size Top DICT encoding using 5-byte int32 (opcode 29) for all offsets
  // so Top DICT length is known before placing subsequent sections:
  //   [charStringsOffset] 17
  //   [vstoreOffset] 24
  //   [fdArrayOffset] 12 36
  // Each 5-byte int + 1-or-2-byte op = 6 + 6 + 7 = 19 bytes.
  const int hdrSize = 5;
  const int topDictLen = 19;
  final int gsubrOff = hdrSize + topDictLen;
  final int vstoreOff = gsubrOff + gsubrs.length;
  final int vstoreTotalLen = 2 + ivsBytes.length;
  final int privOff = vstoreOff + vstoreTotalLen;

  // Build Font DICT (inside FDArray) pointing to privOff
  final _ByteWriter fd0 = _ByteWriter();
  _encodeCffInt(fd0, privBytes.length);
  _encodeCffInt(fd0, privOff);
  fd0.u8(18); // Private
  final Uint8List fdArray = _buildCff2Index(<Uint8List>[fd0.toBytes()]);

  final int fdArrayOff = privOff + privBytes.length;
  final int csOff = fdArrayOff + fdArray.length;

  final _ByteWriter topDict = _ByteWriter()
    ..u8(29)
    ..i32(csOff)
    ..u8(17) // CharStrings
    ..u8(29)
    ..i32(vstoreOff)
    ..u8(24) // vstore
    ..u8(29)
    ..i32(fdArrayOff)
    ..u8(12)
    ..u8(36); // FDArray

  final _ByteWriter cff2 = _ByteWriter()
    ..u8(2) // major
    ..u8(0) // minor
    ..u8(hdrSize)
    ..u16(topDictLen)
    ..bytes(topDict.toBytes())
    ..bytes(gsubrs)
    ..u16(ivsBytes.length)
    ..bytes(ivsBytes)
    ..bytes(privBytes)
    ..bytes(fdArray)
    ..bytes(csIndex);
  return cff2.toBytes();
}

Uint8List _buildCff1Index(List<Uint8List> items) {
  final _ByteWriter w = _ByteWriter()..u16(items.length);
  if (items.isEmpty) {
    return w.toBytes();
  }
  w.u8(4); // offSize = 4
  int off = 1;
  w.u32(off);
  for (final Uint8List item in items) {
    off += item.length;
    w.u32(off);
  }
  for (final Uint8List item in items) {
    w.bytes(item);
  }
  return w.toBytes();
}

Uint8List _buildOs2Table({required int xHeight, required int capHeight}) {
  final _ByteWriter w = _ByteWriter()
    ..u16(4) // version 4
    ..zeros(66)
    ..i16(800) // sTypoAscender @ 68
    ..i16(-200) // sTypoDescender @ 70
    ..zeros(14)
    ..i16(xHeight) // sxHeight @ 86
    ..i16(capHeight) // sCapHeight @ 88
    ..zeros(6);
  return w.toBytes();
}

Uint8List _buildCmapMixedFormat4And12() {
  // Format 4 using idRangeOffset != 0 for U+03B1 -> gid 2
  final _ByteWriter fmt4 = _ByteWriter()
    ..u16(4)
    ..u16(34) // length
    ..u16(0)
    ..u16(4) // segCountX2 = 4 (2 segments)
    ..u16(4)
    ..u16(1)
    ..u16(0)
    ..u16(0x03B1)
    ..u16(0xFFFF)
    ..u16(0) // reservedPad
    ..u16(0x03B1)
    ..u16(0xFFFF)
    ..i16(0) // idDelta[0]
    ..i16(1) // idDelta[1]
    ..u16(4) // idRangeOffset[0] points 4 bytes forward (past idRangeOffset[1])
    ..u16(0)
    ..u16(2); // glyphIdArray[0] = gid 2

  // Format 12 mapping U+1D44E -> gid 1
  final _ByteWriter fmt12 = _ByteWriter()
    ..u16(12)
    ..u16(0)
    ..u32(28)
    ..u32(0)
    ..u32(1) // numGroups = 1
    ..u32(0x1D44E)
    ..u32(0x1D44E)
    ..u32(1);

  final int fmt4Off = 20;
  final int fmt12Off = fmt4Off + fmt4.length;
  final _ByteWriter w = _ByteWriter()
    ..u16(0)
    ..u16(2)
    ..u16(3)
    ..u16(1)
    ..u32(fmt4Off)
    ..u16(3)
    ..u16(10)
    ..u32(fmt12Off)
    ..bytes(fmt4.toBytes())
    ..bytes(fmt12.toBytes());
  return w.toBytes();
}

Uint8List _buildSyntheticCff1CidFont() {
  // Global Subr 0 (bias 107 -> index -107): computes (50 + 50) = 100 and returns
  final _ByteWriter gsubr0 = _ByteWriter();
  _encodeCffInt(gsubr0, 50);
  _encodeCffInt(gsubr0, 50);
  gsubr0
    ..u8(12)
    ..u8(10) // add
    ..u8(11); // return

  // Local Subr 0 (FD 0): pushes 0 and 0, draws hlineto/vlineto, returns
  final _ByteWriter lsubr0 = _ByteWriter();
  _encodeCffInt(lsubr0, 25);
  _encodeCffInt(lsubr0, 2);
  lsubr0
    ..u8(12)
    ..u8(24) // mul -> 50
    ..u8(11); // return

  // Glyph 1 (uses FD 0): exercises callgsubr, callsubr, arithmetic, cntrmask,
  // hflex, flex, hflex1, flex1, hhcurveto, vvcurveto, hvcurveto, vhcurveto,
  // rcurveline, rlinecurve.
  final _ByteWriter cs1 = _ByteWriter();
  _encodeCffInt(cs1, 0); // width delta (nominal 500 + 0)
  _encodeCffInt(cs1, 0);
  _encodeCffInt(cs1, 100);
  cs1.u8(1); // hstem
  cs1
    ..u8(20) // cntrmask
    ..u8(0x80);
  _encodeCffInt(cs1, -107);
  cs1.u8(29); // callgsubr -> pushes 100
  _encodeCffInt(cs1, -107);
  cs1.u8(10); // callsubr -> pushes 50
  cs1.u8(21); // rmoveto(100, 50)
  // arithmetic: put/get, dup, exch, index, roll, neg, abs, sqrt, sub, div, ifelse
  _encodeCffInt(cs1, 16);
  cs1
    ..u8(12)
    ..u8(26) // sqrt(16) = 4
    ..u8(12)
    ..u8(27); // dup -> 4, 4
  _encodeCffInt(cs1, 0);
  cs1
    ..u8(12)
    ..u8(20); // put slot 0 = 4 (pops index 0, val 4)
  _encodeCffInt(cs1, 0);
  cs1
    ..u8(12)
    ..u8(21) // get slot 0 -> 4
    ..u8(12)
    ..u8(10) // add -> 8
    ..u8(12)
    ..u8(14) // neg -> -8
    ..u8(12)
    ..u8(9); // abs -> 8
  _encodeCffInt(cs1, 2);
  cs1
    ..u8(12)
    ..u8(12); // div -> 4
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  _encodeCffInt(cs1, 1);
  _encodeCffInt(cs1, 2);
  cs1
    ..u8(12)
    ..u8(22); // ifelse -> stack [4, 10]
  cs1
    ..u8(12)
    ..u8(28); // exch -> stack [10, 4]
  _encodeCffInt(cs1, 0);
  cs1
    ..u8(12)
    ..u8(29); // index 0 -> stack [10, 4, 4]
  _encodeCffInt(cs1, 3);
  _encodeCffInt(cs1, 1);
  cs1
    ..u8(12)
    ..u8(30); // roll(3, 1) -> stack [4, 10, 4]
  // Clear with hlineto of remaining stack values
  cs1.u8(6); // hlineto
  // hhcurveto & vvcurveto
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  cs1.u8(27); // hhcurveto
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  cs1.u8(26); // vvcurveto
  // hvcurveto & vhcurveto
  _encodeCffInt(cs1, 20);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  cs1.u8(31); // hvcurveto
  _encodeCffInt(cs1, 20);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 10);
  _encodeCffInt(cs1, 20);
  cs1.u8(30); // vhcurveto
  // rcurveline & rlinecurve
  for (int i = 0; i < 8; i++) {
    _encodeCffInt(cs1, 5);
  }
  cs1.u8(24); // rcurveline
  for (int i = 0; i < 8; i++) {
    _encodeCffInt(cs1, 5);
  }
  cs1.u8(25); // rlinecurve
  // hflex (7 args)
  for (int i = 0; i < 7; i++) {
    _encodeCffInt(cs1, 10);
  }
  cs1
    ..u8(12)
    ..u8(34);
  // flex (13 args)
  for (int i = 0; i < 13; i++) {
    _encodeCffInt(cs1, 10);
  }
  cs1
    ..u8(12)
    ..u8(35);
  // hflex1 (9 args)
  for (int i = 0; i < 9; i++) {
    _encodeCffInt(cs1, 10);
  }
  cs1
    ..u8(12)
    ..u8(36);
  // flex1 (11 args)
  for (int i = 0; i < 11; i++) {
    _encodeCffInt(cs1, 10);
  }
  cs1
    ..u8(12)
    ..u8(37);
  cs1.u8(14); // endchar

  // Glyph 2 (uses FD 1): simple box (0,0)-(300,400)
  final _ByteWriter cs2 = _ByteWriter();
  _encodeCffInt(cs2, 0);
  _encodeCffInt(cs2, 0);
  cs2.u8(21); // rmoveto
  _encodeCffInt(cs2, 300);
  _encodeCffInt(cs2, 400);
  _encodeCffInt(cs2, -300);
  cs2.u8(6); // hlineto
  cs2.u8(14); // endchar

  final Uint8List nameIdx = _buildCff1Index(<Uint8List>[
    Uint8List.fromList('SynthCID'.codeUnits),
  ]);
  final Uint8List strIdx = _buildCff1Index(<Uint8List>[]);
  final Uint8List gsubrIdx = _buildCff1Index(<Uint8List>[gsubr0.toBytes()]);
  final Uint8List csIdx = _buildCff1Index(<Uint8List>[
    Uint8List.fromList(<int>[14]), // .notdef endchar
    cs1.toBytes(),
    cs2.toBytes(),
  ]);

  // FDSelect Format 3: [0..2) -> FD 0, [2..3) -> FD 1, sentinel 3
  final _ByteWriter fdSelect = _ByteWriter()
    ..u8(3)
    ..u16(2)
    ..u16(0)
    ..u8(0)
    ..u16(2)
    ..u8(1)
    ..u16(3);

  // Local Subrs for FD 0
  final Uint8List lsubr0Idx = _buildCff1Index(<Uint8List>[lsubr0.toBytes()]);
  // Private DICT for FD 0 (placed right before lsubr0Idx): nominalWidthX=500, Subrs=size_of_priv0
  // Encode with fixed-size 5-byte int32 for Subrs offset: 6 + 6 = 12 bytes
  final _ByteWriter priv0 = _ByteWriter()
    ..u8(29)
    ..i32(500)
    ..u8(21) // nominalWidthX
    ..u8(29)
    ..i32(12)
    ..u8(19); // Subrs rel to priv0 start

  final _ByteWriter priv1 = _ByteWriter()
    ..u8(29)
    ..i32(650)
    ..u8(20); // defaultWidthX = 650

  // Top DICT fixed size using 5-byte int32 offsets:
  // charStringsOffset (17): 6 bytes
  // fdArrayOffset (12 36): 7 bytes
  // fdSelectOffset (12 37): 7 bytes
  // Total = 20 bytes
  const int hdrSize = 4;
  // Build Top DICT placeholder first so we know Top DICT INDEX size!
  Uint8List makeTopDictIdx(int csOff, int fdArrOff, int fdSelOff) {
    final _ByteWriter td = _ByteWriter()
      ..u8(29)
      ..i32(csOff)
      ..u8(17)
      ..u8(29)
      ..i32(fdArrOff)
      ..u8(12)
      ..u8(36)
      ..u8(29)
      ..i32(fdSelOff)
      ..u8(12)
      ..u8(37);
    return _buildCff1Index(<Uint8List>[td.toBytes()]);
  }

  final Uint8List dummyTdIdx = makeTopDictIdx(0, 0, 0);
  final int afterGsubr =
      hdrSize +
      nameIdx.length +
      dummyTdIdx.length +
      strIdx.length +
      gsubrIdx.length;
  final int priv0Off = afterGsubr;
  final int lsubr0Off = priv0Off + priv0.length;
  final int priv1Off = lsubr0Off + lsubr0Idx.length;
  final int fdArrayOff = priv1Off + priv1.length;

  final _ByteWriter fd0 = _ByteWriter()
    ..u8(29)
    ..i32(priv0.length)
    ..u8(29)
    ..i32(priv0Off)
    ..u8(18);
  final _ByteWriter fd1 = _ByteWriter()
    ..u8(29)
    ..i32(priv1.length)
    ..u8(29)
    ..i32(priv1Off)
    ..u8(18);
  final Uint8List fdArrayIdx = _buildCff1Index(<Uint8List>[
    fd0.toBytes(),
    fd1.toBytes(),
  ]);

  final int fdSelectOff = fdArrayOff + fdArrayIdx.length;
  final int csOff = fdSelectOff + fdSelect.length;
  final Uint8List realTdIdx = makeTopDictIdx(csOff, fdArrayOff, fdSelectOff);

  final _ByteWriter cff = _ByteWriter()
    ..u8(1)
    ..u8(0)
    ..u8(hdrSize)
    ..u8(4)
    ..bytes(nameIdx)
    ..bytes(realTdIdx)
    ..bytes(strIdx)
    ..bytes(gsubrIdx)
    ..bytes(priv0.toBytes())
    ..bytes(lsubr0Idx)
    ..bytes(priv1.toBytes())
    ..bytes(fdArrayIdx)
    ..bytes(fdSelect.toBytes())
    ..bytes(csIdx);

  return _assembleSfnt(0x4F54544F, <String, Uint8List>{
    'head': _buildHeadTable(unitsPerEm: 1000, locaFormat: 0),
    'maxp': _buildMaxpTable(3, isTrueType: false),
    'hhea': _buildHheaTable(3),
    'hmtx': _buildHmtxTable(<int>[500, 500, 650], <int>[0, 0, 0]),
    'OS/2': _buildOs2Table(xHeight: 440, capHeight: 690),
    'name': _buildNameTable('SynthCID'),
    'cmap': _buildCmapMixedFormat4And12(),
    'CFF ': cff.toBytes(),
  });
}

Uint8List _buildExtendedTrueTypeFont() {
  // Glyph 1: all-off-curve 4-point contour: (0,0), (0,200), (200,200), (200,0)
  final _ByteWriter g1 = _ByteWriter()
    ..i16(1)
    ..i16(0)
    ..i16(0)
    ..i16(200)
    ..i16(200)
    ..u16(3)
    ..u16(0)
    ..u8(0x00)
    ..u8(0x00)
    ..u8(0x00)
    ..u8(0x00)
    ..i16(0)
    ..i16(0)
    ..i16(200)
    ..i16(0)
    ..i16(0)
    ..i16(200)
    ..i16(0)
    ..i16(-200);
  final Uint8List g1Bytes = g1.toBytes();

  // Glyph 2: two components:
  // Comp A: gid 1 with WE_HAVE_A_TWO_BY_TWO (0x80) | ARGS_ARE_XY_VALUES (0x02) |
  //         MORE_COMPONENTS (0x20) | SCALED_COMPONENT_OFFSET (0x0800)
  //         90 deg rotation: a=0, b=1, c=-1, d=0
  // Comp B: gid 1 point-matched (ARGS_ARE_XY_VALUES = 0): pt 0 matched to pt 2
  final _ByteWriter g2 = _ByteWriter()
    ..i16(-1)
    ..i16(-200)
    ..i16(0)
    ..i16(200)
    ..i16(200)
    ..u16(0x08A2) // flags: ARGS_ARE_XY | MORE | TWO_BY_TWO | SCALED_OFFSET
    ..u16(1)
    ..i8(0)
    ..i8(0)
    ..f2dot14(0.0)
    ..f2dot14(1.0)
    ..f2dot14(-1.0)
    ..f2dot14(0.0)
    ..u16(0x0000) // point match (8-bit parentPt=0, childPt=2), no more
    ..u16(1)
    ..u8(0)
    ..u8(2);
  final Uint8List g2Bytes = g2.toBytes();

  final _ByteWriter glyf = _ByteWriter()
    ..bytes(g1Bytes)
    ..bytes(g2Bytes);
  final int off2 = g1Bytes.length;
  final int off3 = off2 + g2Bytes.length;

  final _ByteWriter loca = _ByteWriter()
    ..u32(0)
    ..u32(0)
    ..u32(off2)
    ..u32(off3);

  return _assembleSfnt(0x00010000, <String, Uint8List>{
    'head': _buildHeadTable(unitsPerEm: 1000, locaFormat: 1),
    'maxp': _buildMaxpTable(3, isTrueType: true),
    'hhea': _buildHheaTable(3),
    'hmtx': _buildHmtxTable(<int>[500, 400, 400], <int>[0, 0, 0]),
    'name': _buildNameTable('SynthExtTT'),
    'loca': loca.toBytes(),
    'glyf': glyf.toBytes(),
  });
}
