// Drives the real router through the whole booking journey, as a thumb would:
// home -> a provider -> pick a service -> where and when -> review and pay ->
// pay -> the waiting room. Proves the screens connect, not just that they
// render.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_client/app/providers.dart';
import 'package:freshly_client/app/router.dart';
import 'package:freshly_core/freshly_core.dart';

import 'harness.dart';

/// A keychain that already holds a session, so the real AuthNotifier
/// restores it through /auth/me exactly as a returning user's app does.
class _StoredSession implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #read) return Future<String?>.value('tok');
    return Future<void>.value();
  }
}

/// No socket in the tour: the real client would keep a reconnect timer
/// alive against a server that does not exist.
class _NoSocket extends RealtimeClient {
  _NoSocket() : super(baseUrl: 'http://fake.invalid');
  @override
  void connect(String accessToken) {}
  @override
  void disconnect() {}
  @override
  void joinBooking(String bookingId) {}
  @override
  void leaveBooking(String bookingId) {}
}

class _FlowApi extends FakeApi {
  final checkouts = <String>[];

  @override
  Future<List<SavedAddress>> savedAddresses() async => [
        SavedAddress.fromJson({
          'id': 'addr1',
          'label': 'Home',
          'formatted': '14 King George Rd, Avondale',
          'lat': -17.7932,
          'lng': 31.0361,
          'isDefault': true,
          'accessNotes': 'Black gate, hoot twice',
        }),
      ];

  @override
  Future<CurrentUser> me() async => CurrentUser(
        id: 'u1',
        fullName: 'Rudo Chikore',
        phone: '+263772000002',
        roles: const ['client'],
        countryCode: 'ZW',
        profileComplete: true,
        serviceArea: sampleArea,
      );

  @override
  Future<Booking> createBooking(Map<String, dynamic> payload,
      {required String idempotencyKey}) async {
    return Booking.fromJson(sampleBookingJson('pending_auth', id: 'new1'));
  }

  @override
  Future<Map<String, dynamic>> checkout(String bookingId,
      {required String method, required String idempotencyKey}) async {
    checkouts.add(method);
    return {'status': 'authorized', 'bookingId': bookingId};
  }

  @override
  Future<Booking> booking(String id) async =>
      Booking.fromJson(sampleBookingJson('authorized', id: id));
}

void main() {
  setUpAll(loadFonts);

  testWidgets('book a skin fade from home to the waiting room', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    addTearDown(tester.view.reset);
    final api = _FlowApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...baseOverrides(),
        apiProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(SessionStore(_StoredSession())),
        realtimeProvider.overrideWithValue(_NoSocket()),
      ],
      child: Consumer(builder: (context, ref, _) {
        return MaterialApp.router(
          theme: FreshlyTheme.light(),
          routerConfig: ref.watch(routerProvider),
        );
      }),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await settle();
    expect(find.text('Top rated near you'), findsOneWidget, reason: 'home');

    await tester.scrollUntilVisible(find.text('Tendai Moyo').first, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle();
    await tester.tap(find.text('Tendai Moyo').first);
    await settle();
    expect(find.text('What clients say'), findsOneWidget, reason: 'provider');

    await tester.scrollUntilVisible(find.text('Skin fade'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Skin fade'));
    await settle();
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle();
    expect(find.text('Where and when'), findsOneWidget, reason: 'logistics');

    // The draft arrived with an address from the fake position resolver? No:
    // geocoding is a platform plugin, so the screen falls back to manual
    // entry and the button must stay disabled until an address exists.
    final review = find.widgetWithText(FilledButton, 'Review and pay');
    expect(tester.widget<FilledButton>(review).enabled, isFalse,
        reason: 'no address yet');

    // Pick the saved home address from the sheet.
    await tester.tap(find.text('Change'));
    await settle();
    await tester.tap(find.text('Home'));
    await settle();
    expect(find.text('14 King George Rd, Avondale'), findsWidgets);
    expect(find.text('Black gate, hoot twice'), findsOneWidget,
        reason: 'saved gate notes carried into the booking');
    expect(tester.widget<FilledButton>(review).enabled, isTrue);
    await tester.tap(review);
    await settle();

    expect(find.text('Confirm and pay'), findsOneWidget, reason: 'checkout');
    expect(find.text('US\$17.00'), findsWidgets, reason: 'server total shown');
    await tester.tap(find.text('EcoCash'));
    await settle();
    await tester.scrollUntilVisible(find.text('Pay US\$17.00'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Pay US\$17.00'));
    await settle();

    expect(api.checkouts, ['ecocash']);
    expect(find.text('Finding your pro'), findsOneWidget, reason: 'escrow');

    // Leave the waiting room so its poll timer is cancelled with it.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('rate a completed booking from the bookings tab', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    addTearDown(tester.view.reset);
    final api = _FlowApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...baseOverrides(),
        apiProvider.overrideWithValue(api),
        sessionStoreProvider.overrideWithValue(SessionStore(_StoredSession())),
        realtimeProvider.overrideWithValue(_NoSocket()),
      ],
      child: Consumer(builder: (context, ref, _) {
        return MaterialApp.router(
          theme: FreshlyTheme.light(),
          routerConfig: ref.watch(routerProvider),
        );
      }),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await settle();
    await tester.tap(find.text('Bookings'));
    await settle();
    expect(find.text('Past'), findsOneWidget, reason: 'bookings tab');
    // One completed booking is unrated and one already rated.
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Rated'), findsOneWidget);

    await tester.tap(find.text('Rate'));
    await settle();
    expect(find.text('Submit review'), findsOneWidget, reason: 'review');
    final submit = find.widgetWithText(FilledButton, 'Submit review');
    expect(tester.widget<FilledButton>(submit).enabled, isFalse,
        reason: 'no stars yet');

    await tester.tap(find.byTooltip('5 stars'));
    await tester.pump();
    await tester.tap(find.text('Clean kit'));
    await tester.pump();
    await tester.tap(submit);
    await settle();

    expect(api.reviews, hasLength(1));
    final (bookingId, rating, tags, comment) = api.reviews.single;
    expect(bookingId, 'b2');
    expect(rating, 5);
    expect(tags, ['Clean kit']);
    expect(comment, isNull);
    expect(find.text('Review sent'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await settle();
    expect(find.text('Past'), findsOneWidget, reason: 'back on the list');
  });
}
