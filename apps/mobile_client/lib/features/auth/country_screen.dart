import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen A.0 — which country.
///
/// First, before anything is asked of the customer, because the answer decides
/// the dial prefix, the currency, the tax label and which service areas are
/// even offered. It used to be a dropdown tucked beside the phone field, which
/// meant someone in Harare could type a number, wait for an OTP and only then
/// discover Freshly is not open to them.
///
/// The list is the live markets from the API, not a hardcoded pair. A country
/// that is configured but not switched on simply does not appear, so this
/// screen can never offer something the backend will refuse.
class CountryScreen extends ConsumerWidget {
  const CountryScreen({super.key});

  static const _flags = {'ZA': '🇿🇦', 'ZW': '🇿🇼'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(marketsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              Text('Where are you?',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              const Text(
                'So we show you the right pros, the right prices and the right '
                'currency.',
                style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              Expanded(
                child: markets.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, __) => _Retry(
                    message: e is ApiException
                        ? e.message
                        : 'We could not load the list of countries',
                    onRetry: () => ref.invalidate(marketsProvider),
                  ),
                  data: (list) => ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FreshlySpacing.sm),
                    itemBuilder: (context, i) {
                      final market = list[i];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Text(_flags[market.code] ?? '🌍',
                              style: const TextStyle(fontSize: 28)),
                          title: Text(market.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${market.dialPrefix} · prices in ${market.currency}'),
                          trailing: const Icon(FreshlyIcons.chevronRight),
                          onTap: () {
                            ref.read(countryCodeProvider.notifier).state =
                                market.code;
                            context.push('/auth/phone');
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
              const Text(
                'Not in the list? We are not open there yet.',
                style: TextStyle(color: FreshlyColors.inkMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FreshlyColors.inkMuted)),
          const SizedBox(height: FreshlySpacing.md),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
