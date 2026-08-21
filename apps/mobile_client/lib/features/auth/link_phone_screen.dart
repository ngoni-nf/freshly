import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/phone_auth.dart';
import '../../app/providers.dart';

/// Shown to a Google or email account that has no verified number yet.
///
/// It is the same Firebase phone verification the phone sign-in uses, but the
/// resulting token is *linked* to the already-signed-in account rather than
/// exchanged for a new one — so social sign-in stays convenient while every
/// account that can book still has a number a provider can reach.
class LinkPhoneScreen extends ConsumerStatefulWidget {
  const LinkPhoneScreen({super.key});

  @override
  ConsumerState<LinkPhoneScreen> createState() => _LinkPhoneScreenState();
}

class _LinkPhoneScreenState extends ConsumerState<LinkPhoneScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static const _markets = {
    'ZA': (prefix: '+27', digits: 9, flag: '🇿🇦'),
    'ZW': (prefix: '+263', digits: 9, flag: '🇿🇼'),
  };

  String get _country => ref.read(countryCodeProvider);

  String get _e164 {
    final digits = _phone.text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return '${_markets[_country]!.prefix}$digits';
  }

  bool get _phoneValid {
    final digits = _phone.text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return digits.length == _markets[_country]!.digits;
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final phoneAuth = ref.read(phoneAuthProvider);
    phoneAuth.onAutoToken = (idToken) async {
      if (!mounted) return;
      await _link(idToken);
    };
    phoneAuth.onAutoError = (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    };
    try {
      await phoneAuth.sendCode(
        _e164,
        onCodeSent: () {
          if (mounted) {
            setState(() {
              _busy = false;
              _codeSent = true;
            });
          }
        },
      );
    } on PhoneAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idToken = await ref.read(phoneAuthProvider).confirm(_code.text);
      await _link(idToken);
    } on PhoneAuthException catch (e) {
      setState(() {
        _error = e.message;
        _code.clear();
      });
      unawaited(HapticFeedback.heavyImpact());
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _code.clear();
      });
      unawaited(HapticFeedback.heavyImpact());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Attach the verified number to this account and let the auth state advance
  /// past AuthNeedsPhone to profile, area, or straight to home.
  Future<void> _link(String idToken) async {
    final session = await ref.read(apiProvider).linkPhone(idToken, _country);
    if (!mounted) return;
    ref.read(authStateProvider.notifier).signedIn(session);
  }

  @override
  Widget build(BuildContext context) {
    final market = _markets[_country]!;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              Text('Add your mobile number',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              const Text(
                'Your provider needs a way to reach you, and it confirms the job '
                'is done. We will send a code to verify it.',
                style: TextStyle(
                    fontSize: 16, height: 1.4, color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              if (!_codeSent)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: FreshlyColors.line),
                        borderRadius:
                            BorderRadius.circular(FreshlySpacing.radius),
                      ),
                      child: Text('${market.flag}  ${market.prefix}'),
                    ),
                    const SizedBox(width: FreshlySpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(market.digits + 1),
                        ],
                        decoration:
                            const InputDecoration(hintText: '82 123 4567'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                )
              else ...[
                Text('Code sent to $_e164',
                    style: const TextStyle(color: FreshlyColors.inkMuted)),
                const SizedBox(height: FreshlySpacing.md),
                TextField(
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(hintText: '6-digit code'),
                  onChanged: (v) {
                    setState(() {});
                    if (v.length == 6) _verify();
                  },
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.md),
                Text(_error!,
                    style: const TextStyle(color: FreshlyColors.crimson)),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _busy
                    ? null
                    : (_codeSent
                        ? (_code.text.length == 6 ? _verify : null)
                        : (_phoneValid ? _sendCode : null)),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_codeSent ? 'Verify' : 'Send code'),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(authStateProvider.notifier).logout(),
                style:
                    TextButton.styleFrom(foregroundColor: FreshlyColors.inkMuted),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }
}
