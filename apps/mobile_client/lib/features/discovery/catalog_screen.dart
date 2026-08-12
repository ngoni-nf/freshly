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
        title: Text(_selectedCategory?.label ?? 'Browse Services'),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, __) => Center(child: Text(err.toString())),
      data: (list) => GridView.builder(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: FreshlySpacing.md,
          mainAxisSpacing: FreshlySpacing.md,
          childAspectRatio: 0.8,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final item = list[i];
          return InkWell(
            onTap: () => onSelect(item.category),
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: FreshlyColors.mintSoft,
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                  ),
                  child: Icon(_icons[item.category],
                      color: FreshlyColors.mintDark, size: 32),
                ),
                const SizedBox(height: FreshlySpacing.xs),
                Text(
                  item.category.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${item.providerCount} pros',
                  style: const TextStyle(
                      color: FreshlyColors.inkMuted, fontSize: 11),
                ),
              ],
            ),
          );
        },
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, __) => Center(child: Text(err.toString())),
      data: (list) => ListView.separated(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: FreshlySpacing.lg),
        itemBuilder: (context, i) {
          final service = list[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(service.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (service.description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(service.description!,
                        style: const TextStyle(
                            fontSize: 13, color: FreshlyColors.inkMuted)),
                  ),
                Row(
                  children: [
                    const Icon(FreshlyIcons.clock,
                        size: 14, color: FreshlyColors.inkMuted),
                    const SizedBox(width: 4),
                    Text('${service.typicalDurationMinutes} min',
                        style: const TextStyle(
                            fontSize: 12, color: FreshlyColors.inkMuted)),
                    if (service.requiresPower) ...[
                      const SizedBox(width: FreshlySpacing.md),
                      const Icon(FreshlyIcons.bolt,
                          size: 14, color: FreshlyColors.mint),
                      const SizedBox(width: 4),
                      const Text('Power needed',
                          style: TextStyle(
                              fontSize: 12, color: FreshlyColors.mint)),
                    ],
                  ],
                ),
              ],
            ),
            trailing: const Icon(FreshlyIcons.chevronRight),
            onTap: () => onSelect(service),
          );
        },
      ),
    );
  }
}
