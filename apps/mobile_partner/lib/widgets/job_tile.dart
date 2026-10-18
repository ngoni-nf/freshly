import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import 'assign_sheet.dart';
import 'job_status.dart';

/// One job in a list: when, where, what state, what it pays.
///
/// Shared by the dashboard and the schedule so the same booking looks the
/// same in both places. The time block leads because "when do I have to be
/// there" is the first question; the money trails because it is the second.
///
/// For a salon the tile grows a second line saying who is doing the job, with
/// the one tap that changes it. A solo provider never sees that line.
class JobTile extends ConsumerWidget {
  const JobTile({required this.job, super.key});

  /// The row shape `scheduleProvider` produces.
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = job['status'] as BookingStatus;
    final money = job['total'] as Money;
    final start = job['scheduledStart'] as DateTime?;
    final staffId = job['assignedStaffId'] as String?;
    final staffName = job['assignedStaffName'] as String?;
    final reviewed = job['reviewedByMe'] as bool? ?? false;
    final done = status == BookingStatus.completed;
    final isSalon = ref.watch(isSalonProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: () => context.push('/job/${job['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  // A finished job is dated by when it ended, not by the
                  // slot it was booked for; an instant one never had a slot.
                  _TimeBlock(
                      start: done
                          ? (job['completedAt'] as DateTime? ?? start)
                          : start,
                      done: done),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money.format(compact: true),
                          style: text.titleMedium),
                      // A finished job's one open question is whether the
                      // client has been rated; the pill answers it without
                      // opening the job.
                      if (done) ...[
                        const SizedBox(height: 4),
                        StatusPill(
                            label: reviewed ? 'Rated' : 'Rate client',
                            tone: reviewed
                                ? FreshlyTone.success
                                : FreshlyTone.warning,
                            dense: true),
                      ],
                    ],
                  ),
                ],
              ),
              if (isSalon && !done) ...[
                Divider(height: 20, color: scheme.outline),
                Row(
                  children: [
                    Icon(FreshlyIcons.person,
                        size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: staffName == null
                          ? Text('You are doing this one',
                              style: text.bodySmall)
                          : AssigneePill(name: staffName),
                    ),
                    if (canAssign(status))
                      TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        onPressed: () => showAssignSheet(context,
                            bookingId: job['id'] as String,
                            currentStaffId: staffId),
                        child:
                            Text(staffName == null ? 'Assign to…' : 'Change'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Who a salon job has been handed to.
class AssigneePill extends StatelessWidget {
  const AssigneePill({required this.name, super.key});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusPill(
          label: name,
          icon: FreshlyIcons.person,
          tone: FreshlyTone.brand,
          dense: true),
    );
  }
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({required this.start, this.done = false});
  final DateTime? start;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A finished job with no known end (older rows) is simply "Done": the
    // mint "Now" block would say it is still happening.
    if (done && start == null) {
      return Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(FreshlySpacing.radiusSmall),
        ),
        child: const Icon(FreshlyIcons.checkCircle,
            size: 22, color: FreshlyColors.mintDark),
      );
    }

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
