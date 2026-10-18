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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final markets = ref.watch(marketsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
              FreshlySpacing.lg, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FreshlyWordmark(size: 26, onDark: false),
              const SizedBox(height: FreshlySpacing.xl),
              const ScreenIntro(
                eyebrow: 'Welcome',
                title: 'Where are you?',
                subtitle: 'So we show you the right pros, the right prices '
                    'and the right currency.',
              ),
              const SizedBox(height: FreshlySpacing.xl),
              Expanded(
                child: markets.when(
                  loading: () => const Column(
                    children: [
                      Skeleton(height: 76, radius: FreshlySpacing.radius),
                      SizedBox(height: FreshlySpacing.sm),
                      Skeleton(height: 76, radius: FreshlySpacing.radius),
                    ],
                  ),
                  error: (e, __) => EmptyState(
                    compact: true,
                    icon: FreshlyIcons.error,
                    title: 'Countries did not load',
                    message: e is ApiException
                        ? e.message
                        : 'Check your connection and try again.',
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(marketsProvider),
                  ),
                  data: (list) => ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: FreshlySpacing.sm),
                    itemBuilder: (context, i) {
                      final market = list[i];
                      return Card(
                        child: InkWell(
                          onTap: () {
                            ref.read(countryCodeProvider.notifier).state =
                                market.code;
                            context.push('/auth/phone');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(FreshlySpacing.md),
                            child: Row(
                              children: [
                                CountryBadge(code: market.code),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(market.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      const SizedBox(height: 2),
                                      Text(
                                          '${market.dialPrefix} · prices in ${market.currency}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ],
                                  ),
                                ),
                                const Icon(FreshlyIcons.chevronRight, size: 18),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Text('Not in the list? We are not open there yet.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
