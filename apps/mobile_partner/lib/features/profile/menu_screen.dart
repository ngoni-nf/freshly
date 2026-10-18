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
                  child: Text(
                      'Tap a service to change its price. Swipe left to '
                      'remove it.',
                      style: text.bodySmall),
                );
              }
              final item = items[i - 1];
              return _MenuRow(
                item: item,
                onEdit: () => _showEditPriceDialog(context, ref, item),
                onRemove: () => _confirmRemove(context, ref, item),
              );
            },
          );
        },
      ),
    );
  }

  /// Taking a service off the menu is reversible only by adding it again at
  /// a price, so it is confirmed. Past bookings keep their own copy of the
  /// name and price; nothing the client already paid for changes.
  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, ProviderMenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text(
          'Clients will no longer be able to book it. You can add it back '
          'from the catalogue at any time.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FreshlyColors.crimson),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(apiProvider).removeMenuItem(item.id);
      ref.invalidate(myMenuProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
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
    // Repricing re-posts the template at the new price. A service that was
    // not built from the catalogue has no template to post, so the only way
    // to change it is to remove it and add the catalogue version.
    final templateId = item.catalogServiceId;
    if (templateId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This service predates the catalogue. Remove it and '
              'add it again from the catalogue to set a new price.')));
      return;
    }
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
                      templateId: templateId,
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

/// One service on the menu. Tap to reprice; swipe or use the menu to remove.
class _MenuRow extends StatelessWidget {
  const _MenuRow(
      {required this.item, required this.onEdit, required this.onRemove});
  final ProviderMenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey('menu-${item.id}'),
      direction: DismissDirection.endToStart,
      // The confirmation dialog owns the removal, so the row is never
      // dismissed optimistically and then put back when the call fails.
      confirmDismiss: (_) async {
        onRemove();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.lg),
        decoration: BoxDecoration(
          color: FreshlyColors.crimsonSoft,
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        ),
        child:
            const Icon(FreshlyIcons.delete, color: Color(0xFFB4232A), size: 22),
      ),
      child: Card(
        child: InkWell(
          onTap: onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
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
                    style: text.titleMedium?.copyWith(color: scheme.primary)),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                  onSelected: (v) => v == 'remove' ? onRemove() : onEdit(),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'price', child: Text('Change price')),
                    PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove from menu',
                          style: FreshlyType.style(15,
                              weight: FontWeight.w600,
                              color: FreshlyColors.crimson)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
                      templateId: service.id,
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
