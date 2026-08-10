import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/load_shedding_banner.dart';

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
  bool _mobileMode = true;
  final _searchController = TextEditingController();
  bool _parsing = false;

  Future<void> _runConcierge() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    setState(() => _parsing = true);
    try {
      final intent = await ref.read(apiProvider).parseIntent(text);
      if (!mounted) return;
      unawaited(context.push(Uri(path: '/discover', queryParameters: {
        if (intent.category != null) 'category': intent.category!.wire,
        'venue': _mobileMode ? 'mobile' : 'in_shop',
        if (intent.powerBackupRequired) 'power': 'true',
        if (intent.bookingType == 'instant') 'instant': 'true',
        'q': intent.rawQuery,
      }).toString()));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _parsing = false);
    }
  }

  void _openCategory(ServiceCategory category) {
    context.push(Uri(path: '/discover', queryParameters: {
      'category': category.wire,
      'venue': _mobileMode ? 'mobile' : 'in_shop',
    }).toString());
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
                padding: const EdgeInsets.fromLTRB(
                    FreshlySpacing.md, FreshlySpacing.md, FreshlySpacing.md, FreshlySpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Freshly',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                          const Text('Freshness on demand.',
                              style: TextStyle(color: FreshlyColors.inkMuted, fontSize: 13)),
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
                padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true, icon: Icon(Icons.directions_car_outlined), label: Text('To me')),
                    ButtonSegment(
                        value: false, icon: Icon(Icons.storefront_outlined), label: Text('At a shop')),
                  ],
                  selected: {_mobileMode},
                  onSelectionChanged: (s) => setState(() => _mobileMode = s.first),
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
                    prefixIcon: const Icon(Icons.auto_awesome, color: FreshlyColors.mint),
                    suffixIcon: _parsing
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2)),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.sm),
                child: Text('What do you need?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              ),
              SizedBox(
                height: 108,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                  itemCount: ServiceCategory.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: FreshlySpacing.sm),
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: Text('Book again',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
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
    ServiceCategory.hair: Icons.brush_outlined,
    ServiceCategory.nails: Icons.back_hand_outlined,
    ServiceCategory.makeup: Icons.face_retouching_natural,
    ServiceCategory.aesthetics: Icons.spa_outlined,
    ServiceCategory.braiding: Icons.waves,
    ServiceCategory.locs: Icons.grain,
    ServiceCategory.massage: Icons.self_improvement,
    ServiceCategory.browsLashes: Icons.remove_red_eye_outlined,
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
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: FreshlyColors.mintSoft,
                borderRadius: BorderRadius.circular(FreshlySpacing.radius),
              ),
              child: Icon(_icons[category], color: FreshlyColors.mintDark, size: 28),
            ),
            const SizedBox(height: 6),
            Text(category.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
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
                      ? const Icon(Icons.navigation_outlined, color: FreshlyColors.mint)
                      : const Icon(Icons.refresh),
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

final recentBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(apiProvider).myBookings(),
);
