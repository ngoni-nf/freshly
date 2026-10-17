import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permissions are requested with an explanation first.
///
/// Asking for location cold, at launch, is the single fastest way to get a
/// permanent denial on iOS — and a client who has denied location cannot be
/// matched to anyone. The pre-prompt costs one screen and buys a materially
/// higher grant rate.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    await Permission.locationWhenInUse.request();
    await Permission.notification.request();
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              const ScreenIntro(
                eyebrow: 'Last step',
                title: 'Two quick permissions',
                subtitle: 'You can change either one later in Settings.',
              ),
              const SizedBox(height: FreshlySpacing.xl),
              const _PermissionRow(
                icon: FreshlyIcons.location,
                title: 'Location',
                body: 'So we can show pros near you. Your address goes to a '
                    'pro only once a booking is confirmed.',
              ),
              const _PermissionRow(
                icon: FreshlyIcons.notifications,
                title: 'Notifications',
                body: 'So you know the moment a pro accepts, and when they '
                    'are at your door.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _request,
                child: const Text('Allow both'),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              TextButton(
                style: TextButton.styleFrom(
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => context.go('/home'),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, size: 48),
              const SizedBox(width: FreshlySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
