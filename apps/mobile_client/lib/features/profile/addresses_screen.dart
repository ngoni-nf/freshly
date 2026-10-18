import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final savedAddressesProvider = FutureProvider.autoDispose<List<SavedAddress>>(
    (ref) => ref.watch(apiProvider).savedAddresses());

/// Places you book to, managed.
///
/// The same picker the booking flow uses, so an address saved here and an
/// address typed at checkout go through one path and cannot disagree about
/// what is servable.
class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final area = ref.read(serviceAreaProvider);
    final picked = await AddressPickerSheet.show(
      context,
      api: ref.read(apiProvider),
      countryCode: ref.read(countryCodeProvider),
      nearLat: area?.lat,
      nearLng: area?.lng,
    );
    if (picked == null || !context.mounted) return;

    // The label is what makes a saved address useful — "Mom's" is findable in
    // a list, "14 Oxford Road" is another address to read.
    final label = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Name this address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(picked.formatted,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: FreshlySpacing.md),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Home, Work, Mom’s',
                ),
                onSubmitted: (v) => Navigator.pop(context, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (label == null || label.isEmpty || !context.mounted) return;

    try {
      await ref.read(apiProvider).saveAddress(
            label: label,
            formatted: picked.formatted,
            lat: picked.lat,
            lng: picked.lng,
          );
      ref.invalidate(savedAddressesProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, SavedAddress address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${address.label}?'),
        content: Text(address.formatted),
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
      await ref.read(apiProvider).deleteAddress(address.id);
      ref.invalidate(savedAddressesProvider);
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved addresses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(FreshlyIcons.add),
        label: const Text('Add address'),
      ),
      body: addresses.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 76, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.sm),
            Skeleton(height: 76, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Addresses did not load',
          message: e is ApiException
              ? e.message
              : 'We could not load your addresses.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(savedAddressesProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: FreshlyIcons.location,
              title: 'No saved addresses yet',
              message: 'Save the places you book to often and they will be '
                  'one tap at checkout.',
            );
          }

          return ListView(
            padding: const EdgeInsets.only(top: FreshlySpacing.sm, bottom: 96),
            children: list
                .map((a) => Card(
                      margin: const EdgeInsets.fromLTRB(FreshlySpacing.md, 0,
                          FreshlySpacing.md, FreshlySpacing.sm),
                      child: ListTile(
                        leading: IconBadge(
                          icon: FreshlyIcons.location,
                          size: 40,
                          tone: a.isDefault
                              ? FreshlyTone.brand
                              : FreshlyTone.neutral,
                        ),
                        title: Row(children: [
                          Flexible(
                            child:
                                Text(a.label, overflow: TextOverflow.ellipsis),
                          ),
                          if (a.isDefault) ...[
                            const SizedBox(width: 8),
                            const StatusPill(
                                label: 'Default',
                                tone: FreshlyTone.brand,
                                dense: true),
                          ],
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.formatted),
                            if (a.accessNotes != null &&
                                a.accessNotes!.isNotEmpty)
                              Text(a.accessNotes!,
                                  style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                        isThreeLine: a.accessNotes?.isNotEmpty ?? false,
                        trailing: IconButton(
                          icon: const Icon(FreshlyIcons.delete),
                          color: FreshlyColors.inkMuted,
                          onPressed: () => _remove(context, ref, a),
                        ),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
