import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../ast.dart';
import '../display_list.dart';
import '../error.dart';
import '../font.dart';
import '../options.dart';
import '../source_span.dart';

/// Immutable TeX-style rectangular box node produced during math layout.
///
/// Coordinates follow the mathematical Y-up convention in em units where the
/// box origin lies on its baseline (`y = 0`), ascent extends upward by
/// [heightEm], and descent extends downward by [depthEm].
@immutable
sealed class MathBox {
  /// Base constructor for immutable math layout boxes.
  const MathBox({
    required this.widthEm,
    required this.heightEm,
    required this.depthEm,
    this.atomClass = TexMathAtomClass.ord,
    this.italicsCorrectionEm = 0.0,
    this.shiftYEm = 0.0,
    this.span,
    this.colorRole = TexMathColorRole.foreground,
    this.customColor,
    this.inheritColor = true,
    this.breakPoint = BreakPoint.none,
  });

  /// Advance width of the box in ems.
  final double widthEm;

  /// Distance above the box baseline in ems.
  final double heightEm;

  /// Distance below the box baseline in ems.
  final double depthEm;

  /// Appendix G mathematical atom classification used for outer spacing.
  final TexMathAtomClass atomClass;

  /// OpenType `MATH` italics correction available after this box in ems.
  final double italicsCorrectionEm;

  /// Optional baseline-relative vertical shift applied by enclosing [HBox]es.
  final double shiftYEm;

  /// Optional source span tracing this box back to TeX input.
  final SourceSpan? span;

  /// Semantic color role for painting primitives inside this box.
  final TexMathColorRole colorRole;

  /// Optional 32-bit ARGB color when [colorRole] is [TexMathColorRole.custom].
  final int? customColor;

  /// Whether this box inherits an enclosing container's explicit color.
  final bool inheritColor;

  /// Line-breaking metadata attached to this box.
  final BreakPoint breakPoint;

  /// Total vertical extent (`heightEm + depthEm`) in ems.
  double get totalHeightEm => heightEm + depthEm;

  bool _baseEquals(MathBox other) =>
      widthEm == other.widthEm &&
      heightEm == other.heightEm &&
      depthEm == other.depthEm &&
      atomClass == other.atomClass &&
      italicsCorrectionEm == other.italicsCorrectionEm &&
      shiftYEm == other.shiftYEm &&
      span == other.span &&
      colorRole == other.colorRole &&
      customColor == other.customColor &&
      inheritColor == other.inheritColor &&
      breakPoint == other.breakPoint;

  int get _baseHash => Object.hash(
    widthEm,
    heightEm,
    depthEm,
    atomClass,
    italicsCorrectionEm,
    shiftYEm,
    span,
    colorRole,
    customColor,
    inheritColor,
    breakPoint,
  );

  /// Returns a wrapper or copy of this box with overridden metadata.
  MathBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  });

  /// Flattens this box hierarchy into a coordinate-resolved [DisplayList].
  ///
  /// Throws [TexMathBudgetError] if the emitted item count exceeds
  /// [maxOutputItems].
  DisplayList toDisplayList({
    int unitsPerEm = 1000,
    String? source,
    int maxOutputItems = TexMathBudgets.defaultMaxOutputItems,
    int? fontSignature,
  }) {
    final List<DisplayItem> items = <DisplayItem>[];
    final List<DisplayBreakHint> breakHints = <DisplayBreakHint>[];
    _flattenWithBreaks(
      items: items,
      breakHints: breakHints,
      originXEm: 0.0,
      originYEm: shiftYEm,
      inheritedRole: TexMathColorRole.foreground,
      inheritedCustomColor: null,
      maxOutputItems: maxOutputItems,
    );
    return DisplayList(
      metrics: DisplayMetrics(
        widthEm: math.max(0.0, widthEm),
        heightEm: math.max(0.0, heightEm + shiftYEm),
        depthEm: math.max(0.0, depthEm - shiftYEm),
        unitsPerEm: unitsPerEm,
      ),
      items: items.isEmpty
          ? const <DisplayItem>[]
          : List<DisplayItem>.unmodifiable(items),
      source: source,
      breakHints: breakHints.isEmpty
          ? const <DisplayBreakHint>[]
          : List<DisplayBreakHint>.unmodifiable(breakHints),
      fontSignature: fontSignature,
    );
  }

  void _flattenWithBreaks({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    _flattenInto(
      items: items,
      breakHints: breakHints,
      originXEm: originXEm,
      originYEm: originYEm,
      inheritedRole: inheritedRole,
      inheritedCustomColor: inheritedCustomColor,
      maxOutputItems: maxOutputItems,
    );
    if (breakPoint != BreakPoint.none) {
      breakHints.add(
        DisplayBreakHint(
          xEm: originXEm + widthEm,
          afterItemIndex: items.length - 1,
          breakPoint: breakPoint,
          span: span,
        ),
      );
    }
  }

  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  });

  static void _appendItem(
    List<DisplayItem> items,
    DisplayItem item,
    int maxOutputItems,
    SourceSpan? span,
  ) {
    if (items.length >= maxOutputItems) {
      throw TexMathBudgetError(
        'DisplayList item count exceeds limit $maxOutputItems.',
        budgetName: 'maxOutputItems',
        limit: maxOutputItems,
        actual: items.length + 1,
        span: span,
      );
    }
    items.add(item);
  }

  static (TexMathColorRole, int?) _resolveColor(
    MathBox box,
    TexMathColorRole inheritedRole,
    int? inheritedCustomColor,
  ) {
    if (!box.inheritColor) {
      return (box.colorRole, box.customColor);
    }
    if (box.colorRole != TexMathColorRole.foreground ||
        box.customColor != null) {
      return (box.colorRole, box.customColor);
    }
    return (inheritedRole, inheritedCustomColor);
  }
}

/// Positioned glyph box referencing a resolved font glyph ID and optional
/// vector outline.
@immutable
final class GlyphBox extends MathBox {
  /// Creates an immutable glyph box.
  const GlyphBox({
    required this.glyphId,
    required this.codePoint,
    required super.widthEm,
    required super.heightEm,
    required super.depthEm,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    double? advanceEm,
    this.xOffsetEm = 0.0,
    this.yOffsetEm = 0.0,
    this.outline,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  }) : advanceEm = advanceEm ?? widthEm;

  /// OpenType glyph ID in the active [MathFont].
  final int glyphId;

  /// Unicode scalar associated with this glyph, or `0` for unencoded parts.
  final int codePoint;

  /// Horizontal scale factor applied when rendering the glyph outline.
  final double scaleX;

  /// Vertical scale factor applied when rendering the glyph outline.
  final double scaleY;

  /// Logical glyph advance width in ems.
  final double advanceEm;

  /// Horizontal drawing offset relative to the box origin in ems.
  final double xOffsetEm;

  /// Vertical drawing offset relative to the box baseline in ems.
  final double yOffsetEm;

  /// Optional vector glyph outline in font design units.
  final GlyphOutline? outline;

  @override
  GlyphBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return GlyphBox(
      glyphId: glyphId,
      codePoint: codePoint,
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      scaleX: scaleX,
      scaleY: scaleY,
      advanceEm: advanceEm,
      xOffsetEm: xOffsetEm,
      yOffsetEm: yOffsetEm,
      outline: outline,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    final (TexMathColorRole role, int? custom) = MathBox._resolveColor(
      this,
      inheritedRole,
      inheritedCustomColor,
    );
    MathBox._appendItem(
      items,
      GlyphItem(
        glyphId: glyphId,
        codePoint: codePoint,
        xEm: originXEm + xOffsetEm,
        yEm: originYEm + yOffsetEm,
        scaleX: scaleX,
        scaleY: scaleY,
        advanceEm: advanceEm,
        outline: outline,
        span: span,
        colorRole: role,
        customColor: custom,
      ),
      maxOutputItems,
      span,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlyphBox &&
          _baseEquals(other) &&
          glyphId == other.glyphId &&
          codePoint == other.codePoint &&
          scaleX == other.scaleX &&
          scaleY == other.scaleY &&
          advanceEm == other.advanceEm &&
          xOffsetEm == other.xOffsetEm &&
          yOffsetEm == other.yOffsetEm &&
          outline == other.outline;

  @override
  int get hashCode => Object.hash(
    _baseHash,
    glyphId,
    codePoint,
    scaleX,
    scaleY,
    advanceEm,
    xOffsetEm,
    yOffsetEm,
    outline,
  );
}

/// Rectangular filled or stroked rule box (fraction bars, radical overbars,
/// array rules, and `\boxed` borders).
@immutable
final class RuleBox extends MathBox {
  /// Creates a rule box with [widthEm], [heightEm], and [depthEm].
  const RuleBox({
    required super.widthEm,
    required super.heightEm,
    super.depthEm = 0.0,
    this.strokeWidthEm,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  });

  /// When non-null, renders as an unfilled stroked frame with this thickness.
  final double? strokeWidthEm;

  @override
  RuleBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return RuleBox(
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      strokeWidthEm: strokeWidthEm,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    final (TexMathColorRole role, int? custom) = MathBox._resolveColor(
      this,
      inheritedRole,
      inheritedCustomColor,
    );
    MathBox._appendItem(
      items,
      RuleItem(
        xEm: originXEm,
        yEm: originYEm - depthEm,
        widthEm: widthEm,
        heightEm: math.max(0.0, heightEm + depthEm),
        strokeWidthEm: strokeWidthEm,
        span: span,
        colorRole: role,
        customColor: custom,
      ),
      maxOutputItems,
      span,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuleBox &&
          _baseEquals(other) &&
          strokeWidthEm == other.strokeWidthEm;

  @override
  int get hashCode => Object.hash(_baseHash, strokeWidthEm);
}

/// Invisible horizontal spacing or kern box (positive or negative).
@immutable
final class KernBox extends MathBox {
  /// Creates a non-inked spacing box with width [widthEm].
  const KernBox({
    required super.widthEm,
    super.heightEm = 0.0,
    super.depthEm = 0.0,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  });

  @override
  KernBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return KernBox(
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    // Invisible spacing emits no primitive.
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KernBox && _baseEquals(other);

  @override
  int get hashCode => Object.hash(KernBox, _baseHash);
}

/// Non-inked semantic anchor box emitting an [AnchorItem] for labels and tags.
@immutable
final class AnchorBox extends MathBox {
  /// Creates a zero-ink semantic anchor box.
  const AnchorBox({
    required this.id,
    this.label,
    super.widthEm = 0.0,
    super.heightEm = 0.0,
    super.depthEm = 0.0,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  });

  /// Identifier written to [AnchorItem.id].
  final String id;

  /// Optional label text written to [AnchorItem.label].
  final String? label;

  @override
  AnchorBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return AnchorBox(
      id: id,
      label: label,
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    final (TexMathColorRole role, int? custom) = MathBox._resolveColor(
      this,
      inheritedRole,
      inheritedCustomColor,
    );
    MathBox._appendItem(
      items,
      AnchorItem(
        id: id,
        xEm: originXEm,
        yEm: originYEm,
        label: label,
        span: span,
        colorRole: role,
        customColor: custom,
      ),
      maxOutputItems,
      span,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnchorBox &&
          _baseEquals(other) &&
          id == other.id &&
          label == other.label;

  @override
  int get hashCode => Object.hash(_baseHash, id, label);
}

/// Horizontal box laying out [children] sequentially along the X axis.
@immutable
final class HBox extends MathBox {
  const HBox._({
    required this.children,
    required super.widthEm,
    required super.heightEm,
    required super.depthEm,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  });

  /// Creates an [HBox] flowing [children] left-to-right and computing
  /// bounding metrics when omitted.
  factory HBox({
    required List<MathBox> children,
    double? widthEm,
    double? heightEm,
    double? depthEm,
    TexMathAtomClass atomClass = TexMathAtomClass.ord,
    double italicsCorrectionEm = 0.0,
    double shiftYEm = 0.0,
    SourceSpan? span,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    BreakPoint breakPoint = BreakPoint.none,
  }) {
    double computedWidth = 0.0;
    double computedHeight = 0.0;
    double computedDepth = 0.0;
    if (children.isNotEmpty) {
      computedHeight = double.negativeInfinity;
      computedDepth = double.negativeInfinity;
      for (int i = 0; i < children.length; i++) {
        final MathBox child = children[i];
        computedWidth += child.widthEm;
        final double childTop = child.heightEm + child.shiftYEm;
        final double childBottom = child.depthEm - child.shiftYEm;
        if (childTop > computedHeight) {
          computedHeight = childTop;
        }
        if (childBottom > computedDepth) {
          computedDepth = childBottom;
        }
      }
      if (!computedHeight.isFinite) {
        computedHeight = 0.0;
      }
      if (!computedDepth.isFinite) {
        computedDepth = 0.0;
      }
    }
    return HBox._(
      children: children.isEmpty ? const <MathBox>[] : children,
      widthEm: widthEm ?? computedWidth,
      heightEm: heightEm ?? math.max(0.0, computedHeight),
      depthEm: depthEm ?? math.max(0.0, computedDepth),
      atomClass: atomClass,
      italicsCorrectionEm: italicsCorrectionEm,
      shiftYEm: shiftYEm,
      span: span,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      breakPoint: breakPoint,
    );
  }

  /// Ordered sequence of horizontal child boxes.
  final List<MathBox> children;

  @override
  HBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return HBox._(
      children: children,
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    final (TexMathColorRole role, int? custom) = MathBox._resolveColor(
      this,
      inheritedRole,
      inheritedCustomColor,
    );
    double cursorX = originXEm;
    for (final MathBox child in children) {
      child._flattenWithBreaks(
        items: items,
        breakHints: breakHints,
        originXEm: cursorX,
        originYEm: originYEm + child.shiftYEm,
        inheritedRole: role,
        inheritedCustomColor: custom,
        maxOutputItems: maxOutputItems,
      );
      cursorX += child.widthEm;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HBox &&
          _baseEquals(other) &&
          _listEquals(children, other.children);

  @override
  int get hashCode => Object.hash(_baseHash, Object.hashAll(children));
}

/// Baseline-relative coordinate placement of a [MathBox] inside a [VBox].
@immutable
final class VBoxChild {
  /// Places [box] at `(` [xEm], [yEm] `)` relative to the enclosing [VBox]
  /// origin (`yEm` positive upward).
  const VBoxChild({required this.box, this.xEm = 0.0, this.yEm = 0.0});

  /// Placed child box.
  final MathBox box;

  /// Horizontal offset from the enclosing box's left edge in ems.
  final double xEm;

  /// Baseline-relative vertical offset in ems (positive upward).
  final double yEm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VBoxChild &&
          box == other.box &&
          xEm == other.xEm &&
          yEm == other.yEm;

  @override
  int get hashCode => Object.hash(box, xEm, yEm);
}

/// Vertical or arbitrarily positioned container box whose [placements] carry
/// explicit baseline-relative coordinates.
@immutable
final class VBox extends MathBox {
  const VBox._({
    required this.placements,
    required super.widthEm,
    required super.heightEm,
    required super.depthEm,
    super.atomClass,
    super.italicsCorrectionEm,
    super.shiftYEm,
    super.span,
    super.colorRole,
    super.customColor,
    super.inheritColor,
    super.breakPoint,
  });

  /// Creates a [VBox] from explicit [VBoxChild] placements, auto-computing
  /// bounding box metrics when omitted.
  factory VBox.positioned({
    required List<VBoxChild> children,
    double? widthEm,
    double? heightEm,
    double? depthEm,
    TexMathAtomClass atomClass = TexMathAtomClass.ord,
    double italicsCorrectionEm = 0.0,
    double shiftYEm = 0.0,
    SourceSpan? span,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    BreakPoint breakPoint = BreakPoint.none,
  }) {
    double computedWidth = 0.0;
    double computedHeight = 0.0;
    double computedDepth = 0.0;
    if (children.isNotEmpty) {
      computedHeight = double.negativeInfinity;
      computedDepth = double.negativeInfinity;
      for (int i = 0; i < children.length; i++) {
        final VBoxChild placement = children[i];
        final double right = placement.xEm + placement.box.widthEm;
        if (right > computedWidth) {
          computedWidth = right;
        }
        final double childY = placement.yEm + placement.box.shiftYEm;
        final double top = childY + placement.box.heightEm;
        final double bottom = placement.box.depthEm - childY;
        if (top > computedHeight) {
          computedHeight = top;
        }
        if (bottom > computedDepth) {
          computedDepth = bottom;
        }
      }
      if (!computedHeight.isFinite) {
        computedHeight = 0.0;
      }
      if (!computedDepth.isFinite) {
        computedDepth = 0.0;
      }
    }
    return VBox._(
      placements: children.isEmpty ? const <VBoxChild>[] : children,
      widthEm: widthEm ?? computedWidth,
      heightEm: heightEm ?? math.max(0.0, computedHeight),
      depthEm: depthEm ?? math.max(0.0, computedDepth),
      atomClass: atomClass,
      italicsCorrectionEm: italicsCorrectionEm,
      shiftYEm: shiftYEm,
      span: span,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      breakPoint: breakPoint,
    );
  }

  /// Creates a vertically stacked [VBox] placing [children] top-to-bottom
  /// separated by [gapEm], horizontally centered inside the widest child.
  factory VBox({
    required List<MathBox> children,
    double gapEm = 0.0,
    double? widthEm,
    double? heightEm,
    double? depthEm,
    TexMathAtomClass atomClass = TexMathAtomClass.ord,
    double italicsCorrectionEm = 0.0,
    double shiftYEm = 0.0,
    SourceSpan? span,
    TexMathColorRole colorRole = TexMathColorRole.foreground,
    int? customColor,
    bool inheritColor = true,
    BreakPoint breakPoint = BreakPoint.none,
  }) {
    if (children.isEmpty) {
      return VBox.positioned(
        children: const <VBoxChild>[],
        widthEm: widthEm,
        heightEm: heightEm,
        depthEm: depthEm,
        atomClass: atomClass,
        italicsCorrectionEm: italicsCorrectionEm,
        shiftYEm: shiftYEm,
        span: span,
        colorRole: colorRole,
        customColor: customColor,
        inheritColor: inheritColor,
        breakPoint: breakPoint,
      );
    }

    double maxWidth = 0.0;
    double totalHeight = 0.0;
    for (int i = 0; i < children.length; i++) {
      final MathBox child = children[i];
      if (child.widthEm > maxWidth) {
        maxWidth = child.widthEm;
      }
      totalHeight += child.totalHeightEm;
      if (i > 0) {
        totalHeight += gapEm;
      }
    }

    final double resolvedWidth = widthEm ?? maxWidth;
    double topCursor = totalHeight / 2.0;
    final List<VBoxChild> placed = <VBoxChild>[];
    for (int i = 0; i < children.length; i++) {
      final MathBox child = children[i];
      final double baselineY = topCursor - child.heightEm;
      final double x = (resolvedWidth - child.widthEm) / 2.0;
      placed.add(VBoxChild(box: child, xEm: x, yEm: baselineY));
      topCursor -= child.totalHeightEm + gapEm;
    }

    return VBox.positioned(
      children: placed,
      widthEm: resolvedWidth,
      heightEm: heightEm,
      depthEm: depthEm,
      atomClass: atomClass,
      italicsCorrectionEm: italicsCorrectionEm,
      shiftYEm: shiftYEm,
      span: span,
      colorRole: colorRole,
      customColor: customColor,
      inheritColor: inheritColor,
      breakPoint: breakPoint,
    );
  }

  /// Positioned child placements relative to this box's origin and baseline.
  final List<VBoxChild> placements;

  /// Child boxes stored in [placements].
  List<MathBox> get children =>
      placements.map((VBoxChild p) => p.box).toList(growable: false);

  @override
  VBox withMetadata({
    TexMathAtomClass? atomClass,
    double? italicsCorrectionEm,
    double? shiftYEm,
    SourceSpan? span,
    TexMathColorRole? colorRole,
    int? customColor,
    bool? inheritColor,
    BreakPoint? breakPoint,
  }) {
    return VBox._(
      placements: placements,
      widthEm: widthEm,
      heightEm: heightEm,
      depthEm: depthEm,
      atomClass: atomClass ?? this.atomClass,
      italicsCorrectionEm: italicsCorrectionEm ?? this.italicsCorrectionEm,
      shiftYEm: shiftYEm ?? this.shiftYEm,
      span: span ?? this.span,
      colorRole: colorRole ?? this.colorRole,
      customColor: customColor ?? this.customColor,
      inheritColor: inheritColor ?? this.inheritColor,
      breakPoint: breakPoint ?? this.breakPoint,
    );
  }

  @override
  void _flattenInto({
    required List<DisplayItem> items,
    required List<DisplayBreakHint> breakHints,
    required double originXEm,
    required double originYEm,
    required TexMathColorRole inheritedRole,
    required int? inheritedCustomColor,
    required int maxOutputItems,
  }) {
    final (TexMathColorRole role, int? custom) = MathBox._resolveColor(
      this,
      inheritedRole,
      inheritedCustomColor,
    );
    for (final VBoxChild placement in placements) {
      placement.box._flattenWithBreaks(
        items: items,
        breakHints: breakHints,
        originXEm: originXEm + placement.xEm,
        originYEm: originYEm + placement.yEm + placement.box.shiftYEm,
        inheritedRole: role,
        inheritedCustomColor: custom,
        maxOutputItems: maxOutputItems,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VBox &&
          _baseEquals(other) &&
          _listEquals(placements, other.placements);

  @override
  int get hashCode => Object.hash(_baseHash, Object.hashAll(placements));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
