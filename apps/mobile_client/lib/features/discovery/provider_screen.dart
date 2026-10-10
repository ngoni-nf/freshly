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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child:
              Text(e is ApiException ? e.message : 'Could not load this pro'),
        ),
        data: (data) {
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
                expandedHeight: 300,
                pinned: true,
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
                  background: portfolio.isEmpty
                      ? const _EmptyPortfolio()
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
                                        Container(color: FreshlyColors.mintSoft),
                                  ),
                                ),
                              ),
                            ),
                            if (portfolio.length > 1)
                              Positioned(
                                bottom: FreshlySpacing.md,
                                right: FreshlySpacing.md,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_portfolioIndex + 1} / ${portfolio.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                sliver: SliverList.list(children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(FreshlyIcons.star,
                        size: 18, color: FreshlyColors.gold),
                    Text(
                        ' ${rating.toStringAsFixed(1)} ($ratingCount reviews)'),
                    const Text('   ·   ',
                        style: TextStyle(color: FreshlyColors.inkMuted)),
                    Text('${data['completedJobs'] ?? 0} jobs done',
                        style: const TextStyle(color: FreshlyColors.inkMuted)),
                  ]),
                  if (power.isNotEmpty) ...[
                    const SizedBox(height: FreshlySpacing.md),
                    Wrap(
                      spacing: 6,
                      children: power
                          .map((p) => Chip(
                                avatar: const Icon(FreshlyIcons.bolt,
                                    size: 15, color: FreshlyColors.gold),
                                label: Text(p.label,
                                    style: const TextStyle(fontSize: 12)),
                              ))
                          .toList(),
                    ),
                  ],
                  if (bio != null) ...[
                    const SizedBox(height: FreshlySpacing.md),
                    Text(bio,
                        style: const TextStyle(
                            height: 1.5, color: FreshlyColors.inkMuted)),
                  ],
                  const SizedBox(height: FreshlySpacing.lg),
                  const Text('Services',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: FreshlySpacing.sm),
                  ...services.map((s) {
                    final chosen = _selected.any((x) => x.id == s.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                      child: CheckboxListTile(
                        value: chosen,
                        onChanged: (_) => _toggle(s),
                        controlAffinity: ListTileControlAffinity.trailing,
                        title: Text(s.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (s.description != null) Text(s.description!),
                            const SizedBox(height: 4),
                            Row(children: [
                              Text(s.price.format(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: FreshlyColors.mintDark)),
                              const Text('  ·  ',
                                  style:
                                      TextStyle(color: FreshlyColors.inkMuted)),
                              Text(formatDuration(s.durationMinutes),
                                  style: const TextStyle(
                                      color: FreshlyColors.inkMuted)),
                              if (s.requiresPower) ...[
                                const SizedBox(width: 6),
                                const Icon(FreshlyIcons.bolt,
                                    size: 14,
                                    color: FreshlyColors.loadShedding),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    );
                  }),

                  // ── What people actually said ───────────────────────────
                  // A score answers "is this person good"; the words answer
                  // "good at what, and what went wrong for someone" — which is
                  // the question somebody booking a stranger to come to their
                  // home is really asking. The API has always returned these;
                  // the screen showed the average and threw the rest away.
                  if (reviews.isNotEmpty) ...[
                    const SizedBox(height: FreshlySpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Recent reviews',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        Text('$ratingCount total',
                            style: const TextStyle(
                                color: FreshlyColors.inkMuted, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: FreshlySpacing.sm),
                    ...reviews.take(5).map((r) {
                      final stars = (r['rating'] as num?)?.toInt() ?? 5;
                      final tags = (r['tags'] as List? ?? []).cast<String>();
                      final comment = r['comment'] as String?;
                      return Card(
                        margin:
                            const EdgeInsets.only(bottom: FreshlySpacing.sm),
                        child: Padding(
                          padding: const EdgeInsets.all(FreshlySpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                for (var i = 0; i < 5; i++)
                                  Icon(FreshlyIcons.star,
                                      size: 14,
                                      color: i < stars
                                          ? FreshlyColors.gold
                                          : FreshlyColors.line),
                                const SizedBox(width: 8),
                                Text(
                                  r['author'] as String? ?? 'A client',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                ),
                              ]),
                              if (comment != null && comment.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(comment,
                                    style: const TextStyle(height: 1.45)),
                              ],
                              if (tags.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: tags
                                      .map((t) => Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4),
                                            decoration: BoxDecoration(
                                              color: FreshlyColors.mintSoft,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(t,
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: FreshlyColors
                                                        .mintDark)),
                                          ))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 100),
                ]),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border:
                      const Border(top: BorderSide(color: FreshlyColors.line)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(formatMinor(_totalMinor, _currency),
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        Text(
                          '${_selected.length} service${_selected.length == 1 ? '' : 's'} · '
                          '${formatDuration(_selected.fold(0, (s, e) => s + e.durationMinutes))}',
                          style: const TextStyle(
                              fontSize: 12, color: FreshlyColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.md),
                  Expanded(
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
                ]),
              ),
            ),
    );
  }
}

/// A pro with no photos yet still gets a header with some depth, instead of a
/// flat block that reads as a page that failed to load.
class _EmptyPortfolio extends StatelessWidget {
  const _EmptyPortfolio();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FreshlyColors.obsidian,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -60,
            bottom: -80,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: FreshlyColors.mint, width: 34),
              ),
            ),
          ),
          Positioned(
            left: -40,
            top: 40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FreshlyColors.mint.withValues(alpha: 0.14),
              ),
            ),
          ),
          const Positioned(
            left: FreshlySpacing.md,
            bottom: FreshlySpacing.lg,
            child: Text(
              'No portfolio photos yet',
              style: TextStyle(color: FreshlyColors.inkMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
