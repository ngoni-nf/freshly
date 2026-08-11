import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import 'job_providers.dart';

/// Screens B.10 to B.12 — the job itself.
///
/// One screen carries the whole fulfilment sequence because a provider working
/// on someone's head cannot navigate a hierarchy. The primary action changes
/// with the state and is always the full-width button at the bottom.
class JobScreen extends ConsumerStatefulWidget {
  const JobScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends ConsumerState<JobScreen> {
  bool _busy = false;

  Future<void> _advance(String status) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).advanceBooking(widget.bookingId, status);
      ref.invalidate(jobProvider(widget.bookingId));
      ref.invalidate(scheduleProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openNavigation(Booking booking) async {
    // Hand off to whatever the provider already uses. Building our own
    // turn-by-turn would be worse than Google's and nobody would use it.
    final uri = Uri.parse(
      'google.navigation:q=${Uri.encodeComponent(booking.destinationAddress)}&mode=d',
    );
    final fallback = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination='
      '${Uri.encodeComponent(booking.destinationAddress)}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _complete() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).completeBooking(
            widget.bookingId,
            idempotencyKey: 'complete-${widget.bookingId}',
          );
      ref.invalidate(walletProvider);
      ref.invalidate(scheduleProvider);
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.check_circle,
                color: FreshlyColors.mint, size: 44),
            title: const Text('Paid'),
            content: const Text(
              'The client\'s payment has been released and your earnings are in your wallet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        if (mounted) context.go('/');
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Declaring a no-show cancels the booking and charges the client a fee, so
  /// it is confirmed first. It lives here rather than in the button, because
  /// only this State owns `_busy` and the booking id the call needs.
  Future<void> _noShow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Declare No-Show?'),
        content: const Text(
          'If the client is not here, you can declare a no-show. '
          'A cancellation fee will be charged to the client to cover your travel.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Wait longer')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FreshlyColors.crimson),
            child: const Text('Declare No-Show'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).cancelBooking(widget.bookingId, 'no_show');
      ref.invalidate(jobProvider(widget.bookingId));
      ref.invalidate(scheduleProvider);
      if (mounted) context.go('/');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Job')),
      body: job.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child:
              Text(e is ApiException ? e.message : 'Could not load this job'),
        ),
        data: (booking) => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: [
            _StatusStrip(status: booking.status),
            const SizedBox(height: FreshlySpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.reference,
                        style: const TextStyle(
                            fontSize: 13, color: FreshlyColors.inkMuted)),
                    const SizedBox(height: 6),
                    Text(booking.total.format(),
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w800)),
                    const Divider(height: FreshlySpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(booking.destinationAddress,
                                style: const TextStyle(height: 1.4))),
                      ],
                    ),
                    if (booking.scheduledStart != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.event_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(formatSlot(booking.scheduledStart!)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: FreshlySpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openNavigation(booking),
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Navigate'),
                  ),
                ),
                const SizedBox(width: FreshlySpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FreshlySpacing.sm),
            if (booking.status == BookingStatus.arrived)
              _NoShowButton(
                arrivedAt: booking.arrivedAt,
                onPressed: _noShow,
              ),
            const SizedBox(height: FreshlySpacing.lg),
            if (booking.status == BookingStatus.inProgress)
              OutlinedButton.icon(
                onPressed: () => context.push('/job/${widget.bookingId}/addon'),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Suggest an extra service'),
              ),
          ],
        ),
      ),
      bottomNavigationBar: job.maybeWhen(
        data: (booking) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            child: _PrimaryAction(
              status: booking.status,
              busy: _busy,
              onEnRoute: () => _advance('en_route'),
              onArrived: () => _advance('arrived'),
              onEnterPin: () => context.push('/job/${widget.bookingId}/pin'),
              onComplete: _complete,
            ),
          ),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

class _NoShowButton extends ConsumerStatefulWidget {
  const _NoShowButton({required this.arrivedAt, required this.onPressed});
  final DateTime? arrivedAt;
  final VoidCallback onPressed;

  @override
  ConsumerState<_NoShowButton> createState() => _NoShowButtonState();
}

class _NoShowButtonState extends ConsumerState<_NoShowButton> {
  Timer? _timer;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    final markets = ref.read(marketsProvider).value;
    final country = ref.read(countryCodeProvider);

    final market = markets?.firstWhere((m) => m.code == country,
        orElse: () => markets.first);
    final graceMinutes = market?.noShowGraceMinutes ?? 10;

    void update() {
      if (widget.arrivedAt == null) return;
      final graceEnd = widget.arrivedAt!.add(Duration(minutes: graceMinutes));
      final diff = graceEnd.difference(DateTime.now()).inSeconds;
      setState(() => _secondsRemaining = diff > 0 ? diff : 0);
    }

    update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _secondsRemaining <= 0;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: enabled ? widget.onPressed : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: FreshlyColors.crimson,
              side: enabled ? const BorderSide(color: FreshlyColors.crimson) : null,
            ),
            child: Text(enabled ? 'Declare No-Show' : 'Wait for client…'),
          ),
        ),
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Available in ${(_secondsRemaining / 60).floor()}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 12, color: FreshlyColors.inkMuted),
            ),
          ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.status,
    required this.busy,
    required this.onEnRoute,
    required this.onArrived,
    required this.onEnterPin,
    required this.onComplete,
  });

  final BookingStatus status;
  final bool busy;
  final VoidCallback onEnRoute;
  final VoidCallback onArrived;
  final VoidCallback onEnterPin;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final (label, action) = switch (status) {
      BookingStatus.accepted => ('Start driving', onEnRoute),
      BookingStatus.enRoute => ('I have arrived', onArrived),
      BookingStatus.arrived => ('Enter client code to start', onEnterPin),
      BookingStatus.inProgress => ('Finish and get paid', onComplete),
      _ => ('Job closed', null),
    };

    return FilledButton(
      onPressed: busy || action == null ? null : action,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontSize: 17)),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.status});
  final BookingStatus status;

  static const _steps = [
    (BookingStatus.accepted, 'Accepted'),
    (BookingStatus.enRoute, 'On the way'),
    (BookingStatus.arrived, 'Arrived'),
    (BookingStatus.inProgress, 'Working'),
    (BookingStatus.completed, 'Paid'),
  ];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _steps.indexWhere((s) => s.$1 == status);
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: done ? FreshlyColors.mint : FreshlyColors.line,
            ),
          );
        }
        final index = i ~/ 2;
        final done = index <= currentIndex && currentIndex >= 0;
        return Column(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: done ? FreshlyColors.mint : Colors.transparent,
                border: Border.all(
                    color: done ? FreshlyColors.mint : FreshlyColors.line,
                    width: 2),
                shape: BoxShape.circle,
              ),
              child: done
                  ? const Icon(Icons.check, size: 13, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 56,
              child: Text(
                _steps[index].$2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: done ? FreshlyColors.mintDark : FreshlyColors.inkMuted,
                  fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
