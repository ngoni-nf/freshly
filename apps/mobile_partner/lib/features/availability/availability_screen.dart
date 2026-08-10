import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final partnerGridProvider = FutureProvider.autoDispose<GridStatus>(
  (ref) => ref.watch(apiProvider).gridStatus('ZA'),
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

  Future<void> _block(DateTime start, DateTime end, String reason, String label) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).blockAvailability(start: start, end: end, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label blocked out')));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context, firstDate: now, lastDate: now.add(const Duration(days: 90)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final range = await showTimeRangePicker(context);
    if (range == null) return;

    final start = DateTime(date.year, date.month, date.day, range.$1.hour, range.$1.minute);
    final end = DateTime(date.year, date.month, date.day, range.$2.hour, range.$2.minute);
    await _block(start, end, 'manual', 'Time');
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(partnerGridProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: [
          grid.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (status) {
              if (!status.isActive || status.nextWindowStart == null) {
                return const Card(
                  child: ListTile(
                    leading: Icon(Icons.bolt, color: FreshlyColors.mint),
                    title: Text('Grid stable'),
                    subtitle: Text('No outage scheduled in your area right now.'),
                  ),
                );
              }
              final start = status.nextWindowStart!;
              final end = status.nextWindowEnd ?? start.add(const Duration(hours: 2));
              return Card(
                color: FreshlyColors.loadShedding.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt, color: FreshlyColors.loadShedding),
                          const SizedBox(width: 8),
                          Text(status.label,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Next outage: ${formatSlot(start)} – '
                        '${TimeOfDay.fromDateTime(end).format(context)}',
                        style: const TextStyle(color: FreshlyColors.inkMuted),
                      ),
                      const SizedBox(height: FreshlySpacing.md),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _block(start, end, 'load_shedding', 'Outage window'),
                        icon: const Icon(Icons.block),
                        label: const Text('Block out this window'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const Text('Block time off',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: FreshlySpacing.sm),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: const Text('Rest of today'),
                  onTap: _busy
                      ? null
                      : () {
                          final now = DateTime.now();
                          _block(now, DateTime(now.year, now.month, now.day, 23, 59),
                              'manual', 'Rest of today');
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.date_range_outlined),
                  title: const Text('Choose a date and time'),
                  onTap: _busy ? null : _pickCustom,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<(TimeOfDay, TimeOfDay)?> showTimeRangePicker(BuildContext context) async {
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
