import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/phone_auth.dart' show PhoneAuthException;
import '../../app/providers.dart';
import '../../app/social_auth.dart';
import 'complete_sign_in.dart';

/// Email + password sign-in. One screen that signs in or, for a new address,
/// creates the account — the social path still needs a phone linked before
/// booking, so nothing here can reach a booking without verification.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  bool get _valid => _email.text.contains('@') && _password.text.length >= 6;

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final country = ref.read(countryCodeProvider);
    try {
      final idToken = await ref
          .read(socialAuthProvider)
          .email(_email.text.trim(), _password.text);
      await completeFirebaseSignIn(ref, idToken, country);
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
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ScreenIntro(
              eyebrow: 'Sign in',
              title: 'Continue with email',
              subtitle: 'New here? We will create your account. You will add '
                  'a mobile number next.',
            ),
            const SizedBox(height: FreshlySpacing.xl),
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                  hintText: 'you@example.com',
                  prefixIcon: Icon(Icons.mail_outline)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: FreshlySpacing.md),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                hintText: 'Password (min 6 characters)',
                prefixIcon: const Icon(FreshlyIcons.lock),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: FreshlySpacing.md),
              Text(_error!,
                  style: FreshlyType.style(14,
                      weight: FontWeight.w600, color: FreshlyColors.crimson)),
            ],
            const Spacer(),
            FilledButton(
              onPressed: _valid && !_busy ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FreshlyColors.obsidian))
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
}
