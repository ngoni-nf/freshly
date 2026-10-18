import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../widgets/business_form.dart' show InlineError;

/// The other end of a salon's invitation.
///
/// Accepting is a sign-up: the session that comes back is the first one with
/// the provider role, exactly as after opening a business of one's own. A
/// stylist who already has a solo business can still join, as long as they
/// have not completed a job on it; the API refuses the rest and this screen
/// says why in words that do not blame them.
class StaffInviteScreen extends ConsumerStatefulWidget {
  const StaffInviteScreen({super.key});

  @override
  ConsumerState<StaffInviteScreen> createState() => _StaffInviteScreenState();
}

class _StaffInviteScreenState extends ConsumerState<StaffInviteScreen> {
  String? _busyFor;
  String? _error;

  Future<void> _accept(StaffInvite invite) async {
    if (_busyFor != null) return;
    setState(() {
      _busyFor = invite.id;
      _error = null;
    });
    try {
      final session = await ref.read(apiProvider).acceptStaffInvite(invite.id);
      if (!mounted) return;
      // A provider who was already verified stays verified; a new account is
      // pending until their identity has been checked like any other pro.
      final auth = ref.read(partnerAuthProvider);
      final kyc = switch (auth) {
        PartnerReady() => 'verified',
        PartnerPendingVerification(:final kycStatus) => kycStatus,
        _ => 'pending',
      };
      ref.invalidate(myBusinessProvider);
      ref.invalidate(staffInvitesProvider);
      ref.invalidate(scheduleProvider);
      ref.read(partnerAuthProvider.notifier).signedIn(session, kycStatus: kyc);
      // The router is rebuilt around the new state; anything pushed before
      // that swap is on screen goes to a navigator about to be discarded.
      final router = ref.read(partnerRouterProvider);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.go('/');
        if (kyc != 'verified') router.push('/verification');
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'has_own_business' =>
              'You have completed jobs on your own business, so it cannot '
                  'be folded into a salon. Ask the salon to reach you '
                  'another way.',
            'invite_not_found' ||
            'invite_cancelled' ||
            'not_found' =>
              'That invitation is no longer open. Ask the salon to send a '
                  'new one.',
            _ => e.message,
          });
      ref.invalidate(staffInvitesProvider);
    } finally {
      if (mounted) setState(() => _busyFor = null);
    }
  }

  void _ownBusiness() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/onboarding/business');
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(staffInvitesProvider);
    final auth = ref.watch(partnerAuthProvider);
    final needsBusiness = auth is PartnerNeedsBusiness;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a salon'),
        actions: [
          if (needsBusiness)
            TextButton(
              onPressed: _busyFor != null
                  ? null
                  : () => ref.read(partnerAuthProvider.notifier).logout(),
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: invites.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          children: const [
            Skeleton(height: 120, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Invitations did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(staffInvitesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.people,
              title: 'No open invitations',
              message: 'When a salon invites this number you will see it '
                  'here. Until then you can set up a business of your own.',
              actionLabel: needsBusiness ? 'Set up my own business' : 'Back',
              onAction: _ownBusiness,
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                FreshlySpacing.sm, FreshlySpacing.lg, FreshlySpacing.xl),
            children: [
              ScreenIntro(
                eyebrow: 'You have been invited',
                title: list.length == 1
                    ? '${list.first.salonName} wants you on the team'
                    : 'Salons want you on their team',
                subtitle: 'Jobs the salon assigns to you land in your '
                    'schedule and you run them from this app. The salon is '
                    'paid through Freshly and settles with you as usual.',
              ),
              const SizedBox(height: FreshlySpacing.lg),
              for (final invite in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                  child: _InviteCard(
                    invite: invite,
                    busy: _busyFor == invite.id,
                    enabled: _busyFor == null,
                    onAccept: () => _accept(invite),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                InlineError(message: _error!),
              ],
              const SizedBox(height: FreshlySpacing.lg),
              Text(
                'You still need to verify your identity before the salon can '
                'hand you a job, the same as any Freshly pro.',
                textAlign: TextAlign.center,
                style: text.bodySmall,
              ),
              const SizedBox(height: FreshlySpacing.sm),
              TextButton(
                onPressed: _busyFor != null ? null : _ownBusiness,
                child: Text(needsBusiness
                    ? 'Set up my own business instead'
                    : 'Not now'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.busy,
    required this.enabled,
    required this.onAccept,
  });

  final StaffInvite invite;
  final bool busy;
  final bool enabled;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FreshlyAvatar(name: invite.salonName, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(invite.salonName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(FreshlyIcons.storefront, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              invite.salonSuburb?.trim().isNotEmpty == true
                                  ? invite.salonSuburb!
                                  : 'Salon',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FreshlySpacing.md),
            FilledButton(
              onPressed: enabled ? onAccept : null,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FreshlyColors.obsidian))
                  : Text('Join ${invite.salonName}'),
            ),
          ],
        ),
      ),
    );
  }
}
