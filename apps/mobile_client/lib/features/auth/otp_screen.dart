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
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter your code',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: FreshlySpacing.sm),
            Text('Sent to ${widget.phone}',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: FreshlyColors.inkMuted)),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (i) {
                      final filled = i < _controller.text.length;
                      return Container(
                        width: 48,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: filled
                                ? FreshlyColors.mint
                                : FreshlyColors.line,
                            width: filled ? 2 : 1,
                          ),
                          borderRadius:
                              BorderRadius.circular(FreshlySpacing.radius),
                        ),
                        child: Text(
                          filled ? _controller.text[i] : '',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w700),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: FreshlySpacing.md),
              Text(_error!,
                  style: const TextStyle(color: FreshlyColors.crimson)),
            ],
            const SizedBox(height: FreshlySpacing.lg),
            Center(
              child: _secondsLeft > 0
                  ? Text('Resend code in ${_secondsLeft}s',
                      style: const TextStyle(color: FreshlyColors.inkMuted))
                  : TextButton(
                      onPressed: _resend, child: const Text('Resend code')),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: FreshlySpacing.lg),
                child: Center(child: CircularProgressIndicator()),
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
