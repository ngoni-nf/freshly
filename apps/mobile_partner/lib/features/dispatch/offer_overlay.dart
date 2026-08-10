import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen B.9 — the incoming request.
///
/// This screen has one job: let someone who is mid-haircut, driving, or
/// holding a client's head decide in under a second. So it shows exactly four
/// things — what it pays, how far, how long, and how much time is left — at a
/// size readable at arm's length, with two targets big enough to hit without
/// looking carefully.
///
/// The countdown is driven from the server's expiry timestamp, not a local
/// timer started on arrival. A push that took four seconds to land must not
/// give the provider a full sixty, or they accept a job the backend has
/// already offered to someone else.
class OfferOverlay extends ConsumerStatefulWidget {
  const OfferOverlay({required this.offer, super.key});

  final DispatchOffer offer;

  @override
  ConsumerState<OfferOverlay> createState() => _OfferOverlayState();
}

class _OfferOverlayState extends ConsumerState<OfferOverlay> {
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.offer.remaining;
    HapticFeedback.heavyImpact();

    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final left = widget.offer.remaining;
      if (!mounted) return;
      if (left.isNegative || left == Duration.zero) {
        _ticker?.cancel();
        _expire();
        return;
      }
      setState(() => _remaining = left);
    });
  }

  Future<void> _respond(bool accept) async {
    if (_responding) return;
    setState(() => _responding = true);
    _ticker?.cancel();
    unawaited(HapticFeedback.selectionClick());

    try {
      await ref
          .read(offerQueueProvider.notifier)
          .respond(widget.offer.offerId, accept);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (accept) unawaited(context.push('/job/${widget.offer.bookingId}'));
    } on ApiException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // The realistic failure is losing the race to another provider.
            // Saying so plainly beats a generic error, which reads as a bug.
            e.code == 'offer_taken'
                ? 'Another pro took that one. We will send you the next.'
                : e.message,
          ),
        ),
      );
    }
  }

  /// The window closed without a response. Drop it locally; the server has
  /// already moved the booking to the next dispatch wave.
  void _expire() {
    ref.read(offerQueueProvider.notifier).remove(widget.offer.offerId);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    const totalSeconds = 60;
    final progress =
        (_remaining.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0);
    final urgent = _remaining.inSeconds <= 15;

    return Material(
      color: FreshlyColors.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            children: [
              // ── Countdown ────────────────────────────────────────────────
              SizedBox(
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 92,
                      height: 92,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation(
                          urgent ? FreshlyColors.crimson : FreshlyColors.mint,
                        ),
                      ),
                    ),
                    Text(
                      '${_remaining.inSeconds}',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),

              // ── Payout, the number that decides it ───────────────────────
              Text(
                offer.payout.format(),
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              const Text('You earn',
                  style: TextStyle(color: Colors.white70, fontSize: 15)),

              const SizedBox(height: FreshlySpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Stat(
                      icon: Icons.near_me_outlined,
                      value: formatDistance(offer.distanceKm),
                      label: 'away'),
                  _Stat(
                      icon: Icons.schedule,
                      value: formatEta(offer.etaMinutes),
                      label: 'drive'),
                  _Stat(
                    icon: Icons.star_rounded,
                    value: offer.clientRating.toStringAsFixed(1),
                    label: 'client',
                  ),
                ],
              ),

              const SizedBox(height: FreshlySpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FreshlySpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (offer.serviceNames.isNotEmpty) ...[
                      Text(offer.serviceNames.join(' · '),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15)),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: Colors.white54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            // Suburb only until acceptance — the exact address
                            // is the client's to give, not ours to broadcast.
                            offer.destinationAddress,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (offer.scheduledStart != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.event_outlined,
                              size: 16, color: Colors.white54),
                          const SizedBox(width: 6),
                          Text(formatSlot(offer.scheduledStart!),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 64,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                        onPressed: _responding ? null : () => _respond(false),
                        child: const Text('Decline',
                            style: TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.md),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 64,
                      child: FilledButton(
                        onPressed: _responding ? null : () => _respond(true),
                        child: _responding
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Accept',
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
}

/// Watches the offer queue anywhere in the app and raises the overlay.
///
/// Mounted once, above the router, so an offer interrupts whatever the
/// provider is doing — including a settings screen or the wallet.
class OfferListener extends ConsumerStatefulWidget {
  const OfferListener({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<OfferListener> createState() => _OfferListenerState();
}

class _OfferListenerState extends ConsumerState<OfferListener> {
  String? _showing;

  @override
  Widget build(BuildContext context) {
    ref.listen<List<DispatchOffer>>(offerQueueProvider, (previous, next) {
      if (next.isEmpty || _showing != null) return;
      final offer = next.first;
      _showing = offer.offerId;

      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useSafeArea: false,
          builder: (_) => OfferOverlay(offer: offer),
        ).whenComplete(() => _showing = null),
      );
    });

    return widget.child;
  }
}
