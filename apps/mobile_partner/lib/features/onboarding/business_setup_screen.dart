import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

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

  /// The invitation screen is pushed once, the first time invites arrive. If
  /// they come back here they chose to, and the banner stays as the way in.
  bool _offeredInvites = false;

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
    // Someone a salon invited before they ever opened the app should see the
    // invitation before a form about a business they may not want.
    ref.listen(staffInvitesProvider, (_, next) {
      final list = next.valueOrNull;
      if (_offeredInvites || list == null || list.isEmpty) return;
      _offeredInvites = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push('/staff/invites');
      });
    });
    final invites = ref.watch(staffInvitesProvider).valueOrNull ?? const [];

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
                if (invites.isNotEmpty) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  _InviteBanner(invites: invites),
                ],
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

/// A salon is waiting on this number. Shown above the form rather than
/// instead of it, because joining a team and opening a business are both
/// valid answers and the person decides which.
class _InviteBanner extends StatelessWidget {
  const _InviteBanner({required this.invites});
  final List<StaffInvite> invites;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final first = invites.first;
    return Card(
      child: InkWell(
        onTap: () => context.push('/staff/invites'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const IconBadge(icon: FreshlyIcons.people, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invites.length == 1
                          ? '${first.salonName} invited you'
                          : '${invites.length} salons invited you',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text('Join their team instead of opening your own',
                        style: text.bodySmall),
                  ],
                ),
              ),
              Icon(FreshlyIcons.chevronRight,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
