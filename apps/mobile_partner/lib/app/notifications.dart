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
  /// and an app that will not start.
  ///
  /// It matters more here than in the client app. A provider whose app refuses
  /// to open cannot work at all.
  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

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
          print('Partner foreground message: ${message.notification?.title}');
        }
        // Partner app might need more prominent alerts for new offers.
      });
    } catch (e) {
      if (kDebugMode) print('Push unavailable, continuing without it: $e');
    }
  }

  /// Sends the token up, if there is a session to attach it to.
  ///
  /// Registration used to happen only on rotation, so a device that acquired
  /// its token the ordinary way — at launch, which is every device — never
  /// reached the server. Every `devices` row held a null `push_token`, and no
  /// job offer could ever have been delivered.
  Future<void> _register(String token) async {
    final auth = _ref.read(partnerAuthProvider);
    if (auth is! PartnerReady && auth is! PartnerPendingVerification) return;
    try {
      await _ref.read(apiProvider).updatePushToken(token);
    } catch (_) {
      // Missing push is degraded; a throw here would be worse.
    }
  }
}

final pushTokenProvider = StateProvider<String?>((ref) => null);

final pushNotificationProvider =
    Provider((ref) => PushNotificationService(ref));
