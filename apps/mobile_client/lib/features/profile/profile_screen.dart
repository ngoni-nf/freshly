import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import 'package:go_router/go_router.dart';

import '../../app/biometric_lock.dart';
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
                  Text(user.phone ?? 'No number linked',
                      style: const TextStyle(color: FreshlyColors.inkMuted)),
                ],
              ),
            ),
            const SizedBox(height: FreshlySpacing.xl),
          ],
          _ProfileTile(
            icon: FreshlyIcons.location,
            title: 'Saved addresses',
            onTap: () => context.push('/profile/addresses'),
          ),
          _ProfileTile(
            icon: FreshlyIcons.storefront,
            title: 'Where you want service',
            subtitle: ref.watch(serviceAreaProvider)?.displayName,
            onTap: () => context.push('/location'),
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
          const _BiometricLockTile(),
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

/// The biometric-lock switch. It hides itself entirely on a device with no
/// biometrics enrolled — a toggle you cannot honour is worse than no toggle.
class _BiometricLockTile extends ConsumerStatefulWidget {
  const _BiometricLockTile();

  @override
  ConsumerState<_BiometricLockTile> createState() => _BiometricLockTileState();
}

class _BiometricLockTileState extends ConsumerState<_BiometricLockTile> {
  bool _available = false;

  @override
  void initState() {
    super.initState();
    ref.read(biometricLockProvider).canUse().then((can) {
      if (mounted) setState(() => _available = can);
    });
  }

  Future<void> _toggle(bool value) async {
    final lock = ref.read(biometricLockProvider);
    // Prove the user can pass the check before turning it on, so enabling it
    // can never lock them out on the next launch.
    if (value && !await lock.authenticate()) return;
    await lock.setEnabled(value);
    if (!mounted) return;
    ref.read(lockEnabledProvider.notifier).state = value;
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final enabled = ref.watch(lockEnabledProvider);
    return SwitchListTile(
      secondary: const Icon(FreshlyIcons.lock, color: FreshlyColors.ink),
      title: const Text('Biometric lock',
          style: TextStyle(fontWeight: FontWeight.w600)),
      subtitle: const Text('Require Face ID or a fingerprint to open Freshly'),
      value: enabled,
      onChanged: _toggle,
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: FreshlyColors.ink),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}
