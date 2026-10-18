import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class BusinessScreen extends ConsumerWidget {
  const BusinessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(partnerAuthProvider);
    final user = auth is PartnerReady
        ? auth.session
        : (auth is PartnerPendingVerification ? auth.session : null);
    final isSalon = ref.watch(isSalonProvider);
    final isStaff = ref.watch(isSalonStaffProvider);
    // A solo pro a salon wants to take on. Salons and existing staff are
    // never invited, so the list is only fetched for someone it can apply to.
    final invites = !isSalon && !isStaff
        ? ref.watch(staffInvitesProvider).valueOrNull ?? const <StaffInvite>[]
        : const <StaffInvite>[];

    return Scaffold(
      appBar: AppBar(title: const Text('My business')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.sm,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          if (user != null) ...[
            _BusinessHeader(
                user: user,
                verified: auth is PartnerReady,
                role: isSalon
                    ? 'Salon'
                    : isStaff
                        ? 'Salon team member'
                        : null),
            const SizedBox(height: FreshlySpacing.lg),
          ],
          GroupedList(
            title: 'Your shop window',
            children: [
              _BusinessTile(
                icon: FreshlyIcons.style,
                title: 'Service menu',
                subtitle: 'Your services and prices',
                onTap: () => context.push('/menu'),
              ),
              _BusinessTile(
                icon: FreshlyIcons.gallery,
                title: 'Portfolio',
                subtitle: 'Photos of your best work',
                onTap: () => context.push('/portfolio'),
              ),
              _BusinessTile(
                icon: FreshlyIcons.star,
                title: 'Reviews',
                subtitle: 'What clients are saying',
                onTap: () => context.push('/reviews'),
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          GroupedList(
            title: 'Running the business',
            children: [
              _BusinessTile(
                icon: FreshlyIcons.people,
                title: 'Clients',
                subtitle: 'History and private notes',
                onTap: () => context.push('/clients'),
              ),
              _BusinessTile(
                icon: FreshlyIcons.calendar,
                title: 'Availability',
                subtitle: 'Block time off and load-shedding',
                onTap: () => context.push('/availability'),
              ),
              // Only a salon has a team to run. A solo provider never sees
              // the row, so the screen cannot offer something the API would
              // refuse with salon_only.
              if (isSalon)
                _BusinessTile(
                  icon: FreshlyIcons.storefront,
                  title: 'Your team',
                  subtitle: 'Invite staff and hand them jobs',
                  onTap: () => context.push('/staff'),
                ),
              if (invites.isNotEmpty)
                _BusinessTile(
                  icon: FreshlyIcons.people,
                  tone: FreshlyTone.warning,
                  title: invites.length == 1
                      ? '${invites.first.salonName} invited you'
                      : '${invites.length} salons invited you',
                  subtitle: 'Join a team instead of working solo',
                  onTap: () => context.push('/staff/invites'),
                ),
              if (auth is PartnerPendingVerification)
                _BusinessTile(
                  icon: FreshlyIcons.verifiedOutline,
                  tone: FreshlyTone.warning,
                  title: 'Verify your identity',
                  subtitle: 'Needed before you can go online',
                  onTap: () => context.push('/verification'),
                ),
              _BusinessTile(
                icon: FreshlyIcons.info,
                tone: FreshlyTone.neutral,
                title: 'Help and support',
                subtitle: 'Get assistance or report an issue',
                onTap: () => context.push('/support'),
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          OutlinedButton(
            onPressed: () => ref.read(partnerAuthProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
                foregroundColor: FreshlyColors.crimson),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _BusinessHeader extends StatelessWidget {
  const _BusinessHeader(
      {required this.user, required this.verified, this.role});
  final AuthSession user;
  final bool verified;

  /// 'Salon' or 'Salon team member'; null for a solo pro, who needs no label.
  final String? role;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Row(
          children: [
            FreshlyAvatar(
                name: user.fullName.isEmpty ? 'Freshly' : user.fullName,
                size: 64),
            const SizedBox(width: FreshlySpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineSmall),
                  if ((user.phone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(user.phone!, style: text.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      verified
                          ? const StatusPill(
                              label: 'Verified pro',
                              icon: FreshlyIcons.verified,
                              tone: FreshlyTone.success)
                          : const StatusPill(
                              label: 'Verification pending',
                              icon: FreshlyIcons.hourglass,
                              tone: FreshlyTone.warning),
                      if (role != null)
                        StatusPill(
                            label: role!,
                            icon: FreshlyIcons.storefront,
                            tone: FreshlyTone.dark),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = FreshlyTone.brand,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final FreshlyTone tone;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconBadge(icon: icon, tone: tone, size: 40),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(FreshlyIcons.chevronRight,
          size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
