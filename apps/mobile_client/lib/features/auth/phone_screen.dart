import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/phone_auth.dart';
import '../../app/providers.dart';
import '../../app/social_auth.dart';
import 'complete_sign_in.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Chosen on the previous screen. The selector stays, because someone who
  /// picked the wrong country should not have to restart, but it is no longer
  /// the first time the question is asked.
  String get _country => ref.read(countryCodeProvider);
  set _country(String value) =>
      ref.read(countryCodeProvider.notifier).state = value;

  static const _markets = {
    'ZA': (prefix: '+27', digits: 9, label: 'South Africa', flag: '🇿🇦'),
    'ZW': (prefix: '+263', digits: 9, label: 'Zimbabwe', flag: '🇿🇼'),
  };

  String get _digits => _controller.text
      .replaceAll(RegExp(r'\D'), '')
      .replaceFirst(RegExp(r'^0+'), '');

  bool get _valid => _digits.length == _markets[_country]!.digits;

  /// The number in the form Firebase and the backend both expect.
  String get _e164 => '${_markets[_country]!.prefix}$_digits';

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(countryCodeProvider.notifier).state = _country;

    final phoneAuth = ref.read(phoneAuthProvider);
    // Android can verify without a typed code. If that happens before we leave
    // this screen, finish here.
    phoneAuth.onAutoToken = (idToken) async {
      if (!mounted) return;
      try {
        await completeFirebaseSignIn(ref, idToken, _country);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
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
          if (!mounted) return;
          setState(() => _busy = false);
          unawaited(context.push('/auth/otp',
              extra: {'phone': _e164, 'countryCode': _country}));
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

  /// Google is one tap and brings no phone, so the session comes back needing
  /// one and the router sends them to link-phone next.
  Future<void> _google() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(countryCodeProvider.notifier).state = _country;
    try {
      final idToken = await ref.read(socialAuthProvider).google();
      if (idToken == null) {
        if (mounted) setState(() => _busy = false);
        return; // backed out of the chooser
      }
      await completeFirebaseSignIn(ref, idToken, _country);
    } on PhoneAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              Text('Welcome to Freshly',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              Text(
                'Enter your mobile number. We will send you a 6-digit code to sign in.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: FreshlyColors.line),
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.radius),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _country,
                        items: _markets.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                      '${e.value.flag}  ${e.value.prefix}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _country = v!),
                      ),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(market.digits + 1),
                      ],
                      decoration:
                          const InputDecoration(hintText: '82 123 4567'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.md),
                Text(_error!,
                    style: const TextStyle(color: FreshlyColors.crimson)),
              ],
              const Spacer(),
              Text(
                'By continuing you agree to the Freshly Terms and Privacy Notice. '
                'We process your information in line with POPIA.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.md),
              FilledButton(
                onPressed: _valid && !_busy ? _submit : null,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Send code'),
              ),
              const SizedBox(height: FreshlySpacing.md),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: FreshlySpacing.md),
                    child: Text('or',
                        style: TextStyle(color: FreshlyColors.inkMuted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: FreshlySpacing.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _google,
                icon: const Icon(Icons.account_circle_outlined, size: 18),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              OutlinedButton.icon(
                onPressed:
                    _busy ? null : () => context.push('/auth/email'),
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Continue with email'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
