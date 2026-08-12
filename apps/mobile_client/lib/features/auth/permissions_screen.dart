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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              Text('Two quick permissions',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.lg),
              const _PermissionRow(
                icon: FreshlyIcons.location,
                title: 'Location',
                body:
                    'So we can show pros near you and give your barber your address '
                    'only once a booking is confirmed.',
              ),
              const _PermissionRow(
                icon: FreshlyIcons.notifications,
                title: 'Notifications',
                body:
                    'So you know the moment a pro accepts, and when they are at your door.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _request,
                child: const Text('Allow'),
              ),
              TextButton(
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
      padding: const EdgeInsets.only(bottom: FreshlySpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FreshlyColors.mintSoft,
              borderRadius: BorderRadius.circular(FreshlySpacing.radius),
            ),
            child: Icon(icon, color: FreshlyColors.mintDark),
          ),
          const SizedBox(width: FreshlySpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: FreshlyColors.inkMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
