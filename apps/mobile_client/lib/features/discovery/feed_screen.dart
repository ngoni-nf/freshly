import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../app/env.dart';
import '../../app/providers.dart';
import '../../widgets/provider_card.dart';

class DiscoveryFilters {
  const DiscoveryFilters({
    this.category,
    this.serviceId,
    this.venue = 'mobile',
    this.radiusKm = 10,
    this.maxPriceMinor,
    this.minRating = 0,
    this.requirePower = false,
    this.instantOnly = false,
  });

  final ServiceCategory? category;
  final String? serviceId;
  final String venue;
  final double radiusKm;
  final int? maxPriceMinor;
  final double minRating;
  final bool requirePower;
  final bool instantOnly;

  DiscoveryFilters copyWith({
    ServiceCategory? category,
    String? serviceId,
    String? venue,
    double? radiusKm,
    int? maxPriceMinor,
    double? minRating,
    bool? requirePower,
    bool? instantOnly,
  }) =>
      DiscoveryFilters(
        category: category ?? this.category,
        serviceId: serviceId ?? this.serviceId,
        venue: venue ?? this.venue,
        radiusKm: radiusKm ?? this.radiusKm,
        maxPriceMinor: maxPriceMinor ?? this.maxPriceMinor,
        minRating: minRating ?? this.minRating,
        requirePower: requirePower ?? this.requirePower,
        instantOnly: instantOnly ?? this.instantOnly,
      );
}

final filtersProvider =
    StateProvider<DiscoveryFilters>((ref) => const DiscoveryFilters());

Position _fixedAt(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Where to search from.
///
/// Precedence, and the reasoning behind it:
///   1. A debug override, so a geofenced marketplace can be exercised on an
///      emulator that insists it is in Mountain View. Never read in release.
///   2. A real GPS fix, because it is the only thing that gets the travel fee
///      and the ETA right.
///   3. The area the customer chose at sign-up.
///
/// The third rung is the point. Discovery used to have only the second, so a
/// declined permission, a cold GPS or a basement produced "Freshly is not live
/// in this area yet" — a statement about a place the customer never chose and
/// could not change. Now the worst case is a slightly less precise feed.
final currentPositionProvider = FutureProvider<Position>((ref) async {
  final override = kDebugMode ? Env.devLatLng : null;
  if (override != null) return _fixedAt(override.lat, override.lng);

  final chosen = ref.watch(serviceAreaProvider);
  Position fallback() {
    if (chosen != null) return _fixedAt(chosen.lat, chosen.lng);
    throw ApiException(
      'location_unavailable',
      'We could not work out where you are. Choose your area in settings and try again.',
    );
  }

  if (!await Geolocator.isLocationServiceEnabled()) return fallback();

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    // Declining location is a legitimate choice, not an error. They told us
    // their area; that is enough to show a feed.
    return fallback();
  }

  // A fresh high-accuracy fix is the ideal, not a requirement. Indoors, in a
  // basement salon, or on a handset with a cold GPS, it can take far longer
  // than anyone will wait — and the previous version had no time limit at all,
  // so the screen sat on "Could not load pros nearby" indefinitely while the
  // phone hunted for satellites. A slightly stale position finds the same
  // barbers; a spinner that never resolves loses the booking.
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8),
      ),
    );
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    return last ?? fallback();
  }
});

/// Set when the feed is showing the chosen area rather than where the phone
/// actually is, so the screen can say so instead of quietly lying about
/// distances.
final searchedAwayFromHereProvider = StateProvider<bool>((ref) => false);

final searchResultsProvider =
    FutureProvider.autoDispose<List<ProviderSummary>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final filters = ref.watch(filtersProvider);
  final grid = await ref.watch(gridStatusProvider.future);
  final chosen = ref.watch(serviceAreaProvider);
  final api = ref.watch(apiProvider);

  Future<List<ProviderSummary>> search(double lat, double lng) =>
      api.searchProviders(
        lat: lat,
        lng: lng,
        radiusKm: filters.radiusKm,
        category: filters.category,
        serviceId: filters.serviceId,
        venue: filters.venue,
        maxPriceMinor: filters.maxPriceMinor,
        minRating: filters.minRating,
        // Stage 4 and above overrides the user's choice: showing a pro who
        // physically cannot work is worse than showing fewer results.
        requirePowerBackup: filters.requirePower || grid.forcesPowerFilter,
        instantOnly: filters.instantOnly,
      );

  try {
    final results = await search(position.latitude, position.longitude);
    ref.read(searchedAwayFromHereProvider.notifier).state = false;
    return results;
  } on ApiException catch (e) {
    // The phone is somewhere we do not cover — travelling, or a bad fix. Fall
    // back to the area they chose rather than telling someone with a perfectly
    // good home city that the app does not work.
    if (e.code == 'outside_service_area' && chosen != null) {
      final results = await search(chosen.lat, chosen.lng);
      ref.read(searchedAwayFromHereProvider.notifier).state = true;
      return results;
    }
    rethrow;
  }
});

/// Shown when the feed is for the customer's chosen area rather than their
/// current position — they are travelling, or the fix was unusable.
class _ElsewhereBanner extends StatelessWidget {
  const _ElsewhereBanner({required this.areaName});
  final String areaName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(FreshlySpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(FreshlyIcons.info,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
          const SizedBox(width: FreshlySpacing.sm),
          Expanded(
            child: Text(
              'Showing $areaName. We could not place you inside one of our '
              'areas, so travel times below are measured from there.',
              style: FreshlyType.style(13,
                  height: 1.45,
                  color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({required this.query, super.key});
  final Map<String, String> query;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(filtersProvider.notifier).state = DiscoveryFilters(
        category: widget.query['category'] != null
            ? ServiceCategory.fromWire(widget.query['category']!)
            : null,
        serviceId: widget.query['serviceId'],
        venue: widget.query['venue'] ?? 'mobile',
        requirePower: widget.query['power'] == 'true',
        instantOnly: widget.query['instant'] == 'true',
        minRating: double.tryParse(widget.query['rating'] ?? '') ?? 0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchResultsProvider);
    final filters = ref.watch(filtersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(filters.category?.label ?? 'Nearby pros'),
        actions: [
          IconButton(
            icon: const Icon(FreshlyIcons.tune),
            onPressed: () => _openFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
              children: [
                _Chip(
                  icon: FreshlyIcons.clock,
                  label: 'Available now',
                  selected: filters.instantOnly,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(instantOnly: !filters.instantOnly),
                ),
                _Chip(
                  icon: FreshlyIcons.bolt,
                  label: 'Backup power',
                  selected: filters.requirePower,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(requirePower: !filters.requirePower),
                ),
                _Chip(
                  icon: FreshlyIcons.star,
                  label: '4.5 and up',
                  selected: filters.minRating >= 4.5,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(
                          minRating: filters.minRating >= 4.5 ? 0 : 4.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => ListView.separated(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: FreshlySpacing.sm),
                itemBuilder: (_, __) =>
                    const Skeleton(height: 110, radius: FreshlySpacing.radius),
              ),
              error: (err, __) => _ErrorState(
                message: err is ApiException
                    ? err.message
                    : 'Could not load pros nearby',
                onRetry: () => ref.invalidate(searchResultsProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return _ErrorState(
                    message: filters.requirePower
                        ? 'No pros with backup power within ${filters.radiusKm.round()} km. '
                            'Try widening your search.'
                        : 'No pros nearby yet. Freshly is expanding — try a wider radius.',
                    onRetry: () => ref.read(filtersProvider.notifier).state =
                        filters.copyWith(radiusKm: filters.radiusKm + 10),
                    retryLabel: 'Search wider',
                  );
                }
                final elsewhere = ref.watch(searchedAwayFromHereProvider);
                final area = ref.watch(serviceAreaProvider);

                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(searchResultsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(FreshlySpacing.md),
                    // The banner is one extra row at the top when the results
                    // are not from where the phone actually is. Saying so
                    // matters: every distance and ETA below is measured from
                    // that area, not from here.
                    itemCount:
                        list.length + (elsewhere && area != null ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FreshlySpacing.sm),
                    itemBuilder: (_, i) {
                      if (elsewhere && area != null) {
                        if (i == 0) {
                          return _ElsewhereBanner(areaName: area.name);
                        }
                        i -= 1;
                      }
                      return ProviderCard(
                        provider: list[i],
                        onTap: () => context.push('/provider/${list[i].id}'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openFilterSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Consumer(
        builder: (context, ref, __) {
          final filters = ref.watch(filtersProvider);
          final text = Theme.of(context).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filters', style: text.headlineSmall),
                  const SizedBox(height: FreshlySpacing.lg),
                  Row(
                    children: [
                      Expanded(child: Text('How far', style: text.titleMedium)),
                      StatusPill(
                          label: '${filters.radiusKm.round()} km',
                          tone: FreshlyTone.dark),
                    ],
                  ),
                  Slider(
                    value: filters.radiusKm,
                    min: 1,
                    max: 25,
                    divisions: 24,
                    label: '${filters.radiusKm.round()} km',
                    onChanged: (v) => ref.read(filtersProvider.notifier).state =
                        filters.copyWith(radiusKm: v),
                  ),
                  const SizedBox(height: FreshlySpacing.sm),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Available now'),
                    value: filters.instantOnly,
                    onChanged: (v) => ref.read(filtersProvider.notifier).state =
                        filters.copyWith(instantOnly: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Backup power only'),
                    subtitle: const Text('Pros who can work through '
                        'load-shedding'),
                    value: filters.requirePower,
                    onChanged: (v) => ref.read(filtersProvider.notifier).state =
                        filters.copyWith(requirePower: v),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Show results'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = selected
        ? (isDark ? Colors.white : FreshlyColors.obsidian)
        : scheme.surface;
    final ink = selected
        ? (isDark ? FreshlyColors.obsidian : Colors.white)
        : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: FreshlySpacing.sm),
      child: Semantics(
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
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 15,
                        color: selected
                            ? (icon == FreshlyIcons.star
                                ? FreshlyColors.gold
                                : FreshlyColors.mint)
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
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState(
      {required this.message,
      required this.onRetry,
      this.retryLabel = 'Try again'});
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: FreshlyIcons.searchOff,
        title: 'No pros to show',
        message: message,
        actionLabel: retryLabel,
        onAction: onRetry,
      );
}
