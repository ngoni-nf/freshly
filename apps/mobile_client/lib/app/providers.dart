import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import 'env.dart';

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

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
        isNewUser: false,
        serviceArea: user.serviceArea,
      );

      state = switch ((user.profileComplete, user.serviceArea)) {
        (false, _) => AuthNeedsProfile(session),
        (true, null) => AuthNeedsArea(session),
        (true, _) => AuthSignedIn(session, user: user),
      };
      _ref.read(countryCodeProvider.notifier).state = user.countryCode;
      if (user.serviceArea != null) {
        _ref.read(serviceAreaProvider.notifier).state = user.serviceArea;
      }
      _ref.read(realtimeProvider).connect(token);
    } on ApiException catch (e) {
      // An unreachable server is not a signed-out user. Sending someone back
      // to the phone screen because their train went into a tunnel loses their
      // session for no reason; the API client will refresh or 401 properly
      // once the network returns.
      if (e.isOffline) {
        state = const AuthSignedOut();
      } else {
        await _ref.read(sessionStoreProvider).clear();
        state = const AuthSignedOut();
      }
    } catch (_) {
      state = const AuthSignedOut();
    }
  }

  void signedIn(AuthSession session) {
    state = switch ((session.profileComplete, session.serviceArea)) {
      (false, _) => AuthNeedsProfile(session),
      (true, null) => AuthNeedsArea(session),
      (true, _) => AuthSignedIn(session),
    };
    if (session.serviceArea != null) {
      _ref.read(serviceAreaProvider.notifier).state = session.serviceArea;
    }
    _ref.read(realtimeProvider).connect(session.accessToken);
  }

  /// Profile done, but the area question comes next for a brand new account.
  void profileCompleted(AuthSession session) => state =
      session.serviceArea == null ? AuthNeedsArea(session) : AuthSignedIn(session);

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

final countryCodeProvider = StateProvider<String>((ref) => 'ZA');

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
