import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import 'env.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiProvider = Provider<FreshlyApi>((ref) => FreshlyApi(
      baseUrl: Env.apiBaseUrl,
      session: ref.watch(sessionStoreProvider),
      onUnauthenticated: () =>
          ref.read(partnerAuthProvider.notifier).signedOut(),
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

  /// Restore a session at launch.
  ///
  /// The previous version left a stored token in PartnerUnknown, which the
  /// router treats as signed out — so a provider who had signed in yesterday
  /// was asked to sign in again every single morning. /auth/me settles it,
  /// and also tells us whether they have been verified since, which decides
  /// whether the online toggle is usable.
  Future<void> _restore() async {
    final token = await _ref.read(sessionStoreProvider).accessToken;
    if (token == null) {
      state = const PartnerSignedOut();
      return;
    }

    try {
      final user = await _ref.read(apiProvider).me();
      if (!user.isProvider) {
        await _ref.read(sessionStoreProvider).clear();
        state = const PartnerSignedOut();
        return;
      }

      final session = AuthSession(
        accessToken: token,
        refreshToken: await _ref.read(sessionStoreProvider).refreshToken ?? '',
        userId: user.id,
        fullName: user.fullName,
        phone: user.phone,
        roles: user.roles,
        countryCode: user.countryCode,
        profileComplete: user.profileComplete,
        isNewUser: false,
      );

      state = user.isVerifiedProvider
          ? PartnerReady(session)
          : PartnerPendingVerification(session, user.kycStatus ?? 'pending');
      _ref.read(realtimeProvider).connect(token);

      // Presence is server state, not local state. A provider who was online
      // when the app was killed is still online as far as dispatch is
      // concerned, and the toggle must say so.
      if (user.isOnline) _ref.read(presenceProvider.notifier).restoreOnline();
    } catch (_) {
      state = const PartnerSignedOut();
    }
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
    StateNotifierProvider<PartnerAuthNotifier, PartnerAuthState>(
        PartnerAuthNotifier.new);

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

    unawaited(_positionSub?.cancel() ?? Future<void>.value());
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

  /// Reflect presence the server already believes, without re-posting it.
  void restoreOnline() {
    state = true;
    unawaited(_startStreaming());
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

final kycStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).kycStatus(),
);

// ─── Menu ────────────────────────────────────────────────────────────────────

final myMenuProvider = FutureProvider.autoDispose<List<ProviderMenuItem>>(
  (ref) => ref.watch(apiProvider).getMyMenu(),
);

final catalogServicesProvider =
    FutureProvider.family<List<CatalogService>, ServiceCategory?>(
  (ref, category) => ref.watch(apiProvider).catalogServices(category: category),
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
    await _ref
        .read(apiProvider)
        .respondToOffer(offerId, accept, reason: reason);
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
