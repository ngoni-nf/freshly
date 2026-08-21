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
    final user = auth is PartnerReady ? auth.session : (auth is PartnerPendingVerification ? auth.session : null);

    return Scaffold(
      appBar: AppBar(title: const Text('My Business')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: [
          if (user != null) ...[
            _BusinessHeader(user: user),
            const SizedBox(height: FreshlySpacing.xl),
          ],
          _BusinessTile(
            icon: FreshlyIcons.style,
            title: 'Service Menu',
            subtitle: 'Manage your services and pricing',
            onTap: () => context.push('/menu'),
          ),
          _BusinessTile(
            icon: FreshlyIcons.gallery,
            title: 'Portfolio',
            subtitle: 'Showcase your best work',
            onTap: () => context.push('/portfolio'),
          ),
          _BusinessTile(
            icon: FreshlyIcons.people,
            title: 'Clients',
            subtitle: 'Your customer database and history',
            onTap: () => context.push('/clients'),
          ),
          _BusinessTile(
            icon: FreshlyIcons.calendar,
            title: 'Availability',
            subtitle: 'Set your hours and block time off',
            onTap: () => context.push('/availability'),
          ),
          const Divider(height: FreshlySpacing.xl),
          _BusinessTile(
            icon: FreshlyIcons.star,
            title: 'Reviews',
            subtitle: 'See what clients are saying',
            onTap: () => context.push('/reviews'),
          ),
          _BusinessTile(
            icon: FreshlyIcons.info,
            title: 'Help & Support',
            subtitle: 'Get assistance or report issues',
            onTap: () {},
          ),
          const SizedBox(height: FreshlySpacing.lg),
          TextButton(
            onPressed: () => ref.read(partnerAuthProvider.notifier).logout(),
            style: TextButton.styleFrom(foregroundColor: FreshlyColors.crimson),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _BusinessHeader extends StatelessWidget {
  const _BusinessHeader({required this.user});
  final AuthSession user;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: FreshlyColors.mintSoft,
          child: Text(
            user.fullName.characters.first.toUpperCase(),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: FreshlyColors.mintDark),
          ),
        ),
        const SizedBox(width: FreshlySpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(user.phone ?? '', style: const TextStyle(color: FreshlyColors.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BusinessTile extends StatelessWidget {
  const _BusinessTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: FreshlyColors.mintDark),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
        onTap: onTap,
      ),
    );
  }
}
