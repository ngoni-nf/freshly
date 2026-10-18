import 'dart:async';

import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import 'category_icon.dart';

/// Everything a provider tells us about their business, as the form holds it
/// while they are still typing. Shared by sign-up and by editing later, so a
/// field cannot be validated one way on the first day and another way after.
class BusinessDraft {
  BusinessDraft({
    this.name = '',
    this.businessMode = 'solo',
    Set<ServiceCategory>? categories,
    this.venue = VenueMode.mobile,
    this.shopAddress = '',
    this.lat,
    this.lng,
    this.baseLabel,
    this.travelRadiusKm = 10,
    Set<PowerBackup>? powerBackup,
    this.bio = '',
    this.acceptsInstant = true,
    this.acceptsScheduled = true,
  })  : categories = categories ?? {},
        powerBackup = powerBackup ?? {};

  factory BusinessDraft.fromBusiness(ProviderBusiness b) => BusinessDraft(
        name: b.displayName,
        businessMode: b.businessMode,
        categories: b.categories.toSet(),
        venue: VenueMode.fromWire(b.venueMode),
        shopAddress: b.shopAddress ?? '',
        lat: b.baseLocation?.lat,
        lng: b.baseLocation?.lng,
        baseLabel: b.baseLocation == null
            ? null
            : (b.shopAddress?.isNotEmpty ?? false)
                ? b.shopAddress
                : (b.serviceAreaName ?? 'Saved location'),
        travelRadiusKm: b.travelRadiusKm,
        powerBackup: b.powerBackup.toSet(),
        bio: b.bio ?? '',
        acceptsInstant: b.acceptsInstant,
        acceptsScheduled: b.acceptsScheduled,
      );

  String name;
  String businessMode;
  Set<ServiceCategory> categories;
  VenueMode venue;
  String shopAddress;
  double? lat;
  double? lng;

  /// What to show for the base: the picked address or "your location".
  String? baseLabel;
  double travelRadiusKm;
  Set<PowerBackup> powerBackup;
  String bio;
  bool acceptsInstant;
  bool acceptsScheduled;

  bool get travels => venue != VenueMode.inShop;
  bool get hasShop => venue != VenueMode.mobile;
  bool get hasBase => lat != null && lng != null;

  /// The first thing stopping this from being submitted, in the order the
  /// form asks for it, or null when it is complete.
  String? get problem {
    if (name.trim().length < 2) return 'Give your business a name.';
    if (categories.isEmpty) return 'Pick at least one thing you do.';
    if (hasShop && shopAddress.trim().isEmpty) {
      return 'Add the address clients should come to.';
    }
    if (!hasBase) return 'Set where you are based so we can find you work.';
    return null;
  }

  ProviderSignUp toSignUp() => ProviderSignUp(
        displayName: name.trim(),
        businessMode: businessMode,
        categories: categories.toList(),
        venueMode: venue.wire,
        lat: lat!,
        lng: lng!,
        shopAddress: hasShop ? shopAddress.trim() : null,
        travelRadiusKm: travels ? travelRadiusKm : null,
        powerBackup: powerBackup.toList(),
        bio: bio.trim().isEmpty ? null : bio.trim(),
      );

  /// Only what differs from [original], so a PATCH never overwrites a field
  /// the provider did not touch.
  Map<String, dynamic> changesFrom(ProviderBusiness original) {
    final changes = <String, dynamic>{};
    if (name.trim() != original.displayName) {
      changes['displayName'] = name.trim();
    }
    if (bio.trim() != (original.bio ?? '')) changes['bio'] = bio.trim();
    final wireCats = categories.map((c) => c.wire).toList()..sort();
    final origCats = original.categories.map((c) => c.wire).toList()..sort();
    if (wireCats.join(',') != origCats.join(',')) {
      changes['categories'] = wireCats;
    }
    if (venue.wire != original.venueMode) changes['venueMode'] = venue.wire;
    final wirePower = powerBackup.map((p) => p.wire).toList()..sort();
    final origPower = original.powerBackup.map((p) => p.wire).toList()..sort();
    if (wirePower.join(',') != origPower.join(',')) {
      changes['powerBackup'] = wirePower;
    }
    final shop = hasShop ? shopAddress.trim() : '';
    if (shop != (original.shopAddress ?? '')) changes['shopAddress'] = shop;
    if (travels && travelRadiusKm != original.travelRadiusKm) {
      changes['travelRadiusKm'] = travelRadiusKm;
    }
    if (acceptsInstant != original.acceptsInstant) {
      changes['acceptsInstant'] = acceptsInstant;
    }
    if (acceptsScheduled != original.acceptsScheduled) {
      changes['acceptsScheduled'] = acceptsScheduled;
    }
    if (hasBase &&
        (lat != original.baseLocation?.lat ||
            lng != original.baseLocation?.lng)) {
      changes['lat'] = lat;
      changes['lng'] = lng;
    }
    return changes;
  }
}

/// The business form itself. It owns its text controllers and reports every
/// change through [onChanged], so the screen around it decides what the
/// button at the bottom does with the result.
class BusinessForm extends StatefulWidget {
  const BusinessForm({
    required this.draft,
    required this.onChanged,
    required this.api,
    required this.countryCode,
    this.numbered = false,
    this.showBookingTypes = false,
    super.key,
  });

  final BusinessDraft draft;
  final VoidCallback onChanged;
  final FreshlyApi api;
  final String countryCode;

  /// Number the sections, as sign-up does; editing does not need a count.
  final bool numbered;

  /// "Instant" and "scheduled" toggles exist only once the business does.
  final bool showBookingTypes;

  @override
  State<BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<BusinessForm> {
  late final _name = TextEditingController(text: widget.draft.name);
  late final _shop = TextEditingController(text: widget.draft.shopAddress);
  late final _bio = TextEditingController(text: widget.draft.bio);
  bool _locating = false;
  String? _locationError;

  @override
  void dispose() {
    _name.dispose();
    _shop.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _update(void Function() change) {
    setState(change);
    widget.onChanged();
  }

  Future<void> _searchAddress() async {
    final picked = await AddressPickerSheet.show(
      context,
      api: widget.api,
      countryCode: widget.countryCode,
      nearLat: widget.draft.lat,
      nearLng: widget.draft.lng,
    );
    if (picked == null) return;
    _update(() {
      widget.draft
        ..lat = picked.lat
        ..lng = picked.lng
        ..baseLabel = picked.formatted;
      _locationError = null;
      // A shop with no address typed yet is almost always at the base just
      // picked; filling it in saves typing the same thing twice.
      if (widget.draft.hasShop && _shop.text.trim().isEmpty) {
        _shop.text = picked.formatted;
        widget.draft.shopAddress = picked.formatted;
      }
    });
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationRefused();
      }
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (_) {
        // Indoors with a cold GPS the fix can take longer than anyone waits;
        // the last known point is close enough to place a business.
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) throw const _LocationRefused();
      if (!mounted) return;
      _update(() {
        widget.draft
          ..lat = position!.latitude
          ..lng = position.longitude
          ..baseLabel = 'Where you are now';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _locationError =
            'Could not get your location. Search for your address instead.');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    var step = 0;
    Widget heading(String label, {String? hint}) {
      step += 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.numbered) ...[
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: FreshlyColors.obsidian,
                      shape: BoxShape.circle,
                    ),
                    child: Text('$step',
                        style: FreshlyType.style(13,
                            weight: FontWeight.w800,
                            color: FreshlyColors.mint)),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(label, style: text.titleMedium),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: text.bodySmall),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('Your business'),
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Business name',
            helperText: 'What clients will see',
          ),
          onChanged: (v) => _update(() => draft.name = v),
        ),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'solo',
                label: Text('Just me'),
                icon: Icon(FreshlyIcons.person, size: 18)),
            ButtonSegment(
                value: 'salon',
                label: Text('A salon or shop'),
                icon: Icon(FreshlyIcons.storefront, size: 18)),
          ],
          selected: {draft.businessMode},
          onSelectionChanged: (s) =>
              _update(() => draft.businessMode = s.first),
        ),
        const SizedBox(height: FreshlySpacing.lg),
        heading('What do you do?', hint: 'Choose everything that applies.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in ServiceCategory.values)
              SelectChip(
                label: c.label,
                icon: categoryIcon(c),
                selected: draft.categories.contains(c),
                onTap: () => _update(() => draft.categories.contains(c)
                    ? draft.categories.remove(c)
                    : draft.categories.add(c)),
              ),
          ],
        ),
        const SizedBox(height: FreshlySpacing.lg),
        heading('Where do you work?'),
        for (final (mode, title, subtitle, icon) in const [
          (
            VenueMode.mobile,
            'I come to clients',
            'You travel to their home or office',
            FreshlyIcons.car
          ),
          (
            VenueMode.inShop,
            'Clients come to me',
            'You work from a shop or a room at home',
            FreshlyIcons.storefront
          ),
          (
            VenueMode.both,
            'Both',
            'Whatever the client prefers',
            FreshlyIcons.nearMe
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChoiceCard(
              icon: icon,
              title: title,
              subtitle: subtitle,
              selected: draft.venue == mode,
              onTap: () => _update(() => draft.venue = mode),
            ),
          ),
        if (draft.hasShop) ...[
          const SizedBox(height: 4),
          TextFormField(
            controller: _shop,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Shop address',
              helperText: 'Street and suburb, so clients can find you',
            ),
            onChanged: (v) => _update(() => draft.shopAddress = v),
          ),
        ],
        const SizedBox(height: FreshlySpacing.lg),
        heading('Where are you based?',
            hint: draft.travels
                ? 'We offer you jobs near here.'
                : 'We show you to clients near here.'),
        BaseLocationCard(
          label: draft.baseLabel,
          locating: _locating,
          error: _locationError,
          onSearch: _searchAddress,
          onUseLocation: _locating ? null : _useMyLocation,
        ),
        if (draft.travels) ...[
          const SizedBox(height: FreshlySpacing.lg),
          heading('How far will you travel?'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Up to',
                            style: text.bodyMedium?.copyWith(color: muted)),
                      ),
                      Text('${draft.travelRadiusKm.round()} km',
                          style: text.titleLarge),
                    ],
                  ),
                  Slider(
                    value: draft.travelRadiusKm.clamp(1, 30).toDouble(),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '${draft.travelRadiusKm.round()} km',
                    onChanged: (v) =>
                        _update(() => draft.travelRadiusKm = v.roundToDouble()),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: FreshlySpacing.lg),
        heading('Backup power',
            hint: 'Clients can filter for pros who keep working when the '
                'grid is off.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in PowerBackup.values)
              SelectChip(
                label: p.label,
                icon: FreshlyIcons.bolt,
                selected: draft.powerBackup.contains(p),
                onTap: () => _update(() => draft.powerBackup.contains(p)
                    ? draft.powerBackup.remove(p)
                    : draft.powerBackup.add(p)),
              ),
          ],
        ),
        if (widget.showBookingTypes) ...[
          const SizedBox(height: FreshlySpacing.lg),
          heading('Bookings you take'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: draft.acceptsInstant,
                  title: const Text('Right now'),
                  subtitle: const Text('Offers while you are online'),
                  onChanged: (v) => _update(() => draft.acceptsInstant = v),
                ),
                Divider(
                    height: 1,
                    indent: 16,
                    color: Theme.of(context).colorScheme.outline),
                SwitchListTile(
                  value: draft.acceptsScheduled,
                  title: const Text('Booked ahead'),
                  subtitle: const Text('Appointments in your working hours'),
                  onChanged: (v) => _update(() => draft.acceptsScheduled = v),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: FreshlySpacing.lg),
        heading('About you',
            hint: 'Optional. A line or two on your clients\' '
                'profile view.'),
        TextFormField(
          controller: _bio,
          minLines: 3,
          maxLines: 5,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Ten years behind the chair, fades and beards a '
                'speciality.',
          ),
          onChanged: (v) => _update(() => draft.bio = v),
        ),
      ],
    );
  }
}

class _LocationRefused implements Exception {
  const _LocationRefused();
}

/// A pill that toggles, for picking several of something.
class SelectChip extends StatelessWidget {
  const SelectChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = selected ? FreshlyColors.obsidian : scheme.surface;
    final ink = selected ? Colors.white : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: fill,
        shape: StadiumBorder(
            side: BorderSide(
                color: selected ? Colors.transparent : scheme.outline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 15,
                      color: selected
                          ? FreshlyColors.mint
                          : scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
                Text(label,
                    style: FreshlyType.style(13,
                        weight: FontWeight.w700, color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a few mutually exclusive options, laid out as a row with a check.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: selected ? FreshlyColors.mintDark : scheme.outline,
              width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconBadge(
                    icon: icon,
                    size: 40,
                    tone: selected ? FreshlyTone.brand : FreshlyTone.neutral),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? FreshlyIcons.checkCircle : FreshlyIcons.addCircle,
                  size: 22,
                  color: selected ? FreshlyColors.mintDark : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The base location: what is set, and the two ways to set it.
class BaseLocationCard extends StatelessWidget {
  const BaseLocationCard({
    required this.label,
    required this.locating,
    required this.error,
    required this.onSearch,
    required this.onUseLocation,
    super.key,
  });

  final String? label;
  final bool locating;
  final String? error;
  final VoidCallback onSearch;
  final VoidCallback? onUseLocation;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final set = label != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconBadge(
                    icon: FreshlyIcons.location,
                    size: 40,
                    tone: set ? FreshlyTone.brand : FreshlyTone.neutral),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(set ? 'Your base' : 'Not set yet',
                          style: text.labelMedium),
                      const SizedBox(height: 2),
                      Text(
                        set ? label! : 'Search your address or use your phone',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                            color: set
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!,
                  style:
                      text.bodySmall?.copyWith(color: FreshlyColors.crimson)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                    onPressed: onSearch,
                    icon: const Icon(FreshlyIcons.search, size: 18),
                    label: Text(set ? 'Change' : 'Search'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 48)),
                    onPressed: onUseLocation,
                    icon: locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: FreshlyColors.mint))
                        : const Icon(FreshlyIcons.nearMe, size: 18),
                    label: const Text('Use my location'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The red box a form shows when the server, or the form itself, has
/// something to say about the submission.
class InlineError extends StatelessWidget {
  const InlineError({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FreshlyColors.crimsonSoft,
        borderRadius: BorderRadius.circular(FreshlySpacing.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(FreshlyIcons.error, size: 18, color: Color(0xFFB4232A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style:
                    text.bodyMedium?.copyWith(color: const Color(0xFFB4232A))),
          ),
        ],
      ),
    );
  }
}
