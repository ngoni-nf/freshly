import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../home/dashboard_screen.dart' show recentBookingsProvider;

final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>(
  (ref) => ref.watch(apiProvider).myTickets(),
);

/// Help and support: raise a ticket, read the replies, add to the thread.
///
/// Tickets land in the ops console's client queue. There is no live chat here
/// on purpose: a client in danger mid-job presses SOS, and everything else
/// can wait for a human who has the booking open in front of them.
class SupportScreen extends ConsumerWidget {
  const SupportScreen({this.initialTicketId, super.key});

  /// The thread to open on arrival: a push about a reply lands here.
  final String? initialTicketId;

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
          title: 'Your requests did not load',
          message: e is ApiException ? e.message : 'Try again in a moment.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myTicketsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: FreshlyIcons.message,
              title: 'How can we help?',
              message: 'A payment, a booking, your account, the app: tell us '
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
              itemBuilder: (context, i) => _TicketCard(
                  key: ValueKey(list[i].id),
                  ticket: list[i],
                  initiallyOpen: list[i].id == initialTicketId),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => NewTicketSheet.show(context),
        icon: const Icon(FreshlyIcons.add),
        label: const Text('New request'),
      ),
    );
  }
}

class _TicketCard extends ConsumerStatefulWidget {
  const _TicketCard(
      {required this.ticket, this.initiallyOpen = false, super.key});
  final SupportTicket ticket;
  final bool initiallyOpen;

  @override
  ConsumerState<_TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends ConsumerState<_TicketCard> {
  final _reply = TextEditingController();
  late bool _open = widget.initiallyOpen;
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

/// The "new request" form, as a sheet.
///
/// With a [booking] it becomes "Report a problem" for that booking: the
/// subject is prefilled with the reference and the ticket carries the
/// booking id, so the ops console opens with the right job on screen.
class NewTicketSheet extends ConsumerStatefulWidget {
  const NewTicketSheet({this.booking, super.key});
  final Booking? booking;

  /// Resolves once the sheet closes; true if a ticket was raised.
  static Future<bool> show(BuildContext context, {Booking? booking}) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NewTicketSheet(booking: booking),
    );
    return sent ?? false;
  }

  @override
  ConsumerState<NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<NewTicketSheet> {
  late final TextEditingController _subject;
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Chosen from the picker when the sheet was opened without a booking.
  Booking? _picked;

  Booking? get _booking => widget.booking ?? _picked;

  @override
  void initState() {
    super.initState();
    final b = widget.booking;
    _subject = TextEditingController(
        text: b == null ? '' : 'Problem with booking ${b.reference}');
  }

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
            raisedBy: 'client',
            bookingId: _booking?.id,
          );
      if (!mounted) return;
      ref.invalidate(myTicketsProvider);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final forBooking = widget.booking != null;
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
              Text(
                  forBooking
                      ? 'What went wrong?'
                      : 'What do you need help with?',
                  style: Theme.of(context).textTheme.headlineSmall),
              if (forBooking) ...[
                const SizedBox(height: 4),
                Text(
                    'A person on the Freshly team reads this with your '
                    'booking open. If you are in danger right now, use SOS '
                    'instead.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              const SizedBox(height: FreshlySpacing.md),
              if (!forBooking) ...[
                _BookingPicker(
                  value: _picked,
                  onChanged: (b) => setState(() => _picked = b),
                ),
                const SizedBox(height: FreshlySpacing.sm),
              ],
              TextField(
                controller: _subject,
                autofocus: !forBooking,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'In a few words'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              TextField(
                controller: _body,
                autofocus: forBooking,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    hintText: forBooking
                        ? 'Tell us what happened.'
                        : 'Tell us what happened and how we can help.'),
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

/// "Which booking is this about?" for a request raised from the support
/// list. Optional: an account or app question has no booking. The list is
/// the same recent bookings the Bookings tab shows, so there is nothing new
/// to load and nothing to type.
class _BookingPicker extends ConsumerWidget {
  const _BookingPicker({required this.value, required this.onChanged});
  final Booking? value;
  final ValueChanged<Booking?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(recentBookingsProvider).valueOrNull ?? const [];
    if (bookings.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: value?.id,
      isExpanded: true,
      decoration:
          const InputDecoration(hintText: 'About a booking? (optional)'),
      items: [
        const DropdownMenuItem<String>(
            value: null, child: Text('Not about a booking')),
        for (final b in bookings)
          DropdownMenuItem<String>(
            value: b.id,
            child: Text(
              '${b.reference} · ${b.providerName ?? 'Freshly'} · '
              '${formatDate(b.scheduledStart ?? b.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) =>
          onChanged(id == null ? null : bookings.firstWhere((b) => b.id == id)),
    );
  }
}
