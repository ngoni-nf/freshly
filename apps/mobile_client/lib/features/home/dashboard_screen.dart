import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/load_shedding_banner.dart';
import '../../widgets/provider_compact_card.dart';
import '../booking/booking_draft.dart';
import '../discovery/feed_screen.dart' show currentPositionProvider;

/// Salons near the customer, for "At a shop".
///
/// Deliberately not the feed's provider: the dashboard asks a narrower
/// question — premises you can walk into — and should not inherit whatever
/// filters the customer last left discovery in. The radius is wider than the
/// mobile default because a shop does not travel, so the only thing that
/// matters is whether the customer is willing to.
final dashboardVenueProvider = StateProvider<String>((ref) => 'mobile');

final nearbyShopsProvider =
    FutureProvider.autoDispose<List<ProviderSummary>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  return ref.watch(apiProvider).searchProviders(
        lat: position.latitude,
        lng: position.longitude,
        venue: 'in_shop',
        radiusKm: 15,
        limit: 10,
      );
});

final topRatedProvidersProvider =
    FutureProvider.autoDispose<List<ProviderSummary>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final venue = ref.watch(dashboardVenueProvider);
  return ref.watch(apiProvider).searchProviders(
        lat: position.latitude,
        lng: position.longitude,
        venue: venue,
        minRating: 4.8,
        limit: 8,
      );
});

final powerBackupProvidersProvider =
    FutureProvider.autoDispose<List<ProviderSummary>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  final venue = ref.watch(dashboardVenueProvider);
  return ref.watch(apiProvider).searchProviders(
        lat: position.latitude,
        lng: position.longitude,
        venue: venue,
        requirePowerBackup: true,
        limit: 8,
      );
});

/// Screen A.6 — the front door.
///
/// Two decisions carry this screen: mobile-versus-shop, which changes what the
/// entire catalogue means, and the concierge bar, which lets someone type
/// "barber at my place tomorrow at 4, load shedding" and skip four taps.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _searchController = TextEditingController();
  bool _parsing = false;

  Future<void> _runConcierge() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    setState(() => _parsing = true);
    try {
      final intent = await ref.read(apiProvider).parseIntent(text);
      if (!mounted) return;
      final venue = ref.read(dashboardVenueProvider);
      unawaited(context.push(Uri(path: '/discover', queryParameters: {
        if (intent.category != null) 'category': intent.category!.wire,
        'venue': venue,
        if (intent.powerBackupRequired) 'power': 'true',
        if (intent.bookingType == 'instant') 'instant': 'true',
        'q': intent.rawQuery,
      }).toString()));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _openCategory(ServiceCategory category) {
    context.push('/catalog?category=${category.wire}');
  }

  Future<void> _rebook(Booking b) async {
    if (b.providerId == null) return;
    setState(() => _parsing = true);
    try {
      final data = await ref.read(apiProvider).providerProfile(b.providerId!);
      final services = (data['services'] as List? ?? [])
          .map((s) => ServiceItem.fromJson(s as Map<String, dynamic>))
          .where((s) => b.serviceIds.contains(s.id))
          .toList();

      if (!mounted) return;
      if (services.isEmpty) {
        throw ApiException('services_unavailable',
            'These services are no longer available. Please choose new ones.');
      }

      unawaited(context.push('/book/logistics',
          extra: BookingDraft(
            providerId: b.providerId!,
            providerName: b.providerName ?? 'Professional',
            services: services,
          )));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grid = ref.watch(gridStatusProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(gridStatusProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                    FreshlySpacing.md, FreshlySpacing.md, FreshlySpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Freshly',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.5)),
                          // The chosen location, and the way to change it.
                          // Where somebody wants service is a preference, and
                          // a preference you cannot revisit is a trap.
                          InkWell(
                            onTap: () => context.push('/location'),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_outlined,
                                    size: 14, color: FreshlyColors.inkMuted),
                                const SizedBox(width: 2),
                                Text(
                                  ref.watch(serviceAreaProvider)?.displayName ??
                                      'Freshness on demand.',
                                  style: const TextStyle(
                                      color: FreshlyColors.inkMuted,
                                      fontSize: 13),
                                ),
                                const Icon(Icons.expand_more,
                                    size: 16, color: FreshlyColors.inkMuted),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.push('/bookings'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      tooltip: 'My bookings',
                    ),
                  ],
                ),
              ),

              // ── Mode switch ────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true,
                        icon: Icon(Icons.directions_car_outlined),
                        label: Text('To me')),
                    ButtonSegment(
                        value: false,
                        icon: Icon(Icons.storefront_outlined),
                        label: Text('At a shop')),
                  ],
                  selected: {ref.watch(dashboardVenueProvider) == 'mobile'},
                  onSelectionChanged: (s) => ref
                      .read(dashboardVenueProvider.notifier)
                      .state = s.first ? 'mobile' : 'in_shop',
                  showSelectedIcon: false,
                ),
              ),

              grid.when(
                data: (status) => LoadSheddingBanner(
                  status: status,
                  onFilterPressed: () => context.push('/discover?power=true'),
                ),
                loading: () => const SizedBox(height: FreshlySpacing.sm),
                error: (_, __) => const SizedBox(height: FreshlySpacing.sm),
              ),

              // ── Concierge search ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runConcierge(),
                  decoration: InputDecoration(
                    hintText: 'Try "fade at my place tomorrow 4pm"',
                    prefixIcon: const Icon(Icons.auto_awesome,
                        color: FreshlyColors.mint),
                    suffixIcon: _parsing
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : IconButton(
                            icon: const Icon(Icons.mic_none),
                            tooltip: 'Speak',
                            onPressed: () {},
                          ),
                  ),
                ),
              ),

              // ── Categories ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('What do you need?',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    TextButton(
                      onPressed: () => context.push('/catalog'),
                      child: const Text('See all'),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                  itemCount: ServiceCategory.values.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: FreshlySpacing.sm),
                  itemBuilder: (context, i) {
                    final category = ServiceCategory.values[i];
                    return _CategoryTile(
                      category: category,
                      onTap: () => _openCategory(category),
                    );
                  },
                ),
              ),

              const SizedBox(height: FreshlySpacing.lg),
              _CollectionSection(
                title: 'Top rated near you',
                provider: topRatedProvidersProvider,
                onSeeAll: () => context.push('/discover?rating=4.5'),
              ),

              const SizedBox(height: FreshlySpacing.lg),
              _CollectionSection(
                title: 'Load-shedding ready',
                provider: powerBackupProvidersProvider,
                onSeeAll: () => context.push('/discover?power=true'),
              ),

              // ── Salons, when they are shopping for one ─────────────────────
              // Only in shop mode. In mobile mode a list of premises is noise:
              // the whole proposition there is that nobody has to travel.
              if (ref.watch(dashboardVenueProvider) == 'in_shop') ...[
                const SizedBox(height: FreshlySpacing.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                  child: Text('Salons near you',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                const _NearbyShops(),
              ],

              const SizedBox(height: FreshlySpacing.lg),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: Text('Book again',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              ),
              const _RecentBookings(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final ServiceCategory category;
  final VoidCallback onTap;

  static const _icons = {
    ServiceCategory.barber: Icons.content_cut,
    ServiceCategory.beard: Icons.face_outlined,
    ServiceCategory.scalp: Icons.psychology_alt_outlined,
    ServiceCategory.hair: Icons.brush_outlined,
    ServiceCategory.braiding: Icons.waves,
    ServiceCategory.locs: Icons.grain,
    ServiceCategory.extensions: Icons.layers_outlined,
    ServiceCategory.color: Icons.palette_outlined,
    ServiceCategory.nails: Icons.back_hand_outlined,
    ServiceCategory.makeup: Icons.face_retouching_natural,
    ServiceCategory.lashes: Icons.visibility_outlined,
    ServiceCategory.brows: Icons.remove_red_eye_outlined,
    ServiceCategory.aesthetics: Icons.spa_outlined,
    ServiceCategory.bodyGrooming: Icons.auto_fix_high_outlined,
    ServiceCategory.massage: Icons.self_improvement,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: FreshlyColors.mintSoft,
                borderRadius: BorderRadius.circular(FreshlySpacing.radius),
              ),
              child: Icon(_icons[category],
                  color: FreshlyColors.mintDark, size: 28),
            ),
            const SizedBox(height: 6),
            Text(category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _NearbyShops extends ConsumerWidget {
  const _NearbyShops();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(nearbyShopsProvider);

    return shops.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(FreshlySpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, __) => Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Text(
          e is ApiException ? e.message : 'We could not load salons near you.',
          style: const TextStyle(color: FreshlyColors.inkMuted),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(FreshlySpacing.md),
            child: Text(
              'No salons near you yet. Switch to "To me" and a pro will come '
              'to you instead.',
              style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
            ),
          );
        }
        return Column(
          children: list.map((p) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                  FreshlySpacing.md, FreshlySpacing.sm, FreshlySpacing.md, 0),
              child: Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: FreshlyColors.mintSoft,
                    child: Icon(Icons.storefront_outlined,
                        color: FreshlyColors.mintDark),
                  ),
                  title: Text(p.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  // The address is the whole point of a salon listing: it is
                  // how somebody decides whether they are willing to travel.
                  subtitle: Text(
                    [
                      if (p.shopAddress != null) p.shopAddress!,
                      '${p.distanceKm.toStringAsFixed(1)} km · from ${p.fromPrice.format()}',
                    ].join('\n'),
                    style: const TextStyle(height: 1.3),
                  ),
                  isThreeLine: p.shopAddress != null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/provider/${p.id}'),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _RecentBookings extends ConsumerWidget {
  const _RecentBookings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(recentBookingsProvider);

    return bookings.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(FreshlySpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(FreshlySpacing.md),
            child: Text('Your past bookings will appear here.',
                style: TextStyle(color: FreshlyColors.inkMuted)),
          );
        }
        return Column(
          children: list.take(3).map((b) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                  FreshlySpacing.md, FreshlySpacing.sm, FreshlySpacing.md, 0),
              child: Card(
                child: ListTile(
                  title: Text(b.providerName ?? 'Freshly booking'),
                  subtitle: Text('${b.reference} · ${b.total.format()}'),
                  trailing: b.status.isLive
                      ? const Icon(Icons.navigation_outlined,
                          color: FreshlyColors.mint)
                      : TextButton(
                          onPressed: () {
                            final state = context
                                .findAncestorStateOfType<_DashboardScreenState>();
                            state?._rebook(b);
                          },
                          child: const Text('Rebook'),
                        ),
                  onTap: () => b.status.isLive
                      ? context.push('/track/${b.id}')
                      : context.push('/provider/${b.providerId}'),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _CollectionSection extends ConsumerWidget {
  const _CollectionSection({
    required this.title,
    required this.provider,
    required this.onSeeAll,
  });

  final String title;
  final AutoDisposeFutureProvider<List<ProviderSummary>> provider;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(provider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: results.when(
            loading: () => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: FreshlySpacing.sm),
              itemBuilder: (_, __) => Container(
                width: 160,
                decoration: BoxDecoration(
                  color: FreshlyColors.line.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: FreshlySpacing.sm),
                itemBuilder: (context, i) => ProviderCompactCard(
                  provider: list[i],
                  onTap: () => context.push('/provider/${list[i].id}'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

final recentBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(apiProvider).myBookings(),
);
