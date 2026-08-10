import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../home/dashboard_screen.dart' show recentBookingsProvider;

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(recentBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: bookings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
            child: Text(e is ApiException ? e.message : 'Could not load')),
        data: (list) => list.isEmpty
            ? const Center(child: Text('No bookings yet.'))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(recentBookingsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: FreshlySpacing.sm),
                  itemBuilder: (_, i) {
                    final b = list[i];
                    return Card(
                      child: ListTile(
                        title: Text(b.providerName ?? 'Freshly booking'),
                        subtitle:
                            Text('${b.reference} · ${b.status.clientLabel}'),
                        trailing: Text(b.total.format(),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        onTap: b.status.isLive
                            ? () => context.push('/track/${b.id}')
                            : null,
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
