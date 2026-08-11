import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';

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
    try {
      await ref.read(apiProvider).updateClientNotes(widget.clientId, _notesController.text);
      ref.invalidate(clientDetailProvider(widget.clientId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notes saved')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _savingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(clientDetailProvider(widget.clientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Client Detail')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(child: Text(err.toString())),
        data: (client) {
          // Sync controller with initial notes from server
          if (_notesController.text.isEmpty && client.notes.isNotEmpty) {
            _notesController.text = client.notes;
          }

          return ListView(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundImage: client.avatarUrl != null
                        ? CachedNetworkImageProvider(client.avatarUrl!)
                        : null,
                    backgroundColor: FreshlyColors.mintSoft,
                    child: client.avatarUrl == null
                        ? Text(client.fullName.characters.first.toUpperCase(),
                            style: const TextStyle(fontSize: 32, color: FreshlyColors.mintDark))
                        : null,
                  ),
                  const SizedBox(width: FreshlySpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(client.fullName,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 16, color: FreshlyColors.gold),
                            Text(' ${client.rating.toStringAsFixed(1)} (${client.ratingCount})'),
                            const Text('  ·  '),
                            Text('Since ${formatDate(client.joinedAt)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FreshlySpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('tel:${client.phone}')),
                      icon: const Icon(Icons.phone_outlined),
                      label: const Text('Call'),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse('sms:${client.phone}')),
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('Message'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FreshlySpacing.xl),
              const Text('Private Notes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              TextField(
                controller: _notesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add notes about styles, allergies, or preferences...',
                  helperText: 'Only you can see these notes.',
                ),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _savingNotes ? null : _saveNotes,
                  child: _savingNotes ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save Notes'),
                ),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              const Text('Booking History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              if (client.history.isEmpty)
                const Text('No bookings yet.', style: TextStyle(color: FreshlyColors.inkMuted))
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
    return Card(
      margin: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: ListTile(
        title: Text(item.services.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${item.reference} · ${formatDate(item.createdAt)}'),
        trailing: Text(item.total.format(), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
