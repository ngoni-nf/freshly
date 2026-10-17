import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final completionPinProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, bookingId) => ref.watch(apiProvider).completionPin(bookingId),
);

/// Screen A.14 — the client's code.
///
/// The pro types this four-digit number on arrival, and the server moves the
/// booking to in_progress only then (BookingsService.verifyPin). It proves the
/// person at the door is the pro who was booked. Capture happens later, when
/// the pro marks the job complete. The copy here describes exactly that: a
/// customer told "do not share until the job is done" refuses at the door and
/// the job can never start.
class PinScreen extends ConsumerWidget {
  const PinScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin = ref.watch(completionPinProvider(bookingId));

    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your code')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                    FreshlySpacing.xl, FreshlySpacing.lg, FreshlySpacing.xl),
                decoration: BoxDecoration(
                  color: FreshlyColors.obsidian,
                  borderRadius:
                      BorderRadius.circular(FreshlySpacing.radiusLarge),
                ),
                child: Column(
                  children: [
                    const IconBadge(
                        icon: FreshlyIcons.lock,
                        size: 52,
                        tone: FreshlyTone.brand),
                    const SizedBox(height: FreshlySpacing.md),
                    Text('Your code',
                        style: text.titleMedium
                            ?.copyWith(color: FreshlyColors.inkMuted)),
                    const SizedBox(height: FreshlySpacing.md),
                    pin.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(FreshlySpacing.lg),
                        child: CircularProgressIndicator(
                            color: FreshlyColors.mint),
                      ),
                      error: (e, __) => Text(
                          e is ApiException
                              ? e.message
                              : 'Could not load your code',
                          textAlign: TextAlign.center,
                          style:
                              text.bodyMedium?.copyWith(color: Colors.white)),
                      data: (code) => Semantics(
                        label: 'Completion code ${code.split('').join(' ')}',
                        child: ExcludeSemantics(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final digit in code.split(''))
                                Container(
                                  margin:
                                      const EdgeInsets.symmetric(horizontal: 5),
                                  width: 62,
                                  height: 80,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: FreshlyColors.obsidianRaised,
                                    borderRadius: BorderRadius.circular(
                                        FreshlySpacing.radius),
                                    border: Border.all(
                                        color: FreshlyColors.mint
                                            .withValues(alpha: 0.5),
                                        width: 1.5),
                                  ),
                                  child: Text(digit,
                                      style: FreshlyType.style(40,
                                          weight: FontWeight.w800,
                                          color: FreshlyColors.mint)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              Text('How it works', style: text.titleLarge),
              const SizedBox(height: 12),
              const _Step(n: '1', text: 'Your pro finishes the service.'),
              const _Step(
                  n: '2',
                  text: 'You check you are happy with it, then read them '
                      'this code.'),
              const _Step(
                  n: '3',
                  text: 'They enter it, and only then is your payment '
                      'released to them.'),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                decoration: BoxDecoration(
                  color: FreshlyColors.loadSheddingSoft,
                  borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                ),
                child: Row(children: [
                  const Icon(FreshlyIcons.warning,
                      color: FreshlyColors.loadSheddingInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Only give this code to your pro, in person at your '
                      'door. Never over the phone or by message.',
                      style: FreshlyType.style(13,
                          weight: FontWeight.w600,
                          height: 1.45,
                          color: FreshlyColors.loadSheddingInk),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final String n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: FreshlyColors.mint, shape: BoxShape.circle),
            child: Text(n,
                style: FreshlyType.style(13,
                    weight: FontWeight.w800, color: FreshlyColors.obsidian)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
