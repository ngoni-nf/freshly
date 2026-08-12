import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Schedule'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(scheduleProvider),
        child: schedule.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => Center(
            child: Text(e is ApiException ? e.message : 'Could not load your schedule'),
          ),
          data: (jobs) {
            if (jobs.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  const Icon(FreshlyIcons.calendar, size: 48, color: FreshlyColors.inkMuted),
                  const SizedBox(height: FreshlySpacing.md),
                  const Text(
                    'No jobs scheduled for today.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: FreshlyColors.inkMuted),
                  ),
                ],
              );
            }

            final instant = jobs.where((j) => j['scheduledStart'] == null).toList();
            final scheduled = jobs.where((j) => j['scheduledStart'] != null).toList();

            return ListView(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              children: [
                if (instant.isNotEmpty) ...[
                  const Text('Active Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: FreshlySpacing.sm),
                  ...instant.map((j) => _ScheduleCard(job: j)),
                  const SizedBox(height: FreshlySpacing.lg),
                ],
                if (scheduled.isNotEmpty) ...[
                  const Text('Upcoming', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: FreshlySpacing.sm),
                  ...scheduled.map((j) => _ScheduleCard(job: j)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as BookingStatus;
    final money = job['total'] as Money;
    final start = job['scheduledStart'] as DateTime?;

    return Card(
      margin: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: start == null ? FreshlyColors.mintSoft : FreshlyColors.line.withValues(alpha: 0.3),
          child: Text(
            start != null ? formatSlot(start).split(', ').last : 'Now',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: start == null ? FreshlyColors.mintDark : FreshlyColors.inkMuted,
            ),
          ),
        ),
        title: Text(job['address'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${job['reference']} · ${status.clientLabel}'),
        trailing: Text(money.format(compact: true), style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => context.push('/job/${job['id']}'),
      ),
    );
  }
}
