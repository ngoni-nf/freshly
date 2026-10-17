import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/job_tile.dart' show JobTileSkeleton;

class ClientListScreen extends ConsumerWidget {
  const ClientListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clients = ref.watch(myClientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My clients')),
      body: clients.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [JobTileSkeleton(count: 5)],
        ),
        error: (err, __) => EmptyState(
          icon: FreshlyIcons.people,
          title: 'Clients did not load',
          message: err is ApiException
              ? err.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myClientsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: FreshlyIcons.people,
              title: 'No clients yet',
              message: 'Everyone you serve is added here automatically, with '
                  'their history and your private notes.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: FreshlySpacing.sm),
            itemBuilder: (context, i) {
              final client = list[i];
              final text = Theme.of(context).textTheme;
              return Card(
                child: InkWell(
                  onTap: () => context.push('/clients/${client.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        FreshlyAvatar(
                          name: client.fullName,
                          size: 48,
                          image: client.avatarUrl == null
                              ? null
                              : CachedNetworkImage(
                                  imageUrl: client.avatarUrl!,
                                  fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(client.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                  'Last visit ${formatDate(client.lastBookingAt)}',
                                  style: text.bodySmall),
                            ],
                          ),
                        ),
                        StatusPill(
                          label:
                              '${client.bookingCount} job${client.bookingCount == 1 ? '' : 's'}',
                          dense: true,
                        ),
                        const SizedBox(width: 4),
                        Icon(FreshlyIcons.chevronRight,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
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
}
