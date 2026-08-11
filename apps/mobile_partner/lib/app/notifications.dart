import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

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

    FirebaseMessaging.onTokenRefresh.listen((token) {
      _ref.read(pushTokenProvider.notifier).state = token;
      final auth = _ref.read(partnerAuthProvider);
      if (auth is PartnerReady || auth is PartnerPendingVerification) {
        _ref.read(apiProvider).updatePushToken(token);
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        print('Partner foreground message: ${message.notification?.title}');
      }
      // Partner app might need more prominent alerts for new offers.
    });
  }
}

final pushTokenProvider = StateProvider<String?>((ref) => null);

final pushNotificationProvider = Provider((ref) => PushNotificationService(ref));
