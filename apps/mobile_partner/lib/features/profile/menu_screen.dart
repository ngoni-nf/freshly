import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../widgets/category_icon.dart';
import '../../widgets/job_tile.dart' show JobTileSkeleton;

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(myMenuProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Service menu')),
      floatingActionButton: menu.valueOrNull?.isNotEmpty ?? false
          ? FloatingActionButton.extended(
              heroTag: 'add-service',
              onPressed: () => _showAddServiceSheet(context, ref),
              icon: const Icon(FreshlyIcons.add),
              label: const Text('Add service'),
            )
          : null,
      body: menu.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [JobTileSkeleton(count: 4)],
        ),
        error: (err, __) => EmptyState(
          icon: FreshlyIcons.style,
          title: 'Your menu did not load',
          message: err is ApiException
              ? err.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myMenuProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.style,
              title: 'Your menu is empty',
              message: 'Add the services you offer and set your price. '
                  'Clients can only book what is on your menu.',
              actionLabel: 'Add my first service',
              onAction: () => _showAddServiceSheet(context, ref),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                FreshlySpacing.md, FreshlySpacing.sm, FreshlySpacing.md, 96),
            itemCount: items.length + 1,
            separatorBuilder: (_, i) =>
                SizedBox(height: i == 0 ? 4 : FreshlySpacing.sm),
            itemBuilder: (context, i) {
              final text = Theme.of(context).textTheme;
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text('Tap a service to change its price.',
                      style: text.bodySmall),
                );
              }
              final item = items[i - 1];
              return Card(
                child: InkWell(
                  onTap: () => _showEditPriceDialog(context, ref, item),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        IconBadge(icon: categoryIcon(item.category), size: 44),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                  '${item.category.label} · ${formatDuration(item.durationMinutes)}',
                                  style: text.bodySmall),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(item.price.format(),
                            style: text.titleMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showAddServiceSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddServiceSheet(),
    );
  }

  void _showEditPriceDialog(
      BuildContext context, WidgetRef ref, ProviderMenuItem item) {
    final controller =
        TextEditingController(text: minorToInput(item.price.minor));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            prefixText: '${item.price.currency} ',
            labelText: 'Your price',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
            onPressed: () async {
              final val = parseMinor(controller.text);
              if (val == null) return;
              try {
                await ref.read(apiProvider).updateMenuItem(
                      catalogServiceId: item.catalogServiceId,
                      priceMinor: val,
                    );
                ref.invalidate(myMenuProvider);
                if (context.mounted) Navigator.pop(context);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _AddServiceSheet extends ConsumerStatefulWidget {
  const _AddServiceSheet();

  @override
  ConsumerState<_AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends ConsumerState<_AddServiceSheet> {
  ServiceCategory? _category;

  /// The provider's own currency beside the price field. A Harare barber
  /// typing a price next to "R" would reasonably wonder which money they are
  /// being asked for.
  String? get _currencyPrefix {
    final code = ref.read(countryCodeProvider);
    final markets = ref.read(marketsProvider).valueOrNull ?? const [];
    for (final m in markets) {
      if (m.code == code) return '${m.currency} ';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          backgroundColor: Colors.transparent,
          title:
              Text(_category == null ? 'Choose a category' : _category!.label),
          leading: _category != null
              ? BackButton(onPressed: () => setState(() => _category = null))
              : const CloseButton(),
        ),
        Expanded(
          child: _category == null
              ? GridView.builder(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: FreshlySpacing.sm,
                    mainAxisSpacing: FreshlySpacing.sm,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: ServiceCategory.values.length,
                  itemBuilder: (context, i) {
                    final cat = ServiceCategory.values[i];
                    return Card(
                      child: InkWell(
                        onTap: () => setState(() => _category = cat),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconBadge(icon: categoryIcon(cat), size: 48),
                              const SizedBox(height: 8),
                              Text(cat.label,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: FreshlyType.style(13,
                                      weight: FontWeight.w600, height: 1.2)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
              : _CatalogServiceList(
                  category: _category!,
                  onSelect: (service) => _showPriceInput(context, service),
                ),
        ),
      ],
    );
  }

  void _showPriceInput(BuildContext context, CatalogService service) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${service.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(service.description ?? 'Set your price for this service.'),
            const SizedBox(height: FreshlySpacing.md),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                prefixText: _currencyPrefix,
                labelText: 'Your price',
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
            onPressed: () async {
              final val = parseMinor(controller.text);
              if (val == null) return;
              try {
                await ref.read(apiProvider).updateMenuItem(
                      catalogServiceId: service.id,
                      priceMinor: val,
                    );
                ref.invalidate(myMenuProvider);
                if (context.mounted) {
                  Navigator.pop(context); // dialog
                  Navigator.pop(context); // sheet
                }
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Add to menu'),
          ),
        ],
      ),
    );
  }
}

class _CatalogServiceList extends ConsumerWidget {
  const _CatalogServiceList({required this.category, required this.onSelect});
  final ServiceCategory category;
  final ValueChanged<CatalogService> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(catalogServicesProvider(category));

    return services.when(
      loading: () => ListView(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        children: const [JobTileSkeleton(count: 5)],
      ),
      error: (err, __) => EmptyState(
        compact: true,
        icon: FreshlyIcons.error,
        title: 'Services did not load',
        message: err is ApiException ? err.message : err.toString(),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            compact: true,
            icon: FreshlyIcons.style,
            title: 'Nothing in this category yet',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.md),
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: FreshlySpacing.sm),
          itemBuilder: (context, i) {
            final s = list[i];
            return Card(
              child: ListTile(
                title: Text(s.name),
                subtitle: Text(formatDuration(s.typicalDurationMinutes)),
                trailing: const IconBadge(icon: FreshlyIcons.add, size: 36),
                onTap: () => onSelect(s),
              ),
            );
          },
        );
      },
    );
  }
}
