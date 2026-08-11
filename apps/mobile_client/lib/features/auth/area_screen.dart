import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen A.0b — which area.
///
/// Asked once, right after sign-up, and it is the fix for the worst first-run
/// experience the app had: discovery resolved the device's GPS against the
/// geofence and, if that failed or landed outside a live area, announced
/// "Freshly is not live in this area yet" about a place the customer had never
/// chosen and could not change.
///
/// The choice is a fallback origin, not a restriction. A real GPS fix inside
/// any live area still wins — someone who picks Johannesburg and then travels
/// to Cape Town sees Cape Town, once we are open there.
class AreaScreen extends ConsumerStatefulWidget {
  const AreaScreen({super.key});

  @override
  ConsumerState<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends ConsumerState<AreaScreen> {
  bool _busy = false;

  Future<void> _choose(ServiceArea area) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(apiProvider).setServiceArea(area.id);
      final auth = ref.read(authStateProvider);
      final session = switch (auth) {
        AuthNeedsArea(:final session) => session,
        AuthSignedIn(:final session) => session,
        _ => null,
      };
      if (session != null) {
        ref.read(authStateProvider.notifier).areaChosen(session, saved);
      }
      if (mounted) context.go('/auth/permissions');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = ref.watch(countryCodeProvider);
    final areas = ref.watch(serviceAreasProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              Text('Where do you want Freshly?',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              const Text(
                'Pick the area you are usually in. We will use your exact '
                'location instead whenever you allow it.',
                style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              Expanded(
                child: areas.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, __) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e is ApiException
                              ? e.message
                              : 'We could not load the areas',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: FreshlyColors.inkMuted),
                        ),
                        const SizedBox(height: FreshlySpacing.md),
                        OutlinedButton(
                          onPressed: () => ref.invalidate(serviceAreasProvider),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                  data: (all) {
                    // Only the areas in this customer's market: a South African
                    // account cannot be priced against a Zimbabwean area, and
                    // the API refuses it anyway.
                    final list = all
                        .where((a) => a.countryCode == null || a.countryCode == country)
                        .toList();

                    if (list.isEmpty) {
                      return const Center(
                        child: Text(
                          'We are not open in your country yet. We will let you '
                          'know the moment that changes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: FreshlySpacing.sm),
                      itemBuilder: (context, i) => Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: const Icon(Icons.location_city_outlined),
                          title: Text(list[i].name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy ? null : () => _choose(list[i]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
