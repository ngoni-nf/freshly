import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class ClientListScreen extends ConsumerWidget {
  const ClientListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(myClientsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Clients'),
      ),
      body: clients.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(
          child: Text(err is ApiException ? err.message : 'Could not load clients'),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(FreshlySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline, size: 48, color: FreshlyColors.inkMuted),
                    SizedBox(height: FreshlySpacing.md),
                    Text(
                      'No clients yet. Your customer database grows automatically '
                      'as you complete bookings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.sm),
            itemBuilder: (context, i) {
              final client = list[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: client.avatarUrl != null
                        ? CachedNetworkImageProvider(client.avatarUrl!)
                        : null,
                    backgroundColor: FreshlyColors.mintSoft,
                    child: client.avatarUrl == null
                        ? Text(client.fullName.characters.first.toUpperCase(),
                            style: const TextStyle(color: FreshlyColors.mintDark))
                        : null,
                  ),
                  title: Text(client.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${client.bookingCount} job${client.bookingCount == 1 ? '' : 's'} · Last ${formatDate(client.lastBookingAt)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/clients/${client.id}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
