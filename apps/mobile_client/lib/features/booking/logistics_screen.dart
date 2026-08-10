import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../discovery/feed_screen.dart' show currentPositionProvider;
import 'booking_draft.dart';

/// Screen A.9 — where and when.
class LogisticsScreen extends ConsumerStatefulWidget {
  const LogisticsScreen({required this.draft, super.key});
  final BookingDraft draft;

  @override
  ConsumerState<LogisticsScreen> createState() => _LogisticsScreenState();
}

class _LogisticsScreenState extends ConsumerState<LogisticsScreen> {
  final _notes = TextEditingController();
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _resolving = true);
    try {
      final position = await ref.read(currentPositionProvider.future);
      final places = await placemarkFromCoordinates(position.latitude, position.longitude);
      final p = places.firstOrNull;
      setState(() {
        widget.draft.destination = GeoPoint(position.latitude, position.longitude);
        widget.draft.destinationAddress = p == null
            ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'
            : [p.street, p.subLocality, p.locality].where((s) => s?.isNotEmpty ?? false).join(', ');
      });
    } catch (_) {
      // Falls through to manual entry rather than blocking the flow.
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _pickSlot() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
      initialDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      widget.draft.bookingType = 'scheduled';
      widget.draft.scheduledStart =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Scaffold(
      appBar: AppBar(title: const Text('Where and when')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'instant', label: Text('As soon as possible')),
              ButtonSegment(value: 'scheduled', label: Text('Pick a time')),
            ],
            selected: {draft.bookingType},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() => draft.bookingType = s.first);
              if (s.first == 'scheduled' && draft.scheduledStart == null) _pickSlot();
            },
          ),
          if (draft.bookingType == 'scheduled') ...[
            const SizedBox(height: FreshlySpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(draft.scheduledStart == null
                    ? 'Choose a date and time'
                    : formatSlot(draft.scheduledStart!)),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickSlot,
              ),
            ),
          ],
          const SizedBox(height: FreshlySpacing.lg),
          const Text('Address', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: FreshlySpacing.sm),
          Card(
            child: ListTile(
              leading: _resolving
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.location_on_outlined, color: FreshlyColors.mint),
              title: Text(draft.destinationAddress ?? 'Finding your location…'),
              subtitle: const Text('Your exact address is shared only after a pro accepts.'),
              trailing: TextButton(onPressed: _useCurrentLocation, child: const Text('Change')),
            ),
          ),
          const SizedBox(height: FreshlySpacing.md),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Access notes (optional)',
              hintText: 'Complex gate code, unit number, which door to use',
            ),
            onChanged: (v) => draft.destinationNotes = v,
          ),
          const SizedBox(height: FreshlySpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.providerName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: FreshlySpacing.sm),
                  ...draft.services.map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(child: Text(s.name)),
                            Text(s.price.format()),
                          ],
                        ),
                      )),
                  const Divider(height: FreshlySpacing.lg),
                  Text('About ${formatDuration(draft.durationMinutes)} in total',
                      style: const TextStyle(color: FreshlyColors.inkMuted)),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: FilledButton(
            onPressed: draft.isReadyForCheckout
                ? () => context.push('/book/checkout', extra: draft)
                : null,
            child: const Text('Review and pay'),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }
}
