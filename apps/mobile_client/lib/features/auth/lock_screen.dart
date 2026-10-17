import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/biometric_lock.dart';
import '../../app/providers.dart';

/// The cover shown over the app while it is locked.
///
/// It prompts once as soon as it appears, so an unlock is usually a glance and
/// the screen is never seen. If that is dismissed it stays up with a button to
/// try again, and a way out — sign out — so a phone whose biometrics have
/// changed is never a permanent lockout.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ref.read(biometricLockProvider).authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.read(appLockedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) {
    // Opaque, so nothing underneath shows through while locked.
    return Scaffold(
      backgroundColor: FreshlyColors.obsidian,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: IconBadge(
                    icon: FreshlyIcons.lock, size: 80, tone: FreshlyTone.brand),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              Text('Freshly is locked',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: Colors.white)),
              const SizedBox(height: FreshlySpacing.sm),
              Text('Unlock with your face or fingerprint.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: FreshlyColors.inkMuted)),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _unlock,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.obsidian))
                    : const Text('Unlock'),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              TextButton(
                onPressed: () {
                  ref.read(appLockedProvider.notifier).state = false;
                  ref.read(authStateProvider.notifier).logout();
                },
                style: TextButton.styleFrom(
                    foregroundColor: FreshlyColors.inkMuted),
                child: const Text('Sign out instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
