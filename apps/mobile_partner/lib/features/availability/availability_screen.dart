import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../widgets/working_hours_editor.dart';

final partnerGridProvider = FutureProvider.autoDispose<GridStatus>(
  // The provider's own market: a Harare barber needs ZESA's schedule, not
  // Eskom's.
  (ref) => ref.watch(apiProvider).gridStatus(ref.watch(countryCodeProvider)),
);

/// Screen B.8 — availability, and the one-tap load-shedding blockout.
///
/// The blockout is the feature providers ask for by name. Without it they
/// either take a booking they cannot fulfil and eat the cancellation, or they
/// go offline entirely and lose the rest of the day's work. One tap that
/// removes exactly the outage window solves it.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});

  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  bool _busy = false;

  Future<void> _block(
      DateTime start, DateTime end, String reason, String label) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .blockAvailability(start: start, end: end, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label blocked out')));
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

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final range = await showTimeRangePicker(context);
    if (range == null) return;

    final start = DateTime(
        date.year, date.month, date.day, range.$1.hour, range.$1.minute);
    final end = DateTime(
        date.year, date.month, date.day, range.$2.hour, range.$2.minute);
    await _block(start, end, 'manual', 'Time');
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(partnerGridProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: [
          const ScreenIntro(
            title: 'When can you work?',
            subtitle: 'Block out time you cannot take jobs, so you never '
                'have to cancel on a client.',
          ),
          const SizedBox(height: FreshlySpacing.lg),
          grid.when(
            loading: () =>
                const Skeleton(height: 150, radius: FreshlySpacing.radius),
            error: (_, __) => const SizedBox.shrink(),
            data: (status) {
              if (!status.isActive || status.nextWindowStart == null) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FreshlySpacing.md),
                    child: Row(
                      children: [
                        const IconBadge(icon: FreshlyIcons.bolt),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Grid stable', style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                  'No outage scheduled in your area right now.',
                                  style: text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final start = status.nextWindowStart!;
              final end =
                  status.nextWindowEnd ?? start.add(const Duration(hours: 2));
              return Container(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                decoration: BoxDecoration(
                  color: FreshlyColors.loadSheddingSoft,
                  borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  border: Border.all(
                      color:
                          FreshlyColors.loadShedding.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const IconBadge(
                            icon: FreshlyIcons.bolt,
                            tone: FreshlyTone.warning,
                            size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('LOAD-SHEDDING',
                                  style: FreshlyType.style(11,
                                          weight: FontWeight.w800,
                                          color: FreshlyColors.loadSheddingInk)
                                      .copyWith(letterSpacing: 1.2)),
                              Text(status.label,
                                  style: text.titleLarge
                                      ?.copyWith(color: FreshlyColors.ink)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(FreshlySpacing.radiusSmall),
                      ),
                      child: Row(
                        children: [
                          const Icon(FreshlyIcons.clock,
                              size: 18, color: FreshlyColors.loadSheddingInk),
                          const SizedBox(width: 8),
                          Text('Next outage',
                              style: text.bodySmall
                                  ?.copyWith(color: FreshlyColors.inkSubtle)),
                          const Spacer(),
                          Text(
                            // Both ends in the same 24-hour clock; the
                            // locale's TimeOfDay format gave "18:00 – 8:00 PM".
                            '${formatSlot(start)} – '
                            '${formatSlot(end).split(', ').last}',
                            style: text.titleSmall
                                ?.copyWith(color: FreshlyColors.ink),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _block(
                              start, end, 'load_shedding', 'Outage window'),
                      icon: const Icon(FreshlyIcons.block, size: 20),
                      label: const Text('Block out this window'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const WorkingHoursEditor(),
          const SizedBox(height: FreshlySpacing.lg),
          GroupedList(
            title: 'Block time off',
            children: [
              ListTile(
                leading: const IconBadge(
                    icon: FreshlyIcons.calendarToday,
                    tone: FreshlyTone.neutral,
                    size: 40),
                title: const Text('Rest of today'),
                subtitle: const Text('Stop new bookings until midnight'),
                trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
                onTap: _busy
                    ? null
                    : () {
                        final now = DateTime.now();
                        _block(
                            now,
                            DateTime(now.year, now.month, now.day, 23, 59),
                            'manual',
                            'Rest of today');
                      },
              ),
              ListTile(
                leading: const IconBadge(
                    icon: FreshlyIcons.dateRange,
                    tone: FreshlyTone.neutral,
                    size: 40),
                title: const Text('Choose a date and time'),
                subtitle: const Text('Up to 90 days ahead'),
                trailing: const Icon(FreshlyIcons.chevronRight, size: 16),
                onTap: _busy ? null : _pickCustom,
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: FreshlySpacing.md),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

Future<(TimeOfDay, TimeOfDay)?> showTimeRangePicker(
    BuildContext context) async {
  final start = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Blocked from',
  );
  if (start == null || !context.mounted) return null;
  final end = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: (start.hour + 2) % 24, minute: start.minute),
    helpText: 'Blocked until',
  );
  if (end == null) return null;
  return (start, end);
}
