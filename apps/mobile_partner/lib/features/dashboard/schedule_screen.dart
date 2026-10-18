import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/job_tile.dart';

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);
    final recent = ref.watch(recentJobsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule'),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/availability'),
            icon: const Icon(FreshlyIcons.eventAvailable, size: 18),
            label: const Text('Availability'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(scheduleProvider);
          ref.invalidate(recentJobsProvider);
        },
        child: schedule.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            children: const [JobTileSkeleton(count: 4)],
          ),
          // Inside a ListView so pull-to-refresh still works on an error.
          error: (e, __) => ListView(
            children: [
              EmptyState(
                icon: FreshlyIcons.error,
                title: 'Your schedule did not load',
                message:
                    e is ApiException ? e.message : 'Pull down to try again.',
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(scheduleProvider),
              ),
            ],
          ),
          data: (jobs) {
            final recentJobs = recent.valueOrNull ?? const [];
            if (jobs.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(
                    FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.xl),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                  EmptyState(
                    icon: FreshlyIcons.calendar,
                    title: 'Nothing booked yet',
                    message: 'Scheduled jobs land here as clients book you. '
                        'Keep your hours up to date so they can.',
                    actionLabel: 'Set availability',
                    onAction: () => context.push('/availability'),
                  ),
                  if (recentJobs.isNotEmpty) _RecentSection(jobs: recentJobs),
                ],
              );
            }

            // Sort by start time, instant (null start) first.
            final sorted = List<Map<String, dynamic>>.from(jobs)
              ..sort((a, b) {
                final aStart = a['scheduledStart'] as DateTime?;
                final bStart = b['scheduledStart'] as DateTime?;
                if (aStart == null) return -1;
                if (bStart == null) return 1;
                return aStart.compareTo(bStart);
              });

            final instant =
                sorted.where((j) => j['scheduledStart'] == null).toList();
            final scheduled =
                sorted.where((j) => j['scheduledStart'] != null).toList();

            // Group scheduled by day
            final grouped = <String, List<Map<String, dynamic>>>{};
            for (final job in scheduled) {
              final date = (job['scheduledStart'] as DateTime).toLocal();
              final key =
                  DateTime(date.year, date.month, date.day).toIso8601String();
              grouped.putIfAbsent(key, () => []).add(job);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                  FreshlySpacing.sm, FreshlySpacing.md, FreshlySpacing.xl),
              children: [
                if (instant.isNotEmpty) ...[
                  const _DayHeader(label: 'Active now', live: true),
                  ...instant.map((j) => _ScheduleCard(job: j)),
                  const SizedBox(height: FreshlySpacing.md),
                ],
                ...grouped.entries.map((entry) {
                  final date = DateTime.parse(entry.key);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DayHeader(
                        label: formatSlot(date).split(', ').first,
                        detail: formatDate(date),
                        count: entry.value.length,
                      ),
                      ...entry.value.map((j) => _ScheduleCard(job: j)),
                      const SizedBox(height: FreshlySpacing.md),
                    ],
                  );
                }),
                if (recentJobs.isNotEmpty) _RecentSection(jobs: recentJobs),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(
      {required this.label, this.detail, this.count, this.live = false});
  final String label;
  final String? detail;
  final int? count;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // formatSlot names today and tomorrow; any other day it already returns
    // the date, so the detail would repeat it.
    final showDetail = detail != null && !label.contains(' ');
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(4, FreshlySpacing.sm, 4, FreshlySpacing.sm),
      child: Row(
        children: [
          if (live) ...[
            const OnlineDot(size: 10),
            const SizedBox(width: 8),
          ],
          Text(label, style: text.titleLarge),
          if (showDetail) ...[
            const SizedBox(width: 8),
            Text(detail!, style: text.bodySmall),
          ],
          const Spacer(),
          if (count != null)
            Text('$count job${count == 1 ? '' : 's'}', style: text.labelMedium),
        ],
      ),
    );
  }
}

/// Finished jobs, so a client can be rated and an invoice shared after the
/// fact. It trails the live schedule because it is never the first question.
class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.jobs});
  final List<Map<String, dynamic>> jobs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DayHeader(label: 'Recently done', count: jobs.length),
        ...jobs.map((j) => _ScheduleCard(job: j)),
      ],
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: JobTile(job: job),
    );
  }
}
