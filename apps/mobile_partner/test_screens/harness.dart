// Screen tour harness: renders real partner screens with real fonts against a
// fake API so a designer can look at them without a phone, an emulator or a
// backend.
//
//   flutter test test_screens --update-goldens
//
// PNGs land in test_screens/out/ (git-ignored). This is a looking tool, not a
// regression suite: it lives outside test/ so CI never compares pixels that
// legitimately differ between machines.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';
import 'package:freshly_partner/app/providers.dart';
import 'package:freshly_partner/widgets/main_scaffold.dart';

Future<void> loadFonts() async {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, dynamic>;
  String root(String name) {
    final pkg = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == name);
    final uri = pkg['rootUri'] as String;
    return uri.startsWith('file://')
        ? Uri.parse(uri).toFilePath()
        : Directory('.dart_tool').uri.resolve(uri).toFilePath();
  }

  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  final core = root('freshly_core');
  final jakarta = [
    for (final w in [
      '400Regular',
      '500Medium',
      '600SemiBold',
      '700Bold',
      '800ExtraBold'
    ])
      '$core/assets/fonts/PlusJakartaSans_$w.ttf'
  ];
  await load('packages/freshly_core/PlusJakartaSans', jakarta);
  await load('PlusJakartaSans', jakarta);

  final cupertino = root('cupertino_icons');
  await load('packages/cupertino_icons/CupertinoIcons',
      ['$cupertino/assets/CupertinoIcons.ttf']);

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? '/opt/sdk/flutter';
  final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
  await load('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await load('Roboto', [
    '$material/Roboto-Regular.ttf',
    '$material/Roboto-Medium.ttf',
    '$material/Roboto-Bold.ttf',
  ]);
}

Map<String, dynamic> _money(int minor) => {'minor': minor, 'currency': 'USD'};

DateTime _today(int hour, [int minute = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, hour, minute);
}

Map<String, dynamic> bookingJson(
  String id,
  String status, {
  String ref = 'FR-7Q2K',
  String address = '14 King George Rd, Avondale',
  int totalMinor = 1050,
  DateTime? start,
  DateTime? arrivedAt,
  DateTime? completedAt,
  String? staffId,
  String? staffName,
  bool reviewed = false,
}) =>
    {
      'id': id,
      'reference': ref,
      'status': status,
      'destinationAddress': address,
      'total': _money(totalMinor),
      'providerId': 'p1',
      'providerName': 'Tendai Moyo',
      'serviceIds': ['s1'],
      'scheduledStart': start?.toIso8601String(),
      'arrivedAt': arrivedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'createdAt': _today(8).toIso8601String(),
      'assignedStaffId': staffId,
      'assignedStaffName': staffName,
      'reviewedByMe': reviewed,
    };

DispatchOffer sampleOffer() => DispatchOffer(
      offerId: 'o1',
      bookingId: 'b1',
      reference: 'FR-9M4T',
      serviceNames: const ['Skin fade', 'Beard trim'],
      distanceKm: 3.2,
      etaMinutes: 12,
      payout: const Money(minor: 1350, currency: 'USD'),
      destinationAddress: 'Mount Pleasant, Harare',
      expiresAt: DateTime.now().add(const Duration(seconds: 42)),
      clientRating: 4.8,
      durationMinutes: 65,
    );

class FakeApi extends FreshlyApi {
  FakeApi({
    this.kyc = 'verified',
    this.online = false,
    this.empty = false,
    this.businessMode = 'solo',
    this.hasBusiness = true,
    this.invited = false,
  }) : super(baseUrl: 'http://fake.invalid', session: SessionStore());

  final String kyc;
  final bool online;
  final bool empty;

  /// 'solo', 'salon' or 'salon_staff'.
  final String businessMode;

  /// False renders the app as a customer account that has not opened a
  /// business yet, which is who sees a salon's invitation.
  final bool hasBusiness;
  final bool invited;

  bool get _salon => businessMode == 'salon';

  @override
  Future<CurrentUser> me() async => CurrentUser.fromJson({
        'id': 'u1',
        'fullName': 'Tendai Moyo',
        'phone': '+263771234567',
        'roles': [hasBusiness ? 'provider' : 'client'],
        'countryCode': 'ZW',
        'profileComplete': true,
        if (hasBusiness)
          'provider': {'id': 'p1', 'kycStatus': kyc, 'isOnline': online},
      });

  @override
  Future<List<Market>> markets() async => [
        Market.fromJson({
          'code': 'ZW',
          'name': 'Zimbabwe',
          'currency': 'USD',
          'dialPrefix': '+263',
          'noShowGraceMinutes': 10,
          'emergencyNumber': '999',
        }),
      ];

  @override
  Future<ProviderBusiness> myBusiness() async => ProviderBusiness.fromJson({
        'id': 'p1',
        'displayName': _salon ? 'Blush & Blade Salon' : 'Tendai Moyo',
        'businessMode': businessMode,
        'categories': ['barber', 'beard'],
        'venueMode': _salon ? 'in_shop' : 'mobile',
        'powerBackup': ['inverter'],
        'kycStatus': kyc,
        'isOnline': online,
        'rating': 4.9,
        'ratingCount': 38,
        'completedJobs': 112,
        'currency': 'USD',
        'serviceArea': {'name': 'Avondale'},
      });

  // ─── Salon staff ──────────────────────────────────────────────────────

  @override
  Future<List<StaffMember>> myStaff() async => [
        for (final (id, name, phone, status, week, done) in [
          ('st1', 'Rudo Chikafu', '+263 77 ••• 0003', 'active', 6, 41),
          ('st2', 'Blessing Moyo', '+263 71 ••• 2210', 'active', 2, 9),
          ('inv1', null, '+263 78 ••• 7781', 'pending', 0, 0),
        ])
          StaffMember.fromJson({
            'id': id,
            'kind': status == 'pending' ? 'invite' : 'staff',
            'displayName': name,
            'phone': phone,
            'status': status,
            'jobsThisWeek': week,
            'completedJobs': done,
          }),
      ];

  @override
  Future<void> inviteStaff(String phoneE164) async {}

  @override
  Future<void> removeStaff(String id) async {}

  @override
  Future<void> assignBooking(String bookingId, String? staffId) async {}

  @override
  Future<List<StaffInvite>> staffInvites() async => invited
      ? [
          StaffInvite.fromJson({
            'id': 'inv1',
            'salonName': 'Blush & Blade Salon',
            'salonSuburb': 'Avondale',
          }),
        ]
      : [];

  @override
  Future<AuthSession> acceptStaffInvite(String id) async => const AuthSession(
        accessToken: 'token',
        refreshToken: 'refresh',
        userId: 'u1',
        fullName: 'Tendai Moyo',
        phone: '+263771234567',
        roles: ['client', 'provider'],
        countryCode: 'ZW',
        profileComplete: true,
        needsPhone: false,
        isNewUser: false,
      );

  // ─── Reviews, invoices, safety ────────────────────────────────────────

  @override
  Future<void> submitReview(String bookingId,
      {required int rating,
      List<String> tags = const [],
      String? comment}) async {}

  @override
  Future<List<Invoice>> invoices(String bookingId) async => [
        Invoice.fromJson({
          'id': 'i1',
          'kind': 'provider_to_client',
          'number': 'FR-ZW-2026-000412',
          'issuedAt': _today(11, 40).toIso8601String(),
          'currency': 'USD',
          'totalMinor': 1050,
        }),
        Invoice.fromJson({
          'id': 'i2',
          'kind': 'platform_to_provider',
          'number': 'FR-ZW-2026-000413',
          'issuedAt': _today(11, 40).toIso8601String(),
          'currency': 'USD',
          'totalMinor': 226,
        }),
      ];

  @override
  Future<List<int>> downloadInvoice(String invoiceId) async =>
      '%PDF-1.4 fake'.codeUnits;

  @override
  Future<Map<String, dynamic>> triggerSos(
          {String? bookingId,
          required double lat,
          required double lng,
          double? accuracyM,
          int? batteryPct}) async =>
      {'id': 'sos1', 'dispatched': true, 'emergencyNumber': '999'};

  @override
  Future<void> abortSos(String sosId) async {}

  @override
  Future<List<Booking>> myBookings({String? status}) async => empty
      ? []
      : status == 'completed'
          ? [
              Booking.fromJson(bookingJson('done', 'completed',
                  ref: 'FR-5RTM',
                  address: 'Belgravia, Harare',
                  totalMinor: 1200,
                  completedAt: _today(11, 35))),
              Booking.fromJson(bookingJson('done_rated', 'completed',
                  ref: 'FR-6NBC',
                  address: 'Milton Park, Harare',
                  totalMinor: 900,
                  completedAt: _today(17).subtract(const Duration(days: 1)),
                  reviewed: true)),
            ]
          : [
              Booking.fromJson(bookingJson('b1', 'en_route')),
              Booking.fromJson(bookingJson('b2', 'accepted',
                  ref: 'FR-3XHD',
                  address: 'Borrowdale Brooke, Harare',
                  totalMinor: 2500,
                  start: _today(16),
                  staffId: _salon ? 'st1' : null,
                  staffName: _salon ? 'Rudo Chikafu' : null)),
              Booking.fromJson(bookingJson('b3', 'accepted',
                  ref: 'FR-8KQW',
                  address: 'Greendale, Harare',
                  totalMinor: 800,
                  start: _today(10, 30).add(const Duration(days: 1)))),
              Booking.fromJson(bookingJson('b4', 'accepted',
                  ref: 'FR-2PLA',
                  address: 'Highlands, Harare',
                  totalMinor: 1500,
                  start: _today(14).add(const Duration(days: 3)))),
            ];

  @override
  Future<Booking> booking(String id) async => Booking.fromJson(switch (id) {
        'arrived' => bookingJson(id, 'arrived',
            arrivedAt: DateTime.now().subtract(const Duration(minutes: 4))),
        'working' => bookingJson(id, 'in_progress'),
        'scheduled' => bookingJson(id, 'accepted', start: _today(16)),
        'done' => bookingJson(id, 'completed',
            ref: 'FR-5RTM',
            address: 'Belgravia, Harare',
            totalMinor: 1200,
            completedAt: _today(11, 35)),
        'done_rated' => bookingJson(id, 'completed',
            ref: 'FR-6NBC',
            address: 'Milton Park, Harare',
            totalMinor: 900,
            completedAt: _today(17).subtract(const Duration(days: 1)),
            reviewed: true),
        'b2' => bookingJson(id, 'accepted',
            ref: 'FR-3XHD',
            address: 'Borrowdale Brooke, Harare',
            totalMinor: 2500,
            start: _today(16),
            staffId: _salon ? 'st1' : null,
            staffName: _salon ? 'Rudo Chikafu' : null),
        _ => bookingJson(id, 'en_route'),
      });

  @override
  Future<Map<String, dynamic>> wallet() async => {
        'currency': 'USD',
        'availableMinor': empty ? 0 : 18450,
        'pendingMinor': empty ? 0 : 3550,
        'lifetimeEarnedMinor': empty ? 0 : 214600,
        'instantFeeBps': 150,
        'canCashOut': !empty && kyc == 'verified',
        'blockedReason': kyc == 'verified' ? null : 'kyc_required',
      };

  @override
  Future<List<EarningsTransaction>> getEarningsHistory() async => empty
      ? []
      : [
          for (final (i, ref, svc, travel) in [
            (0, 'FR-7Q2K', 1000, 200),
            (1, 'FR-4HNM', 2500, 350),
            (2, 'FR-9WEX', 800, 150),
          ])
            EarningsTransaction.fromJson({
              'bookingId': 'e$i',
              'reference': ref,
              'completedAt':
                  DateTime.now().subtract(Duration(days: i)).toIso8601String(),
              'serviceMinor': svc,
              'travelMinor': travel,
              'commissionMinor': (svc * 12) ~/ 100,
              'currency': 'USD',
            }),
        ];

  @override
  Future<GridStatus> gridStatus(String countryCode) async =>
      GridStatus.fromJson({
        'countryCode': countryCode,
        'stage': 2,
        'source': 'zesa',
        'nextWindow': {
          'start': _today(18).toIso8601String(),
          'end': _today(20).toIso8601String(),
        },
      });

  @override
  Future<Map<String, dynamic>> kycStatus() async => {'status': 'unstarted'};

  @override
  Future<List<ProviderMenuItem>> getMyMenu() async => [
        for (final (id, name, cat, minor, mins) in [
          ('m1', 'Skin fade', 'barber', 1000, 45),
          ('m2', 'Beard trim and shape', 'beard', 500, 20),
          ('m3', 'Kids cut (under 12)', 'barber', 600, 30),
          ('m4', 'Scalp treatment', 'scalp', 1500, 40),
        ])
          ProviderMenuItem.fromJson({
            'id': id,
            'catalogServiceId': 'c$id',
            'name': name,
            'category': cat,
            'price': _money(minor),
            'priceMinor': minor,
            'currency': 'USD',
            'durationMinutes': mins,
          }),
      ];

  @override
  Future<List<ClientSummary>> getMyClients() async => [
        for (final (id, name, n) in [
          ('c1', 'Kuda Mutasa', 12),
          ('c2', 'Nyasha Chari', 4),
          ('c3', 'Tafadzwa Ncube', 1),
        ])
          ClientSummary.fromJson({
            'id': id,
            'fullName': name,
            'phone': '+263771112222',
            'lastBookingAt':
                DateTime.now().subtract(Duration(days: n)).toIso8601String(),
            'bookingCount': n,
          }),
      ];

  @override
  Future<ClientDetail> getClientDetail(String id) async =>
      ClientDetail.fromJson({
        'id': id,
        'fullName': 'Kuda Mutasa',
        'phone': '+263771112222',
        'rating': 4.9,
        'ratingCount': 12,
        'joinedAt': DateTime(2026, 3, 2).toIso8601String(),
        'notes': 'Number 2 on the sides, keep the top long. Gate code 4471.',
        'history': [
          {
            'id': 'h1',
            'reference': 'FR-7Q2K',
            'status': 'completed',
            'createdAt': _today(9).toIso8601String(),
            'total': _money(1050),
            'services': ['Skin fade'],
          },
          {
            'id': 'h2',
            'reference': 'FR-1ZZA',
            'status': 'cancelled',
            'createdAt': DateTime(2026, 9, 20).toIso8601String(),
            'total': _money(500),
            'services': ['Beard trim and shape'],
          },
        ],
      });

  @override
  Future<List<Map<String, dynamic>>> getMyReviews() async => [
        {
          'rating': 5,
          'author': 'Kuda',
          'comment': 'On time even with the power off. Best fade in Avondale.',
          'tags': ['On time', 'Great cut'],
          'createdAt': _today(11).toIso8601String(),
        },
        {
          'rating': 4,
          'author': 'Nyasha',
          'comment': 'Came to the house for my boys, very patient with them.',
          'tags': ['Friendly'],
          'createdAt': DateTime(2026, 10, 2).toIso8601String(),
        },
      ];

  @override
  Future<List<PortfolioItem>> getMyPortfolio() async => [];

  @override
  Future<List<WorkingHours>> workingHours() async => [
        for (final d in [1, 2, 3, 4, 5])
          WorkingHours(weekday: d, startsAt: '08:00', endsAt: '18:00'),
        const WorkingHours(weekday: 6, startsAt: '09:00', endsAt: '14:00'),
      ];

  @override
  Future<List<SupportTicket>> myTickets() async => [
        SupportTicket.fromJson({
          'id': 't1',
          'subject': 'Cash-out still processing',
          'body': 'My Tuesday cash-out of US\$48 has been processing for '
              'two days. Reference FR-4HNM.',
          'status': 'open',
          'createdAt': DateTime(2026, 10, 15, 9).toIso8601String(),
          'messages': [
            {
              'id': 'm1',
              'isStaff': true,
              'body': 'Hi Tendai, EcoCash confirmed it this morning. It '
                  'should show on your wallet within the hour.',
              'createdAt': DateTime(2026, 10, 16, 11).toIso8601String(),
            },
          ],
        }),
      ];
}

/// Restores a session without touching secure storage.
class FakeSessionStore extends SessionStore {
  @override
  Future<String?> get accessToken async => 'token';
  @override
  Future<String?> get refreshToken async => 'refresh';
}

/// Never opens a socket.
class FakeRealtime extends RealtimeClient {
  FakeRealtime() : super(baseUrl: 'http://fake.invalid');
  @override
  void connect(String accessToken) {}
  @override
  void disconnect() {}
}

/// Presence without the GPS stream, which needs a platform plugin.
class FakePresence extends PresenceNotifier {
  FakePresence(super.ref, bool online) {
    state = online;
  }
  @override
  void restoreOnline() {}
}

List<Override> partnerOverrides({
  String kyc = 'verified',
  bool online = false,
  bool empty = false,
  String businessMode = 'solo',
  bool hasBusiness = true,
  bool invited = false,
}) =>
    [
      apiProvider.overrideWithValue(FakeApi(
          kyc: kyc,
          online: online,
          empty: empty,
          businessMode: businessMode,
          hasBusiness: hasBusiness,
          invited: invited)),
      sessionStoreProvider.overrideWithValue(FakeSessionStore()),
      realtimeProvider.overrideWithValue(FakeRealtime()),
      presenceProvider.overrideWith((ref) => FakePresence(ref, online)),
    ];

/// Renders [builder] as the app's first route at phone size and writes
/// out/[name].png. [height] lets a scrolling page be captured whole.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget Function(BuildContext) builder, {
  double height = 844,
  List<Override>? overrides,
  bool withNav = false,
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(390 * 2, height * 2);
  tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
  addTearDown(tester.view.reset);

  StatefulShellBranch branch(String path, Widget Function(BuildContext) b) =>
      StatefulShellBranch(
          routes: [GoRoute(path: path, builder: (c, _) => b(c))]);
  final router = GoRouter(routes: [
    if (withNav)
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => MainScaffold(navigationShell: shell),
        branches: [
          branch('/', builder),
          branch('/x1', (_) => const SizedBox()),
          branch('/x2', (_) => const SizedBox()),
          branch('/x3', (_) => const SizedBox()),
        ],
      )
    else
      GoRoute(path: '/', builder: (c, _) => builder(c)),
    GoRoute(
        path: '/:rest(.*)',
        builder: (_, __) => const Scaffold(body: SizedBox())),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: overrides ?? partnerOverrides(),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: FreshlyTheme.light(),
      darkTheme: FreshlyTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (act != null) {
    await act(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  await expectLater(
      find.byType(MaterialApp), matchesGoldenFile('out/$name.png'));

  // Tear the tree down so periodic timers (offer countdown, no-show clock,
  // skeleton shimmer) are cancelled before the test ends.
  await tester.pumpWidget(const SizedBox());
}
