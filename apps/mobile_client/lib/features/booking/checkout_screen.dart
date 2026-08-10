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
            ('ecocash', 'EcoCash', Icons.phone_android),
            ('card', 'Card (USD)', Icons.credit_card),
            ('innbucks', 'InnBucks', Icons.account_balance_wallet_outlined),
          ]
        : const [
            ('capitec_pay', 'Capitec Pay', Icons.phone_android),
            ('instant_eft', 'Instant EFT', Icons.account_balance_outlined),
            ('card', 'Card', Icons.credit_card),
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('Confirm and pay')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              children: [
                if (_quote != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(FreshlySpacing.md),
                      child: Column(
                        children: [
                          ..._quote!.breakdown.map((line) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(line.label,
                                          style: TextStyle(
                                              color: line.kind == 'discount'
                                                  ? FreshlyColors.mintDark
                                                  : null)),
                                    ),
                                    Text(
                                      '${line.kind == 'discount' ? '−' : ''}'
                                      '${formatMinor(line.amountMinor.abs(), _quote!.currency)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: line.kind == 'discount'
                                            ? FreshlyColors.mintDark
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          const Divider(height: FreshlySpacing.lg),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700)),
                              Text(_quote!.total.format(),
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                  Container(
                    padding: const EdgeInsets.all(FreshlySpacing.md),
                    decoration: BoxDecoration(
                      color: FreshlyColors.mintSoft,
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.radius),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline,
                            color: FreshlyColors.mintDark, size: 20),
                        SizedBox(width: FreshlySpacing.sm),
                        Expanded(
                          child: Text(
                            'We hold your payment securely and only release it to your pro '
                            'once the service is done and you have shared your 4-digit code.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: FreshlySpacing.lg),
                const Text('Pay with',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: FreshlySpacing.sm),
                // RadioGroup replaced per-tile groupValue/onChanged in Flutter
                // 3.32; the group now owns the selection.
                RadioGroup<String>(
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                  child: Column(
                    children: methods
                        .map((m) => Card(
                              margin: const EdgeInsets.only(
                                  bottom: FreshlySpacing.sm),
                              child: RadioListTile<String>(
                                value: m.$1,
                                secondary: Icon(m.$3),
                                title: Text(m.$2),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  Text(_error!,
                      style: const TextStyle(color: FreshlyColors.crimson)),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: FilledButton(
            onPressed: _quote == null || _paying ? null : _pay,
            child: _paying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_quote == null
                    ? 'Confirm'
                    : 'Pay ${_quote!.total.format()}'),
          ),
        ),
      ),
    );
  }
}
