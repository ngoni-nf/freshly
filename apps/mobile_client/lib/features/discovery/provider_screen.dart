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

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 260,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: portfolio.isEmpty
                      ? Container(color: FreshlyColors.mintSoft)
                      : PageView.builder(
                          itemCount: portfolio.length,
                          itemBuilder: (_, i) => Image.network(
                            portfolio[i]['url'] as String,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Container(color: FreshlyColors.mintSoft),
                          ),
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
                    const Icon(Icons.star_rounded,
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
                                avatar: const Icon(Icons.bolt,
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
                                const Icon(Icons.bolt,
                                    size: 14,
                                    color: FreshlyColors.loadShedding),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    );
                  }),
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
