import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/models.dart';

/// Persists the session on the device keychain / Android keystore.
/// Tokens never touch SharedPreferences — on a rooted or jailbroken handset
/// that is a plaintext file, and these tokens can authorise a payment.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions:
                  IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  final FlutterSecureStorage _storage;
  static const _accessKey = 'freshly.access';
  static const _refreshKey = 'freshly.refresh';

  Future<void> save(AuthSession session) async {
    await _storage.write(key: _accessKey, value: session.accessToken);
    await _storage.write(key: _refreshKey, value: session.refreshToken);
  }

  Future<String?> get accessToken => _storage.read(key: _accessKey);
  Future<String?> get refreshToken => _storage.read(key: _refreshKey);

  Future<void> updateAccessToken(String token) =>
      _storage.write(key: _accessKey, value: token);

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// Errors surfaced to the UI carry the backend's stable machine code, so
/// screens branch on `code`, never on a localised message string.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.statusCode, this.details});
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  bool get isOffline => code == 'network_offline';
  bool get isAuthFailure => statusCode == 401;

  @override
  String toString() => 'ApiException($code): $message';
}

class FreshlyApi {
  FreshlyApi({
    required String baseUrl,
    required this.session,
    this.onUnauthenticated,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _attachAuth,
      onError: _handleError,
    ));
  }

  final Dio _dio;
  final SessionStore session;
  final void Function()? onUnauthenticated;

  Completer<void>? _refreshInFlight;

  Future<void> _attachAuth(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await session.accessToken;
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }

  /// Endpoints where a 401 must NOT trigger a refresh.
  ///
  /// Only sign-in itself and the refresh call, which would recurse. This was
  /// previously any path containing '/auth/', which silently included
  /// `/auth/me` — the one call made at every launch. An access token expires
  /// after fifteen minutes, so opening the app the next morning produced a 401
  /// on `/auth/me`, no refresh was attempted, and `_restore` reacted by
  /// clearing a perfectly good thirty-day refresh token. Every user was
  /// signed out on the next launch.
  static const _neverRefresh = [
    '/auth/refresh',
    '/auth/otp/request',
    '/auth/otp/verify',
    '/auth/firebase',
  ];

  /// Whether a 401 on this path should trigger a token refresh.
  ///
  /// Public and pure so the rule can be asserted directly. The bug it replaced
  /// was invisible in the app until a session had aged past the access token
  /// TTL, which is exactly the kind of thing a test should catch instead.
  static bool shouldAttemptRefresh(String path) =>
      !_neverRefresh.any(path.startsWith);

  /// A 401 triggers exactly one refresh attempt, shared across every request
  /// that failed concurrently. Without the completer, a screen that fires four
  /// parallel calls on resume would rotate the refresh token four times and
  /// invalidate its own session.
  Future<void> _handleError(
      DioException error, ErrorInterceptorHandler handler) async {
    final response = error.response;

    if (response?.statusCode == 401 &&
        shouldAttemptRefresh(error.requestOptions.path)) {
      try {
        await _refreshSession();
        final retried = await _dio.fetch(error.requestOptions);
        return handler.resolve(retried);
      } catch (_) {
        await session.clear();
        onUnauthenticated?.call();
      }
    }

    if (response?.data is Map) {
      final body = response!.data as Map<String, dynamic>;
      return handler.reject(DioException(
        requestOptions: error.requestOptions,
        error: ApiException(
          body['code'] as String? ?? 'unknown_error',
          body['message'] as String? ?? 'Something went wrong',
          statusCode: response.statusCode,
          details: body['details'] as Map<String, dynamic>?,
        ),
      ));
    }

    final offline = error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout;
    return handler.reject(DioException(
      requestOptions: error.requestOptions,
      error: ApiException(
        offline ? 'network_offline' : 'network_error',
        offline
            ? 'You appear to be offline. Check your connection and try again.'
            : 'We could not reach Freshly. Please try again.',
      ),
    ));
  }

  Future<void> _refreshSession() async {
    if (_refreshInFlight != null) return _refreshInFlight!.future;
    final completer = Completer<void>();
    _refreshInFlight = completer;
    try {
      final refresh = await session.refreshToken;
      if (refresh == null)
        throw ApiException('no_refresh_token', 'Sign in again');
      final res = await Dio(BaseOptions(baseUrl: _dio.options.baseUrl))
          .post<Map<String, dynamic>>('/auth/refresh',
              data: {'refreshToken': refresh});
      await session.save(AuthSession.fromJson(res.data!));
      completer.complete();
    } catch (err) {
      completer.completeError(err);
      rethrow;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<T> _unwrap<T>(
      Future<Response<dynamic>> call, T Function(dynamic) parse) async {
    try {
      final res = await call;
      return parse(res.data);
    } on DioException catch (e) {
      throw e.error is ApiException
          ? e.error as ApiException
          : ApiException('unknown_error', e.message ?? 'Request failed');
    }
  }

  // ─── Auth ────────────────────────────────────────────────────────────────
  Future<void> requestOtp(String phone, String countryCode) => _unwrap(
        _dio.post('/auth/otp/request',
            data: {'phone': phone, 'countryCode': countryCode}),
        (_) {},
      );

  Future<AuthSession> verifyOtp(
    String phone,
    String countryCode,
    String code, {
    String? platform,
    String? pushToken,
  }) async {
    final result = await _unwrap(
      _dio.post('/auth/otp/verify', data: {
        'phone': phone,
        'countryCode': countryCode,
        'code': code,
        if (platform != null) 'platform': platform,
        if (pushToken != null) 'pushToken': pushToken,
      }),
      (d) => AuthSession.fromJson(d as Map<String, dynamic>),
    );
    await session.save(result);
    return result;
  }

  /// Exchange a Firebase phone-auth ID token for a Freshly session.
  ///
  /// Firebase proves the person holds the phone number; the roles, suspension
  /// state and everything else still come from our own JWT, issued here. The
  /// app does the Firebase dance and hands us only the resulting token.
  Future<AuthSession> signInWithFirebase(
    String idToken,
    String countryCode, {
    String? platform,
    String? pushToken,
  }) async {
    final result = await _unwrap(
      _dio.post('/auth/firebase', data: {
        'idToken': idToken,
        'countryCode': countryCode,
        if (platform != null) 'platform': platform,
        if (pushToken != null) 'pushToken': pushToken,
      }),
      (d) => AuthSession.fromJson(d as Map<String, dynamic>),
    );
    await session.save(result);
    return result;
  }

  /// Attach a verified phone to a social/email account, using a Firebase
  /// phone-auth token. Returns a fresh session with the number now linked.
  Future<AuthSession> linkPhone(String idToken, String countryCode) async {
    final result = await _unwrap(
      _dio.post('/auth/link-phone',
          data: {'idToken': idToken, 'countryCode': countryCode}),
      (d) => AuthSession.fromJson(d as Map<String, dynamic>),
    );
    await session.save(result);
    return result;
  }

  Future<void> completeProfile({
    required String fullName,
    String? email,
    required bool acceptTerms,
    required bool acceptPrivacy,
    bool acceptMarketing = false,
  }) =>
      _unwrap(
        _dio.post('/auth/profile', data: {
          'fullName': fullName,
          if (email != null) 'email': email,
          'acceptTerms': acceptTerms,
          'acceptPrivacy': acceptPrivacy,
          'acceptMarketing': acceptMarketing,
        }),
        (_) {},
      );

  /// Turn the signed-in account into a provider. Returns a new session,
  /// because the provider role and id live in the token; the caller must
  /// replace the one it holds.
  Future<AuthSession> becomeProvider(ProviderSignUp input) async {
    final result = await _unwrap(
      _dio.post('/auth/become-provider', data: input.toJson()),
      (d) => AuthSession.fromJson(d as Map<String, dynamic>),
    );
    await session.save(result);
    return result;
  }

  Future<ProviderBusiness> myBusiness() => _unwrap(_dio.get('/providers/me'),
      (d) => ProviderBusiness.fromJson(d as Map<String, dynamic>));

  /// Only the fields given change; everything else stays as it is.
  Future<ProviderBusiness> updateBusiness(Map<String, dynamic> changes) =>
      _unwrap(
        _dio.patch('/providers/me', data: changes),
        (d) => ProviderBusiness.fromJson(d as Map<String, dynamic>),
      );

  Future<List<WorkingHours>> workingHours() => _unwrap(
      _dio.get('/providers/me/availability/rules'),
      (d) => (d as List)
          .map((r) => WorkingHours.fromJson(r as Map<String, dynamic>))
          .toList());

  /// Replaces the whole week.
  Future<List<WorkingHours>> setWorkingHours(List<WorkingHours> rules) =>
      _unwrap(
        _dio.put('/providers/me/availability/rules',
            data: {'rules': rules.map((r) => r.toJson()).toList()}),
        (d) => (d as List)
            .map((r) => WorkingHours.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  /// Suggest one more service mid-job. The client approves it in their app
  /// before anything is charged.
  Future<AddonRequest> requestAddon(String bookingId, String serviceId) =>
      _unwrap(
        _dio.post('/bookings/$bookingId/addons',
            data: {'serviceId': serviceId}),
        (d) => AddonRequest.fromJson(d as Map<String, dynamic>),
      );

  /// The signed-in user. Used to restore a session at launch — the stored
  /// token proves nothing about the account's current state.
  Future<CurrentUser> me() => _unwrap(_dio.get('/auth/me'),
      (d) => CurrentUser.fromJson(d as Map<String, dynamic>));

  Future<void> logout() async {
    await _unwrap(_dio.post('/auth/logout'), (_) {});
    await session.clear();
  }

  Future<void> updatePushToken(String token) => _unwrap(
        _dio.post('/auth/push-token', data: {'pushToken': token}),
        (_) {},
      );

  // ─── Where we operate ────────────────────────────────────────────────────
  /// Live markets. Public, because someone deciding whether to sign up is
  /// entitled to know whether we cover them before handing over a number.
  Future<List<Market>> markets() => _unwrap(
        _dio.get('/markets'),
        (d) => (d as List)
            .map((e) => Market.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<List<ServiceArea>> serviceAreas() => _unwrap(
        _dio.get('/markets/areas'),
        (d) => (d as List)
            .map((e) => ServiceArea.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Suburb autocomplete. Only ever suggests somewhere we actually operate, so
  /// a result the user picks can always be served.
  ///
  /// An empty query returns the busiest suburbs, which makes the field useful
  /// before the first keystroke.
  Future<List<Place>> places(
          {String? query, String? countryCode, int limit = 8}) =>
      _unwrap(
        _dio.get('/markets/places', queryParameters: {
          if (query != null && query.isNotEmpty) 'q': query,
          if (countryCode != null) 'countryCode': countryCode,
          'limit': limit,
        }),
        (d) => (d as List)
            .map((e) => Place.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  // ─── Addresses ───────────────────────────────────────────────────────────

  /// Street-address autocomplete, brokered through our API so the Places key
  /// never ships in the app.
  ///
  /// [sessionToken] must stay the same for every keystroke of one address and
  /// change once it is chosen. Google bills a session, not a request, and a
  /// fresh token per keystroke turns roughly $2.83 per thousand addresses into
  /// something closer to $80.
  Future<List<AddressSuggestion>> searchAddresses({
    required String query,
    required String sessionToken,
    String countryCode = 'ZA',
    double? nearLat,
    double? nearLng,
  }) =>
      _unwrap(
        _dio.get('/markets/address-search', queryParameters: {
          'q': query,
          'session': sessionToken,
          'countryCode': countryCode,
          if (nearLat != null) 'lat': nearLat,
          if (nearLng != null) 'lng': nearLng,
        }),
        (d) => (d as List)
            .map((e) => AddressSuggestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Turn a chosen suggestion into something bookable. Same session token.
  Future<ResolvedAddress> resolveAddress(String placeId, String sessionToken) =>
      _unwrap(
        _dio.get('/markets/address-search/$placeId',
            queryParameters: {'session': sessionToken}),
        (d) => ResolvedAddress.fromJson(d as Map<String, dynamic>),
      );

  Future<List<SavedAddress>> savedAddresses() => _unwrap(
        _dio.get('/addresses'),
        (d) => (d as List)
            .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<SavedAddress> saveAddress({
    required String label,
    required String formatted,
    required double lat,
    required double lng,
    String? unitNotes,
    String? accessNotes,
    bool? isDefault,
  }) =>
      _unwrap(
        _dio.post('/addresses', data: {
          'label': label,
          'formatted': formatted,
          'lat': lat,
          'lng': lng,
          if (unitNotes != null) 'unitNotes': unitNotes,
          if (accessNotes != null) 'accessNotes': accessNotes,
          if (isDefault != null) 'isDefault': isDefault,
        }),
        (d) => SavedAddress.fromJson(d as Map<String, dynamic>),
      );

  Future<void> deleteAddress(String id) =>
      _unwrap(_dio.delete('/addresses/$id'), (_) {});

  /// Where the user wants service. Asked at sign-up and changeable at any time
  /// afterwards — it is the same call either way.
  ///
  /// Prefer [placeId]: a suburb is what the person recognises, and it decides
  /// the area on the server, so the two can never disagree.
  Future<ServiceArea> setServiceArea(
          {String? serviceAreaId, String? placeId}) =>
      _unwrap(
        _dio.post('/auth/service-area', data: {
          if (serviceAreaId != null) 'serviceAreaId': serviceAreaId,
          if (placeId != null) 'placeId': placeId,
        }),
        (d) => ServiceArea.fromJson(d as Map<String, dynamic>),
      );

  // ─── Discovery ───────────────────────────────────────────────────────────
  Future<List<ProviderSummary>> searchProviders({
    required double lat,
    required double lng,
    double radiusKm = 10,
    ServiceCategory? category,
    String? serviceId,
    String? venue,
    int? maxPriceMinor,
    double minRating = 0,
    bool requirePowerBackup = false,
    bool instantOnly = false,
    int limit = 20,
    int offset = 0,
  }) =>
      _unwrap(
        _dio.get('/discovery/providers', queryParameters: {
          'lat': lat,
          'lng': lng,
          'radiusKm': radiusKm,
          if (category != null) 'category': category.wire,
          if (serviceId != null) 'serviceId': serviceId,
          if (venue != null) 'venue': venue,
          if (maxPriceMinor != null) 'maxPriceMinor': maxPriceMinor,
          'minRating': minRating,
          'requirePowerBackup': requirePowerBackup,
          'instantOnly': instantOnly,
          'limit': limit,
          'offset': offset,
        }),
        (d) => (d as List).map((e) => ProviderSummary.fromJson(e)).toList(),
      );

  Future<Map<String, dynamic>> providerProfile(String providerId) => _unwrap(
        _dio.get('/providers/$providerId'),
        (d) => d as Map<String, dynamic>,
      );

  Future<GridStatus> gridStatus(String countryCode) => _unwrap(
        _dio.get('/grid/status', queryParameters: {'countryCode': countryCode}),
        (d) => GridStatus.fromJson(d as Map<String, dynamic>),
      );

  // ─── Catalog ─────────────────────────────────────────────────────────────
  Future<List<CategorySummary>> catalogCategories() => _unwrap(
        _dio.get('/catalog/categories'),
        (d) => (d as List)
            .map((e) => CategorySummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<List<CatalogService>> catalogServices({ServiceCategory? category}) =>
      _unwrap(
        _dio.get('/catalog/services', queryParameters: {
          if (category != null) 'category': category.wire,
        }),
        (d) => (d as List)
            .map((e) => CatalogService.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<List<ProviderMenuItem>> getMyMenu() => _unwrap(
        _dio.get('/catalog/me/menu'),
        (d) => (d as List)
            .map((e) => ProviderMenuItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<ProviderMenuItem> updateMenuItem({
    required String catalogServiceId,
    required int priceMinor,
  }) =>
      _unwrap(
        _dio.post('/catalog/me/menu', data: {
          'catalogServiceId': catalogServiceId,
          'priceMinor': priceMinor
        }),
        (d) => ProviderMenuItem.fromJson(d as Map<String, dynamic>),
      );

  Future<void> removeMenuItem(String catalogServiceId) => _unwrap(
        _dio.delete('/catalog/me/menu/$catalogServiceId'),
        (_) {},
      );

  Future<ParsedIntent> parseIntent(String text) => _unwrap(
        _dio.post('/ai/parse-intent', data: {'text': text}),
        (d) => ParsedIntent.fromJson(d as Map<String, dynamic>),
      );

  // ─── Bookings ────────────────────────────────────────────────────────────
  Future<PriceQuote> quote({
    required String providerId,
    required List<String> serviceIds,
    required double lat,
    required double lng,
    String? promoCode,
  }) =>
      _unwrap(
        _dio.post('/bookings/quote', data: {
          'providerId': providerId,
          'serviceIds': serviceIds,
          'destination': {'lat': lat, 'lng': lng},
          if (promoCode != null) 'promoCode': promoCode,
        }),
        (d) => PriceQuote.fromJson(d as Map<String, dynamic>),
      );

  Future<Booking> createBooking(Map<String, dynamic> payload,
          {required String idempotencyKey}) =>
      _unwrap(
        _dio.post('/bookings',
            data: payload,
            options: Options(headers: {'Idempotency-Key': idempotencyKey})),
        (d) => Booking.fromJson(d as Map<String, dynamic>),
      );

  Future<Map<String, dynamic>> checkout(
    String bookingId, {
    required String method,
    required String idempotencyKey,
  }) =>
      _unwrap(
        _dio.post('/bookings/$bookingId/checkout',
            data: {'method': method},
            options: Options(headers: {'Idempotency-Key': idempotencyKey})),
        (d) => d as Map<String, dynamic>,
      );

  Future<Booking> booking(String id) => _unwrap(_dio.get('/bookings/$id'),
      (d) => Booking.fromJson(d as Map<String, dynamic>));

  Future<List<Booking>> myBookings({String? status}) => _unwrap(
        _dio.get('/bookings',
            queryParameters: {if (status != null) 'status': status}),
        (d) => (d as List).map((e) => Booking.fromJson(e)).toList(),
      );

  Future<String> completionPin(String bookingId) => _unwrap(
        _dio.get('/bookings/$bookingId/pin'),
        (d) => (d as Map<String, dynamic>)['pin'] as String,
      );

  Future<void> cancelBooking(String bookingId, String reason) => _unwrap(
        _dio.post('/bookings/$bookingId/cancel', data: {'reason': reason}),
        (_) {},
      );

  Future<void> respondToAddon(String bookingId, String itemId, bool approve) =>
      _unwrap(
        _dio.post('/bookings/$bookingId/addons/$itemId/respond',
            data: {'approve': approve}),
        (_) {},
      );

  Future<void> submitReview(
    String bookingId, {
    required int rating,
    List<String> tags = const [],
    String? comment,
  }) =>
      _unwrap(
        _dio.post('/bookings/$bookingId/review', data: {
          'rating': rating,
          'tags': tags,
          if (comment != null) 'comment': comment
        }),
        (_) {},
      );

  // ─── Provider app ────────────────────────────────────────────────────────
  Future<void> setOnline(bool online) => _unwrap(
      _dio.post('/providers/me/presence', data: {'isOnline': online}), (_) {});

  Future<void> pushLocation(double lat, double lng,
          {double? heading, double? speedKph}) =>
      _unwrap(
        _dio.post('/providers/me/location', data: {
          'lat': lat,
          'lng': lng,
          if (heading != null) 'heading': heading,
          if (speedKph != null) 'speedKph': speedKph,
        }),
        (_) {},
      );

  Future<void> respondToOffer(String offerId, bool accept, {String? reason}) =>
      _unwrap(
        _dio.post('/dispatch/offers/$offerId/respond',
            data: {'accept': accept, if (reason != null) 'reason': reason}),
        (_) {},
      );

  Future<void> advanceBooking(String bookingId, String toStatus) => _unwrap(
        _dio.post('/bookings/$bookingId/status', data: {'status': toStatus}),
        (_) {},
      );

  Future<void> verifyPin(String bookingId, String pin) => _unwrap(
      _dio.post('/bookings/$bookingId/verify-pin', data: {'pin': pin}), (_) {});

  /// Finish a job and release escrow.
  ///
  /// Deliberately not part of advanceBooking: completion captures the client's
  /// money, so it is a distinct endpoint carrying an idempotency key. A
  /// retried network call must never capture twice.
  Future<void> completeBooking(String bookingId,
          {required String idempotencyKey}) =>
      _unwrap(
        _dio.post('/bookings/$bookingId/complete',
            options: Options(headers: {'Idempotency-Key': idempotencyKey})),
        (_) {},
      );

  Future<Map<String, dynamic>> wallet() =>
      _unwrap(_dio.get('/payouts/wallet'), (d) => d as Map<String, dynamic>);

  /// Cash out. `instant` defaults to false — the free daily batch — so a fee
  /// is never applied because a caller forgot to pass a flag.
  Future<Map<String, dynamic>> requestPayout(
    int amountMinor, {
    required String idempotencyKey,
    bool instant = false,
  }) =>
      _unwrap(
        _dio.post('/payouts',
            data: {'amountMinor': amountMinor, 'instant': instant},
            options: Options(headers: {'Idempotency-Key': idempotencyKey})),
        (d) => d as Map<String, dynamic>,
      );

  Future<List<Map<String, dynamic>>> payoutHistory() => _unwrap(
        _dio.get('/payouts'),
        (d) => (d as List).cast<Map<String, dynamic>>(),
      );

  Future<List<EarningsTransaction>> getEarningsHistory() => _unwrap(
        _dio.get('/payouts/transactions'),
        (d) => (d as List)
            .map((e) => EarningsTransaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<List<Map<String, dynamic>>> payoutAccounts() => _unwrap(
        _dio.get('/payouts/accounts'),
        (d) => (d as List).cast<Map<String, dynamic>>(),
      );

  Future<Map<String, dynamic>> addPayoutAccount({
    required String method,
    required String accountNumber,
    required String accountName,
    String? institutionCode,
    String? institutionName,
  }) =>
      _unwrap(
        _dio.post('/payouts/accounts', data: {
          'method': method,
          'accountNumber': accountNumber,
          'accountName': accountName,
          if (institutionCode != null) 'institutionCode': institutionCode,
          if (institutionName != null) 'institutionName': institutionName,
        }),
        (d) => d as Map<String, dynamic>,
      );

  // ─── Identity verification ───────────────────────────────────────────────
  Future<Map<String, dynamic>> kycStatus() =>
      _unwrap(_dio.get('/kyc/status'), (d) => d as Map<String, dynamic>);

  Future<Map<String, dynamic>> submitKyc({
    required String documentType,
    required String idNumber,
    required String fullName,
    String? dateOfBirth,
    String? documentFrontKey,
    String? documentBackKey,
    String? selfieKey,
  }) =>
      _unwrap(
        _dio.post('/kyc/submissions', data: {
          'documentType': documentType,
          'idNumber': idNumber,
          'fullName': fullName,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
          if (documentFrontKey != null) 'documentFrontKey': documentFrontKey,
          if (documentBackKey != null) 'documentBackKey': documentBackKey,
          if (selfieKey != null) 'selfieKey': selfieKey,
        }),
        (d) => d as Map<String, dynamic>,
      );

  Future<void> blockAvailability({
    required DateTime start,
    required DateTime end,
    String reason = 'load_shedding',
  }) =>
      _unwrap(
        _dio.post('/providers/me/availability/blocks', data: {
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
          'reason': reason,
        }),
        (_) {},
      );

  Future<List<PortfolioItem>> getMyPortfolio() => _unwrap(
        _dio.get('/providers/me/portfolio'),
        (d) => (d as List)
            .map((e) => PortfolioItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<PortfolioItem> addPortfolioItem({
    required String mediaKey,
    List<String> tags = const [],
  }) =>
      _unwrap(
        _dio.post('/providers/me/portfolio',
            data: {'mediaKey': mediaKey, 'tags': tags}),
        (d) => PortfolioItem.fromJson(d as Map<String, dynamic>),
      );

  Future<void> removePortfolioItem(String id) => _unwrap(
        _dio.delete('/providers/me/portfolio/$id'),
        (_) {},
      );

  // ─── CRM ─────────────────────────────────────────────────────────────────
  Future<List<ClientSummary>> getMyClients() => _unwrap(
        _dio.get('/providers/me/clients'),
        (d) => (d as List)
            .map((e) => ClientSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<ClientDetail> getClientDetail(String id) => _unwrap(
        _dio.get('/providers/me/clients/$id'),
        (d) => ClientDetail.fromJson(d as Map<String, dynamic>),
      );

  Future<void> updateClientNotes(String id, String notes) => _unwrap(
        _dio.post('/providers/me/clients/$id/notes', data: {'notes': notes}),
        (_) {},
      );

  Future<List<Map<String, dynamic>>> getMyReviews() => _unwrap(
        _dio.get('/providers/me/reviews'),
        (d) => (d as List).cast<Map<String, dynamic>>(),
      );

  // ─── Chat ────────────────────────────────────────────────────────────────
  Future<List<ChatMessage>> getChatHistory(String bookingId) => _unwrap(
        _dio.get('/bookings/$bookingId/chat'),
        (d) => (d as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Future<ChatMessage> sendChatMessage(String bookingId, String body) => _unwrap(
        _dio.post('/bookings/$bookingId/chat', data: {'body': body}),
        (d) => ChatMessage.fromJson(d as Map<String, dynamic>),
      );

  Future<void> markChatAsRead(String bookingId) => _unwrap(
        _dio.post('/bookings/$bookingId/chat/read'),
        (_) {},
      );

  // ─── Safety ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> triggerSos({
    String? bookingId,
    required double lat,
    required double lng,
    double? accuracyM,
    int? batteryPct,
  }) =>
      _unwrap(
        _dio.post('/safety/sos', data: {
          if (bookingId != null) 'bookingId': bookingId,
          'lat': lat,
          'lng': lng,
          if (accuracyM != null) 'accuracyM': accuracyM,
          if (batteryPct != null) 'batteryPct': batteryPct,
        }),
        (d) => d as Map<String, dynamic>,
      );

  Future<void> abortSos(String sosId) =>
      _unwrap(_dio.post('/safety/sos/$sosId/abort'), (_) {});

  // ─── Storage ─────────────────────────────────────────────────────────────
  Future<UploadInstruction> getUploadUrl(String contentType) => _unwrap(
        _dio.post('/storage/uploads', data: {'contentType': contentType}),
        (d) => UploadInstruction.fromJson(d as Map<String, dynamic>),
      );

  /// Uploads a file to a signed URL.
  ///
  /// The Authorization header is NOT sent — a signed URL carries its own proof
  /// of permission, and a service role token or a user JWT will cause most
  /// cloud providers to reject the request.
  Future<void> uploadFile(
      String url, List<int> bytes, String contentType) async {
    final res = await Dio().put(
      url,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          'Content-Type': contentType,
          'Content-Length': bytes.length,
        },
      ),
    );
    if (res.statusCode! < 200 || res.statusCode! >= 300) {
      throw ApiException('upload_failed', 'Could not upload file');
    }
  }
}

class ParsedIntent {
  const ParsedIntent({
    required this.category,
    required this.rawQuery,
    required this.bookingType,
    required this.powerBackupRequired,
    this.targetDate,
    this.targetTime,
    this.locationContext,
  });

  final ServiceCategory? category;
  final String rawQuery;
  final String bookingType;
  final bool powerBackupRequired;
  final String? targetDate;
  final String? targetTime;
  final String? locationContext;

  factory ParsedIntent.fromJson(Map<String, dynamic> j) => ParsedIntent(
        category: j['serviceCategory'] != null
            ? ServiceCategory.fromWire(j['serviceCategory'] as String)
            : null,
        rawQuery: j['rawSearchQuery'] as String? ?? '',
        bookingType: j['bookingType'] as String? ?? 'instant',
        powerBackupRequired: j['powerBackupRequired'] as bool? ?? false,
        targetDate: j['targetDate'] as String?,
        targetTime: j['targetTime'] as String?,
        locationContext: j['locationContext'] as String?,
      );
}
