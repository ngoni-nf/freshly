import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/phone_auth.dart';
import '../../app/providers.dart';
import 'complete_sign_in.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.phone, required this.countryCode, super.key});
  final String phone;
  final String countryCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  int _secondsLeft = 60;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Auto-retrieval can complete while this screen is open; catch it here too.
    final phoneAuth = ref.read(phoneAuthProvider);
    phoneAuth.onAutoToken = (idToken) async {
      if (!mounted) return;
      try {
        await completeFirebaseSignIn(ref, idToken, widget.countryCode);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    };
    phoneAuth.onAutoError = (e) {
      if (mounted) setState(() => _error = e.message);
    };
  }

  void _startCountdown() {
    _secondsLeft = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft == 0) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify(String code) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await ref.read(phoneAuthProvider).confirm(code);
      await completeFirebaseSignIn(ref, idToken, widget.countryCode);
    } on PhoneAuthException catch (e) {
      setState(() {
        _error = e.message;
        _controller.clear();
      });
      unawaited(HapticFeedback.heavyImpact());
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _controller.clear();
      });
      unawaited(HapticFeedback.heavyImpact());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    await ref
        .read(phoneAuthProvider)
        .sendCode(widget.phone, resend: true, onCodeSent: () {});
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeEdge = isDark ? FreshlyColors.mint : FreshlyColors.obsidian;

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(
            FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScreenIntro(
              eyebrow: 'Verify',
              title: 'Enter your code',
              subtitle: 'We sent 6 digits to ${widget.phone}',
            ),
            const SizedBox(height: FreshlySpacing.xl),
            // A single hidden field backs six visible boxes: SMS autofill on
            // both platforms targets one field, and fighting that with six
            // separate controllers is how autofill silently breaks.
            Stack(
              children: [
                Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (v) {
                      setState(() {});
                      if (v.length == 6) _verify(v);
                    },
                  ),
                ),
                GestureDetector(
                  onTap: () => _focus.requestFocus(),
                  child: Row(
                    children: List.generate(6, (i) {
                      final filled = i < _controller.text.length;
                      final active = i == _controller.text.length;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: filled
                                  ? scheme.surface
                                  : scheme.surfaceContainerHighest,
                              border: Border.all(
                                color: _error != null
                                    ? FreshlyColors.crimson
                                    : active || filled
                                        ? activeEdge
                                        : Colors.transparent,
                                width: active ? 2 : 1.5,
                              ),
                              borderRadius: BorderRadius.circular(
                                  FreshlySpacing.buttonRadius),
                            ),
                            child: Text(
                              filled ? _controller.text[i] : '',
                              style: FreshlyType.style(26,
                                  weight: FontWeight.w800),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: FreshlySpacing.md),
              Row(
                children: [
                  const Icon(FreshlyIcons.error,
                      size: 18, color: FreshlyColors.crimson),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: FreshlyType.style(14,
                            weight: FontWeight.w600,
                            color: FreshlyColors.crimson)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FreshlySpacing.lg),
            if (_busy)
              const Row(
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Checking your code…'),
                ],
              )
            else if (_secondsLeft > 0)
              Text(
                  'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant))
            else
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: _resend,
                icon: const Icon(FreshlyIcons.message, size: 18),
                label: const Text('Send a new code'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }
}
