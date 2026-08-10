import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import 'env.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiProvider = Provider<FreshlyApi>((ref) => FreshlyApi(
      baseUrl: Env.apiBaseUrl,
      session: ref.watch(sessionStoreProvider),
      onUnauthenticated: () => ref.read(partnerAuthProvider.notifier).signedOut(),
    ));

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(baseUrl: Env.realtimeUrl);
  ref.onDispose(client.dispose);
  return client;
});

// ─── Auth ────────────────────────────────────────────────────────────────────

sealed class PartnerAuthState {
  const PartnerAuthState();
}

class PartnerUnknown extends PartnerAuthState {
  const PartnerUnknown();
}

class PartnerSignedOut extends PartnerAuthState {
  const PartnerSignedOut();
}

/// Signed in but not yet cleared to work. The provider can browse and finish
/// onboarding, but cannot go online or receive a dispatch offer.
class PartnerPendingVerification extends PartnerAuthState {
  const PartnerPendingVerification(this.session, this.kycStatus);
  final AuthSession session;
  final String kycStatus;
}

class PartnerReady extends PartnerAuthState {
  const PartnerReady(this.session);
  final AuthSession session;
}

class PartnerAuthNotifier extends StateNotifier<PartnerAuthState> {
  PartnerAuthNotifier(this._ref) : super(const PartnerUnknown()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final token = await _ref.read(sessionStoreProvider).accessToken;
    state = token == null ? const PartnerSignedOut() : const PartnerUnknown();
  }

  void signedIn(AuthSession session, {String kycStatus = 'verified'}) {
    state = kycStatus == 'verified'
        ? PartnerReady(session)
        : PartnerPendingVerification(session, kycStatus);
    _ref.read(realtimeProvider).connect(session.accessToken);
  }

  void signedOut() {
    _ref.read(realtimeProvider).disconnect();
    _ref.read(presenceProvider.notifier).forceOffline();
    state = const PartnerSignedOut();
  }

  Future<void> logout() async {
    await _ref.read(apiProvider).logout();
    signedOut();
  }
}

final partnerAuthProvider =
    StateNotifierProvider<PartnerAuthNotifier, PartnerAuthState>(PartnerAuthNotifier.new);

// ─── Presence and location streaming ─────────────────────────────────────────

/// Going online starts a position stream; going offline stops it and purges
/// the last known point.
///
/// The stream is distance-filtered rather than time-based. A provider parked
/// outside a client's gate for ten minutes should not be uploading a position
/// every five seconds — that is their battery and their prepaid data being
/// spent to tell us nothing new.
class PresenceNotifier extends StateNotifier<bool> {
  PresenceNotifier(this._ref) : super(false);

  final Ref _ref;
  StreamSubscription<Position>? _positionSub;

  Future<void> setOnline(bool online) async {
    await _ref.read(apiProvider).setOnline(online);
    state = online;
    online ? await _startStreaming() : await _stopStreaming();
  }

  Future<void> _startStreaming() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    ).listen((position) {
      _ref.read(realtimeProvider).publishLocation(
            position.latitude,
            position.longitude,
            heading: position.heading,
            speedKph: position.speed * 3.6,
          );
    });
  }

  Future<void> _stopStreaming() async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  void forceOffline() {
    state = false;
    unawaited(_positionSub?.cancel() ?? Future<void>.value());
    _positionSub = null;
  }

  @override
  void dispose() {
    unawaited(_positionSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}

final presenceProvider =
    StateNotifierProvider<PresenceNotifier, bool>(PresenceNotifier.new);

// ─── Work queues ─────────────────────────────────────────────────────────────

final scheduleProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final api = ref.watch(apiProvider);
    final raw = await api.myBookings();
    return raw
        .where((b) => b.status.isLive)
        .map((b) => {
              'id': b.id,
              'reference': b.reference,
              'status': b.status,
              'address': b.destinationAddress,
              'total': b.total,
              'scheduledStart': b.scheduledStart,
            })
        .toList();
  },
);

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).wallet(),
);

/// Live dispatch offers. Held in memory only — an offer that outlives the app
/// is an offer the client has already given to somebody else.
class OfferQueue extends StateNotifier<List<DispatchOffer>> {
  OfferQueue(this._ref) : super(const []) {
    final realtime = _ref.read(realtimeProvider);
    _offerSub = realtime.offers.listen((offer) {
      state = [...state.where((o) => o.offerId != offer.offerId), offer];
    });
    _revokedSub = realtime.offerRevoked.listen((offerId) {
      state = state.where((o) => o.offerId != offerId).toList();
    });
  }

  final Ref _ref;
  StreamSubscription<DispatchOffer>? _offerSub;
  StreamSubscription<String>? _revokedSub;

  void remove(String offerId) =>
      state = state.where((o) => o.offerId != offerId).toList();

  Future<void> respond(String offerId, bool accept, {String? reason}) async {
    remove(offerId);
    await _ref.read(apiProvider).respondToOffer(offerId, accept, reason: reason);
  }

  @override
  void dispose() {
    unawaited(_offerSub?.cancel() ?? Future<void>.value());
    unawaited(_revokedSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }
}

final offerQueueProvider =
    StateNotifierProvider<OfferQueue, List<DispatchOffer>>(OfferQueue.new);
