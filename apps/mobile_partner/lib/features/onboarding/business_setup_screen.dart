import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/business_form.dart';

/// Screen B.1 — opening a business.
///
/// A number that signs in with no provider row is a customer as far as the
/// API is concerned, and every provider screen would answer
/// `insufficient_role`. This is the one screen such an account can see, and
/// the session it gets back on success is the first one to carry the role.
class BusinessSetupScreen extends ConsumerStatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  ConsumerState<BusinessSetupScreen> createState() =>
      _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends ConsumerState<BusinessSetupScreen> {
  late final BusinessDraft _draft;
  bool _busy = false;
  bool _tried = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final session = ref.read(partnerAuthProvider.notifier).session;
    _draft = BusinessDraft(name: session?.fullName ?? '');
  }

  Future<void> _submit() async {
    setState(() {
      _tried = true;
      _error = _draft.problem;
    });
    if (_error != null) return;

    setState(() => _busy = true);
    try {
      final session =
          await ref.read(apiProvider).becomeProvider(_draft.toSignUp());
      if (!mounted) return;
      // The router is rebuilt around the new state and lands on the
      // dashboard; the verification push has to wait for that swap to be on
      // screen, or it is sent to a navigator that is about to be thrown away.
      ref
          .read(partnerAuthProvider.notifier)
          .signedIn(session, kycStatus: 'pending');
      final router = ref.read(partnerRouterProvider);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => router.push('/verification'));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'outside_service_area' =>
              'Freshly is not live where you are based yet. If you work '
                  'from somewhere we do cover, set that as your base instead.',
            'already_provider' =>
              'This number already has a business. Sign in again to open it.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your business'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => ref.read(partnerAuthProvider.notifier).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                  FreshlySpacing.sm, FreshlySpacing.lg, FreshlySpacing.lg),
              children: [
                const ScreenIntro(
                  eyebrow: 'Welcome to Freshly',
                  title: 'Tell us about your work',
                  subtitle: 'A few questions so the right clients can find '
                      'you. You can change any of this later.',
                ),
                const SizedBox(height: FreshlySpacing.lg),
                BusinessForm(
                  draft: _draft,
                  numbered: true,
                  api: ref.read(apiProvider),
                  countryCode: ref.read(countryCodeProvider),
                  // Re-check only once they have tried, so the form does not
                  // nag before they have had a chance to fill it in.
                  onChanged: () => setState(() {
                    if (_tried) _error = _draft.problem;
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  InlineError(message: _error!),
                ],
              ],
            ),
          ),
          StickyActionBar(
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FreshlyColors.obsidian))
                  : const Text('Open my business'),
            ),
          ),
        ],
      ),
    );
  }
}
