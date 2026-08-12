import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen A.12 — the waiting room while dispatch finds a pro.
///
/// The socket is the fast path; the poll is the honest one. On a congested
/// mobile network the websocket can be silently dead for thirty seconds, and a
/// customer who has just been charged deserves better than a spinner that
/// never resolves.
class EscrowScreen extends ConsumerStatefulWidget {
  const EscrowScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<EscrowScreen> createState() => _EscrowScreenState();
}

class _EscrowScreenState extends ConsumerState<EscrowScreen> {
  Timer? _poll;
  StreamSubscription<TrackingUpdate>? _sub;
  BookingStatus _status = BookingStatus.authorized;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    final realtime = ref.read(realtimeProvider)..joinBooking(widget.bookingId);
    _sub = realtime.tracking.listen((update) {
      if (update.bookingId == widget.bookingId) _apply(update.status);
    });
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _elapsed += 4);
    try {
      final booking = await ref.read(apiProvider).booking(widget.bookingId);
      _apply(booking.status);
    } catch (_) {/* keep waiting; the next tick retries */}
  }

  void _apply(BookingStatus status) {
    if (!mounted) return;
    setState(() => _status = status);
    if (status == BookingStatus.accepted || status == BookingStatus.enRoute) {
      context.go('/track/${widget.bookingId}');
    } else if (status == BookingStatus.expired ||
        status == BookingStatus.cancelled) {
      _poll?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed =
        _status == BookingStatus.expired || _status == BookingStatus.cancelled;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!failed) ...[
                const SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: FreshlyColors.mint),
                ),
                const SizedBox(height: FreshlySpacing.xl),
                Text(_status.clientLabel,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: FreshlySpacing.sm),
                Text(
                  _elapsed < 30
                      ? 'We are sending your booking to pros nearby.'
                      : 'Still looking — we are widening the search radius.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: FreshlyColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.xl),
                Container(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  decoration: BoxDecoration(
                    color: FreshlyColors.mintSoft,
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                  child: const Row(children: [
                    Icon(FreshlyIcons.shield, color: FreshlyColors.mintDark),
                    SizedBox(width: FreshlySpacing.sm),
                    Expanded(
                      child: Text(
                        'Your payment is held, not taken. If no pro accepts, it is released '
                        'back to you automatically.',
                        style: TextStyle(fontSize: 13, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ] else ...[
                const Icon(FreshlyIcons.searchOff,
                    size: 56, color: FreshlyColors.inkMuted),
                const SizedBox(height: FreshlySpacing.lg),
                const Text('No pro available right now',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: FreshlySpacing.sm),
                const Text(
                  'Your payment hold has been released in full. Nothing was charged.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.xl),
                FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Try another pro'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sub?.cancel();
    ref.read(realtimeProvider).leaveBooking(widget.bookingId);
    super.dispose();
  }
}
