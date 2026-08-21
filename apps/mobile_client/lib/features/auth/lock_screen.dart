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
      backgroundColor: FreshlyColors.mint,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(FreshlyIcons.lock, size: 48, color: Colors.white),
              const SizedBox(height: FreshlySpacing.lg),
              const Text(
                'Freshly is locked',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              const Text(
                'Unlock with your face or fingerprint.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              if (_busy)
                const CircularProgressIndicator(color: Colors.white)
              else
                FilledButton(
                  onPressed: _unlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FreshlyColors.mintDark,
                  ),
                  child: const Text('Unlock'),
                ),
              const SizedBox(height: FreshlySpacing.md),
              TextButton(
                onPressed: () {
                  ref.read(appLockedProvider.notifier).state = false;
                  ref.read(authStateProvider.notifier).logout();
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Sign out instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
