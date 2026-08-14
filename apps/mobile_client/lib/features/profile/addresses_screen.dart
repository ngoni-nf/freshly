import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final savedAddressesProvider =
    FutureProvider.autoDispose<List<SavedAddress>>((ref) =>
        ref.watch(apiProvider).savedAddresses());

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
                  style: const TextStyle(color: FreshlyColors.inkMuted)),
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.lg),
            child: Text(
              e is ApiException ? e.message : 'We could not load your addresses',
              textAlign: TextAlign.center,
              style: const TextStyle(color: FreshlyColors.inkMuted),
            ),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(FreshlySpacing.xl),
                child: Text(
                  'No saved addresses yet.\n\nSave the places you book to often '
                  'and they will be one tap at checkout.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FreshlyColors.inkMuted, height: 1.5),
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.only(
                top: FreshlySpacing.sm, bottom: 96),
            children: list
                .map((a) => Card(
                      margin: const EdgeInsets.fromLTRB(FreshlySpacing.md, 0,
                          FreshlySpacing.md, FreshlySpacing.sm),
                      child: ListTile(
                        leading: Icon(
                          a.isDefault
                              ? FreshlyIcons.checkCircle
                              : FreshlyIcons.location,
                          color: a.isDefault
                              ? FreshlyColors.mint
                              : FreshlyColors.inkMuted,
                        ),
                        title: Row(children: [
                          Text(a.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          if (a.isDefault) ...[
                            const SizedBox(width: 8),
                            const Text('Default',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: FreshlyColors.mintDark)),
                          ],
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.formatted),
                            if (a.accessNotes != null &&
                                a.accessNotes!.isNotEmpty)
                              Text(a.accessNotes!,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: FreshlyColors.inkMuted)),
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
