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
    'ZW': (
      prefix: '+263',
      digits: 9,
      label: 'Zimbabwe',
      hint: '77 123 4567',
      // Zimbabwe's Cyber and Data Protection Act; POPIA is South Africa's.
      law: 'the Cyber and Data Protection Act',
    ),
    'ZA': (
      prefix: '+27',
      digits: 9,
      label: 'South Africa',
      hint: '82 123 4567',
      law: 'POPIA',
    ),
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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ScreenIntro(
                eyebrow: 'Sign in',
                title: 'What is your number?',
                subtitle: 'We will text you a 6-digit code. No passwords.',
              ),
              const SizedBox(height: FreshlySpacing.xl),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                style: FreshlyType.style(20, weight: FontWeight.w700),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(market.digits + 1),
                ],
                decoration: InputDecoration(
                  hintText: market.hint,
                  hintStyle: FreshlyType.style(20,
                      weight: FontWeight.w500, color: FreshlyColors.inkMuted),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 4),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _country,
                        borderRadius:
                            BorderRadius.circular(FreshlySpacing.radius),
                        icon: const Icon(FreshlyIcons.expandMore, size: 16),
                        items: _markets.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CountryBadge(code: e.key, size: 28),
                                      const SizedBox(width: 8),
                                      Text(e.value.prefix,
                                          style: FreshlyType.style(17,
                                              weight: FontWeight.w700)),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _country = v!),
                      ),
                    ),
                  ),
                  suffixIcon: _valid
                      ? const Icon(FreshlyIcons.checkCircle,
                          color: FreshlyColors.mintDark)
                      : null,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
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
              const Spacer(),
              FilledButton(
                onPressed: _valid && !_busy ? _submit : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.obsidian))
                    : const Text('Send code'),
              ),
              const SizedBox(height: FreshlySpacing.md),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FreshlySpacing.md),
                    child: Text('or', style: text.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: FreshlySpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _google,
                      icon: const Icon(Icons.account_circle_outlined, size: 20),
                      label: const Text('Google'),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _busy ? null : () => context.push('/auth/email'),
                      icon: const Icon(Icons.mail_outline, size: 20),
                      label: const Text('Email'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FreshlySpacing.md),
              Text(
                'By continuing you agree to the Freshly Terms and Privacy '
                'Notice. We process your information in line with '
                '${market.law}.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
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
