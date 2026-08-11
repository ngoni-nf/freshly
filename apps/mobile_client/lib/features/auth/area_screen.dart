import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen A.0b — where the customer is.
///
/// Asked once right after sign-up, and reachable afterwards from the dashboard,
/// because where somebody wants service is a preference and not a fact fixed at
/// registration. It is the fix for the worst first-run experience the app had:
/// discovery resolved the device's GPS against the geofence and, if that failed
/// or landed outside a live area, announced "Freshly is not live in this area
/// yet" about a place the customer had never chosen and could not change.
///
/// Suburbs rather than metros, because people know they are in Rosebank and
/// have never once thought of themselves as being in "Johannesburg North".
/// Every suggestion resolves to an area we operate in, so anything offered here
/// can actually be served — the alternative is a customer discovering the
/// refusal after choosing instead of before.
///
/// The choice is a fallback origin, not a restriction. A real GPS fix inside
/// any live area still wins.
class AreaScreen extends ConsumerStatefulWidget {
  const AreaScreen({super.key, this.isOnboarding = true});

  /// During sign-up this continues to the permissions step; opened later from
  /// the dashboard it just closes.
  final bool isOnboarding;

  @override
  ConsumerState<AreaScreen> createState() => _AreaScreenState();
}

class _AreaScreenState extends ConsumerState<AreaScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Guards against an earlier request landing after a later one and
  /// overwriting the results for what the user has since typed.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Long enough that typing a suburb is one request rather than eight, short
    // enough that the list feels like it is keeping up.
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final found = await ref.read(apiProvider).places(query: query.trim());
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = found;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _choose(Place place) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(apiProvider).setServiceArea(placeId: place.id);
      final auth = ref.read(authStateProvider);
      final session = switch (auth) {
        AuthNeedsArea(:final session) => session,
        AuthSignedIn(:final session) => session,
        _ => null,
      };
      if (session != null) {
        ref.read(authStateProvider.notifier).areaChosen(session, saved);
      }
      if (!mounted) return;
      if (widget.isOnboarding) {
        context.go('/auth/permissions');
      } else {
        context.pop();
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
    final current = ref.watch(serviceAreaProvider);

    return Scaffold(
      appBar: widget.isOnboarding
          ? null
          : AppBar(title: const Text('Change location'), elevation: 0),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isOnboarding) ...[
                const SizedBox(height: FreshlySpacing.xl),
                Text(
                  'Where are you?',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: FreshlySpacing.sm),
                const Text(
                  'Start typing your suburb. We will use your exact location '
                  'instead whenever you allow it.',
                  style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.lg),
              ],
              TextField(
                controller: _controller,
                onChanged: _onChanged,
                autofocus: widget.isOnboarding,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Suburb, e.g. Rosebank',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _controller.clear();
                            _search('');
                            setState(() {});
                          },
                        ),
                ),
              ),
              if (current != null && !widget.isOnboarding) ...[
                const SizedBox(height: FreshlySpacing.md),
                Text(
                  'Currently set to ${current.displayName}',
                  style: const TextStyle(color: FreshlyColors.inkMuted),
                ),
              ],
              const SizedBox(height: FreshlySpacing.md),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: FreshlyColors.inkMuted),
            ),
            const SizedBox(height: FreshlySpacing.md),
            OutlinedButton(
              onPressed: () => _search(_controller.text),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_results.isEmpty) {
      final typed = _controller.text.trim();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.lg),
          child: Text(
            typed.isEmpty
                ? 'We are not open in your country yet. We will let you know the '
                    'moment that changes.'
                : 'We are not in $typed yet. Try a nearby suburb — we are adding '
                    'areas all the time.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.xs),
      itemBuilder: (context, i) {
        final place = _results[i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(place.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            // The metro is the reassurance that we cover this, without making
            // the customer choose it.
            subtitle: Text(
              place.postalCode == null
                  ? place.serviceAreaName
                  : '${place.serviceAreaName} · ${place.postalCode}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _choose(place),
          ),
        );
      },
    );
  }
}
