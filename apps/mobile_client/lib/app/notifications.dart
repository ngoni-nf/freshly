import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import 'notification_prefs.dart';
import 'providers.dart';
import 'router.dart';

/// Handed to MaterialApp.router so a push that arrives while the app is open
/// can be shown from outside any screen's build method.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Where a push's payload points. The server sends a `type` and an id; this
/// is the one place that turns them into a route, for the foreground banner
/// and for a tap on a notification in the tray alike.
String? pushDestination(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  final bookingId = data['bookingId']?.toString();
  final ticketId = data['ticketId']?.toString();
  if (type == 'support.reply') {
    return ticketId == null || ticketId.isEmpty
        ? '/support'
        : '/support?ticket=$ticketId';
  }
  if (bookingId == null || bookingId.isEmpty) return null;
  return switch (type) {
    'chat' => '/track/$bookingId/chat',
    // A cancelled job has no map to show; the booking page says what
    // happened and what was charged.
    'booking_cancelled' => '/bookings/$bookingId',
    _ => '/track/$bookingId',
  };
}

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

      // The OS shows nothing for a push that lands while the app is in the
      // foreground, so the app does: a banner with the way to the booking.
      FirebaseMessaging.onMessage.listen(showForegroundMessage);

      // A tap in the tray while the app is in the background, and the push
      // that launched the app from cold: both land on the same route.
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromTray);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openFromTray(initial);
    } catch (e) {
      if (kDebugMode) print('Push unavailable, continuing without it: $e');
    }
  }

  /// Never throws: a malformed push is dropped, not a crash.
  void showForegroundMessage(RemoteMessage message) {
    try {
      final prefs = _ref.read(notificationPrefsProvider);
      if (!prefs.bannersInApp) return;
      final title = message.notification?.title ??
          message.data['title']?.toString() ??
          'Freshly';
      final body =
          message.notification?.body ?? message.data['body']?.toString() ?? '';
      final destination = pushDestination(message.data);
      if (prefs.vibrate) unawaited(HapticFeedback.mediumImpact());
      showInAppBanner(
        title: title,
        body: body,
        onOpen: destination == null
            ? null
            : () => _ref.read(routerProvider).push(destination),
      );
    } catch (e) {
      if (kDebugMode) print('Dropped a foreground push: $e');
    }
  }

  /// A tap on a notification in the tray, whether the app was in the
  /// background or not running at all.
  void _openFromTray(RemoteMessage message) {
    try {
      final destination = pushDestination(message.data);
      if (destination == null) return;
      if (_ref.read(authStateProvider) is AuthSignedIn) {
        _ref.read(routerProvider).push(destination);
      } else {
        // Cold start: the router sends everything to the splash until the
        // session is restored, so the push would be redirected away. Held
        // until sign-in settles, then opened.
        _pending = destination;
      }
    } catch (e) {
      if (kDebugMode) print('Could not open a push: $e');
    }
  }

  String? _pending;

  /// Opens the push that launched the app, once there is a session to open
  /// it under.
  void flushPending() {
    final destination = _pending;
    if (destination == null) return;
    _pending = null;
    try {
      _ref.read(routerProvider).push(destination);
    } catch (e) {
      if (kDebugMode) print('Could not open a push: $e');
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

final pushNotificationProvider = Provider((ref) {
  final service = PushNotificationService(ref);
  ref.listen(authStateProvider, (_, next) {
    if (next is AuthSignedIn) service.flushPending();
  });
  return service;
});

/// The in-app banner for a push that arrived while the app was open. Lives
/// outside the service so a screen (or a test) can raise one directly.
///
/// A banner at the top, not a snackbar at the bottom: it reads as a
/// notification, not as a confirmation of something the person just did,
/// and it does not cover the sticky action bar on a decision screen. It
/// leaves on its own, on a tap, or on Dismiss.
void showInAppBanner({
  required String title,
  required String body,
  VoidCallback? onOpen,
  Duration showFor = const Duration(seconds: 8),
}) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.hideCurrentMaterialBanner();
  final timer = Timer(showFor, messenger.hideCurrentMaterialBanner);
  void dismiss() {
    timer.cancel();
    messenger.hideCurrentMaterialBanner();
  }

  void open() {
    dismiss();
    onOpen?.call();
  }

  // Surface, not obsidian: half the screens open on a dark hero and a dark
  // banner on top of one has no edge.
  final scheme = Theme.of(messenger.context).colorScheme;
  messenger.showMaterialBanner(MaterialBanner(
    backgroundColor: scheme.surface,
    dividerColor: scheme.outline,
    elevation: 2,
    padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, 12, 8, 0),
    leading: const IconBadge(
        icon: FreshlyIcons.notifications, size: 36, tone: FreshlyTone.brand),
    content: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen == null ? dismiss : open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FreshlyType.style(14,
                  weight: FontWeight.w700, color: scheme.onSurface)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: FreshlyType.style(13,
                    weight: FontWeight.w500, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
        onPressed: dismiss,
        child: const Text('Dismiss'),
      ),
      if (onOpen != null)
        TextButton(
          onPressed: open,
          child: const Text('Open'),
        ),
    ],
  ));
}
