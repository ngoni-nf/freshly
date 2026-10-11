import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import 'env.dart';
import 'notifications.dart' show pushTokenProvider;
import 'phone_auth.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// One verification handle shared by the phone screen and the code screen, so
/// the verificationId from `codeSent` survives the navigation between them.
final phoneAuthProvider = Provider<PhoneAuth>((ref) => PhoneAuth());

final apiProvider = Provider<FreshlyApi>((ref) {
  final api = FreshlyApi(
    baseUrl: Env.apiBaseUrl,
    session: ref.watch(sessionStoreProvider),
    onUnauthenticated: () => ref.read(authStateProvider.notifier).signedOut(),
  );
  return api;
});

final realtimeProvider = Provider<RealtimeClient>((ref) {
  final client = RealtimeClient(baseUrl: Env.realtimeUrl);
  ref.onDispose(client.dispose);
  return client;
});

// ─── Auth ────────────────────────────────────────────────────────────────────

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthSignedOut extends AuthState {
  const AuthSignedOut();
}

/// Signed in with Google or email, but with no verified number yet.
///
/// A social account exists and holds a session, but the booking path refuses
/// it until a phone is linked — the provider has to be able to reach the
/// client and the escrow release needs the PIN. The router sends them to
/// verify a number before anything else.
class AuthNeedsPhone extends AuthState {
  const AuthNeedsPhone(this.session);
  final AuthSession session;
}

class AuthNeedsProfile extends AuthState {
  const AuthNeedsProfile(this.session);
  final AuthSession session;
}

/// Signed in, profile complete, but has never said where they want service.
///
/// A distinct state rather than a flag, because the router has to send them
/// somewhere specific. Discovery without an area is what produced "Freshly is
/// not live in this area yet" for people standing in Rosebank.
class AuthNeedsArea extends AuthState {
  const AuthNeedsArea(this.session);
  final AuthSession session;
}

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session, {this.user});
  final AuthSession session;

  /// Present when the session was restored at launch rather than just created.
  final CurrentUser? user;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthUnknown()) {
    _restore();
  }

  final Ref _ref;

  /// Restore a session at launch.
  ///
  /// A stored token is provisional — it may be expired, revoked, or belong to
  /// an account that has since been suspended. /auth/me is the authority, and
  /// the refresh interceptor handles a merely-expired access token
  /// transparently. Every path must land on a concrete state: leaving this in
  /// AuthUnknown pins the router to the splash screen forever, which is what
  /// it used to do.
  Future<void> _restore() async {
    final token = await _ref.read(sessionStoreProvider).accessToken;
    if (token == null) {
      state = const AuthSignedOut();
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
        needsPhone: user.needsPhone,
        isNewUser: false,
        serviceArea: user.serviceArea,
      );

      // A missing number comes first: without it nothing downstream — profile,
      // area, a booking — can be completed anyway.
      state = user.needsPhone
          ? AuthNeedsPhone(session)
          : switch ((user.profileComplete, user.serviceArea)) {
              (false, _) => AuthNeedsProfile(session),
              (true, null) => AuthNeedsArea(session),
              (true, _) => AuthSignedIn(session, user: user),
            };
      _ref.read(countryCodeProvider.notifier).state = user.countryCode;
      if (user.serviceArea != null) {
        _ref.read(serviceAreaProvider.notifier).state = user.serviceArea;
      }
      _ref.read(realtimeProvider).connect(token);
      _registerPushToken();
    } on ApiException catch (e) {
      // Only a genuine 401 means the stored session is dead — and by the time
      // one reaches here the client has already tried to refresh it. Anything
      // else (offline, a 500, a timeout) is the server's problem, not proof
      // the user is signed out, so the tokens are kept and the next launch can
      // succeed. Discarding them on a transient error is how a working
      // session gets destroyed by a bad five minutes.
      if (e.isAuthFailure) {
        await _ref.read(sessionStoreProvider).clear();
      }
      state = const AuthSignedOut();
    } catch (_) {
      state = const AuthSignedOut();
    }
  }

  void signedIn(AuthSession session) {
    state = session.needsPhone
        ? AuthNeedsPhone(session)
        : switch ((session.profileComplete, session.serviceArea)) {
            (false, _) => AuthNeedsProfile(session),
            (true, null) => AuthNeedsArea(session),
            (true, _) => AuthSignedIn(session),
          };
    if (session.serviceArea != null) {
      _ref.read(serviceAreaProvider.notifier).state = session.serviceArea;
    }
    _ref.read(realtimeProvider).connect(session.accessToken);
    _registerPushToken();
  }

  /// Push registration needs a session, and FCM hands us the token at launch —
  /// before there is one. So the token is also sent here, once signing in has
  /// given it somewhere to belong. Without this a device only ever registers
  /// if its token happens to rotate while the app is open, which for most
  /// installs is never.
  void _registerPushToken() {
    final token = _ref.read(pushTokenProvider);
    if (token == null) return;
    // Not awaited and errors ignored: missing push is a degraded app, a throw
    // on the sign-in path is a broken one.
    unawaited(_ref.read(apiProvider).updatePushToken(token).catchError((_) {}));
  }

  /// Profile done, but the area question comes next for a brand new account.
  void profileCompleted(AuthSession session) =>
      state = session.serviceArea == null
          ? AuthNeedsArea(session)
          : AuthSignedIn(session);

  /// Called once the client has picked where they want service.
  void areaChosen(AuthSession session, ServiceArea area) {
    _ref.read(serviceAreaProvider.notifier).state = area;
    state = AuthSignedIn(session);
  }

  void signedOut() {
    _ref.read(realtimeProvider).disconnect();
    state = const AuthSignedOut();
  }

  Future<void> logout() async {
    await _ref.read(apiProvider).logout();
    signedOut();
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ─── Market & grid ───────────────────────────────────────────────────────────

// Zimbabwe launches first, so a person who has not chosen yet starts there.
final countryCodeProvider = StateProvider<String>((ref) => 'ZW');

/// Where the client said they want service. Discovery falls back to this
/// centroid whenever a live GPS fix is unavailable or lands outside every
/// service area, so the feed shows something useful instead of a refusal.
final serviceAreaProvider = StateProvider<ServiceArea?>((ref) => null);

/// Markets Freshly is open in. Drives the country step at sign-up; a country
/// absent from this list is one we cannot serve, and saying so up front beats
/// letting someone enter a number and fail later.
final marketsProvider = FutureProvider<List<Market>>(
  (ref) => ref.watch(apiProvider).markets(),
);

final serviceAreasProvider = FutureProvider<List<ServiceArea>>(
  (ref) => ref.watch(apiProvider).serviceAreas(),
);

/// Load-shedding status drives a banner on the dashboard and, at stage 4+,
/// silently forces the power-backup filter in discovery.
final gridStatusProvider = FutureProvider.autoDispose<GridStatus>((ref) async {
  final country = ref.watch(countryCodeProvider);
  return ref.watch(apiProvider).gridStatus(country);
});

// ─── Catalog ─────────────────────────────────────────────────────────────────

final catalogCategoriesProvider = FutureProvider<List<CategorySummary>>(
  (ref) => ref.watch(apiProvider).catalogCategories(),
);

final catalogServicesProvider =
    FutureProvider.family<List<CatalogService>, ServiceCategory?>(
  (ref, category) => ref.watch(apiProvider).catalogServices(category: category),
);
