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
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.xs,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          if (user != null) ...[
            Container(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              decoration: BoxDecoration(
                color: FreshlyColors.obsidian,
                borderRadius: BorderRadius.circular(FreshlySpacing.radiusLarge),
              ),
              child: Row(
                children: [
                  FreshlyAvatar(name: user.fullName, size: 60),
                  const SizedBox(width: FreshlySpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName,
                            style: text.headlineSmall
                                ?.copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text(user.phone ?? 'No number linked',
                            style: text.bodyMedium
                                ?.copyWith(color: FreshlyColors.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FreshlySpacing.lg),
          ],
          GroupedList(
            title: 'Your places',
            children: [
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
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const GroupedList(
            title: 'Security',
            children: [_BiometricLockTile()],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          GroupedList(
            title: 'App',
            children: [
              _ProfileTile(
                icon: FreshlyIcons.notifications,
                title: 'Notifications',
                onTap: () => context.push('/profile/notifications'),
              ),
              _ProfileTile(
                icon: FreshlyIcons.info,
                title: 'Help and support',
                onTap: () => context.push('/support'),
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          GroupedList(
            title: 'Legal',
            children: [
              _ProfileTile(
                icon: FreshlyIcons.shield,
                title: 'Privacy policy',
                onTap: () => context.push('/profile/legal/privacy'),
              ),
              _ProfileTile(
                icon: FreshlyIcons.receipt,
                title: 'Terms of service',
                onTap: () => context.push('/profile/legal/terms'),
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.sm),
          // There is no "payment methods" page because there is nothing to
          // manage: every booking is paid at checkout and nothing is stored.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              ref.watch(countryCodeProvider) == 'ZA'
                  ? 'You pay per booking with Capitec Pay, Instant EFT or '
                      'card; nothing is stored on your phone.'
                  : 'You pay per booking with EcoCash, card or InnBucks; '
                      'nothing is stored on your phone.',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          OutlinedButton.icon(
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
                foregroundColor: FreshlyColors.crimson),
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('Sign out'),
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
    if (!_available) {
      return const ListTile(
        leading: IconBadge(
            icon: FreshlyIcons.lock, size: 36, tone: FreshlyTone.neutral),
        title: Text('Biometric lock'),
        subtitle: Text('Set up a fingerprint or face unlock on this phone '
            'to use it'),
      );
    }
    final enabled = ref.watch(lockEnabledProvider);
    return SwitchListTile(
      secondary: const IconBadge(
          icon: FreshlyIcons.lock, size: 36, tone: FreshlyTone.neutral),
      title: const Text('Biometric lock'),
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
      leading: IconBadge(icon: icon, size: 36, tone: FreshlyTone.brand),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
      onTap: onTap,
    );
  }
}
