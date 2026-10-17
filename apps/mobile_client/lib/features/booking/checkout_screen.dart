import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'booking_draft.dart';

/// Screens A.10 and A.11 — itemised total, then payment.
///
/// The quote is fetched from the server and rendered verbatim. The client
/// never computes a total: if the app and the backend ever disagreed about the
/// travel fee, the customer would be charged something other than what they
/// agreed to, which is both a trust failure and a chargeback.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({required this.draft, super.key});
  final BookingDraft draft;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  PriceQuote? _quote;
  String? _error;
  bool _loading = true;
  bool _paying = false;
  String _method = 'card';

  @override
  void initState() {
    super.initState();
    _fetchQuote();
  }

  Future<void> _fetchQuote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quote = await ref.read(apiProvider).quote(
            providerId: widget.draft.providerId,
            serviceIds: widget.draft.services.map((s) => s.id).toList(),
            lat: widget.draft.destination!.lat,
            lng: widget.draft.destination!.lng,
            promoCode: widget.draft.promoCode,
          );
      setState(() {
        _quote = quote;
        widget.draft.quote = quote;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pay() async {
    if (_paying) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    final key =
        '${widget.draft.providerId}-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final api = ref.read(apiProvider);
      final booking = await api.createBooking(widget.draft.toCreatePayload(),
          idempotencyKey: key);
      await api.checkout(booking.id,
          method: _method, idempotencyKey: '$key-pay');
      if (mounted) context.go('/book/${booking.id}/escrow');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(countryCodeProvider);
    final methods = country == 'ZW'
        ? const [
            ('ecocash', 'EcoCash', FreshlyIcons.mobile),
            ('card', 'Card (USD)', FreshlyIcons.card),
            ('innbucks', 'InnBucks', FreshlyIcons.wallet),
          ]
        : const [
            ('capitec_pay', 'Capitec Pay', FreshlyIcons.mobile),
            ('instant_eft', 'Instant EFT', FreshlyIcons.bank),
            ('card', 'Card', FreshlyIcons.card),
          ];

    final text = Theme.of(context).textTheme;
    final draft = widget.draft;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm and pay')),
      body: _loading
          ? const _CheckoutSkeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                  FreshlySpacing.sm, FreshlySpacing.md, FreshlySpacing.xl),
              children: [
                // What they are paying for, in one glance, before the money.
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(FreshlySpacing.md),
                    child: Row(
                      children: [
                        FreshlyAvatar(name: draft.providerName, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(draft.providerName, style: text.titleMedium),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  draft.bookingType == 'scheduled' &&
                                          draft.scheduledStart != null
                                      ? formatSlot(draft.scheduledStart!)
                                      : 'As soon as possible',
                                  if (draft.destinationAddress != null)
                                    draft.destinationAddress!,
                                ].join(' · '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_quote != null) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, 10,
                          FreshlySpacing.md, FreshlySpacing.md),
                      child: Column(
                        children: [
                          for (final line in _quote!.breakdown)
                            LineItem(
                              label: line.label,
                              value: '${line.kind == 'discount' ? '−' : ''}'
                                  '${formatMinor(line.amountMinor.abs(), _quote!.currency)}',
                              muted: line.kind == 'info',
                            ),
                          const SizedBox(height: 8),
                          const Divider(),
                          const SizedBox(height: 8),
                          LineItem(
                            label: 'Total',
                            value: _quote!.total.format(),
                            emphasis: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  const _SecurePaymentInfo(),
                ],
                const SizedBox(height: FreshlySpacing.lg),
                Text('Pay with', style: text.titleLarge),
                const SizedBox(height: 12),
                // RadioGroup replaced per-tile groupValue/onChanged in Flutter
                // 3.32; the group now owns the selection.
                RadioGroup<String>(
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  child: Column(
                    children: [
                      for (final m in methods)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: FreshlySpacing.sm),
                          child: _MethodTile(
                            value: m.$1,
                            label: m.$2,
                            icon: m.$3,
                            selected: _method == m.$1,
                          ),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FreshlySpacing.sm),
                  _ErrorBanner(
                      message: _error!,
                      onRetry: _quote == null ? _fetchQuote : null),
                ],
                const SizedBox(height: FreshlySpacing.md),
                const _CancellationPolicyInfo(),
              ],
            ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          onPressed: _quote == null || _paying ? null : _pay,
          child: _paying
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: FreshlyColors.obsidian))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FreshlyIcons.lock, size: 18),
                    const SizedBox(width: 8),
                    Text(_quote == null
                        ? 'Confirm'
                        : 'Pay ${_quote!.total.format()}'),
                  ],
                ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.selected,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        side: BorderSide(
          color: selected
              ? (isDark ? FreshlyColors.mint : FreshlyColors.obsidian)
              : scheme.outline,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RadioListTile<String>(
        value: value,
        controlAffinity: ListTileControlAffinity.trailing,
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        secondary: IconBadge(
            icon: icon,
            size: 40,
            tone: selected ? FreshlyTone.dark : FreshlyTone.neutral),
        title: Text(label),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: FreshlyColors.crimsonSoft,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      ),
      child: Row(
        children: [
          const Icon(FreshlyIcons.error, color: FreshlyColors.crimson),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: FreshlyType.style(14,
                    weight: FontWeight.w600, color: const Color(0xFFB4232A))),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FreshlySpacing.md),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Skeleton(height: 80, radius: FreshlySpacing.radius),
        SizedBox(height: FreshlySpacing.md),
        Skeleton(height: 180, radius: FreshlySpacing.radius),
        SizedBox(height: FreshlySpacing.lg),
        Skeleton(width: 120, height: 22),
        SizedBox(height: 12),
        Skeleton(height: 64, radius: FreshlySpacing.radius),
        SizedBox(height: 8),
        Skeleton(height: 64, radius: FreshlySpacing.radius),
      ],
    );
  }
}

class _SecurePaymentInfo extends StatelessWidget {
  const _SecurePaymentInfo();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(FreshlySpacing.md),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E3A2A) : FreshlyColors.mintSoft,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBadge(
              icon: FreshlyIcons.shield, size: 36, tone: FreshlyTone.dark),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Protected by Freshly',
                    style: FreshlyType.style(14,
                        weight: FontWeight.w800,
                        color: isDark
                            ? FreshlyColors.mint
                            : FreshlyColors.mintInk)),
                const SizedBox(height: 2),
                Text(
                  'We hold your payment securely and only release it to your '
                  'pro once the service is done and you have shared your '
                  '4-digit code.',
                  style: FreshlyType.style(13,
                      height: 1.45,
                      color: isDark ? Colors.white70 : FreshlyColors.mintInk),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CancellationPolicyInfo extends ConsumerWidget {
  const _CancellationPolicyInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(marketsProvider);
    final country = ref.watch(countryCodeProvider);

    return markets.when(
      data: (list) {
        final market =
            list.firstWhere((m) => m.code == country, orElse: () => list.first);
        final feePct = (market.cancellationFeeBps / 100).toStringAsFixed(0);
        final windowHrs =
            (market.cancellationWindowMinutes / 60).toStringAsFixed(0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FreshlyIcons.info,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Free cancellation up to $windowHrs hours before your '
                  'appointment. Late cancellations or no-shows carry a '
                  '$feePct% fee to protect your professional’s time and '
                  'travel costs.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
