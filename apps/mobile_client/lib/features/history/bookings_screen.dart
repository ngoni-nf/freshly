import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../home/dashboard_screen.dart' show recentBookingsProvider;

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(recentBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: bookings.when(
        loading: () => ListView.separated(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          separatorBuilder: (_, __) =>
              const SizedBox(height: FreshlySpacing.sm),
          itemBuilder: (_, __) =>
              const Skeleton(height: 96, radius: FreshlySpacing.radius),
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Bookings did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(recentBookingsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.calendar,
              title: 'No bookings yet',
              message: 'Find a pro near you and your bookings will live here.',
              actionLabel: 'Find a pro',
              onAction: () => context.go('/home'),
            );
          }
          // Live first: the one thing somebody opening this tab during a
          // booking wants is the way back to the map.
          final live = list.where((b) => b.status.isLive).toList();
          final past = list.where((b) => !b.status.isLive).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(recentBookingsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                  FreshlySpacing.xs, FreshlySpacing.md, FreshlySpacing.xl),
              children: [
                if (live.isNotEmpty) ...[
                  const SectionHeader(
                      title: 'Happening now',
                      padding: EdgeInsets.only(bottom: 12)),
                  for (final b in live) _BookingCard(booking: b),
                  const SizedBox(height: FreshlySpacing.md),
                ],
                if (past.isNotEmpty) ...[
                  const SectionHeader(
                      title: 'Past', padding: EdgeInsets.only(bottom: 12)),
                  for (final b in past) _BookingCard(booking: b),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final text = Theme.of(context).textTheme;
    final name = b.providerName ?? 'Freshly booking';
    final when = b.scheduledStart ?? b.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: Card(
        child: InkWell(
          onTap: b.status.isLive
              ? () => context.push('/track/${b.id}')
              : b.providerId != null
                  ? () => context.push('/provider/${b.providerId}')
                  : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                FreshlyAvatar(name: name, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleMedium),
                          ),
                          Text(b.total.format(), style: text.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                          '${b.status.isLive ? formatSlot(when) : formatDate(when)} · ${b.reference}',
                          style: text.bodySmall),
                      const SizedBox(height: 8),
                      StatusPill(
                        label: b.status.clientLabel,
                        tone: toneForBooking(b.status),
                        icon: b.status.isLive ? FreshlyIcons.navigation : null,
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
