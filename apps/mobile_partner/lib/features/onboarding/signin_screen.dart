import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/notifications.dart';
import '../../app/phone_auth.dart';
import '../../app/providers.dart';
import '../../widgets/phone_field.dart';

/// Partner sign-in. Same phone-first flow as the client app, with copy that
/// speaks to someone deciding whether this is worth their time.
class PartnerSignInScreen extends ConsumerStatefulWidget {
  const PartnerSignInScreen({super.key});

  @override
  ConsumerState<PartnerSignInScreen> createState() =>
      _PartnerSignInScreenState();
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: FreshlyColors.mint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('F',
              style: FreshlyType.style(22,
                  weight: FontWeight.w800, color: FreshlyColors.obsidian)),
        ),
        const SizedBox(width: 10),
        Text('Freshly',
            style: FreshlyType.style(20,
                weight: FontWeight.w800, color: Colors.white)),
        const SizedBox(width: 8),
        const StatusPill(
            label: 'Partner', tone: FreshlyTone.brand, dense: true),
      ],
    );
  }
}

class _PartnerSignInScreenState extends ConsumerState<PartnerSignInScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String _country = 'ZW';
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  /// The number as Firebase and the backend expect it.
  String get _e164 => toE164(_country, _phone.text);

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final phoneAuth = ref.read(phoneAuthProvider);
    phoneAuth.onAutoToken = (idToken) async {
      if (!mounted) return;
      try {
        await _exchange(idToken);
      } on ApiException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
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
      await _exchange(idToken);
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

  /// The half shared by the typed-code path and Android's instant verification:
  /// swap the Firebase token for a session. A number with no business yet is
  /// not refused — the notifier routes it to business set-up, which is how a
  /// new pro signs up in the first place.
  Future<void> _exchange(String idToken) async {
    final session = await ref.read(apiProvider).signInWithFirebase(
          idToken,
          _country,
          platform:
              defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          pushToken: ref.read(pushTokenProvider),
        );
    ref.read(partnerAuthProvider.notifier).signedIn(session);
  }

  @override
  Widget build(BuildContext context) {
    final market = phoneMarkets[_country]!;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final canSubmit = _codeSent
        ? _code.text.length == 6
        : isCompleteNumber(_country, _phone.text);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ParallaxHero(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                          FreshlySpacing.lg,
                          MediaQuery.paddingOf(context).top + FreshlySpacing.lg,
                          FreshlySpacing.lg,
                          FreshlySpacing.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _BrandMark(),
                          const SizedBox(height: FreshlySpacing.xl),
                          Text('Run your chair\nfrom your phone.',
                              style: text.displaySmall
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: FreshlySpacing.sm),
                          Text(
                            'Take bookings, get paid the moment a job is '
                            'done, and keep your own diary.',
                            style: text.bodyLarge
                                ?.copyWith(color: FreshlyColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(FreshlySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_codeSent) ...[
                          Text('Your mobile number', style: text.titleMedium),
                          const SizedBox(height: 4),
                          Text('We will text you a code to sign in.',
                              style: text.bodyMedium?.copyWith(color: muted)),
                          const SizedBox(height: FreshlySpacing.md),
                          PhoneNumberField(
                            country: _country,
                            controller: _phone,
                            autofocus: true,
                            onCountryChanged: (v) =>
                                setState(() => _country = v),
                            onChanged: (_) => setState(() {}),
                          ),
                        ] else ...[
                          Text('Enter your code', style: text.titleMedium),
                          const SizedBox(height: 4),
                          Text('Sent to ${market.prefix} ${_phone.text}',
                              style: text.bodyMedium?.copyWith(color: muted)),
                          const SizedBox(height: FreshlySpacing.md),
                          TextField(
                            controller: _code,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            textAlign: TextAlign.center,
                            style: FreshlyType.style(26,
                                    weight: FontWeight.w800,
                                    color: FreshlyColors.ink)
                                .copyWith(letterSpacing: 10),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration:
                                const InputDecoration(hintText: '000000'),
                            onChanged: (v) {
                              setState(() {});
                              if (v.length == 6) _verify();
                            },
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: FreshlySpacing.md),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FreshlyColors.crimsonSoft,
                              borderRadius: BorderRadius.circular(
                                  FreshlySpacing.radiusSmall),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(FreshlyIcons.error,
                                    size: 18, color: Color(0xFFB4232A)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_error!,
                                      style: text.bodyMedium?.copyWith(
                                          color: const Color(0xFFB4232A))),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            StickyActionBar(
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : (canSubmit ? (_codeSent ? _verify : _sendCode) : null),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.inkMuted))
                    : Text(_codeSent ? 'Sign in' : 'Send code'),
              ),
            ),
          ],
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
