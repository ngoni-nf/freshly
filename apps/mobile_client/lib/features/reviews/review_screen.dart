import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../history/booking_detail_screen.dart';
import '../history/invoices.dart';

/// The tags a client can pin on a review. Free strings on the wire; this is
/// the client-side vocabulary, and the provider app has its own.
const reviewTags = [
  'On time',
  'Great cut',
  'Friendly',
  'Clean kit',
  'Professional',
  'Would rebook',
];

/// Screen A.15 — rate the pro after a completed job.
///
/// Double-sided: the pro rates the client too, and neither side sees the
/// other's review until both are in or fourteen days pass. That is what stops
/// a rating from being a reply.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _rating = 0;
  final _tags = <String>{};
  final _comment = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final comment = _comment.text.trim();
      await ref.read(apiProvider).submitReview(
            widget.bookingId,
            rating: _rating,
            tags: _tags.toList(),
            comment: comment.isEmpty ? null : comment,
          );
      if (!mounted) return;
      refreshBookingLists(ref, widget.bookingId);
      setState(() => _done = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingDetailProvider(widget.bookingId));
    final name = booking.valueOrNull?.providerName ?? 'your pro';
    final text = Theme.of(context).textTheme;

    if (_done) return _Thanks(bookingId: widget.bookingId, name: name);

    return Scaffold(
      appBar: AppBar(title: const Text('Rate your pro')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.sm,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          Center(
            child: Column(
              children: [
                FreshlyAvatar(name: name, size: 72),
                const SizedBox(height: FreshlySpacing.md),
                Text('How was $name?',
                    textAlign: TextAlign.center, style: text.headlineMedium),
                const SizedBox(height: 4),
                Text(
                    booking.valueOrNull == null
                        ? ''
                        : 'Booking ${booking.valueOrNull!.reference}',
                    style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          _Stars(value: _rating, onChanged: (v) => setState(() => _rating = v)),
          const SizedBox(height: 6),
          Center(
            child: Text(_ratingLabel(_rating),
                style: text.titleMedium?.copyWith(
                    color: _rating == 0
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.onSurface)),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          const SectionHeader(
              title: 'What stood out?', padding: EdgeInsets.only(bottom: 10)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in reviewTags)
                FilterChip(
                  label: Text(tag),
                  // The theme's selected fill is obsidian (white in dark);
                  // FilterChip does not pick up secondaryLabelStyle, so the
                  // ink is set here or the label vanishes on selection.
                  labelStyle: FreshlyType.style(13,
                      weight: FontWeight.w600,
                      color: _tags.contains(tag)
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? FreshlyColors.obsidian
                              : Colors.white)
                          : Theme.of(context).colorScheme.onSurface),
                  selected: _tags.contains(tag),
                  onSelected: (on) => setState(() {
                    on ? _tags.add(tag) : _tags.remove(tag);
                  }),
                ),
            ],
          ),
          const SizedBox(height: FreshlySpacing.lg),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Anything else? (optional)',
              counterText: '',
            ),
          ),
          const SizedBox(height: FreshlySpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FreshlyIcons.info,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Reviews are shown once both of you have reviewed, or '
                    'after 14 days.',
                    style: text.bodySmall),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: FreshlySpacing.sm),
            Text(_error!,
                style: FreshlyType.style(14,
                    weight: FontWeight.w600, color: FreshlyColors.crimson)),
          ],
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          onPressed: _rating > 0 && !_busy ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: FreshlyColors.obsidian))
              : const Text('Submit review'),
        ),
      ),
    );
  }
}

String _ratingLabel(int rating) => switch (rating) {
      1 => 'Not good',
      2 => 'Could be better',
      3 => 'Okay',
      4 => 'Good',
      5 => 'Excellent',
      _ => 'Tap a star',
    };

/// Five large stars. Each is a full 56-point target: this is pressed with a
/// thumb, often one-handed, often on a small phone.
class _Stars extends StatelessWidget {
  const _Stars({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final off = Theme.of(context).colorScheme.outline;
    return Semantics(
      label: 'Rating',
      value: value == 0 ? 'none' : '$value of 5',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i ${i == 1 ? 'star' : 'stars'}',
              iconSize: 44,
              constraints: const BoxConstraints.tightFor(width: 60, height: 60),
              onPressed: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              icon: Icon(
                i <= value ? FreshlyIcons.star : CupertinoIcons.star,
                color: i <= value ? FreshlyColors.gold : off,
              ),
            ),
        ],
      ),
    );
  }
}

/// The success state: thanks, the invoice to keep, and the way back.
class _Thanks extends StatelessWidget {
  const _Thanks({required this.bookingId, required this.name});
  final String bookingId;
  final String name;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Thank you'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.md,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          const Center(
            child: IconBadge(
                icon: FreshlyIcons.checkCircle,
                size: 72,
                tone: FreshlyTone.success),
          ),
          const SizedBox(height: FreshlySpacing.md),
          Text('Review sent',
              textAlign: TextAlign.center, style: text.headlineMedium),
          const SizedBox(height: 6),
          Text(
              '$name will see it once they have reviewed you too, or in '
              '14 days.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: FreshlySpacing.xl),
          const SectionHeader(
              title: 'Your invoice', padding: EdgeInsets.only(bottom: 12)),
          InvoiceList(bookingId: bookingId),
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          onPressed: () => context.go('/bookings'),
          child: const Text('Done'),
        ),
      ),
    );
  }
}
