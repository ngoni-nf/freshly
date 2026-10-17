import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../widgets/job_status.dart';

class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({required this.clientId, super.key});
  final String clientId;

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  final _notesController = TextEditingController();
  bool _savingNotes = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    setState(() => _savingNotes = true);
    // Read before the await: a provider who backs out while the save is in
    // flight disposes this State, and touching `ref` after that throws.
    final api = ref.read(apiProvider);
    try {
      await api.updateClientNotes(widget.clientId, _notesController.text);
      // The detail provider is autoDispose, so once this screen is gone there
      // is no cached copy left to refresh.
      if (mounted) ref.invalidate(clientDetailProvider(widget.clientId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(clientDetailProvider(widget.clientId));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
      body: detail.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 120, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.md),
            Skeleton(height: 140, radius: FreshlySpacing.radius),
          ],
        ),
        error: (err, __) => EmptyState(
          icon: FreshlyIcons.person,
          title: 'This client did not load',
          message: err is ApiException
              ? err.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(clientDetailProvider(widget.clientId)),
        ),
        data: (client) {
          // Sync controller with initial notes from server
          if (_notesController.text.isEmpty && client.notes.isNotEmpty) {
            _notesController.text = client.notes;
          }

          return ListView(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          FreshlyAvatar(
                            name: client.fullName,
                            size: 64,
                            image: client.avatarUrl == null
                                ? null
                                : CachedNetworkImage(
                                    imageUrl: client.avatarUrl!,
                                    fit: BoxFit.cover),
                          ),
                          const SizedBox(width: FreshlySpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(client.fullName,
                                    style: text.headlineSmall),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    RatingLabel(
                                        rating: client.rating,
                                        count: client.ratingCount),
                                    Text('Since ${formatDate(client.joinedAt)}',
                                        style: text.bodySmall),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: FreshlySpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  launchUrl(Uri.parse('tel:${client.phone}')),
                              icon: const Icon(FreshlyIcons.phone, size: 18),
                              label: const Text('Call'),
                            ),
                          ),
                          const SizedBox(width: FreshlySpacing.sm),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  launchUrl(Uri.parse('sms:${client.phone}')),
                              icon: const Icon(FreshlyIcons.message, size: 18),
                              label: const Text('Message'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              const SectionHeader(
                title: 'Private notes',
                subtitle: 'Only you can see these.',
                padding: EdgeInsets.fromLTRB(4, 0, 4, FreshlySpacing.sm),
              ),
              TextField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Styles, allergies, preferences, gate code...',
                ),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(140, 48)),
                  onPressed: _savingNotes ? null : _saveNotes,
                  child: _savingNotes
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save notes'),
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              const SectionHeader(
                title: 'Booking history',
                padding: EdgeInsets.fromLTRB(4, 0, 4, FreshlySpacing.sm),
              ),
              if (client.history.isEmpty)
                const Card(
                  child: EmptyState(
                    compact: true,
                    icon: FreshlyIcons.calendar,
                    title: 'No bookings yet',
                  ),
                )
              else
                ...client.history.map((h) => _HistoryCard(item: h)),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item});
  final ClientHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.services.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text('${item.reference} · ${formatDate(item.createdAt)}',
                        style: text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(item.total.format(), style: text.titleMedium),
                  const SizedBox(height: 4),
                  StatusPill(
                      label: item.status.partnerLabel,
                      tone: item.status.tone,
                      dense: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
