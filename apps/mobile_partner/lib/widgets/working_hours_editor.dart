import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../app/providers.dart';

final workingHoursProvider = FutureProvider.autoDispose<List<WorkingHours>>(
  (ref) => ref.watch(apiProvider).workingHours(),
);

/// The weekly hours a provider can be booked for a scheduled slot.
///
/// A day with no window is a day off; "Pick a time" on the client side only
/// offers times inside these windows. Instant bookings do not consult them,
/// so a provider who is online on a Sunday with no Sunday hours still gets
/// "as soon as possible" work.
class WorkingHoursEditor extends ConsumerStatefulWidget {
  const WorkingHoursEditor({super.key});

  @override
  ConsumerState<WorkingHoursEditor> createState() => _WorkingHoursEditorState();
}

class _WorkingHoursEditorState extends ConsumerState<WorkingHoursEditor> {
  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool _busy = false;

  Future<void> _save(List<WorkingHours> rules) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setWorkingHours(rules);
      ref.invalidate(workingHoursProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(List<WorkingHours> rules, int weekday) async {
    final current = rules.where((r) => r.weekday == weekday).firstOrNull;
    final start = await showTimePicker(
      context: context,
      initialTime: _parse(current?.startsAt ?? '08:00'),
      helpText: '${_days[weekday]}: start',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: _parse(current?.endsAt ?? '18:00'),
      helpText: '${_days[weekday]}: finish',
    );
    if (end == null || !mounted) return;
    if (end.hour * 60 + end.minute <= start.hour * 60 + start.minute) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Finish must be after start.')));
      return;
    }
    final next = [
      ...rules.where((r) => r.weekday != weekday),
      WorkingHours(
          weekday: weekday, startsAt: _format(start), endsAt: _format(end)),
    ];
    await _save(next);
  }

  Future<void> _toggle(List<WorkingHours> rules, int weekday, bool on) async {
    if (!on) {
      await _save(rules.where((r) => r.weekday != weekday).toList());
      return;
    }
    // Copy the most common window they already keep, so turning a day on
    // is one tap rather than two pickers.
    final template = rules.isEmpty
        ? const WorkingHours(weekday: 0, startsAt: '08:00', endsAt: '18:00')
        : rules.first;
    await _save([
      ...rules,
      WorkingHours(
          weekday: weekday,
          startsAt: template.startsAt,
          endsAt: template.endsAt),
    ]);
  }

  static TimeOfDay _parse(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hours = ref.watch(workingHoursProvider);
    return hours.when(
      loading: () => const Skeleton(height: 320, radius: FreshlySpacing.radius),
      error: (e, __) => EmptyState(
        compact: true,
        icon: FreshlyIcons.error,
        title: 'Hours did not load',
        message: e is ApiException ? e.message : 'Try again in a moment.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(workingHoursProvider),
      ),
      data: (rules) => GroupedList(
        title: 'Working hours',
        children: [
          // Monday first: a week that starts on Sunday reads wrong here.
          for (final weekday in const [1, 2, 3, 4, 5, 6, 0])
            _DayRow(
              label: _days[weekday],
              rule: rules.where((r) => r.weekday == weekday).firstOrNull,
              enabled: !_busy,
              onToggle: (on) => _toggle(rules, weekday, on),
              onEdit: () => _edit(rules, weekday),
            ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.label,
    required this.rule,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
  });

  final String label;
  final WorkingHours? rule;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final on = rule != null;
    return ListTile(
      enabled: enabled,
      onTap: on ? onEdit : () => onToggle(true),
      leading: SizedBox(
        width: 44,
        child: Text(label, style: Theme.of(context).textTheme.titleSmall),
      ),
      title: Text(on ? '${rule!.startsAt} – ${rule!.endsAt}' : 'Day off'),
      subtitle: on ? const Text('Tap to change') : null,
      trailing: Switch(
        value: on,
        onChanged: enabled ? onToggle : null,
      ),
    );
  }
}
