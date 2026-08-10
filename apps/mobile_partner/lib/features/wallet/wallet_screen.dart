import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

/// Screen B.13 — wallet and cash-out.
///
/// Two balances, explained in plain language. "Held in escrow" is the number
/// providers query support about most: it is money they have earned but that
/// the client has not released yet, and if the app does not say so clearly
/// they assume the platform is holding their money arbitrarily.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _busy = false;

  Future<void> _cashOut(int availableMinor, String currency) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cash out',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: FreshlySpacing.md),
            Text(formatMinor(availableMinor, currency),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: FreshlySpacing.sm),
            const Text(
              'Instant payouts carry a small fee. The free daily batch settles '
              'to your bank overnight.',
              style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: FreshlySpacing.lg),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send to my bank'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).requestPayout(
            availableMinor,
            idempotencyKey: 'payout-${DateTime.now().millisecondsSinceEpoch}',
          );
      ref.invalidate(walletProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payout requested. You will get an SMS when it lands.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Text(e is ApiException ? e.message : 'Could not load your wallet'),
        ),
        data: (data) {
          final currency = data['currency'] as String? ?? 'ZAR';
          final available = (data['availableMinor'] as num?)?.toInt() ?? 0;
          final pending = (data['pendingMinor'] as num?)?.toInt() ?? 0;
          final lifetime = (data['lifetimeEarnedMinor'] as num?)?.toInt() ?? 0;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(walletProvider),
            child: ListView(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FreshlySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available to cash out',
                            style: TextStyle(color: FreshlyColors.inkMuted)),
                        const SizedBox(height: 4),
                        Text(formatMinor(available, currency),
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                        const SizedBox(height: FreshlySpacing.md),
                        FilledButton(
                          onPressed: available <= 0 || _busy
                              ? null
                              : () => _cashOut(available, currency),
                          child: Text(_busy ? 'Sending…' : 'Cash out'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.lock_clock_outlined),
                    title: Text(formatMinor(pending, currency),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text(
                      'Held in escrow — released to you when each client confirms '
                      'the job is done with their code.',
                    ),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.trending_up),
                    title: Text(formatMinor(lifetime, currency),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Earned with Freshly, all time'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
