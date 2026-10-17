import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
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
      final places =
          await placemarkFromCoordinates(position.latitude, position.longitude);
      final p = places.firstOrNull;
      setState(() {
        widget.draft.destination =
            GeoPoint(position.latitude, position.longitude);
        widget.draft.destinationAddress = p == null
            ? '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}'
            : [p.street, p.subLocality, p.locality]
                .where((s) => s?.isNotEmpty ?? false)
                .join(', ');
      });
    } catch (_) {
      // Falls through to manual entry rather than blocking the flow.
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  /// Type an address, or reuse a saved one.
  ///
  /// "Change" used to re-run the GPS fix, which is only useful if the first
  /// one was wrong about where the phone is — and useless in the common case,
  /// which is booking somewhere the phone is not. Somebody arranging a cut for
  /// their mother has no way to say so by standing somewhere else.
  Future<void> _pickAddress() async {
    final current = widget.draft.destination;
    final picked = await AddressPickerSheet.show(
      context,
      api: ref.read(apiProvider),
      countryCode: ref.read(countryCodeProvider),
      nearLat: current?.lat,
      nearLng: current?.lng,
    );
    if (picked == null || !mounted) return;

    setState(() {
      widget.draft.destination = GeoPoint(picked.lat, picked.lng);
      widget.draft.destinationAddress = picked.formatted;
      // A saved address carries its own gate code; keep whatever the customer
      // has already typed here rather than overwriting it.
      if (picked.accessNotes != null &&
          picked.accessNotes!.isNotEmpty &&
          _notes.text.trim().isEmpty) {
        _notes.text = picked.accessNotes!;
        widget.draft.destinationNotes = picked.accessNotes;
      }
    });
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
    final time =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
    final text = Theme.of(context).textTheme;
    final scheduled = draft.bookingType == 'scheduled';

    return Scaffold(
      appBar: AppBar(title: const Text('Where and when')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.sm,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          Text('When', style: text.titleLarge),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ChoiceCard(
                  icon: FreshlyIcons.bolt,
                  title: 'As soon as possible',
                  subtitle: 'First available pro',
                  selected: !scheduled,
                  onTap: () => setState(() => draft.bookingType = 'instant'),
                ),
              ),
              const SizedBox(width: FreshlySpacing.sm),
              Expanded(
                child: _ChoiceCard(
                  icon: FreshlyIcons.calendar,
                  title: 'Pick a time',
                  subtitle: scheduled && draft.scheduledStart != null
                      ? formatSlot(draft.scheduledStart!)
                      : 'Up to 60 days ahead',
                  selected: scheduled,
                  onTap: () {
                    setState(() => draft.bookingType = 'scheduled');
                    _pickSlot();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          Text('Where', style: text.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: InkWell(
              onTap: _pickAddress,
              child: Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: Row(
                  children: [
                    _resolving
                        ? const SizedBox(
                            width: 44,
                            height: 44,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ))
                        : const IconBadge(icon: FreshlyIcons.location),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              draft.destinationAddress ??
                                  (_resolving
                                      ? 'Finding your location…'
                                      : 'Add an address'),
                              style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text('Shared with your pro only after they accept.',
                              style: text.bodySmall),
                        ],
                      ),
                    ),
                    TextButton(
                        onPressed: _pickAddress, child: const Text('Change')),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              hintText: 'Access notes: gate code, unit number, which door',
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 22),
                child: Icon(FreshlyIcons.info),
              ),
            ),
            onChanged: (v) => draft.destinationNotes = v,
          ),
          const SizedBox(height: FreshlySpacing.lg),
          Text('Your booking', style: text.titleLarge),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FreshlyAvatar(name: draft.providerName, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(draft.providerName,
                              style: text.titleMedium)),
                      StatusPill(
                          label: formatDuration(draft.durationMinutes),
                          icon: FreshlyIcons.clock,
                          dense: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  for (final s in draft.services)
                    LineItem(label: s.name, value: s.price.format()),
                  const SizedBox(height: 4),
                  Text('Travel and fees are added on the next screen.',
                      style: text.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          onPressed: draft.isReadyForCheckout
              ? () => context.push('/book/checkout', extra: draft)
              : null,
          child: const Text('Review and pay'),
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

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edge = isDark ? FreshlyColors.mint : FreshlyColors.obsidian;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: selected ? edge : scheme.outline, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FreshlySpacing.radius)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(
                    icon: icon,
                    size: 40,
                    tone: selected ? FreshlyTone.dark : FreshlyTone.neutral),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
