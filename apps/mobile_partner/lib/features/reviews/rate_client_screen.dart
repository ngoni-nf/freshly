import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/business_form.dart' show InlineError;
import '../job/job_providers.dart';

/// The provider's side of the double-sided review.
///
/// Neither side sees the other's words until both have written theirs or a
/// fortnight has passed, so a rating cannot be written in reply to one. The
/// screen says so in one line, because a pro who thinks the client will read
/// this tonight writes something different from one who knows they will not.
class RateClientScreen extends ConsumerStatefulWidget {
  const RateClientScreen({required this.bookingId, super.key});
  final String bookingId;

  /// The tags offered to providers. Free strings on the wire; this list is
  /// the provider app's vocabulary, agreed in the API contract.
  static const tags = [
    'On time',
    'Clear directions',
    'Friendly',
    'Respectful',
    'Easy to find',
    'Would work again',
  ];

  @override
  ConsumerState<RateClientScreen> createState() => _RateClientScreenState();
}

class _RateClientScreenState extends ConsumerState<RateClientScreen> {
  int _rating = 0;
  final _picked = <String>{};
  final _comment = TextEditingController();
  bool _busy = false;
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
            tags: _picked.toList(),
            comment: comment.isEmpty ? null : comment,
          );
      _done();
    } on ApiException catch (e) {
      if (!mounted) return;
      // Already rated means the earlier tap went through; nothing to redo.
      if (e.code == 'already_reviewed') {
        _done();
        return;
      }
      setState(() => _error = switch (e.code) {
            'booking_not_completed' =>
              'You can rate the client once the job is finished.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    if (!mounted) return;
    ref.invalidate(jobProvider(widget.bookingId));
    ref.invalidate(scheduleProvider);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  static String _word(int rating) => switch (rating) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Great',
        5 => 'Excellent',
        _ => 'Tap a star',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate your client'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _done,
            child: const Text('Skip'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(FreshlySpacing.lg, FreshlySpacing.sm,
                  FreshlySpacing.lg, FreshlySpacing.lg + inset),
              children: [
                const ScreenIntro(
                  eyebrow: 'Job complete',
                  title: 'How did it go?',
                  subtitle: 'Other pros see your rating before they accept '
                      'this client. Reviews are shown once both sides have '
                      'reviewed, or after 14 days.',
                ),
                const SizedBox(height: FreshlySpacing.lg),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: FreshlySpacing.lg, horizontal: 12),
                    child: Column(
                      children: [
                        Semantics(
                          label: _rating == 0
                              ? 'Rating, not set'
                              : 'Rating, $_rating out of 5 stars',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 1; i <= 5; i++)
                                _Star(
                                  filled: i <= _rating,
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _rating = i);
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(_word(_rating),
                            style: FreshlyType.style(15,
                                weight: FontWeight.w700,
                                color: _rating == 0
                                    ? scheme.onSurfaceVariant
                                    : scheme.onSurface)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                Text('What stood out?', style: text.titleMedium),
                const SizedBox(height: FreshlySpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in RateClientScreen.tags)
                      FilterChip(
                        label: Text(tag),
                        selected: _picked.contains(tag),
                        // The theme's chip label is ink in every state, which
                        // vanishes on the obsidian selected fill.
                        labelStyle: FreshlyType.style(13,
                            weight: FontWeight.w600,
                            color: _picked.contains(tag)
                                ? (isDark
                                    ? FreshlyColors.obsidian
                                    : Colors.white)
                                : scheme.onSurface),
                        showCheckmark: false,
                        onSelected: (on) => setState(
                            () => on ? _picked.add(tag) : _picked.remove(tag)),
                      ),
                  ],
                ),
                const SizedBox(height: FreshlySpacing.lg),
                Text('Anything else?', style: text.titleMedium),
                const SizedBox(height: 4),
                Text('Optional. Keep it about the job.', style: text.bodySmall),
                const SizedBox(height: FreshlySpacing.sm),
                TextField(
                  controller: _comment,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                      hintText: 'Gate was easy to find, lovely to work with.'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FreshlySpacing.sm),
                  InlineError(message: _error!),
                ],
              ],
            ),
          ),
          StickyActionBar(
            child: FilledButton(
              onPressed: _rating == 0 || _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: FreshlyColors.obsidian))
                  : const Text('Send rating'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.filled, required this.onTap});
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return InkResponse(
      onTap: onTap,
      radius: 30,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedScale(
          scale: filled ? 1 : 0.88,
          duration: still ? Duration.zero : const Duration(milliseconds: 140),
          child: Icon(
            FreshlyIcons.star,
            size: 48,
            color: filled
                ? FreshlyColors.gold
                : Theme.of(context).colorScheme.outline,
          ),
        ),
      ),
    );
  }
}
