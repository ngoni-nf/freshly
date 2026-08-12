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

  /// The fee is quoted before the provider commits, not discovered afterwards
  /// in the history list. `instant` is null when they backed out.
  Future<void> _cashOut(
      int availableMinor, String currency, int instantFeeBps) async {
    final feeMinor = (availableMinor * instantFeeBps / 10000).round();

    final instant = await showModalBottomSheet<bool>(
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
                style:
                    const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
            const SizedBox(height: FreshlySpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(FreshlyIcons.schedule),
              title: const Text('Free — overnight batch'),
              subtitle:
                  Text('You receive ${formatMinor(availableMinor, currency)}'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(FreshlyIcons.bolt),
              title: Text('Instant — ${formatMinor(feeMinor, currency)} fee'),
              subtitle: Text(
                  'You receive ${formatMinor(availableMinor - feeMinor, currency)}'),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: FreshlySpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );

    if (instant == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await ref.read(apiProvider).requestPayout(
            availableMinor,
            idempotencyKey: 'payout-${DateTime.now().millisecondsSinceEpoch}',
            instant: instant,
          );
      ref.invalidate(walletProvider);
      if (mounted) {
        final netMinor =
            (result['netMinor'] as num?)?.toInt() ?? availableMinor;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${formatMinor(netMinor, currency)} on the way. '
              'You will get an SMS when it lands.',
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Why the button is disabled, in the provider's words rather than ours.
  /// A greyed-out control with no explanation is a support ticket.
  static String? _blockedMessage(String? reason) => switch (reason) {
        'kyc_required' => 'Finish identity verification to cash out.',
        'payout_account_missing' =>
          'Add a bank or mobile money account to cash out.',
        'payout_account_unverified' =>
          'Your payout account is still being verified.',
        'below_minimum' => 'Your balance is below the minimum cash-out.',
        'account_suspended' => 'Your account is on hold. Contact support.',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: wallet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Text(
              e is ApiException ? e.message : 'Could not load your wallet'),
        ),
        data: (data) {
          final currency = data['currency'] as String? ?? 'ZAR';
          final available = (data['availableMinor'] as num?)?.toInt() ?? 0;
          final pending = (data['pendingMinor'] as num?)?.toInt() ?? 0;
          final lifetime = (data['lifetimeEarnedMinor'] as num?)?.toInt() ?? 0;
          final instantFeeBps = (data['instantFeeBps'] as num?)?.toInt() ?? 150;
          final canCashOut = data['canCashOut'] as bool? ?? false;
          final blocked = _blockedMessage(data['blockedReason'] as String?);

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
                            style: const TextStyle(
                                fontSize: 38, fontWeight: FontWeight.w800)),
                        const SizedBox(height: FreshlySpacing.md),
                        FilledButton(
                          onPressed: !canCashOut || _busy
                              ? null
                              : () =>
                                  _cashOut(available, currency, instantFeeBps),
                          child: Text(_busy ? 'Sending…' : 'Cash out'),
                        ),
                        if (blocked != null) ...[
                          const SizedBox(height: FreshlySpacing.sm),
                          Text(blocked,
                              style: const TextStyle(
                                  color: FreshlyColors.inkMuted)),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(FreshlyIcons.lockClock),
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
                    leading: const Icon(FreshlyIcons.trendingUp),
                    title: Text(formatMinor(lifetime, currency),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Earned with Freshly, all time'),
                  ),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: FreshlySpacing.sm),
                  child: Text('Recent Earnings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                const _EarningsHistoryList(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EarningsHistoryList extends ConsumerWidget {
  const _EarningsHistoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(earningsHistoryProvider);

    return history.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(FreshlySpacing.md),
            child: Text('Completed jobs will appear here.', style: TextStyle(color: FreshlyColors.inkMuted)),
          );
        }
        return Column(
          children: list.map((t) => _TransactionCard(transaction: t)).toList(),
        );
      },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction});
  final EarningsTransaction transaction;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: ExpansionTile(
        title: Text(transaction.reference, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(formatDate(transaction.completedAt)),
        trailing: Text(transaction.netEarnings.format(),
            style: const TextStyle(fontWeight: FontWeight.w700, color: FreshlyColors.mintDark)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _BreakdownRow(label: 'Service total', value: formatMinor(transaction.serviceMinor, transaction.currency)),
                _BreakdownRow(label: 'Travel fee', value: formatMinor(transaction.travelMinor, transaction.currency)),
                _BreakdownRow(
                  label: 'Commission',
                  value: '- ${formatMinor(transaction.commissionMinor, transaction.currency)}',
                  isNegative: true,
                ),
                const Divider(height: 16),
                _BreakdownRow(
                  label: 'Net earnings',
                  value: transaction.netEarnings.format(),
                  isBold: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.isNegative = false,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isNegative;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: FreshlyColors.inkMuted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: isNegative ? FreshlyColors.crimson : null,
            ),
          ),
        ],
      ),
    );
  }
}
