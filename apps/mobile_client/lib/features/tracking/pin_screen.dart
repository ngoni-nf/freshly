import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final completionPinProvider =
    FutureProvider.autoDispose.family<String, String>(
  (ref, bookingId) => ref.watch(apiProvider).completionPin(bookingId),
);

/// Screen A.14 — the completion code.
///
/// This four-digit number is the whole escrow release mechanism. The customer
/// holds it, the pro types it, and the platform captures only then. It means
/// "the job is done" is asserted by the person who paid, not by the person
/// being paid.
class PinScreen extends ConsumerWidget {
  const PinScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pin = ref.watch(completionPinProvider(bookingId));

    return Scaffold(
      appBar: AppBar(title: const Text('Completion code')),
      body: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: FreshlySpacing.xl),
            const Text(
              'Share this code with your pro once you are happy with the service.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, height: 1.5, color: FreshlyColors.inkMuted),
            ),
            const SizedBox(height: FreshlySpacing.xl),
            pin.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, __) => Center(
                child: Text(e is ApiException ? e.message : 'Could not load your code'),
              ),
              data: (code) => Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: code.split('').map((digit) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    width: 64, height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: FreshlyColors.mintSoft,
                      borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                      border: Border.all(color: FreshlyColors.mint, width: 2),
                    ),
                    child: Text(digit,
                        style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: FreshlyColors.mintDark)),
                  );
                }).toList(),
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              decoration: BoxDecoration(
                color: FreshlyColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(FreshlySpacing.radius),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: FreshlyColors.gold),
                SizedBox(width: FreshlySpacing.sm),
                Expanded(
                  child: Text(
                    'Do not share this code before the service is finished. '
                    'Once entered, payment is released to your pro.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
