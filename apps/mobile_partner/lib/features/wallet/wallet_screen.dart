import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../widgets/job_tile.dart' show JobTileSkeleton;

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
    final feeMinor = applyBps(availableMinor, instantFeeBps);

    final instant = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cash out', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(formatMinor(availableMinor, currency),
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: FreshlySpacing.lg),
              _PayoutOption(
                icon: FreshlyIcons.schedule,
                tone: FreshlyTone.neutral,
                title: 'Overnight',
                badge: 'Free',
                subtitle:
                    'You receive ${formatMinor(availableMinor, currency)}',
                onTap: () => Navigator.pop(context, false),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              _PayoutOption(
                icon: FreshlyIcons.bolt,
                tone: FreshlyTone.brand,
                title: 'Instant',
                badge: '${formatMinor(feeMinor, currency)} fee',
                subtitle:
                    'You receive ${formatMinor(availableMinor - feeMinor, currency)}',
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
    final text = Theme.of(context).textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: wallet.when(
            loading: () => ListView(
              padding: EdgeInsets.zero,
              children: [
                const _Hero(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 120, height: 14),
                      SizedBox(height: 12),
                      Skeleton(width: 200, height: 44),
                      SizedBox(height: FreshlySpacing.lg),
                      Skeleton(height: 54, radius: FreshlySpacing.buttonRadius),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(FreshlySpacing.md),
                  child: JobTileSkeleton(count: 3),
                ),
              ],
            ),
            error: (e, __) => EmptyState(
              icon: FreshlyIcons.wallet,
              title: 'Your wallet did not load',
              message: e is ApiException
                  ? e.message
                  : 'Check your connection and try again.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(walletProvider),
            ),
            data: (data) {
              final currency = data['currency'] as String? ?? 'ZAR';
              final available = (data['availableMinor'] as num?)?.toInt() ?? 0;
              final pending = (data['pendingMinor'] as num?)?.toInt() ?? 0;
              final lifetime =
                  (data['lifetimeEarnedMinor'] as num?)?.toInt() ?? 0;
              final instantFeeBps =
                  (data['instantFeeBps'] as num?)?.toInt() ?? 150;
              final canCashOut = data['canCashOut'] as bool? ?? false;
              final blocked = _blockedMessage(data['blockedReason'] as String?);

              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(walletProvider),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
                  children: [
                    _Hero(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Earnings',
                              style: text.titleLarge
                                  ?.copyWith(color: Colors.white)),
                          const SizedBox(height: FreshlySpacing.lg),
                          Text('Available to cash out',
                              style: text.bodyMedium
                                  ?.copyWith(color: FreshlyColors.inkMuted)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(formatMinor(available, currency),
                                style: FreshlyType.style(44,
                                    weight: FontWeight.w800,
                                    height: 1.1,
                                    color: Colors.white)),
                          ),
                          const SizedBox(height: FreshlySpacing.lg),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              disabledBackgroundColor:
                                  FreshlyColors.obsidianRaised,
                              disabledForegroundColor: FreshlyColors.inkMuted,
                            ),
                            onPressed: !canCashOut || _busy
                                ? null
                                : () => _cashOut(
                                    available, currency, instantFeeBps),
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: FreshlyColors.obsidian))
                                : const Icon(FreshlyIcons.bank, size: 20),
                            label: Text(_busy ? 'Sending…' : 'Cash out'),
                          ),
                          if (blocked != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(FreshlyIcons.info,
                                      size: 16, color: FreshlyColors.inkMuted),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(blocked,
                                      style: text.bodySmall?.copyWith(
                                          color: FreshlyColors.inkMuted)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(FreshlySpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _BalanceTile(
                              icon: FreshlyIcons.lockClock,
                              tone: FreshlyTone.warning,
                              label: 'Held in escrow',
                              value: formatMinor(pending, currency),
                              note: 'Released by each client\'s code.',
                            ),
                          ),
                          const SizedBox(width: FreshlySpacing.sm),
                          Expanded(
                            child: _BalanceTile(
                              icon: FreshlyIcons.trendingUp,
                              tone: FreshlyTone.brand,
                              label: 'All time',
                              value: formatMinor(lifetime, currency),
                              note: 'Earned with Freshly.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FreshlySpacing.sm),
                    const SectionHeader(title: 'Recent earnings'),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                      child: _EarningsHistoryList(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ParallaxHero(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            FreshlySpacing.md,
            MediaQuery.paddingOf(context).top + FreshlySpacing.md,
            FreshlySpacing.md,
            FreshlySpacing.lg),
        child: child,
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.note,
  });

  final IconData icon;
  final FreshlyTone tone;
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, tone: tone, size: 36),
            const SizedBox(height: 12),
            Text(label, style: text.labelMedium),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: text.titleLarge),
            ),
            const SizedBox(height: 6),
            Text(note, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PayoutOption extends StatelessWidget {
  const _PayoutOption({
    required this.icon,
    required this.tone,
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final FreshlyTone tone;
  final String title;
  final String badge;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBadge(icon: icon, tone: tone, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(title, style: text.titleMedium),
                        const SizedBox(width: 8),
                        StatusPill(label: badge, tone: tone, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
              Icon(FreshlyIcons.chevronRight,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
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
      loading: () => const JobTileSkeleton(count: 3),
      error: (e, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return const Card(
            child: EmptyState(
              compact: true,
              icon: FreshlyIcons.receipt,
              title: 'No earnings yet',
              message: 'Completed jobs will appear here with a full '
                  'breakdown of what you were paid.',
            ),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: Card(
        child: Theme(
          // ExpansionTile draws its own dividers when open; on a bordered
          // card they double up.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            leading: const IconBadge(
                icon: FreshlyIcons.checkCircle,
                tone: FreshlyTone.success,
                size: 40),
            title: Text(transaction.reference, style: text.titleMedium),
            subtitle: Text(formatDate(transaction.completedAt),
                style: text.bodySmall),
            trailing: Text(transaction.netEarnings.format(),
                style: text.titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    const Divider(),
                    const SizedBox(height: 6),
                    LineItem(
                        label: 'Service',
                        value: formatMinor(
                            transaction.serviceMinor, transaction.currency)),
                    LineItem(
                        label: 'Travel fee',
                        value: formatMinor(
                            transaction.travelMinor, transaction.currency)),
                    LineItem(
                      label: 'Freshly commission',
                      value:
                          '- ${formatMinor(transaction.commissionMinor, transaction.currency)}',
                      muted: true,
                    ),
                    const Divider(height: 16),
                    LineItem(
                      label: 'You received',
                      value: transaction.netEarnings.format(),
                      emphasis: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
