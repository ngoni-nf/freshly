import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/freshly_theme.dart';

/// Moves its child against the scroll of the nearest [Scrollable], so it
/// appears to sit at a different depth from the content around it.
///
/// [factor] is how much of the scroll the child gives back: 0 scrolls normally,
/// 0.5 travels at half speed, a negative value runs ahead of the content.
/// [fadeOutExtent], when set, fades the child out over that many pixels of
/// scroll past its own top edge.
///
/// The offset is applied at paint time and nowhere else. Scrolling repaints
/// this one layer instead of rebuilding the screen, which matters on the
/// low-end handsets that make up most of both markets — a `setState` per
/// scroll frame would rebuild every provider card on the dashboard sixty
/// times a second.
///
/// Honours the platform's reduce-motion setting by standing still. Motion
/// that a user has asked the OS to remove is not decoration they can ignore;
/// for some of them it is nausea.
class Parallax extends SingleChildRenderObjectWidget {
  const Parallax({
    required Widget super.child,
    this.factor = 0.5,
    this.fadeOutExtent,
    super.key,
  });

  final double factor;
  final double? fadeOutExtent;

  bool _reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  RenderParallax createRenderObject(BuildContext context) {
    final still = _reduceMotion(context);
    return RenderParallax(
      position: Scrollable.maybeOf(context)?.position,
      factor: still ? 0 : factor,
      fadeOutExtent: still ? null : fadeOutExtent,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderParallax renderObject) {
    final still = _reduceMotion(context);
    renderObject
      ..position = Scrollable.maybeOf(context)?.position
      ..factor = still ? 0 : factor
      ..fadeOutExtent = still ? null : fadeOutExtent;
  }
}

class RenderParallax extends RenderProxyBox {
  RenderParallax({
    ScrollPosition? position,
    required double factor,
    double? fadeOutExtent,
  })  : _position = position,
        _factor = factor,
        _fadeOutExtent = fadeOutExtent;

  final _opacityLayer = LayerHandle<OpacityLayer>();

  ScrollPosition? _position;
  ScrollPosition? get position => _position;
  set position(ScrollPosition? value) {
    if (value == _position) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = value;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _factor;
  set factor(double value) {
    if (value == _factor) return;
    _factor = value;
    markNeedsPaint();
  }

  double? _fadeOutExtent;
  set fadeOutExtent(double? value) {
    if (value == _fadeOutExtent) return;
    final compositingChanged = (value == null) != (_fadeOutExtent == null);
    _fadeOutExtent = value;
    if (compositingChanged) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _opacityLayer.layer = null;
    super.dispose();
  }

  /// How far the list has scrolled past this box's top edge. Measured against
  /// the viewport rather than the screen, so it is the same number inside a
  /// tab, a sheet or a nested navigator.
  double get _scrolledPast {
    final position = _position;
    if (position == null || !position.hasPixels || !hasSize) return 0;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return 0;
    return position.pixels - viewport.getOffsetToReveal(this, 0).offset;
  }

  double get _shift => _factor == 0 ? 0 : _scrolledPast * _factor;

  double get _opacity {
    final extent = _fadeOutExtent;
    if (extent == null || extent <= 0) return 1;
    return (1 - _scrolledPast / extent).clamp(0.0, 1.0);
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _fadeOutExtent != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final shifted = offset.translate(0, _shift);
    final opacity = _opacity;
    if (_fadeOutExtent == null) {
      _opacityLayer.layer = null;
      context.paintChild(child!, shifted);
      return;
    }
    if (opacity == 0) {
      _opacityLayer.layer = null;
      return;
    }
    _opacityLayer.layer = context.pushOpacity(
      shifted,
      (opacity * 255).round(),
      (context, offset) => context.paintChild(child!, offset),
      oldLayer: _opacityLayer.layer,
    );
  }

  // Taps follow the drawing. Without these two overrides a button that has
  // drifted forty pixels would still answer at its old position.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (child == null || _opacity == 0) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _shift),
      position: position,
      hitTest: (result, transformed) =>
          child!.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(Matrix4.translationValues(0, _shift, 0));
  }
}

/// The dark header both apps open on: brand shapes drifting at three depths
/// behind whatever [child] holds, which itself lifts and fades as the list
/// scrolls under it.
///
/// [accent] carries state where a screen has one — the partner dashboard dims
/// it while the provider is offline, so the header itself says whether they
/// are taking work.
class ParallaxHero extends StatelessWidget {
  const ParallaxHero({
    required this.child,
    this.accent = FreshlyColors.mint,
    this.color = FreshlyColors.obsidian,
    super.key,
  });

  final Widget child;
  final Color accent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(FreshlySpacing.radiusLarge)),
      ),
      child: Stack(
        children: [
          _layer(0.55, top: -90, right: -70, shape: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 32),
            ),
          )),
          _layer(0.3, bottom: -70, left: -50, shape: Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
            ),
          )),
          _layer(-0.2, top: 28, right: 150, shape: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          )),
          Parallax(factor: 0.25, fadeOutExtent: 200, child: child),
        ],
      ),
    );
  }

  /// One depth of decoration. The layer always spans the whole header and the
  /// shape is placed inside it, so every layer measures its scroll from the
  /// header's top edge. Positioning the parallax box itself at, say, -90 would
  /// make it start ninety pixels "scrolled" and sit off its mark at rest.
  Widget _layer(
    double factor, {
    required Widget shape,
    double? top,
    double? right,
    double? bottom,
    double? left,
  }) {
    return Positioned.fill(
      child: Parallax(
        factor: factor,
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                  top: top,
                  right: right,
                  bottom: bottom,
                  left: left,
                  child: shape),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
