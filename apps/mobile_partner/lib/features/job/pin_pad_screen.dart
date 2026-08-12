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
    return Scaffold(
      appBar: AppBar(title: const Text('Client code')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(FreshlySpacing.lg, FreshlySpacing.lg,
                  FreshlySpacing.lg, FreshlySpacing.sm),
              child: Text(
                'Ask the client for their 4-digit code once you are ready to start.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, height: 1.5, color: FreshlyColors.inkMuted),
              ),
            ),
            const SizedBox(height: FreshlySpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: filled ? FreshlyColors.mint : Colors.transparent,
                    border: Border.all(
                      color: _error != null
                          ? FreshlyColors.crimson
                          : FreshlyColors.line,
                      width: 2,
                    ),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FreshlySpacing.md),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: FreshlyColors.crimson)),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: FreshlySpacing.md),
                child: CircularProgressIndicator(),
              ),
            const Spacer(),
            _Keypad(onDigit: _press, onBackspace: _backspace),
            const SizedBox(height: FreshlySpacing.lg),
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
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              height: 68,
              child: TextButton(
                onPressed: onTap ?? () => onDigit(label),
                style: TextButton.styleFrom(
                  backgroundColor: FreshlyColors.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                ),
                child: icon != null
                    ? Icon(icon, size: 24, color: FreshlyColors.ink)
                    : Text(label,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: FreshlyColors.ink)),
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.lg),
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
