import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/load_shedding_banner.dart';
import '../../widgets/provider_card.dart';
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

    // The hero runs up behind the status bar, so the bar's icons have to turn
    // light over it. SafeArea keeps the bottom inset and leaves the top to the
    // hero, which pads itself by the same amount.
    final venue = ref.watch(dashboardVenueProvider);
    final text = Theme.of(context).textTheme;

    // The hero runs up behind the status bar, so the bar's icons have to turn
    // light over it. SafeArea keeps the bottom inset and leaves the top to the
    // hero, which pads itself by the same amount.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(gridStatusProvider);
              ref.invalidate(topRatedProvidersProvider);
              ref.invalidate(powerBackupProvidersProvider);
              ref.invalidate(recentBookingsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
              children: [
                ParallaxHero(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        FreshlySpacing.md,
                        MediaQuery.paddingOf(context).top + FreshlySpacing.sm,
                        FreshlySpacing.md,
                        FreshlySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _LocationChip(
                                label: ref
                                        .watch(serviceAreaProvider)
                                        ?.displayName ??
                                    'Choose your area',
                                onTap: () => context.push('/location'),
                              ),
                            ),
                            const SizedBox(width: FreshlySpacing.sm),
                            _HeroIconButton(
                              icon: FreshlyIcons.receipt,
                              tooltip: 'My bookings',
                              onPressed: () => context.go('/bookings'),
                            ),
                          ],
                        ),
                        const SizedBox(height: FreshlySpacing.lg),
                        Text(_greeting(),
                            style: text.bodyLarge
                                ?.copyWith(color: FreshlyColors.inkMuted)),
                        const SizedBox(height: 4),
                        Text('Look sharp,\nwherever you are.',
                            style: text.displaySmall
                                ?.copyWith(color: Colors.white)),
                        const SizedBox(height: FreshlySpacing.lg),
                        // The concierge: one sentence instead of four taps.
                        TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _runConcierge(),
                          style: FreshlyType.style(15,
                              weight: FontWeight.w500,
                              color: FreshlyColors.ink),
                          decoration: InputDecoration(
                            fillColor: Colors.white,
                            hintText: 'Try "fade at my place tomorrow 4pm"',
                            prefixIcon: const Icon(FreshlyIcons.sparkles,
                                color: FreshlyColors.mintDark),
                            suffixIcon: _parsing
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(FreshlyIcons.search),
                                    color: FreshlyColors.ink,
                                    tooltip: 'Search',
                                    onPressed: _runConcierge,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.md),

                // ── Mode switch ──────────────────────────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          icon: Icon(FreshlyIcons.car),
                          label: Text('Come to me')),
                      ButtonSegment(
                          value: false,
                          icon: Icon(FreshlyIcons.storefront),
                          label: Text('At a shop')),
                    ],
                    selected: {venue == 'mobile'},
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

                // ── Categories ───────────────────────────────────────────────
                const SizedBox(height: FreshlySpacing.md),
                SectionHeader(
                  title: 'What do you need?',
                  actionLabel: 'See all',
                  onAction: () => context.push('/catalog'),
                ),
                SizedBox(
                  height: 104,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: FreshlySpacing.md),
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
                  subtitle: venue == 'mobile'
                      ? 'Pros who come to your door'
                      : 'Chairs worth the trip',
                  provider: topRatedProvidersProvider,
                  onSeeAll: () => context.push('/discover?rating=4.5'),
                ),

                const SizedBox(height: FreshlySpacing.lg),
                _CollectionSection(
                  title: 'Load-shedding ready',
                  subtitle: 'Battery clippers, lights and backup power',
                  provider: powerBackupProvidersProvider,
                  onSeeAll: () => context.push('/discover?power=true'),
                ),

                // ── Salons, when they are shopping for one ───────────────────
                // Only in shop mode. In mobile mode a list of premises is noise:
                // the whole proposition there is that nobody has to travel.
                if (venue == 'in_shop') ...[
                  const SizedBox(height: FreshlySpacing.lg),
                  const SectionHeader(title: 'Salons near you'),
                  const _NearbyShops(),
                ],

                const SizedBox(height: FreshlySpacing.lg),
                const SectionHeader(title: 'Book again'),
                const _RecentBookings(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
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
    ServiceCategory.barber: FreshlyIcons.barber,
    ServiceCategory.beard: FreshlyIcons.beard,
    ServiceCategory.scalp: FreshlyIcons.scalp,
    ServiceCategory.hair: FreshlyIcons.hair,
    ServiceCategory.braiding: FreshlyIcons.braiding,
    ServiceCategory.locs: FreshlyIcons.locs,
    ServiceCategory.extensions: FreshlyIcons.extensions,
    ServiceCategory.color: FreshlyIcons.colour,
    ServiceCategory.nails: FreshlyIcons.nails,
    ServiceCategory.makeup: FreshlyIcons.makeup,
    ServiceCategory.lashes: FreshlyIcons.lashes,
    ServiceCategory.brows: FreshlyIcons.brows,
    ServiceCategory.aesthetics: FreshlyIcons.aesthetics,
    ServiceCategory.bodyGrooming: FreshlyIcons.bodyGrooming,
    ServiceCategory.massage: FreshlyIcons.massage,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: category.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              IconBadge(icon: _icons[category]!, size: 64),
              const SizedBox(height: 8),
              ExcludeSemantics(
                child: Text(category.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FreshlyType.style(12,
                        weight: FontWeight.w600, height: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Where somebody wants service is a preference, and a preference you
    // cannot revisit is a trap — so the location is always one tap away.
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FreshlyIcons.location,
                    size: 16, color: FreshlyColors.mint),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: FreshlyType.style(14,
                          weight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(width: 4),
                const Icon(FreshlyIcons.expandMore,
                    size: 14, color: FreshlyColors.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton(
      {required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 44),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _NearbyShops extends ConsumerWidget {
  const _NearbyShops();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(nearbyShopsProvider);

    return shops.when(
      loading: () => const _ListSkeleton(),
      error: (e, __) => EmptyState(
        compact: true,
        icon: FreshlyIcons.storefront,
        title: 'Salons did not load',
        message: e is ApiException ? e.message : 'Pull down to try again.',
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            compact: true,
            icon: FreshlyIcons.storefront,
            title: 'No salons near you yet',
            message: 'Switch to "Come to me" and a pro will come to you '
                'instead.',
            actionLabel: 'Come to me',
            onAction: () =>
                ref.read(dashboardVenueProvider.notifier).state = 'mobile',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
          child: Column(
            children: [
              for (final p in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                  child: ProviderCard(
                    provider: p,
                    onTap: () => context.push('/provider/${p.id}'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < 2; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: FreshlySpacing.sm),
              child: Skeleton(height: 84, radius: FreshlySpacing.radius),
            ),
        ],
      ),
    );
  }
}

class _RecentBookings extends ConsumerWidget {
  const _RecentBookings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(recentBookingsProvider);

    return bookings.when(
      loading: () => const _ListSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            compact: true,
            icon: FreshlyIcons.calendar,
            title: 'Nothing booked yet',
            message: 'Your favourite pros will be here, one tap from your '
                'next appointment.',
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
          child: Column(
            children: list.take(3).map((b) {
              final name = b.providerName ?? 'Freshly booking';
              return Padding(
                padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                child: Card(
                  child: InkWell(
                    onTap: () => b.status.isLive
                        ? context.push('/track/${b.id}')
                        : context.push('/provider/${b.providerId}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          FreshlyAvatar(name: name, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                    '${formatDate(b.scheduledStart ?? b.createdAt)} · ${b.total.format()}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          if (b.status.isLive)
                            const StatusPill(
                                label: 'Live',
                                tone: FreshlyTone.brand,
                                icon: FreshlyIcons.navigation)
                          else
                            FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                textStyle: FreshlyType.style(14,
                                    weight: FontWeight.w700),
                              ),
                              onPressed: () {
                                final state = context.findAncestorStateOfType<
                                    _DashboardScreenState>();
                                state?._rebook(b);
                              },
                              child: const Text('Rebook'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
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
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final AutoDisposeFutureProvider<List<ProviderSummary>> provider;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(provider);

    // A rail with nothing in it is a heading over a gap; drop the section.
    if (results.hasValue && (results.value?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }
    if (results.hasError) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          actionLabel: 'See all',
          onAction: onSeeAll,
        ),
        SizedBox(
          height: ProviderCompactCard.height,
          child: results.when(
            loading: () => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: FreshlySpacing.sm + 4),
              itemBuilder: (_, __) => const Skeleton(
                  width: ProviderCompactCard.width,
                  height: ProviderCompactCard.height,
                  radius: FreshlySpacing.radius),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding:
                  const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: FreshlySpacing.sm + 4),
              itemBuilder: (context, i) => ProviderCompactCard(
                provider: list[i],
                onTap: () => context.push('/provider/${list[i].id}'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final recentBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(apiProvider).myBookings(),
);
