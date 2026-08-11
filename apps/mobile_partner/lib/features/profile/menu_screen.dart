import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menu = ref.watch(myMenuProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Services'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddServiceSheet(context, ref),
            tooltip: 'Add service',
          ),
        ],
      ),
      body: menu.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.xl),
            child: Text(
              err is ApiException ? err.message : 'Could not load your menu',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FreshlyColors.inkMuted),
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(FreshlySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.style_outlined, size: 48, color: FreshlyColors.inkMuted),
                    const SizedBox(height: FreshlySpacing.md),
                    const Text(
                      'Your menu is empty. Add services you offer to start receiving jobs.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: FreshlySpacing.lg),
                    FilledButton(
                      onPressed: () => _showAddServiceSheet(context, ref),
                      child: const Text('Add my first service'),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.sm),
            itemBuilder: (context, i) {
              final item = items[i];
              return Card(
                child: ListTile(
                  title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(item.category.label),
                  trailing: Text(
                    item.price.format(),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: FreshlyColors.mintDark),
                  ),
                  onTap: () => _showEditPriceDialog(context, ref, item),
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

  void _showEditPriceDialog(BuildContext context, WidgetRef ref, ProviderMenuItem item) {
    final controller = TextEditingController(text: (item.price.minor / 100).toStringAsFixed(2));
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Price: ${item.name}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            prefixText: 'R ',
            labelText: 'Your price',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final val = double.tryParse(controller.text);
              if (val == null) return;
              try {
                await ref.read(apiProvider).updateMenuItem(
                      catalogServiceId: item.catalogServiceId,
                      priceMinor: (val * 100).round(),
                    );
                ref.invalidate(myMenuProvider);
                if (context.mounted) Navigator.pop(context);
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          title: Text(_category == null ? 'Choose Category' : _category!.label),
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
                    crossAxisSpacing: FreshlySpacing.md,
                    mainAxisSpacing: FreshlySpacing.md,
                  ),
                  itemCount: ServiceCategory.values.length,
                  itemBuilder: (context, i) {
                    final cat = ServiceCategory.values[i];
                    return InkWell(
                      onTap: () => setState(() => _category = cat),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.category_outlined, color: FreshlyColors.mint),
                          const SizedBox(height: 4),
                          Text(cat.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                        ],
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: const InputDecoration(
                prefixText: 'R ',
                labelText: 'Price',
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final val = double.tryParse(controller.text);
              if (val == null) return;
              try {
                await ref.read(apiProvider).updateMenuItem(
                      catalogServiceId: service.id,
                      priceMinor: (val * 100).round(),
                    );
                ref.invalidate(myMenuProvider);
                if (context.mounted) {
                  Navigator.pop(context); // dialog
                  Navigator.pop(context); // sheet
                }
              } on ApiException catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, __) => Center(child: Text(err.toString())),
      data: (list) => ListView.separated(
        itemCount: list.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final s = list[i];
          return ListTile(
            title: Text(s.name),
            subtitle: Text('${s.typicalDurationMinutes} min'),
            trailing: const Icon(Icons.add),
            onTap: () => onSelect(s),
          );
        },
      ),
    );
  }
}
