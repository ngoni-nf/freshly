import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import 'job_status.dart';

/// One job in a list: when, where, what state, what it pays.
///
/// Shared by the dashboard and the schedule so the same booking looks the
/// same in both places. The time block leads because "when do I have to be
/// there" is the first question; the money trails because it is the second.
class JobTile extends StatelessWidget {
  const JobTile({required this.job, super.key});

  /// The row shape `scheduleProvider` produces.
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as BookingStatus;
    final money = job['total'] as Money;
    final start = job['scheduledStart'] as DateTime?;
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: () => context.push('/job/${job['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _TimeBlock(start: start),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job['address'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        StatusPill(
                            label: status.partnerLabel,
                            tone: status.tone,
                            dense: true),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(job['reference'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(money.format(compact: true), style: text.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.start});
  final DateTime? start;

  @override
  Widget build(BuildContext context) {
    // An instant job is happening now: it gets the brand fill so it stands
    // apart from the diary entries around it.
    if (start == null) {
      return Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FreshlyColors.mint,
          borderRadius: BorderRadius.circular(FreshlySpacing.radiusSmall),
        ),
        child: Text('Now',
            style: FreshlyType.style(15,
                weight: FontWeight.w800, color: FreshlyColors.obsidian)),
      );
    }

    final slot = formatSlot(start!);
    final parts = slot.split(', ');
    final time = parts.last;
    final day = parts.length > 1 ? parts.first.split(' ').first : '';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(FreshlySpacing.radiusSmall),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(time,
              style: FreshlyType.style(15,
                  weight: FontWeight.w800, color: scheme.onSurface)),
          if (day.isNotEmpty)
            Text(day,
                style: FreshlyType.style(11,
                    weight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// The loading shape of a list of [JobTile]s.
class JobTileSkeleton extends StatelessWidget {
  const JobTileSkeleton({this.count = 2, super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          const Padding(
            padding: EdgeInsets.only(bottom: FreshlySpacing.sm),
            child: Skeleton(height: 80, radius: FreshlySpacing.radius),
          ),
      ],
    );
  }
}
