import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// What the app itself controls about notifications.
///
/// Only switches that genuinely do something live here. The OS decides
/// whether a push in the background is shown at all, and the server decides
/// what is sent; a switch that pretended to govern either would be a lie on
/// a settings page. What the app does own is the banner it draws for a push
/// that lands while it is open, so that is what can be turned off.
class NotificationPrefs {
  const NotificationPrefs({
    this.bannersInApp = true,
    this.vibrate = true,
    this.persisted = true,
  });

  /// Show a banner for a push that arrives while the app is in front.
  final bool bannersInApp;

  /// A short buzz with that banner.
  final bool vibrate;

  /// False when the local store was unavailable and these live only until
  /// the app closes; the screen says so.
  final bool persisted;

  NotificationPrefs copyWith(
          {bool? bannersInApp, bool? vibrate, bool? persisted}) =>
      NotificationPrefs(
        bannersInApp: bannersInApp ?? this.bannersInApp,
        vibrate: vibrate ?? this.vibrate,
        persisted: persisted ?? this.persisted,
      );

  Map<String, dynamic> toJson() =>
      {'bannersInApp': bannersInApp, 'vibrate': vibrate};

  factory NotificationPrefs.fromJson(Map<String, dynamic> j) =>
      NotificationPrefs(
        bannersInApp: j['bannersInApp'] as bool? ?? true,
        vibrate: j['vibrate'] as bool? ?? true,
      );
}

/// Kept in the cache box main() opens, under one key. There is no
/// shared_preferences in this app and one more native plugin for two
/// booleans is not worth its build time.
class NotificationPrefsNotifier extends Notifier<NotificationPrefs> {
  static const _box = 'freshly_cache';
  static const _key = 'notification_prefs';

  @override
  NotificationPrefs build() {
    try {
      final raw = Hive.box<String>(_box).get(_key);
      if (raw == null) return const NotificationPrefs();
      return NotificationPrefs.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Box not open (a test, or a launch where Hive failed): defaults that
      // last the session, and the screen tells the person as much.
      return const NotificationPrefs(persisted: false);
    }
  }

  void setBannersInApp(bool on) => _save(state.copyWith(bannersInApp: on));
  void setVibrate(bool on) => _save(state.copyWith(vibrate: on));

  void _save(NotificationPrefs next) {
    state = next;
    if (!next.persisted) return;
    try {
      Hive.box<String>(_box).put(_key, jsonEncode(next.toJson()));
    } catch (_) {
      state = next.copyWith(persisted: false);
    }
  }
}

final notificationPrefsProvider =
    NotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
        NotificationPrefsNotifier.new);
