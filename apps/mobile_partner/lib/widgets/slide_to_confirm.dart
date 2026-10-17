import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freshly_core/freshly_core.dart';

/// A drag-the-knob control for a step that should not happen by accident.
///
/// "I have arrived" starts the client's no-show clock and tells them to open
/// the door. A phone in a pocket or a cup holder taps buttons on its own; it
/// does not drag a knob the full width of the screen. Screen readers get a
/// plain button through [Semantics.onTap], because a drag gesture is
/// unreachable with TalkBack or VoiceOver.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    required this.label,
    required this.onConfirmed,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onConfirmed;
  final bool busy;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  static const _height = 64.0;
  static const _knob = 56.0;
  static const _inset = (_height - _knob) / 2;

  double _drag = 0;

  bool get _enabled => widget.onConfirmed != null && !widget.busy;

  void _end(double max) {
    if (_drag >= max * 0.85 && _enabled) {
      HapticFeedback.mediumImpact();
      widget.onConfirmed!();
    }
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      onTap: _enabled ? widget.onConfirmed : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        final max = box.maxWidth - _knob - _inset * 2;
        final progress = max <= 0 ? 0.0 : (_drag / max).clamp(0.0, 1.0);
        return Container(
          height: _height,
          decoration: BoxDecoration(
            color: _enabled
                ? FreshlyColors.obsidian
                : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(_height / 2),
          ),
          child: Stack(
            children: [
              // The track fills behind the knob so the distance left to go is
              // visible at a glance.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: _drag + _knob + _inset * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: FreshlyColors.mint.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(left: _knob),
                  child: Opacity(
                    opacity: 1 - progress,
                    child: Text(
                      widget.busy ? 'Updating…' : widget.label,
                      style: FreshlyType.style(17,
                          weight: FontWeight.w700,
                          color:
                              _enabled ? Colors.white : FreshlyColors.inkMuted),
                    ),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: _drag == 0 && !still
                    ? const Duration(milliseconds: 220)
                    : Duration.zero,
                curve: Curves.easeOutCubic,
                left: _inset + _drag,
                top: _inset,
                child: GestureDetector(
                  onHorizontalDragUpdate: _enabled
                      ? (d) => setState(
                          () => _drag = (_drag + d.delta.dx).clamp(0.0, max))
                      : null,
                  onHorizontalDragEnd: _enabled ? (_) => _end(max) : null,
                  child: Container(
                    width: _knob,
                    height: _knob,
                    decoration: BoxDecoration(
                      color: _enabled
                          ? FreshlyColors.mint
                          : Theme.of(context).colorScheme.outline,
                      shape: BoxShape.circle,
                    ),
                    child: widget.busy
                        ? const Padding(
                            padding: EdgeInsets.all(18),
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: FreshlyColors.obsidian),
                          )
                        : const Icon(FreshlyIcons.chevronRight,
                            color: FreshlyColors.obsidian, size: 24),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
