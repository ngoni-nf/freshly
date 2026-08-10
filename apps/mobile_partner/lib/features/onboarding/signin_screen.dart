import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

/// Partner sign-in. Same phone-first flow as the client app, with copy that
/// speaks to someone deciding whether this is worth their time.
class PartnerSignInScreen extends ConsumerStatefulWidget {
  const PartnerSignInScreen({super.key});

  @override
  ConsumerState<PartnerSignInScreen> createState() =>
      _PartnerSignInScreenState();
}

class _PartnerSignInScreenState extends ConsumerState<PartnerSignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String _country = 'ZA';
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  static const _markets = {
    'ZA': (prefix: '+27', digits: 9, flag: '🇿🇦'),
    'ZW': (prefix: '+263', digits: 9, flag: '🇿🇼'),
  };

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).requestOtp(_phone.text, _country);
      setState(() => _codeSent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref.read(apiProvider).verifyOtp(
            _phone.text,
            _country,
            _code.text,
            platform: Theme.of(context).platform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
          );
      if (!session.isProvider) {
        setState(() => _error =
            'This number is registered as a client. Contact support to become a Freshly pro.');
        return;
      }
      ref.read(partnerAuthProvider.notifier).signedIn(session);
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
              Text('Freshly Partner',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              const Text(
                'Take bookings, get paid the moment a job is done, and keep your '
                'own diary.',
                style: TextStyle(
                    fontSize: 16, height: 1.5, color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              if (!_codeSent) ...[
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
                ),
              ] else ...[
                Text('Code sent to ${market.prefix}${_phone.text}',
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
                        : (_phone.text
                                    .replaceFirst(RegExp(r'^0+'), '')
                                    .length ==
                                market.digits
                            ? _sendCode
                            : null)),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_codeSent ? 'Sign in' : 'Send code'),
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
