import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'job_providers.dart';

/// Screen B.12 — the payout unlock keypad.
///
/// A custom keypad rather than the system keyboard: gloved or wet hands, one
/// thumb, and four digits. The system numeric keyboard puts small keys at the
/// bottom of a tall screen and hides half the context.
class PinPadScreen extends ConsumerStatefulWidget {
  const PinPadScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<PinPadScreen> createState() => _PinPadScreenState();
}

class _PinPadScreenState extends ConsumerState<PinPadScreen> {
  String _pin = '';
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).verifyPin(widget.bookingId, _pin);
      ref.invalidate(jobProvider(widget.bookingId));
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _error = e.message;
        _pin = '';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _press(String digit) {
    if (_pin.length >= 4 || _busy) return;
    HapticFeedback.selectionClick();
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasError = _error != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Client code')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(FreshlySpacing.lg, FreshlySpacing.sm,
                  FreshlySpacing.lg, 0),
              child: ScreenIntro(
                eyebrow: 'Start the job',
                title: 'Enter the client\'s code',
                subtitle: 'Ask your client for the 4-digit code in their app '
                    'once you are ready to start.',
              ),
            ),
            const Spacer(),
            Semantics(
              label: '${_pin.length} of 4 digits entered',
              liveRegion: true,
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  final active = i == _pin.length && !_busy;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 60,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hasError
                          ? FreshlyColors.crimsonSoft
                          : filled
                              ? scheme.surface
                              : scheme.surfaceContainer,
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.buttonRadius),
                      border: Border.all(
                        color: hasError
                            ? FreshlyColors.crimson
                            : active
                                ? FreshlyColors.mintDark
                                : filled
                                    ? scheme.outline
                                    : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: filled
                        ? Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: FreshlyColors.obsidian,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                  );
                }),
              ),
            ),
            SizedBox(
              height: 56,
              child: Center(
                child: _busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('Checking code',
                              style: Theme.of(context).textTheme.labelMedium),
                        ],
                      )
                    : hasError
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: FreshlySpacing.lg),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: FreshlyColors.crimsonSoft,
                                borderRadius: BorderRadius.circular(
                                    FreshlySpacing.radiusSmall),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(FreshlyIcons.error,
                                      size: 16, color: Color(0xFFB4232A)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(_error!,
                                        textAlign: TextAlign.center,
                                        style: FreshlyType.style(14,
                                            weight: FontWeight.w600,
                                            color: const Color(0xFFB4232A))),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : null,
              ),
            ),
            const Spacer(),
            _Keypad(onDigit: _press, onBackspace: _backspace),
            const SizedBox(height: FreshlySpacing.md),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: SizedBox(
              height: 72,
              child: TextButton(
                onPressed: onTap ?? () => onDigit(label),
                style: TextButton.styleFrom(
                  backgroundColor: icon != null
                      ? Colors.transparent
                      : scheme.surface,
                  foregroundColor: scheme.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                    side: icon != null
                        ? BorderSide.none
                        : BorderSide(color: scheme.outline),
                  ),
                ),
                child: icon != null
                    ? Icon(icon, size: 28, semanticLabel: 'Delete')
                    : Text(label,
                        style: FreshlyType.style(30,
                            weight: FontWeight.w700,
                            color: scheme.onSurface)),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
      child: Column(
        children: [
          Row(children: [key('1'), key('2'), key('3')]),
          Row(children: [key('4'), key('5'), key('6')]),
          Row(children: [key('7'), key('8'), key('9')]),
          Row(children: [
            const Expanded(child: SizedBox()),
            key('0'),
            key('', onTap: onBackspace, icon: FreshlyIcons.backspace),
          ]),
        ],
      ),
    );
  }
}
