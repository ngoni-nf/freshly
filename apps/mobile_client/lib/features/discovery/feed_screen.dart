import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/provider_card.dart';

class DiscoveryFilters {
  const DiscoveryFilters({
    this.category,
    this.venue = 'mobile',
    this.radiusKm = 10,
    this.maxPriceMinor,
    this.minRating = 0,
    this.requirePower = false,
    this.instantOnly = false,
  });

  final ServiceCategory? category;
  final String venue;
  final double radiusKm;
  final int? maxPriceMinor;
  final double minRating;
  final bool requirePower;
  final bool instantOnly;

  DiscoveryFilters copyWith({
    ServiceCategory? category,
    String? venue,
    double? radiusKm,
    int? maxPriceMinor,
    double? minRating,
    bool? requirePower,
    bool? instantOnly,
  }) =>
      DiscoveryFilters(
        category: category ?? this.category,
        venue: venue ?? this.venue,
        radiusKm: radiusKm ?? this.radiusKm,
        maxPriceMinor: maxPriceMinor ?? this.maxPriceMinor,
        minRating: minRating ?? this.minRating,
        requirePower: requirePower ?? this.requirePower,
        instantOnly: instantOnly ?? this.instantOnly,
      );
}

final filtersProvider = StateProvider<DiscoveryFilters>((ref) => const DiscoveryFilters());

final currentPositionProvider = FutureProvider<Position>((ref) async {
  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) throw ApiException('location_off', 'Turn on location to find pros near you');
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw ApiException('location_denied', 'Freshly needs your location to find nearby pros');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
});

final searchResultsProvider =
    FutureProvider.autoDispose<List<ProviderSummary>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final filters = ref.watch(filtersProvider);
  final grid = await ref.watch(gridStatusProvider.future);

  return ref.watch(apiProvider).searchProviders(
        lat: position.latitude,
        lng: position.longitude,
        radiusKm: filters.radiusKm,
        category: filters.category,
        venue: filters.venue,
        maxPriceMinor: filters.maxPriceMinor,
        minRating: filters.minRating,
        // Stage 4 and above overrides the user's choice: showing a pro who
        // physically cannot work is worse than showing fewer results.
        requirePowerBackup: filters.requirePower || grid.forcesPowerFilter,
        instantOnly: filters.instantOnly,
      );
});

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
        venue: widget.query['venue'] ?? 'mobile',
        requirePower: widget.query['power'] == 'true',
        instantOnly: widget.query['instant'] == 'true',
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
            icon: const Icon(Icons.tune),
            onPressed: () => _openFilterSheet(context),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
              children: [
                _Chip(
                  label: 'Available now',
                  selected: filters.instantOnly,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(instantOnly: !filters.instantOnly),
                ),
                _Chip(
                  label: '🔋 Power backup',
                  selected: filters.requirePower,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(requirePower: !filters.requirePower),
                ),
                _Chip(
                  label: '4.5★ and up',
                  selected: filters.minRating >= 4.5,
                  onTap: () => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(minRating: filters.minRating >= 4.5 ? 0 : 4.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, __) => _ErrorState(
                message: err is ApiException ? err.message : 'Could not load pros nearby',
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
                return RefreshIndicator(
                  onRefresh: () async => ref.invalidate(searchResultsProvider),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(FreshlySpacing.md),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.sm),
                    itemBuilder: (_, i) => ProviderCard(
                      provider: list[i],
                      onTap: () => context.push('/provider/${list[i].id}'),
                    ),
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
          return Padding(
            padding: const EdgeInsets.all(FreshlySpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filters',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: FreshlySpacing.lg),
                Text('Distance: ${filters.radiusKm.round()} km'),
                Slider(
                  value: filters.radiusKm,
                  min: 1, max: 25, divisions: 24,
                  label: '${filters.radiusKm.round()} km',
                  onChanged: (v) => ref.read(filtersProvider.notifier).state =
                      filters.copyWith(radiusKm: v),
                ),
                const SizedBox(height: FreshlySpacing.md),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Show results'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: FreshlySpacing.sm),
        child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry, this.retryLabel = 'Try again'});
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 44, color: FreshlyColors.inkMuted),
              const SizedBox(height: FreshlySpacing.md),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FreshlyColors.inkMuted, height: 1.4)),
              const SizedBox(height: FreshlySpacing.lg),
              OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
            ],
          ),
        ),
      );
}
