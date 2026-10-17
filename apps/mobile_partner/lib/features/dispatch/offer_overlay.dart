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
    final text = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: FreshlyColors.obsidian,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                FreshlySpacing.md, FreshlySpacing.lg, FreshlySpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Countdown ──────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NEW JOB REQUEST',
                              style: FreshlyType.style(12,
                                      weight: FontWeight.w800,
                                      color: FreshlyColors.mint)
                                  .copyWith(letterSpacing: 1.4)),
                          const SizedBox(height: 8),
                          StatusPill(
                            label: offer.scheduledStart == null
                                ? 'Leave now'
                                : formatSlot(offer.scheduledStart!),
                            icon: offer.scheduledStart == null
                                ? FreshlyIcons.bolt
                                : FreshlyIcons.calendar,
                            tone: FreshlyTone.neutral,
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: '${_remaining.inSeconds} seconds left to accept',
                      excludeSemantics: true,
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 6,
                                strokeCap: StrokeCap.round,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation(
                                  urgent
                                      ? FreshlyColors.crimson
                                      : FreshlyColors.mint,
                                ),
                              ),
                            ),
                            Text(
                              '${_remaining.inSeconds}',
                              style: FreshlyType.style(30,
                                  weight: FontWeight.w800,
                                  color: urgent
                                      ? const Color(0xFFFF8A8D)
                                      : Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const Spacer(flex: 3),

                // ── What the job actually is ───────────────────────────────
                // Above the money on purpose. The amount cannot be judged
                // without it: the same R78 is generous for a line-up and an
                // insult for a two-hour braid, and a provider deciding whether
                // to drive across town is really asking what the work is.
                if (offer.serviceNames.isNotEmpty)
                  Text(
                    offer.serviceNames.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineSmall?.copyWith(color: Colors.white),
                  ),
                const SizedBox(height: FreshlySpacing.lg),

                // ── Payout, the number that decides it ─────────────────────
                Text('You earn',
                    style: text.bodyLarge
                        ?.copyWith(color: FreshlyColors.inkMuted)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    offer.payout.format(),
                    style: FreshlyType.style(60,
                        weight: FontWeight.w800,
                        height: 1,
                        color: FreshlyColors.mint),
                  ),
                ),

                const SizedBox(height: FreshlySpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: FreshlyColors.obsidianRaised,
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Stat(
                            icon: FreshlyIcons.nearMe,
                            value: formatDistance(offer.distanceKm),
                            label: 'away'),
                      ),
                      Expanded(
                        child: _Stat(
                            icon: FreshlyIcons.car,
                            value: formatEta(offer.etaMinutes),
                            label: 'drive'),
                      ),
                      // How long they are committing the chair for, which is
                      // the other half of "is this worth it".
                      if (offer.durationMinutes > 0)
                        Expanded(
                          child: _Stat(
                            icon: FreshlyIcons.timelapse,
                            value: formatDuration(offer.durationMinutes),
                            label: 'work',
                          ),
                        ),
                      Expanded(
                        child: _Stat(
                          icon: FreshlyIcons.star,
                          iconColor: FreshlyColors.gold,
                          value: offer.clientRating.toStringAsFixed(1),
                          label: 'client',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                Container(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  decoration: BoxDecoration(
                    color: FreshlyColors.obsidianRaised,
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                  child: Row(
                    children: [
                      const Icon(FreshlyIcons.location,
                          size: 20, color: FreshlyColors.mint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          // Suburb only until acceptance — the exact address
                          // is the client's to give, not ours to broadcast.
                          offer.destinationAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FreshlyType.style(16,
                              weight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      Text(offer.reference,
                          style: FreshlyType.style(12,
                              weight: FontWeight.w600,
                              color: FreshlyColors.inkMuted)),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Accept is the big target at the bottom, where the thumb
                // already is; decline is deliberately quieter beside it.
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 72,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: FreshlyColors.inkMuted,
                            disabledForegroundColor:
                                FreshlyColors.inkSubtle,
                            side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.16),
                                width: 1.5),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed:
                              _responding ? null : () => _respond(false),
                          child: const Text('Decline'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 72,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            disabledBackgroundColor:
                                FreshlyColors.mint.withValues(alpha: 0.6),
                          ),
                          onPressed: _responding ? null : () => _respond(true),
                          child: _responding
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: FreshlyColors.obsidian))
                              : Text('Accept',
                                  style: FreshlyType.style(22,
                                      weight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = FreshlyColors.inkMuted,
  });
  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: FreshlyType.style(18,
                    weight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: FreshlyType.style(12,
                  weight: FontWeight.w500, color: FreshlyColors.inkMuted)),
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
