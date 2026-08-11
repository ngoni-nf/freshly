import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class PushNotificationService {
  PushNotificationService(this._ref);
  final Ref _ref;

  /// Never throws.
  ///
  /// Acquiring an FCM token needs a reachable Google, and that is not a given:
  /// offline, a handset without Play Services, a restricted network, or an
  /// emulator with no DNS all make `getToken` fail with SERVICE_NOT_AVAILABLE.
  /// This runs on the launch path, so an escaping exception is a white screen
  /// and an app that will not start — an unacceptable price for a feature that
  /// only makes notifications work.
  ///
  /// Losing push is a degraded app. Failing to boot is a broken one.
  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Registration is attempted even if the token arrives later: the stream
      // below covers the case where Google becomes reachable mid-session.
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await messaging.getToken();
        if (token != null) {
          _ref.read(pushTokenProvider.notifier).state = token;
          await _register(token);
        }
      }

      messaging.onTokenRefresh.listen((token) {
        _ref.read(pushTokenProvider.notifier).state = token;
        unawaited(_register(token));
      });

      FirebaseMessaging.onMessage.listen((message) {
        if (kDebugMode) {
          print('Foreground message: ${message.notification?.title}');
        }
        // TODO: Show an in-app banner if needed. The system handles background
        // notifications on its own.
      });
    } catch (e) {
      if (kDebugMode) print('Push unavailable, continuing without it: $e');
    }
  }

  /// Hands the token to the API, if there is a session to attach it to.
  ///
  /// Registration used to happen only on rotation, so a device that acquired
  /// its token the ordinary way — at launch, which is every device — never
  /// reached the server at all. Every `devices` row had a null `push_token`
  /// and no notification could ever have been delivered.
  ///
  /// Failure is swallowed on purpose. Not receiving push is a degraded app;
  /// an exception on the launch path is a broken one. The next launch retries.
  Future<void> _register(String token) async {
    if (_ref.read(authStateProvider) is! AuthSignedIn) return;
    try {
      await _ref.read(apiProvider).updatePushToken(token);
    } catch (_) {
      // Deliberately ignored — see above.
    }
  }
}

final pushTokenProvider = StateProvider<String?>((ref) => null);

final pushNotificationProvider =
    Provider((ref) => PushNotificationService(ref));
