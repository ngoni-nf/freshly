import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../booking/booking_draft.dart';

final providerProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => ref.watch(apiProvider).providerProfile(id),
);

/// Screen A.8 — the showroom. Portfolio first, then the menu, with a sticky
/// bar that always shows what the current selection costs.
class ProviderScreen extends ConsumerStatefulWidget {
  const ProviderScreen({required this.providerId, super.key});
  final String providerId;

  @override
  ConsumerState<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends ConsumerState<ProviderScreen> {
  final _selected = <ServiceItem>[];
  int _portfolioIndex = 0;

  int get _totalMinor => _selected.fold(0, (s, e) => s + e.price.minor);
  String get _currency =>
      _selected.isEmpty ? 'ZAR' : _selected.first.price.currency;

  void _toggle(ServiceItem service) {
    setState(() {
      _selected.any((s) => s.id == service.id)
          ? _selected.removeWhere((s) => s.id == service.id)
          : _selected.add(service);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(providerProfileProvider(widget.providerId));
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      body: profile.when(
        loading: () => const _ProfileSkeleton(),
        error: (e, __) => Center(
          child: EmptyState(
            icon: FreshlyIcons.error,
            title: 'We could not load this pro',
            message: e is ApiException
                ? e.message
                : 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: () =>
                ref.invalidate(providerProfileProvider(widget.providerId)),
          ),
        ),
        data: (data) {
          final text = Theme.of(context).textTheme;
          final name = data['displayName'] as String;
          final rating = (data['rating'] as num).toDouble();
          final ratingCount = data['ratingCount'] as int? ?? 0;
          final bio = data['bio'] as String?;
          final power = (data['powerBackup'] as List? ?? [])
              .map((p) => PowerBackup.fromWire(p as String))
              .toList();
          final services = (data['services'] as List? ?? [])
              .map((s) => ServiceItem.fromJson(s as Map<String, dynamic>))
              .toList();
          final portfolio =
              (data['portfolio'] as List? ?? []).cast<Map<String, dynamic>>();
          final reviews =
              (data['reviews'] as List? ?? []).cast<Map<String, dynamic>>();

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                backgroundColor: FreshlyColors.obsidian,
                foregroundColor: Colors.white,
                leading: const _RoundBack(),
                // Pulling down past the top zooms the portfolio rather than
                // showing a blank gap. On iOS that is the native feel; on
                // Android the clamping physics simply never trigger it.
                stretch: true,
                flexibleSpace: FlexibleSpaceBar(
                  // The photo drifts up at a fraction of the scroll speed
                  // while the menu slides over it. With reduce motion on it
                  // is pinned instead and the menu simply covers it.
                  collapseMode:
                      still ? CollapseMode.pin : CollapseMode.parallax,
                  stretchModes: still
                      ? const <StretchMode>[]
                      : const [StretchMode.zoomBackground],
                  background: _SheetLip(
                    child: portfolio.isEmpty
                        ? _EmptyPortfolio(name: name)
                        : Stack(
                            children: [
                              Positioned.fill(
                                child: PageView.builder(
                                  itemCount: portfolio.length,
                                  onPageChanged: (i) =>
                                      setState(() => _portfolioIndex = i),
                                  itemBuilder: (context, i) => InkWell(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => GalleryViewer(
                                            urls: portfolio
                                                .map((p) => p['url'] as String)
                                                .toList(),
                                            initialIndex: i,
                                          ),
                                          fullscreenDialog: true,
                                        ),
                                      );
                                    },
                                    child: Image.network(
                                      portfolio[i]['url'] as String,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          MonogramArt(name: name),
                                    ),
                                  ),
                                ),
                              ),
                              // Keeps the back button legible over a bright photo.
                              const Positioned(
                                left: 0,
                                right: 0,
                                top: 0,
                                height: 120,
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x8C0B0F19),
                                          Color(0x000B0F19)
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (portfolio.length > 1)
                                Positioned(
                                  bottom: FreshlySpacing.lg + 12,
                                  right: FreshlySpacing.md,
                                  child: StatusPill(
                                    label:
                                        '${_portfolioIndex + 1} / ${portfolio.length}',
                                    tone: FreshlyTone.dark,
                                    icon: FreshlyIcons.gallery,
                                    dense: true,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                      FreshlySpacing.xs, FreshlySpacing.md, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name, style: text.headlineMedium),
                          ),
                          if (data['isOnline'] == true)
                            const StatusPill(
                                label: 'Available now',
                                tone: FreshlyTone.brand),
                        ],
                      ),
                      const SizedBox(height: FreshlySpacing.md),
                      Row(
                        children: [
                          _Stat(
                            value: ratingCount == 0
                                ? 'New'
                                : rating.toStringAsFixed(1),
                            label: 'Rating',
                            icon: FreshlyIcons.star,
                          ),
                          const SizedBox(width: FreshlySpacing.sm),
                          _Stat(
                              value: '$ratingCount',
                              label: 'Reviews',
                              icon: FreshlyIcons.message),
                          const SizedBox(width: FreshlySpacing.sm),
                          _Stat(
                              value: '${data['completedJobs'] ?? 0}',
                              label: 'Jobs done',
                              icon: FreshlyIcons.checkCircle),
                        ],
                      ),
                      if (power.isNotEmpty) ...[
                        const SizedBox(height: FreshlySpacing.md),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final p in power)
                              StatusPill(
                                label: p.label,
                                icon: FreshlyIcons.bolt,
                                tone: FreshlyTone.warning,
                              ),
                          ],
                        ),
                      ],
                      if (bio != null) ...[
                        const SizedBox(height: FreshlySpacing.md),
                        Text(bio,
                            style: text.bodyMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                      ],
                      const SizedBox(height: FreshlySpacing.lg),
                      const SectionHeader(
                        title: 'Services',
                        subtitle: 'Choose one or more',
                        padding: EdgeInsets.only(bottom: 12),
                      ),
                      for (final s in services)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: FreshlySpacing.sm),
                          child: _ServiceTile(
                            service: s,
                            selected: _selected.any((x) => x.id == s.id),
                            onTap: () => _toggle(s),
                          ),
                        ),

                      // ── What people actually said ───────────────────────
                      // A score answers "is this person good"; the words answer
                      // "good at what, and what went wrong for someone" — which
                      // is the question somebody booking a stranger to come to
                      // their home is really asking.
                      if (reviews.isNotEmpty) ...[
                        const SizedBox(height: FreshlySpacing.lg),
                        SectionHeader(
                          title: 'What clients say',
                          subtitle: '$ratingCount reviews',
                          padding: const EdgeInsets.only(bottom: 12),
                        ),
                        for (final r in reviews.take(5))
                          Padding(
                            padding: const EdgeInsets.only(
                                bottom: FreshlySpacing.sm),
                            child: _ReviewCard(review: r),
                          ),
                      ],
                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : StickyActionBar(
              leading: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatMinor(_totalMinor, _currency),
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(
                    '${_selected.length} service${_selected.length == 1 ? '' : 's'} · '
                    '${formatDuration(_selected.fold(0, (s, e) => s + e.durationMinutes))}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              child: FilledButton(
                onPressed: () {
                  final data = profile.value!;
                  context.push('/book/logistics',
                      extra: BookingDraft(
                        providerId: widget.providerId,
                        providerName: data['displayName'] as String,
                        services: List.of(_selected),
                      ));
                },
                child: const Text('Continue'),
              ),
            ),
    );
  }
}

/// The page's top edge, drawn inside the header so it rides over the photo:
/// the profile reads as one sheet sliding over the portfolio. (A sliver
/// after a pinned app bar is painted beneath it, so an overlap has to live
/// here rather than on the content.)
class _SheetLip extends StatelessWidget {
  const _SheetLip({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: -1,
          height: FreshlySpacing.radiusLarge,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FreshlySpacing.radiusLarge)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoundBack extends StatelessWidget {
  const _RoundBack();

  @override
  Widget build(BuildContext context) {
    if (!(ModalRoute.of(context)?.canPop ?? false) &&
        !GoRouter.of(context).canPop()) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.all(6),
      child: IconButton(
        tooltip: 'Back',
        style: IconButton.styleFrom(
          backgroundColor: FreshlyColors.obsidian.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
        ),
        onPressed: () => context.pop(),
        icon: const Icon(FreshlyIcons.chevronLeft, size: 20),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 15,
                    color: icon == FreshlyIcons.star
                        ? FreshlyColors.gold
                        : Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A service as a whole tappable card: selection is shown by the border and a
/// filled check, so it reads at a glance which services are in the basket.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile(
      {required this.service, required this.selected, required this.onTap});
  final ServiceItem service;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedEdge = isDark ? FreshlyColors.mint : FreshlyColors.obsidian;
    return Semantics(
      checked: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: selected ? selectedEdge : scheme.outline,
              width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FreshlySpacing.radius)),
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service.name, style: text.titleMedium),
                      if (service.description != null) ...[
                        const SizedBox(height: 2),
                        Text(service.description!, style: text.bodySmall),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(service.price.format(),
                              style: FreshlyType.style(15,
                                  weight: FontWeight.w800,
                                  color: scheme.primary)),
                          const SizedBox(width: 8),
                          StatusPill(
                              label: formatDuration(service.durationMinutes),
                              icon: FreshlyIcons.clock,
                              dense: true),
                          if (service.requiresPower) ...[
                            const SizedBox(width: 6),
                            const StatusPill(
                                label: 'Needs power',
                                icon: FreshlyIcons.bolt,
                                tone: FreshlyTone.warning,
                                dense: true),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? selectedEdge : Colors.transparent,
                    border: Border.all(
                        color: selected ? selectedEdge : scheme.outline,
                        width: 2),
                  ),
                  child: selected
                      ? Icon(FreshlyIcons.check,
                          size: 16,
                          color: isDark
                              ? FreshlyColors.obsidian
                              : FreshlyColors.mint)
                      : const Icon(FreshlyIcons.add, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final stars = (review['rating'] as num?)?.toInt() ?? 5;
    final tags = (review['tags'] as List? ?? []).cast<String>();
    final comment = review['comment'] as String?;
    final author = review['author'] as String? ?? 'A client';
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              FreshlyAvatar(name: author, size: 32),
              const SizedBox(width: 10),
              Expanded(child: Text(author, style: text.titleSmall)),
              Semantics(
                label: '$stars out of 5 stars',
                child: ExcludeSemantics(
                  child: Row(children: [
                    for (var i = 0; i < 5; i++)
                      Icon(FreshlyIcons.star,
                          size: 14,
                          color: i < stars
                              ? FreshlyColors.gold
                              : Theme.of(context).colorScheme.outline),
                  ]),
                ),
              ),
            ]),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(comment, style: text.bodyMedium),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in tags)
                    StatusPill(label: t, tone: FreshlyTone.brand, dense: true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Skeleton(height: 320, radius: 0),
        Padding(
          padding: EdgeInsets.all(FreshlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 220, height: 28),
              SizedBox(height: 16),
              Skeleton(height: 72, radius: FreshlySpacing.radius),
              SizedBox(height: 24),
              Skeleton(height: 96, radius: FreshlySpacing.radius),
              SizedBox(height: 8),
              Skeleton(height: 96, radius: FreshlySpacing.radius),
            ],
          ),
        ),
      ],
    );
  }
}

/// A pro with no photos yet still gets a header with some depth, instead of a
/// flat block that reads as a page that failed to load.
class _EmptyPortfolio extends StatelessWidget {
  const _EmptyPortfolio({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MonogramArt(name: name, fontSize: 96),
        const Positioned(
          left: FreshlySpacing.md,
          bottom: FreshlySpacing.lg + 12,
          child: StatusPill(
            label: 'Portfolio coming soon',
            icon: FreshlyIcons.gallery,
            tone: FreshlyTone.dark,
            dense: true,
          ),
        ),
      ],
    );
  }
}
