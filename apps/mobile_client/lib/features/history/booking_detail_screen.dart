import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../discovery/provider_screen.dart' show providerProfileProvider;
import '../home/dashboard_screen.dart' show recentBookingsProvider;
import '../support/support_screen.dart';
import '../tracking/pin_screen.dart' show completionPinProvider;
import 'invoices.dart';

final bookingDetailProvider =
    FutureProvider.autoDispose.family<Booking, String>(
  (ref, id) => ref.watch(apiProvider).booking(id),
);

/// One booking, past or present: who, what, when, where, what it cost, and
/// the things you can still do about it (track it, rate it, share the
/// invoice, ask for help).
class BookingDetailScreen extends ConsumerWidget {
  const BookingDetailScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingDetailProvider(bookingId));

    return Scaffold(
      appBar: AppBar(
        title: Text(booking.valueOrNull?.reference ?? 'Booking'),
      ),
      body: booking.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 88, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.md),
            Skeleton(height: 220, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'This booking did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(bookingDetailProvider(bookingId)),
        ),
        data: (b) => _Detail(booking: b),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = booking;
    final text = Theme.of(context).textTheme;
    final name = b.providerName ?? 'Freshly booking';
    final when = b.scheduledStart ?? b.createdAt;
    final completed = b.status == BookingStatus.completed;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bookingDetailProvider(b.id));
        ref.invalidate(invoicesProvider(b.id));
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.xs,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Row(
                children: [
                  FreshlyAvatar(name: name, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium),
                        const SizedBox(height: 6),
                        StatusPill(
                          label: b.status.clientLabel,
                          tone: toneForBooking(b.status),
                          icon:
                              b.status.isLive ? FreshlyIcons.navigation : null,
                          dense: true,
                        ),
                      ],
                    ),
                  ),
                  if (completed && b.reviewedByMe)
                    const StatusPill(
                        label: 'Rated',
                        icon: FreshlyIcons.star,
                        tone: FreshlyTone.success,
                        dense: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: FreshlySpacing.md),
          if (b.status.isLive) ...[
            FilledButton.icon(
              onPressed: () => context.push('/track/${b.id}'),
              icon: const Icon(FreshlyIcons.navigation),
              label: const Text('Track your pro'),
            ),
            const SizedBox(height: FreshlySpacing.md),
            _PinCard(bookingId: b.id),
            const SizedBox(height: FreshlySpacing.md),
          ],
          if (completed && !b.reviewedByMe) ...[
            FilledButton.icon(
              onPressed: () => context.push('/bookings/${b.id}/review'),
              icon: const Icon(FreshlyIcons.star),
              label: Text('Rate ${b.providerName ?? 'your pro'}'),
            ),
            const SizedBox(height: FreshlySpacing.md),
          ],
          const SectionHeader(
              title: 'Details', padding: EdgeInsets.only(bottom: 12)),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: FreshlySpacing.md, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ServicesLine(booking: b),
                  _Fact(
                      label: 'When',
                      value: b.status.isLive
                          ? formatSlot(when)
                          : formatDate(when)),
                  if (b.destinationAddress.isNotEmpty)
                    _Fact(label: 'Where', value: b.destinationAddress),
                  if (b.assignedStaffName != null)
                    _Fact(label: 'Your pro', value: b.assignedStaffName!),
                ],
              ),
            ),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const SectionHeader(
              title: 'Payment', padding: EdgeInsets.only(bottom: 12)),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: FreshlySpacing.md, vertical: 10),
              child: Column(
                children: [
                  // Each line is the server's own figure. Nothing here is
                  // added up on the phone: the total is the total the client
                  // agreed to, and the lines are how the server explains it.
                  for (final line in b.breakdown)
                    LineItem(
                      label: line.label,
                      value: formatMinor(line.amountMinor, b.total.currency),
                      muted: line.kind == 'discount',
                    ),
                  if (b.breakdown.isNotEmpty)
                    Divider(color: Theme.of(context).colorScheme.outline),
                  LineItem(
                      label: 'Total', value: b.total.format(), emphasis: true),
                ],
              ),
            ),
          ),
          if (completed) ...[
            const SizedBox(height: FreshlySpacing.lg),
            const SectionHeader(
                title: 'Invoice', padding: EdgeInsets.only(bottom: 12)),
            InvoiceList(bookingId: b.id),
          ],
          const SizedBox(height: FreshlySpacing.lg),
          if (b.providerId != null && !b.status.isLive)
            OutlinedButton.icon(
              onPressed: () => context.push('/provider/${b.providerId}'),
              icon: const Icon(FreshlyIcons.calendar, size: 18),
              label: const Text('Book again'),
            ),
          const SizedBox(height: FreshlySpacing.sm),
          TextButton.icon(
            style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () async {
              final sent = await NewTicketSheet.show(context, booking: b);
              if (sent && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Sent. Replies arrive under Help and support.')));
              }
            },
            icon: const Icon(FreshlyIcons.warning, size: 18),
            label: const Text('Get help with this booking'),
          ),
        ],
      ),
    );
  }
}

/// The client's four-digit code, on the booking as well as on the tracking
/// screen: a client who opens the app at the door from the Bookings tab must
/// not have to find the map first.
class _PinCard extends ConsumerWidget {
  const _PinCard({required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin = ref.watch(completionPinProvider(bookingId));
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(FreshlySpacing.md),
      decoration: BoxDecoration(
        color: FreshlyColors.obsidian,
        borderRadius: BorderRadius.circular(FreshlySpacing.radiusLarge),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your code',
                    style: text.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                    'Give it to your pro at the door. It starts the job; '
                    'payment is only taken when the job is done.',
                    style: text.bodySmall
                        ?.copyWith(color: FreshlyColors.inkMuted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          pin.when(
            loading: () => const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: FreshlyColors.mint)),
            error: (_, __) => TextButton(
              style: TextButton.styleFrom(foregroundColor: FreshlyColors.mint),
              onPressed: () => ref.invalidate(completionPinProvider(bookingId)),
              child: const Text('Retry'),
            ),
            data: (code) => Semantics(
              label: 'Completion code ${code.split('').join(' ')}',
              child: ExcludeSemantics(
                child: Text(code.split('').join(' '),
                    style: FreshlyType.style(26,
                            weight: FontWeight.w800, color: FreshlyColors.mint)
                        .copyWith(fontFeatures: const [
                      FontFeature.tabularFigures()
                    ])),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bookings carry service ids, not names; the names live on the provider's
/// menu. Resolved from there when it loads, with a plain count until then.
class _ServicesLine extends ConsumerWidget {
  const _ServicesLine({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = booking.serviceIds;
    final count = '${ids.length} ${ids.length == 1 ? 'service' : 'services'}';
    final providerId = booking.providerId;
    if (providerId == null || ids.isEmpty) {
      return _Fact(label: 'Services', value: count);
    }
    final profile = ref.watch(providerProfileProvider(providerId));
    final names = profile.valueOrNull == null
        ? null
        : (profile.valueOrNull!['services'] as List? ?? [])
            .map((s) => ServiceItem.fromJson(s as Map<String, dynamic>))
            .where((s) => ids.contains(s.id))
            .map((s) => s.name)
            .toList();
    final value = names == null || names.isEmpty ? count : names.join(', ');
    return _Fact(label: 'Services', value: value);
  }
}

/// A label over a value that may run to several lines (an address, a list of
/// services), where a single-line receipt row would overflow.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall),
          const SizedBox(height: 2),
          Text(value,
              style: FreshlyType.style(15,
                  weight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

/// Keeps the Bookings tab honest after a change made from this screen.
void refreshBookingLists(WidgetRef ref, String bookingId) {
  ref.invalidate(recentBookingsProvider);
  ref.invalidate(bookingDetailProvider(bookingId));
}
