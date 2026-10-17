import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({this.initialCategory, super.key});
  final ServiceCategory? initialCategory;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  ServiceCategory? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedCategory?.label ?? 'Explore'),
        leading: _selectedCategory != null
            ? BackButton(
                onPressed: () => setState(() => _selectedCategory = null))
            : null,
      ),
      body: _selectedCategory == null
          ? _SpecialityGrid(onSelect: (cat) {
              setState(() => _selectedCategory = cat);
            })
          : _ServiceList(
              category: _selectedCategory!,
              onSelect: (service) {
                context.push(Uri(path: '/discover', queryParameters: {
                  'category': _selectedCategory!.wire,
                  'serviceId': service.id,
                }).toString());
              },
            ),
    );
  }
}

class _SpecialityGrid extends ConsumerWidget {
  const _SpecialityGrid({required this.onSelect});
  final ValueChanged<ServiceCategory> onSelect;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(catalogCategoriesProvider);

    return categories.when(
      loading: () => GridView.count(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        crossAxisCount: 2,
        crossAxisSpacing: FreshlySpacing.sm,
        mainAxisSpacing: FreshlySpacing.sm,
        childAspectRatio: 1.35,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
            6, (_) => const Skeleton(radius: FreshlySpacing.radius)),
      ),
      error: (err, __) => EmptyState(
        icon: FreshlyIcons.error,
        title: 'Services did not load',
        message: err is ApiException
            ? err.message
            : 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(catalogCategoriesProvider),
      ),
      data: (list) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                FreshlySpacing.xs, FreshlySpacing.md, FreshlySpacing.md),
            sliver: SliverToBoxAdapter(
              child: Text('What are you in the mood for?',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.xl),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: FreshlySpacing.sm,
                mainAxisSpacing: FreshlySpacing.sm,
                childAspectRatio: 1.35,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final item = list[i];
                final text = Theme.of(context).textTheme;
                return Card(
                  child: InkWell(
                    onTap: () => onSelect(item.category),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          IconBadge(icon: _icons[item.category]!, size: 44),
                          const Spacer(),
                          Text(item.category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                              item.providerCount == 1
                                  ? '1 pro'
                                  : '${item.providerCount} pros',
                              style: text.bodySmall),
                        ],
                      ),
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
}

class _ServiceList extends ConsumerWidget {
  const _ServiceList({required this.category, required this.onSelect});
  final ServiceCategory category;
  final ValueChanged<CatalogService> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(catalogServicesProvider(category));

    return services.when(
      loading: () => ListView.separated(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.sm),
        itemBuilder: (_, __) =>
            const Skeleton(height: 84, radius: FreshlySpacing.radius),
      ),
      error: (err, __) => EmptyState(
        icon: FreshlyIcons.error,
        title: 'Services did not load',
        message: err is ApiException
            ? err.message
            : 'Check your connection and try again.',
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(catalogServicesProvider(category)),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: FreshlyIcons.category,
            title: 'Nothing here yet',
            message: 'No pros offer this in your area yet. Check back soon.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: FreshlySpacing.sm),
          itemBuilder: (context, i) {
            final service = list[i];
            final text = Theme.of(context).textTheme;
            return Card(
              child: InkWell(
                onTap: () => onSelect(service),
                child: Padding(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  child: Row(
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
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusPill(
                                  label: formatDuration(
                                      service.typicalDurationMinutes),
                                  icon: FreshlyIcons.clock,
                                  dense: true,
                                ),
                                if (service.requiresPower)
                                  const StatusPill(
                                    label: 'Needs power',
                                    icon: FreshlyIcons.bolt,
                                    tone: FreshlyTone.warning,
                                    dense: true,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(FreshlyIcons.chevronRight, size: 18),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
