import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../widgets/assign_sheet.dart';
import '../../widgets/job_status.dart';
import '../../widgets/job_tile.dart' show AssigneePill;
import '../../widgets/slide_to_confirm.dart';
import '../../widgets/sos_button.dart';
import 'invoices_section.dart';
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
      ref.invalidate(jobProvider(widget.bookingId));
      if (mounted) {
        final isStaff = ref.read(isSalonStaffProvider);
        // The screen stays on the finished job rather than bouncing home:
        // the invoices and the client rating live here, and the provider is
        // standing next to the person they are about to rate.
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const IconBadge(
                icon: FreshlyIcons.checkCircle,
                tone: FreshlyTone.success,
                size: 64),
            title: Text(isStaff ? 'Job done' : 'Paid'),
            content: Text(
              isStaff
                  ? 'The client\'s payment has been released to the salon.'
                  : 'The client\'s payment has been released and your '
                      'earnings are in your wallet.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
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
        title: const Text('Declare a no-show?'),
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
            child: const Text('Declare no-show'),
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
    final booking = job.valueOrNull;
    final text = Theme.of(context).textTheme;
    final isSalon = ref.watch(isSalonProvider);
    final isStaff = ref.watch(isSalonStaffProvider);
    final status = booking?.status;
    final finished = status == BookingStatus.completed;
    // SOS belongs to a job that is still happening. On a closed one the
    // button would sit over the invoices and mean nothing.
    final live = status != null && status.isLive;

    return Scaffold(
      appBar: AppBar(
        title: Text(booking?.reference ?? 'Job'),
        actions: [
          if (booking != null)
            Padding(
              padding: const EdgeInsets.only(right: FreshlySpacing.md),
              child: Center(
                child: StatusPill(
                    label: booking.status.partnerLabel,
                    tone: booking.status.tone),
              ),
            ),
        ],
      ),
      body: job.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 72, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.md),
            Skeleton(height: 200, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.md),
            Skeleton(height: 54, radius: FreshlySpacing.buttonRadius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'This job did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(jobProvider(widget.bookingId)),
        ),
        data: (booking) => ListView(
          // Room at the bottom for the SOS button, so it never sits on top of
          // the last control on the page.
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.md, FreshlySpacing.sm, FreshlySpacing.md, 96),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, FreshlySpacing.md, 8, 12),
                child: _StatusStrip(status: booking.status),
              ),
            ),
            const SizedBox(height: FreshlySpacing.sm),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_headline(booking.status, isStaff: isStaff),
                        style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text(_hint(booking.status, isStaff: isStaff),
                        style: text.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    const Divider(height: FreshlySpacing.xl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const IconBadge(icon: FreshlyIcons.location, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Client', style: text.labelMedium),
                              const SizedBox(height: 2),
                              Text(booking.destinationAddress,
                                  style: text.titleMedium),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (booking.scheduledStart != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const IconBadge(
                              icon: FreshlyIcons.calendar,
                              tone: FreshlyTone.info,
                              size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Booked for', style: text.labelMedium),
                                const SizedBox(height: 2),
                                Text(formatSlot(booking.scheduledStart!),
                                    style: text.titleMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (isSalon || booking.assignedStaffName != null) ...[
                      const SizedBox(height: 12),
                      _AssignedRow(
                        booking: booking,
                        canChange: isSalon && canAssign(booking.status),
                        onChange: () async {
                          final changed = await showAssignSheet(context,
                              bookingId: widget.bookingId,
                              currentStaffId: booking.assignedStaffId);
                          if (changed) {
                            ref.invalidate(jobProvider(widget.bookingId));
                          }
                        },
                      ),
                    ],
                    const Divider(height: FreshlySpacing.xl),
                    Row(
                      children: [
                        Expanded(
                            child: Text('Job total',
                                style: text.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant))),
                        Text(booking.total.format(),
                            style: text.headlineMedium),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FreshlySpacing.sm),
            if (booking.status.isLive)
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      icon: FreshlyIcons.navigation,
                      label: 'Navigate',
                      onTap: () => _openNavigation(booking),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.sm),
                  Expanded(
                    child: _ActionTile(
                      icon: FreshlyIcons.chat,
                      label: 'Message',
                      onTap: () =>
                          context.push('/job/${widget.bookingId}/chat'),
                    ),
                  ),
                ],
              ),
            if (finished) ...[
              _RateCard(
                reviewed: booking.reviewedByMe,
                onRate: () => context.push('/job/${widget.bookingId}/rate'),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              InvoicesSection(bookingId: widget.bookingId, isStaff: isStaff),
            ],
            if (booking.status == BookingStatus.arrived) ...[
              const SizedBox(height: FreshlySpacing.md),
              _NoShowButton(
                arrivedAt: booking.arrivedAt,
                onPressed: _noShow,
              ),
            ],
            if (booking.status == BookingStatus.inProgress) ...[
              const SizedBox(height: FreshlySpacing.md),
              OutlinedButton.icon(
                onPressed: () => context.push('/job/${widget.bookingId}/addon'),
                icon: const Icon(FreshlyIcons.addCircle),
                label: const Text('Suggest an extra service'),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton:
          live ? SosButton(bookingId: widget.bookingId) : null,
      bottomNavigationBar: job.maybeWhen(
        data: (booking) {
          if (booking.status == BookingStatus.completed) {
            // Rating is the one thing left to do on a finished job; once it
            // is done the bar goes, so the invoices get the whole screen.
            if (booking.reviewedByMe) return const SizedBox.shrink();
            return StickyActionBar(
              child: FilledButton(
                onPressed: () => context.push('/job/${widget.bookingId}/rate'),
                child: const Text('Rate your client'),
              ),
            );
          }
          if (!booking.status.isLive) return const SizedBox.shrink();
          return StickyActionBar(
            child: _PrimaryAction(
              status: booking.status,
              busy: _busy,
              onEnRoute: () => _advance('en_route'),
              onArrived: () => _advance('arrived'),
              onEnterPin: () => context.push('/job/${widget.bookingId}/pin'),
              onComplete: _complete,
            ),
          );
        },
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }

  /// A staff member's pay comes from the salon, not from this app, so the
  /// money lines are reworded for them rather than hidden.
  static String _headline(BookingStatus status, {required bool isStaff}) =>
      switch (status) {
        BookingStatus.authorized => 'Booked and paid for',
        BookingStatus.accepted => 'Head to your client',
        BookingStatus.enRoute => 'On your way',
        BookingStatus.arrived => 'You are at the door',
        BookingStatus.inProgress => 'Working',
        BookingStatus.completed => isStaff ? 'Job done' : 'Paid',
        BookingStatus.cancelled => 'Cancelled',
        _ => 'Job closed',
      };

  static String _hint(BookingStatus status, {required bool isStaff}) =>
      switch (status) {
        BookingStatus.authorized =>
          'The client\'s payment is held. You will be offered this job '
              'when it is time to leave.',
        BookingStatus.accepted =>
          'Tap start driving when you leave so your client can follow you.',
        BookingStatus.enRoute =>
          'Slide when you are outside. Your client is told to open up.',
        BookingStatus.arrived =>
          'Ask your client for their 4-digit code to start the job.',
        BookingStatus.inProgress => isStaff
            ? 'When you are done, finish the job to release the client\'s '
                'payment to the salon.'
            : 'When you are done, finish the job to release your payment.',
        BookingStatus.completed => isStaff
            ? 'The client\'s payment has gone to the salon.'
            : 'The money for this job is in your wallet.',
        BookingStatus.cancelled => 'This booking was cancelled.',
        _ => 'Nothing more to do on this booking.',
      };
}

/// Who is doing a salon's job, with the one tap that changes it while the
/// job is still ahead of them.
class _AssignedRow extends StatelessWidget {
  const _AssignedRow(
      {required this.booking, required this.canChange, required this.onChange});
  final Booking booking;
  final bool canChange;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = booking.assignedStaffName;
    return Row(
      children: [
        const IconBadge(
            icon: FreshlyIcons.person, tone: FreshlyTone.dark, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Assigned to', style: text.labelMedium),
              const SizedBox(height: 4),
              name == null
                  ? Text('You', style: text.titleMedium)
                  : AssigneePill(name: name),
            ],
          ),
        ),
        if (canChange)
          TextButton(
            onPressed: onChange,
            child: Text(name == null ? 'Assign' : 'Change'),
          ),
      ],
    );
  }
}

/// The double-sided review, from the provider's side. Other pros see the
/// rating before they accept this client, which is the reason to ask.
class _RateCard extends StatelessWidget {
  const _RateCard({required this.reviewed, required this.onRate});
  final bool reviewed;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: reviewed ? null : onRate,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              IconBadge(
                  icon: FreshlyIcons.star,
                  tone: reviewed ? FreshlyTone.success : FreshlyTone.warning,
                  size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        reviewed ? 'You rated this client' : 'Rate your client',
                        style: text.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      reviewed
                          ? 'Thanks. It helps other pros decide.'
                          : 'Other pros see it before they accept them.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              reviewed
                  ? const StatusPill(
                      label: 'Rated',
                      icon: FreshlyIcons.check,
                      tone: FreshlyTone.success,
                      dense: true)
                  : Icon(FreshlyIcons.chevronRight,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
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
    final countdown =
        '${(_secondsRemaining / 60).floor()}:${(_secondsRemaining % 60).toString().padLeft(2, '0')}';

    return OutlinedButton.icon(
      onPressed: enabled ? widget.onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: FreshlyColors.crimson,
        side: BorderSide(
            color: enabled
                ? FreshlyColors.crimson
                : Theme.of(context).colorScheme.outline,
            width: 1.5),
      ),
      icon:
          Icon(enabled ? FreshlyIcons.block : FreshlyIcons.hourglass, size: 18),
      label: Text(enabled
          ? 'Client not here? Declare no-show'
          : 'No-show available in $countdown'),
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
      BookingStatus.authorized => ('Confirmed, offer to come', null),
      _ => ('Job closed', null),
    };

    // Arriving is the one step that starts a clock on the client's side, so
    // it is a slide rather than a tap.
    if (status == BookingStatus.enRoute) {
      return SlideToConfirm(
        label: label,
        busy: busy,
        onConfirmed: action,
      );
    }

    return FilledButton(
      onPressed: busy || action == null ? null : action,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: FreshlyColors.obsidian))
          : Text(label),
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final done = (i ~/ 2) < currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.only(top: 13),
              decoration: BoxDecoration(
                color: done ? FreshlyColors.mintDark : scheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final index = i ~/ 2;
        final done = index < currentIndex;
        final current = index == currentIndex;
        return SizedBox(
          width: 52,
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: done
                      ? FreshlyColors.obsidian
                      : current
                          ? FreshlyColors.mint
                          : scheme.surface,
                  border: Border.all(
                      color:
                          done || current ? Colors.transparent : scheme.outline,
                      width: 2),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(FreshlyIcons.check,
                        size: 14, color: FreshlyColors.mint)
                    : current
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: FreshlyColors.obsidian,
                                  shape: BoxShape.circle),
                            ),
                          )
                        : null,
              ),
              const SizedBox(height: 6),
              Text(
                _steps[index].$2,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: FreshlyType.style(
                  11,
                  weight: current ? FontWeight.w800 : FontWeight.w600,
                  color: current
                      ? scheme.onSurface
                      : done
                          ? FreshlyColors.mintDark
                          : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
