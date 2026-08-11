import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class PushNotificationService {
  PushNotificationService(this._ref);
  final Ref _ref;

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await messaging.getToken();
      if (token != null) _ref.read(pushTokenProvider.notifier).state = token;
    }

    messaging.onTokenRefresh.listen((token) {
      _ref.read(pushTokenProvider.notifier).state = token;
      // If we are signed in, tell the backend immediately.
      final auth = _ref.read(authStateProvider);
      if (auth is AuthSignedIn) {
        _ref.read(apiProvider).updatePushToken(token);
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        print('Foreground message: ${message.notification?.title}');
      }
      // TODO: Show an in-app banner if needed. The system handles background
      // notifications on its own.
    });
  }
}

final pushTokenProvider = StateProvider<String?>((ref) => null);

final pushNotificationProvider =
    Provider((ref) => PushNotificationService(ref));
