import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth is AuthSignedIn ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: [
          if (user != null) ...[
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: FreshlyColors.mintSoft,
                    child: Text(
                      user.fullName.characters.first.toUpperCase(),
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: FreshlyColors.mintDark),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  Text(user.fullName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  Text(user.phone, style: const TextStyle(color: FreshlyColors.inkMuted)),
                ],
              ),
            ),
            const SizedBox(height: FreshlySpacing.xl),
          ],
          _ProfileTile(
            icon: FreshlyIcons.location,
            title: 'Saved Addresses',
            onTap: () {},
          ),
          _ProfileTile(
            icon: FreshlyIcons.card,
            title: 'Payment Methods',
            onTap: () {},
          ),
          _ProfileTile(
            icon: FreshlyIcons.notifications,
            title: 'Notifications',
            onTap: () {},
          ),
          const Divider(height: FreshlySpacing.xl),
          _ProfileTile(
            icon: FreshlyIcons.info,
            title: 'Help & Support',
            onTap: () {},
          ),
          _ProfileTile(
            icon: FreshlyIcons.shield,
            title: 'Privacy Policy',
            onTap: () {},
          ),
          const SizedBox(height: FreshlySpacing.lg),
          TextButton(
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            style: TextButton.styleFrom(foregroundColor: FreshlyColors.crimson),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.icon, required this.title, required this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: FreshlyColors.ink),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}
