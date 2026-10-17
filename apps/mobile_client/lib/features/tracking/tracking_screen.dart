import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../app/providers.dart';
import 'sos_button.dart';

/// Screen A.13 — live tracking.
class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  GoogleMapController? _map;
  StreamSubscription<TrackingUpdate>? _sub;
  StreamSubscription<RealtimeConnectionState>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _addonSub;
  Timer? _poll;
  late final RealtimeClient _realtime;

  TrackingUpdate? _latest;
  Booking? _booking;
  bool _degraded = false;

  @override
  void initState() {
    super.initState();
    // Held for dispose(): Riverpod forbids `ref` once the widget is being
    // torn down, and reading it there threw on every exit from this screen.
    final realtime =
        _realtime = ref.read(realtimeProvider)..joinBooking(widget.bookingId);

    _sub = realtime.tracking.listen((update) {
      if (update.bookingId != widget.bookingId) return;
      setState(() => _latest = update);
      if (update.providerLocation != null) {
        _map?.animateCamera(CameraUpdate.newLatLng(
          LatLng(update.providerLocation!.lat, update.providerLocation!.lng),
        ));
      }
      if (update.status == BookingStatus.arrived) _promptForPin();
      if (update.status.isTerminal) _onFinished(update.status);
    });

    _statusSub =
        realtime.status.listen((s) => setState(() => _degraded = s.isDegraded));
    _addonSub = realtime.addonRequests.listen(_promptAddon);

    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final booking = await ref.read(apiProvider).booking(widget.bookingId);
      if (mounted) setState(() => _booking = booking);
      if (booking.status.isTerminal) _onFinished(booking.status);
    } catch (_) {/* retried on the next tick */}
  }

  void _onFinished(BookingStatus status) {
    _poll?.cancel();
    if (status == BookingStatus.completed && mounted) {
      context.go('/bookings');
    }
  }

  void _promptForPin() {
    if (!mounted) return;
    context.push('/track/${widget.bookingId}/pin');
  }

  /// Screen B.11's counterpart: the pro proposes an extra, the client approves
  /// it here, and only then does the escrow hold increase. A provider can never
  /// unilaterally raise what a customer pays.
  Future<void> _promptAddon(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(icon: FreshlyIcons.addCircle, size: 52),
              const SizedBox(height: FreshlySpacing.md),
              Text('Your pro suggested an extra',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                  'Nothing changes unless you approve. The amount is added to '
                  'the payment we are holding.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: FreshlySpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            payload['name'] as String? ?? 'Additional service',
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      Text(
                        formatMinor(payload['priceMinor'] as int? ?? 0,
                            payload['currency'] as String? ?? 'ZAR'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No thanks'),
                  ),
                ),
                const SizedBox(width: FreshlySpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Approve'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );

    if (approved != null) {
      try {
        await ref.read(apiProvider).respondToAddon(
              widget.bookingId,
              payload['itemId'] as String,
              approved,
            );
        if (mounted && approved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Add-on approved and authorized')),
          );
        }
      } on ApiException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = _latest?.providerLocation;
    final status =
        _latest?.status ?? _booking?.status ?? BookingStatus.accepted;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: location != null
                  ? LatLng(location.lat, location.lng)
                  // Only until the first position arrives. Harare, where
                  // the first bookings are.
                  : const LatLng(-17.8252, 31.0530),
              zoom: 14,
            ),
            onMapCreated: (c) => _map = c,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: {
              if (location != null)
                Marker(
                  markerId: const MarkerId('pro'),
                  position: LatLng(location.lat, location.lng),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                ),
            },
          ),
          if (_degraded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: FreshlySpacing.md,
              right: FreshlySpacing.md,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: FreshlyColors.obsidian,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: FreshlyColors.mint),
                    ),
                    const SizedBox(width: 10),
                    Text('Reconnecting — updates may be delayed',
                        style: FreshlyType.style(12,
                            weight: FontWeight.w600, color: Colors.white)),
                  ]),
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: FreshlySpacing.sm,
            child: IconButton(
              tooltip: 'Back',
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
              icon: const Icon(FreshlyIcons.chevronLeft, size: 20),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.36,
            minChildSize: 0.24,
            maxChildSize: 0.7,
            builder: (context, controller) => DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(FreshlySpacing.radiusLarge)),
                boxShadow: FreshlyShadows.floating,
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, 10,
                    FreshlySpacing.md, FreshlySpacing.lg),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(status.clientLabel,
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 2),
                            Text(_booking?.reference ?? '',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      if (_latest?.etaMinutes != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatEta(_latest!.etaMinutes),
                                style: FreshlyType.style(24,
                                    weight: FontWeight.w800,
                                    color:
                                        Theme.of(context).colorScheme.primary)),
                            Text('away',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  BookingProgress(status: status),
                  const SizedBox(height: FreshlySpacing.lg),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          FreshlyAvatar(
                              name: _booking?.providerName ?? 'Your pro',
                              size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_booking?.providerName ?? 'Your pro',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 2),
                                Text('Calls and messages are private',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          _RoundAction(
                            icon: FreshlyIcons.chat,
                            tooltip: 'Message',
                            onPressed: () =>
                                context.push('/track/${widget.bookingId}/chat'),
                          ),
                          const SizedBox(width: 8),
                          _RoundAction(
                            icon: FreshlyIcons.call,
                            tooltip: 'Call',
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  if (status == BookingStatus.arrived ||
                      status == BookingStatus.inProgress) ...[
                    FilledButton.icon(
                      onPressed: _promptForPin,
                      icon: const Icon(FreshlyIcons.lock),
                      label: const Text('Show my code'),
                    ),
                    const SizedBox(height: FreshlySpacing.sm),
                  ],
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                    onPressed: () {},
                    icon: const Icon(FreshlyIcons.warning, size: 18),
                    label: const Text('Report a problem'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: FreshlySpacing.md,
            bottom: MediaQuery.of(context).size.height * 0.38,
            child: SosButton(bookingId: widget.bookingId),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    _statusSub?.cancel();
    _addonSub?.cancel();
    _realtime.leaveBooking(widget.bookingId);
    _map?.dispose();
    super.dispose();
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction(
      {required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      icon: Icon(icon, size: 20),
    );
  }
}
