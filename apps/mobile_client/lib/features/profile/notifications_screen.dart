import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/notification_prefs.dart';

/// The OS-level notification permission, read fresh each time the screen is
/// shown. Overridable so the screen tour can render each state.
final notificationPermissionProvider =
    FutureProvider.autoDispose<PermissionStatus>((ref) async {
  try {
    return await Permission.notification.status;
  } catch (_) {
    // No platform channel (a test, an unsupported platform): say so rather
    // than crash a settings page.
    return PermissionStatus.denied;
  }
});

/// What Freshly sends, whether the phone lets it through, and the two things
/// the app itself can switch.
///
/// There is nothing to toggle per category on purpose: every push we send is
/// about a booking in flight, and a client who turns off "arrival" alerts is
/// a client who misses their pro at the gate. The OS owns the big switch;
/// the app owns only the banner it draws while it is open.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings page is the moment the answer
    // may have changed.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationPermissionProvider);
    }
  }

  Future<void> _request(PermissionStatus current) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (current.isPermanentlyDenied) {
        await openAppSettings();
      } else {
        await Permission.notification.request();
      }
    } catch (_) {
      // The OS said no, or there is no OS to ask. The refreshed status below
      // tells the truth either way.
    } finally {
      ref.invalidate(notificationPermissionProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(notificationPermissionProvider);
    final prefs = ref.watch(notificationPrefsProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.sm,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          status.when(
            loading: () =>
                const Skeleton(height: 132, radius: FreshlySpacing.radius),
            error: (_, __) => const _StatusCard(
                status: PermissionStatus.denied, busy: false, onAction: null),
            data: (s) => _StatusCard(
                status: s, busy: _busy, onAction: () => _request(s)),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          GroupedList(
            title: 'While the app is open',
            children: [
              SwitchListTile.adaptive(
                secondary: const IconBadge(
                    icon: FreshlyIcons.message,
                    size: 36,
                    tone: FreshlyTone.brand),
                title: const Text('Show banners'),
                subtitle: const Text(
                    'A banner at the top of the screen when something '
                    'happens on a booking.'),
                value: prefs.bannersInApp,
                onChanged: (on) => ref
                    .read(notificationPrefsProvider.notifier)
                    .setBannersInApp(on),
              ),
              SwitchListTile.adaptive(
                secondary: const IconBadge(
                    icon: FreshlyIcons.mobile,
                    size: 36,
                    tone: FreshlyTone.brand),
                title: const Text('Vibrate'),
                subtitle: const Text('A short buzz with each banner.'),
                value: prefs.vibrate,
                onChanged: prefs.bannersInApp
                    ? (on) => ref
                        .read(notificationPrefsProvider.notifier)
                        .setVibrate(on)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
                prefs.persisted
                    ? 'Saved on this phone only.'
                    : 'Could not save on this phone; these reset when the '
                        'app closes.',
                style: text.bodySmall),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const SectionHeader(
              title: 'What we send', padding: EdgeInsets.only(bottom: 12)),
          Card(
            child: Column(children: [
              const _WhatTile(
                icon: FreshlyIcons.calendar,
                title: 'Job updates',
                body: 'When a pro accepts your booking, sets off, or has to '
                    'cancel.',
              ),
              Divider(indent: 64, color: Theme.of(context).colorScheme.outline),
              const _WhatTile(
                icon: FreshlyIcons.navigation,
                title: 'Arrival',
                body: 'When your pro is a few minutes away and when they are '
                    'at your door.',
              ),
              Divider(indent: 64, color: Theme.of(context).colorScheme.outline),
              const _WhatTile(
                icon: FreshlyIcons.lock,
                title: 'Code reminders',
                body: 'A nudge to have your four-digit code ready when the '
                    'job is done.',
              ),
              Divider(indent: 64, color: Theme.of(context).colorScheme.outline),
              const _WhatTile(
                icon: FreshlyIcons.chat,
                title: 'Messages',
                body: 'A reply from your pro, or from the Freshly team on a '
                    'support request.',
              ),
            ]),
          ),
          const SizedBox(height: FreshlySpacing.md),
          Text(
              'No marketing, no deals, no "we miss you". Every notification '
              'is about a booking you made.',
              style: text.bodySmall),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(
      {required this.status, required this.busy, required this.onAction});
  final PermissionStatus status;
  final bool busy;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final granted =
        status.isGranted || status.isLimited || status.isProvisional;
    final settings = status.isPermanentlyDenied;

    final title = granted ? 'Notifications are on' : 'Notifications are off';
    final body = granted
        ? 'You will hear when your pro is on the way and at your door.'
        : settings
            ? 'This phone is blocking Freshly. Turn notifications on in '
                'Settings or you will not know when your pro arrives.'
            : 'Without them you will not know when your pro is on the way '
                'or at your door.';

    return Container(
      padding: const EdgeInsets.all(FreshlySpacing.md),
      decoration: BoxDecoration(
        color: FreshlyColors.obsidian,
        borderRadius: BorderRadius.circular(FreshlySpacing.radiusLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            IconBadge(
                icon:
                    granted ? FreshlyIcons.notifications : FreshlyIcons.warning,
                size: 44,
                tone: granted ? FreshlyTone.brand : FreshlyTone.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.titleMedium?.copyWith(color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(body,
                      style: text.bodySmall
                          ?.copyWith(color: FreshlyColors.inkMuted)),
                ],
              ),
            ),
          ]),
          if (!granted) ...[
            const SizedBox(height: FreshlySpacing.md),
            FilledButton(
              onPressed: busy ? null : onAction,
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FreshlyColors.obsidian))
                  : Text(settings ? 'Open Settings' : 'Turn on'),
            ),
          ],
        ],
      ),
    );
  }
}

class _WhatTile extends StatelessWidget {
  const _WhatTile(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: IconBadge(icon: icon, size: 36, tone: FreshlyTone.neutral),
      title: Text(title),
      subtitle: Text(body),
    );
  }
}
