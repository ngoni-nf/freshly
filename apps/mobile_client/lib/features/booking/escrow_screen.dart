import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final RealtimeClient _realtime;
  StreamSubscription<TrackingUpdate>? _sub;
  BookingStatus _status = BookingStatus.authorized;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    // Held for dispose(): Riverpod forbids `ref` once the widget is being
    // torn down, and reading it there threw on every exit from this screen.
    final realtime =
        _realtime = ref.read(realtimeProvider)..joinBooking(widget.bookingId);
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
    final text = Theme.of(context).textTheme;

    if (failed) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const Expanded(
                child: EmptyState(
                  icon: FreshlyIcons.searchOff,
                  title: 'No pro available right now',
                  message: 'Your payment hold has been released in full. '
                      'Nothing was charged.',
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: FilledButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Try another pro'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // The wait happens on obsidian: it is the one screen where nothing is
    // asked of the customer, so it can afford to be calm and full-bleed.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: FreshlyColors.obsidian,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.lg),
            child: Column(
              children: [
                const Spacer(),
                const _Radar(),
                const SizedBox(height: FreshlySpacing.xl),
                Text(_status.clientLabel,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: FreshlySpacing.sm),
                Text(
                  _elapsed < 30
                      ? 'We are sending your booking to pros nearby.'
                      : 'Still looking — we are widening the search radius.',
                  textAlign: TextAlign.center,
                  style:
                      text.bodyLarge?.copyWith(color: FreshlyColors.inkMuted),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  decoration: BoxDecoration(
                    color: FreshlyColors.obsidianRaised,
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                  child: Row(children: [
                    const Icon(FreshlyIcons.shield, color: FreshlyColors.mint),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your payment is held, not taken. If no pro accepts, '
                        'it is released back to you automatically.',
                        style: FreshlyType.style(13,
                            height: 1.45, color: const Color(0xFFC3CCD8)),
                      ),
                    ),
                  ]),
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
    _poll?.cancel();
    _sub?.cancel();
    _realtime.leaveBooking(widget.bookingId);
    super.dispose();
  }
}

/// Rings expanding from a mint core: "we are looking" without a spinner.
/// Still under reduce-motion.
class _Radar extends StatefulWidget {
  const _Radar();

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.value = 0.5;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(builder: (context) {
                final t = (_c.value + i / 3) % 1;
                return Container(
                  width: 72 + 148 * t,
                  height: 72 + 148 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: FreshlyColors.mint
                            .withValues(alpha: (1 - t) * 0.55),
                        width: 2),
                  ),
                );
              }),
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: FreshlyColors.mint,
              ),
              child: const Icon(FreshlyIcons.search,
                  size: 30, color: FreshlyColors.obsidian),
            ),
          ],
        ),
      ),
    );
  }
}
