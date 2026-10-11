import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../theme/freshly_icons.dart';
import '../theme/freshly_theme.dart';

/// What the picker hands back: somewhere bookable.
class PickedAddress {
  const PickedAddress({
    required this.formatted,
    required this.lat,
    required this.lng,
    this.accessNotes,
  });

  final String formatted;
  final double lat;
  final double lng;
  final String? accessNotes;
}

/// Choosing where a job happens.
///
/// Saved addresses first, then typing. The saved list is free and instant and
/// covers most repeat bookings; Google is only consulted once somebody starts
/// typing something new, which is also when it starts costing money.
///
/// One session token per open. Google bills a session rather than a request,
/// so a token created here and reused for every keystroke and the final lookup
/// is roughly $2.83 per thousand addresses — a new token per keystroke is
/// nearer $80. Opening the sheet again starts a new session, which is correct:
/// that is a new address being entered.
class AddressPickerSheet extends StatefulWidget {
  const AddressPickerSheet({
    required this.api,
    this.countryCode = 'ZW',
    this.nearLat,
    this.nearLng,
    super.key,
  });

  final FreshlyApi api;
  final String countryCode;

  /// Biases results towards where the person is, so their own street sorts
  /// above an identically named one four provinces away.
  final double? nearLat;
  final double? nearLng;

  static Future<PickedAddress?> show(
    BuildContext context, {
    required FreshlyApi api,
    String countryCode = 'ZW',
    double? nearLat,
    double? nearLng,
  }) =>
      showModalBottomSheet<PickedAddress>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AddressPickerSheet(
          api: api,
          countryCode: countryCode,
          nearLat: nearLat,
          nearLng: nearLng,
        ),
      );

  @override
  State<AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<AddressPickerSheet> {
  final _controller = TextEditingController();
  late final String _sessionToken;
  Timer? _debounce;
  List<SavedAddress> _saved = const [];
  List<AddressSuggestion> _suggestions = const [];
  bool _loadingSaved = true;
  bool _searching = false;
  bool _resolving = false;
  String? _error;

  /// Guards against a slow early response landing after a later one and
  /// replacing results for what has since been typed.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _sessionToken = _newSessionToken();
    _loadSaved();
  }

  static String _newSessionToken() {
    final r = Random();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Future<void> _loadSaved() async {
    try {
      final saved = await widget.api.savedAddresses();
      if (mounted) setState(() { _saved = saved; _loadingSaved = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    // Long enough that typing an address is a handful of requests rather than
    // one per character, short enough that the list keeps up.
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() { _searching = true; _error = null; });
    try {
      final found = await widget.api.searchAddresses(
        query: query.trim(),
        sessionToken: _sessionToken,
        countryCode: widget.countryCode,
        nearLat: widget.nearLat,
        nearLng: widget.nearLng,
      );
      if (!mounted || id != _requestId) return;
      setState(() { _suggestions = found; _searching = false; });
    } on ApiException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        // Says what is actually wrong. "Address search is not set up yet"
        // sends somebody to a saved address instead of retrying forever.
        _error = e.message;
        _searching = false;
      });
    }
  }

  Future<void> _choose(AddressSuggestion suggestion) async {
    setState(() => _resolving = true);
    try {
      final resolved =
          await widget.api.resolveAddress(suggestion.placeId, _sessionToken);
      if (!mounted) return;
      Navigator.pop(
        context,
        PickedAddress(
          formatted: resolved.formatted,
          lat: resolved.lat,
          lng: resolved.lng,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _resolving = false; });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typing = _controller.text.trim().length >= 3;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(FreshlySpacing.radiusLarge)),
        ),
        child: Column(
          children: [
            const SizedBox(height: FreshlySpacing.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FreshlyColors.line,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) { _onChanged(v); setState(() {}); },
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: widget.countryCode == 'ZA'
                      ? 'Street and suburb, e.g. 12 Sandton Drive'
                      : 'Street and suburb, e.g. King George Rd, Avondale',
                  prefixIcon: const Icon(FreshlyIcons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(FreshlyIcons.close),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _suggestions = const []);
                              },
                            ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: FreshlySpacing.md, vertical: 4),
                child: Text(_error!,
                    style: const TextStyle(color: FreshlyColors.crimson)),
              ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
                children: [
                  // Saved first while the field is empty: it is the answer for
                  // most bookings and costs nothing to show.
                  if (!typing) ...[
                    if (_loadingSaved)
                      const Padding(
                        padding: EdgeInsets.all(FreshlySpacing.lg),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_saved.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(FreshlySpacing.lg),
                        child: Text(
                          'Start typing an address. Save the ones you use often '
                          'and they will appear here.',
                          style: TextStyle(
                              color: FreshlyColors.inkMuted, height: 1.4),
                        ),
                      )
                    else ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(FreshlySpacing.md, 0,
                            FreshlySpacing.md, FreshlySpacing.sm),
                        child: Text('Saved',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      ..._saved.map((a) => ListTile(
                            leading: Icon(
                              a.isDefault
                                  ? FreshlyIcons.checkCircle
                                  : FreshlyIcons.location,
                              color: a.isDefault
                                  ? FreshlyColors.mint
                                  : FreshlyColors.inkMuted,
                            ),
                            title: Text(a.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(a.formatted),
                            onTap: () => Navigator.pop(
                              context,
                              PickedAddress(
                                formatted: a.formatted,
                                lat: a.lat,
                                lng: a.lng,
                                accessNotes: a.accessNotes,
                              ),
                            ),
                          )),
                    ],
                  ],

                  if (typing)
                    ..._suggestions.map((s) => ListTile(
                          leading: const Icon(FreshlyIcons.location),
                          title: Text(s.primary),
                          subtitle: s.secondary.isEmpty ? null : Text(s.secondary),
                          enabled: !_resolving,
                          onTap: () => _choose(s),
                        )),

                  if (typing && _suggestions.isEmpty && !_searching && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(FreshlySpacing.lg),
                      child: Text('No addresses matched.',
                          style: TextStyle(color: FreshlyColors.inkMuted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
