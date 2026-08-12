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

  TrackingUpdate? _latest;
  Booking? _booking;
  bool _degraded = false;

  @override
  void initState() {
    super.initState();
    final realtime = ref.read(realtimeProvider)..joinBooking(widget.bookingId);

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
      builder: (_) => Padding(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your pro suggested an extra',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: FreshlySpacing.md),
            Text(payload['name'] as String? ?? 'Additional service',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              formatMinor(payload['priceMinor'] as int? ?? 0,
                  payload['currency'] as String? ?? 'ZAR'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
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
                  : const LatLng(-26.1076, 28.0473),
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: FreshlyColors.ink.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                  SizedBox(width: 8),
                  Text('Reconnecting — updates may be delayed',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ),
          DraggableScrollableSheet(
            initialChildSize: 0.32,
            minChildSize: 0.22,
            maxChildSize: 0.7,
            builder: (context, controller) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(FreshlySpacing.radiusLarge)),
              ),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(FreshlySpacing.lg),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FreshlyColors.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  Text(status.clientLabel,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    _latest?.etaMinutes != null
                        ? 'Arriving in ${formatEta(_latest!.etaMinutes)}'
                        : _booking?.reference ?? '',
                    style: const TextStyle(color: FreshlyColors.inkMuted),
                  ),
                  const SizedBox(height: FreshlySpacing.lg),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: FreshlyColors.mintSoft,
                        child: Icon(FreshlyIcons.person,
                            color: FreshlyColors.mintDark),
                      ),
                      title: Text(_booking?.providerName ?? 'Your pro'),
                      subtitle:
                          const Text('Calls and messages are number-masked'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                            icon: const Icon(FreshlyIcons.chat),
                            onPressed: () => context
                                .push('/track/${widget.bookingId}/chat')),
                        IconButton(
                            icon: const Icon(FreshlyIcons.call),
                            onPressed: () {}),
                      ]),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  if (status == BookingStatus.arrived ||
                      status == BookingStatus.inProgress)
                    FilledButton.icon(
                      onPressed: _promptForPin,
                      icon: const Icon(FreshlyIcons.pin),
                      label: const Text('Show my completion code'),
                    ),
                  const SizedBox(height: FreshlySpacing.md),
                  TextButton.icon(
                    onPressed: () {},
                    icon: const Icon(FreshlyIcons.warning),
                    label: const Text('Report a problem'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: FreshlySpacing.md,
            bottom: MediaQuery.of(context).size.height * 0.36,
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
    ref.read(realtimeProvider).leaveBooking(widget.bookingId);
    _map?.dispose();
    super.dispose();
  }
}
