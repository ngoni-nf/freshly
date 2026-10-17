import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>(
  (ref) => ref.watch(apiProvider).myTickets(),
);

/// Help and support: raise a ticket, read the replies, add to the thread.
///
/// Tickets land in the ops console's provider queue. There is no live chat
/// here on purpose: a provider mid-job with a problem presses SOS, and
/// everything else can wait for a human who has the booking open.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tickets = ref.watch(myTicketsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Help and support')),
      body: tickets.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 92, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.sm),
            Skeleton(height: 92, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Your tickets did not load',
          message: e is ApiException ? e.message : 'Try again in a moment.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myTicketsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: FreshlyIcons.message,
              title: 'How can we help?',
              message: 'Payments, a client, your account, the app: tell us '
                  'and a person on the Freshly team replies here.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myTicketsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  FreshlySpacing.md, FreshlySpacing.xs, FreshlySpacing.md, 96),
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: FreshlySpacing.sm),
              itemBuilder: (context, i) => _TicketCard(ticket: list[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _NewTicketSheet.show(context, ref),
        icon: const Icon(FreshlyIcons.add),
        label: const Text('New request'),
      ),
    );
  }
}

class _TicketCard extends ConsumerStatefulWidget {
  const _TicketCard({required this.ticket});
  final SupportTicket ticket;

  @override
  ConsumerState<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<_TicketCard> {
  final _reply = TextEditingController();
  bool _open = false;
  bool _busy = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _reply.text.trim();
    if (body.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).addTicketMessage(widget.ticket.id, body);
      _reply.clear();
      ref.invalidate(myTicketsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.subject, style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                            '${formatDate(t.createdAt)} · '
                            '${t.messages.length} '
                            '${t.messages.length == 1 ? 'reply' : 'replies'}',
                            style: text.bodySmall),
                      ],
                    ),
                  ),
                  StatusPill(
                    label: t.isOpen ? 'Open' : 'Closed',
                    tone: t.isOpen ? FreshlyTone.info : FreshlyTone.neutral,
                    dense: true,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                      _open
                          ? FreshlyIcons.expandMore
                          : FreshlyIcons.chevronRight,
                      size: 16,
                      color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Bubble(body: t.body, isStaff: false, when: t.createdAt),
                  for (final m in t.messages)
                    _Bubble(
                        body: m.body, isStaff: m.isStaff, when: m.createdAt),
                  if (t.isOpen) ...[
                    const SizedBox(height: FreshlySpacing.sm),
                    TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add to this request',
                        suffixIcon: IconButton(
                          tooltip: 'Send',
                          onPressed: _busy ? null : _send,
                          icon: const Icon(FreshlyIcons.send),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.body, required this.isStaff, required this.when});
  final String body;
  final bool isStaff;
  final DateTime when;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(isStaff ? 'Freshly team' : 'You',
                  style: FreshlyType.style(12,
                      weight: FontWeight.w700,
                      color: isStaff ? scheme.primary : scheme.onSurface)),
              const SizedBox(width: 8),
              Text(formatSlot(when),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isStaff
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(FreshlySpacing.radiusSmall),
            ),
            child: Text(body, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  static Future<void> show(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _NewTicketSheet(),
      );

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _valid =>
      _subject.text.trim().length >= 3 && _body.text.trim().length >= 10;

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).raiseTicket(
            subject: _subject.text.trim(),
            body: _body.text.trim(),
            raisedBy: 'provider',
          );
      if (!mounted) return;
      ref.invalidate(myTicketsProvider);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What do you need help with?',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: FreshlySpacing.md),
              TextField(
                controller: _subject,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'In a few words'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'Tell us what happened. Mention the booking '
                        'reference if there is one.'),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                Text(_error!,
                    style: FreshlyType.style(14,
                        weight: FontWeight.w600, color: FreshlyColors.crimson)),
              ],
              const SizedBox(height: FreshlySpacing.md),
              FilledButton(
                onPressed: _valid && !_busy ? _submit : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.obsidian))
                    : const Text('Send to Freshly'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
