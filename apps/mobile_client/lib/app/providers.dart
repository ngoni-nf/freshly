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

class AuthSignedIn extends AuthState {
  const AuthSignedIn(this.session);
  final AuthSession session;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._ref) : super(const AuthUnknown()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final token = await _ref.read(sessionStoreProvider).accessToken;
    if (token == null) {
      state = const AuthSignedOut();
      return;
    }
    // A stored token is provisional: the splash screen holds until the first
    // authenticated call either succeeds or triggers the refresh interceptor.
    try {
      await _ref.read(apiProvider).myBookings();
      state = const AuthUnknown();
    } catch (_) {
      state = const AuthSignedOut();
    }
  }

  void signedIn(AuthSession session) {
    state = session.profileComplete ? AuthSignedIn(session) : AuthNeedsProfile(session);
    _ref.read(realtimeProvider).connect(session.accessToken);
  }

  void profileCompleted(AuthSession session) => state = AuthSignedIn(session);

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

/// Load-shedding status drives a banner on the dashboard and, at stage 4+,
/// silently forces the power-backup filter in discovery.
final gridStatusProvider = FutureProvider.autoDispose<GridStatus>((ref) async {
  final country = ref.watch(countryCodeProvider);
  return ref.watch(apiProvider).gridStatus(country);
});
