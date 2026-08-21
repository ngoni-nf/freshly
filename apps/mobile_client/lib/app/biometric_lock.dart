import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Biometric app-lock.
///
/// Not a sign-in method — a re-entry gate. The account is authenticated once
/// with the phone; after that the session lives in secure storage and this
/// decides whether to reveal the app or demand a face or fingerprint first.
/// Keeping it separate from auth means a failed unlock never destroys the
/// session, it just keeps the screen covered.
class BiometricLock {
  BiometricLock(this._storage);
  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth = LocalAuthentication();

  static const _enabledKey = 'freshly.biometric_lock_enabled';

  /// Whether this device can actually do it: hardware present and something
  /// enrolled. A toggle for a capability the phone lacks is a dead switch, so
  /// the settings screen asks this before offering it.
  Future<bool> canUse() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return supported && canCheck;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async => (await _storage.read(key: _enabledKey)) == '1';

  Future<void> setEnabled(bool value) =>
      _storage.write(key: _enabledKey, value: value ? '1' : '0');

  /// Prompt for a face or fingerprint. Device PIN is allowed as a fallback
  /// (biometricOnly: false) so a wet finger or a failed scan cannot lock a
  /// paying customer out of a booking. Any error reads as "not authenticated".
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock Freshly',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricLockProvider = Provider<BiometricLock>(
  (ref) => BiometricLock(const FlutterSecureStorage()),
);

/// Whether the user has turned the lock on. Hydrated once at startup so the
/// overlay and the settings switch can read it synchronously.
final lockEnabledProvider = StateProvider<bool>((ref) => false);

/// Whether the app is currently covered, awaiting an unlock. Set true when the
/// app goes to the background and at a cold start, cleared on a successful
/// unlock.
final appLockedProvider = StateProvider<bool>((ref) => false);

/// Read the stored preference into [lockEnabledProvider] at launch, and if the
/// lock is on, start covered so a warm resume never flashes the last screen.
Future<void> hydrateBiometricLock(WidgetRef ref) async {
  final enabled = await ref.read(biometricLockProvider).isEnabled();
  ref.read(lockEnabledProvider.notifier).state = enabled;
  if (enabled) ref.read(appLockedProvider.notifier).state = true;
  if (kDebugMode && enabled) debugPrint('biometric lock enabled');
}
