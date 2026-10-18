import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import 'env.dart';
import 'phone_auth.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// One verification handle for the sign-in screen, holding the verificationId
/// between requesting a code and confirming it.
final phoneAuthProvider = Provider<PhoneAuth>((ref) => PhoneAuth());

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

/// Signed in with a plain customer account. Every provider endpoint answers
/// `insufficient_role` until they open a business, so the app shows nothing
/// else until they have.
class PartnerNeedsBusiness extends PartnerAuthState {
  const PartnerNeedsBusiness(this.session);
  final AuthSession session;
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

      final session = AuthSession(
        accessToken: token,
        refreshToken: await _ref.read(sessionStoreProvider).refreshToken ?? '',
        userId: user.id,
        fullName: user.fullName,
        phone: user.phone,
        roles: user.roles,
        countryCode: user.countryCode,
        profileComplete: user.profileComplete,
        // Providers sign in by phone, so this is always false; carried through
        // only because the session shape is shared with the client app.
        needsPhone: user.needsPhone,
        isNewUser: false,
      );

      _ref.read(countryCodeProvider.notifier).state = user.countryCode;

      // A number that signed up in the client app, or a pro who closed the app
      // halfway through sign-up, is a customer with no provider row yet. The
      // old code signed them out, which looked like a broken login; what they
      // need is the business set-up step they never finished.
      if (!user.isProvider) {
        state = PartnerNeedsBusiness(session);
        return;
      }

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
    _ref.read(countryCodeProvider.notifier).state = session.countryCode;
    if (!session.isProvider) {
      state = PartnerNeedsBusiness(session);
      return;
    }
    state = kycStatus == 'verified'
        ? PartnerReady(session)
        : PartnerPendingVerification(session, kycStatus);
    _ref.read(realtimeProvider).connect(session.accessToken);
  }

  /// The session the user is signed in with, whatever stage they are at.
  AuthSession? get session => switch (state) {
        PartnerNeedsBusiness(:final session) => session,
        PartnerPendingVerification(:final session) => session,
        PartnerReady(:final session) => session,
        _ => null,
      };

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

// Zimbabwe launches first; sign-in replaces this with the provider's own market.
final countryCodeProvider = StateProvider<String>((ref) => 'ZW');

final marketsProvider = FutureProvider<List<Market>>(
  (ref) => ref.watch(apiProvider).markets(),
);

/// The market the signed-in provider works in, once the list has loaded.
///
/// Everything that used to default to South Africa (currency labels, the
/// emergency number) reads this instead, so a Harare provider never sees a
/// rand sign or a Johannesburg police line because a response was slow.
final currentMarketProvider = Provider<Market?>((ref) {
  final code = ref.watch(countryCodeProvider);
  final markets = ref.watch(marketsProvider).valueOrNull;
  if (markets == null || markets.isEmpty) return null;
  for (final m in markets) {
    if (m.code == code) return m;
  }
  return null;
});

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

/// The row shape the dashboard and schedule tiles render.
Map<String, dynamic> jobRow(Booking b) => {
      'id': b.id,
      'reference': b.reference,
      'status': b.status,
      'address': b.destinationAddress,
      'total': b.total,
      'scheduledStart': b.scheduledStart,
      'completedAt': b.completedAt,
      'assignedStaffId': b.assignedStaffId,
      'assignedStaffName': b.assignedStaffName,
      'reviewedByMe': b.reviewedByMe,
    };

final scheduleProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final api = ref.watch(apiProvider);
    final raw = await api.myBookings();
    return raw.where((b) => b.status.isLive).map(jobRow).toList();
  },
);

/// Finished jobs, newest first. This is where a provider comes back to rate
/// a client or share an invoice, so it is a short list rather than a ledger;
/// the wallet has the money view.
final recentJobsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final raw = await ref.watch(apiProvider).myBookings(status: 'completed');
  final done = raw.where((b) => b.status == BookingStatus.completed).toList()
    ..sort((a, b) =>
        (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
  return done.take(10).map(jobRow).toList();
});

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).wallet(),
);

final earningsHistoryProvider =
    FutureProvider.autoDispose<List<EarningsTransaction>>(
  (ref) => ref.watch(apiProvider).getEarningsHistory(),
);

final kycStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(apiProvider).kycStatus(),
);

// ─── Business ────────────────────────────────────────────────────────────────

final myBusinessProvider = FutureProvider.autoDispose<ProviderBusiness>(
  (ref) => ref.watch(apiProvider).myBusiness(),
);

final workingHoursProvider = FutureProvider.autoDispose<List<WorkingHours>>(
  (ref) => ref.watch(apiProvider).workingHours(),
);

/// Whether the signed-in provider runs a salon, and so can hand jobs to
/// staff. False until the business has loaded: a tap that appears a moment
/// late is better than one that appears for a solo provider and then errors.
final isSalonProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(myBusinessProvider).valueOrNull?.businessMode == 'salon');

/// Whether the signed-in provider works for a salon rather than for
/// themselves. Their jobs are assigned by the salon and their pay settles
/// with the salon, so wallet copy and earnings make no sense to them.
final isSalonStaffProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(myBusinessProvider).valueOrNull?.businessMode == 'salon_staff');

// ─── Salon staff ─────────────────────────────────────────────────────────────

final myStaffProvider = FutureProvider.autoDispose<List<StaffMember>>(
  (ref) => ref.watch(apiProvider).myStaff(),
);

/// Invitations waiting on this account. Checked at business set-up, where a
/// new account may have been invited before it ever signed in, and on the
/// dashboard for a solo provider a salon wants to take on.
final staffInvitesProvider = FutureProvider.autoDispose<List<StaffInvite>>(
  (ref) => ref.watch(apiProvider).staffInvites(),
);

// ─── Invoices ────────────────────────────────────────────────────────────────

final invoicesProvider =
    FutureProvider.autoDispose.family<List<Invoice>, String>(
  (ref, bookingId) => ref.watch(apiProvider).invoices(bookingId),
);

// ─── Menu ────────────────────────────────────────────────────────────────────

final myMenuProvider = FutureProvider.autoDispose<List<ProviderMenuItem>>(
  (ref) => ref.watch(apiProvider).getMyMenu(),
);

final catalogServicesProvider =
    FutureProvider.family<List<CatalogService>, ServiceCategory?>(
  (ref, category) => ref.watch(apiProvider).catalogServices(category: category),
);

// ─── Portfolio ───────────────────────────────────────────────────────────────

final myPortfolioProvider = FutureProvider.autoDispose<List<PortfolioItem>>(
  (ref) => ref.watch(apiProvider).getMyPortfolio(),
);

// ─── CRM ─────────────────────────────────────────────────────────────────────

final myClientsProvider = FutureProvider.autoDispose<List<ClientSummary>>(
  (ref) => ref.watch(apiProvider).getMyClients(),
);

final clientDetailProvider =
    FutureProvider.autoDispose.family<ClientDetail, String>(
  (ref, id) => ref.watch(apiProvider).getClientDetail(id),
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
