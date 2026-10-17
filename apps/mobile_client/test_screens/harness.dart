// Screen tour harness: renders real screens with real fonts against a fake API
// so a designer can look at them without a phone, an emulator or a backend.
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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:freshly_client/app/phone_auth.dart';
import 'package:freshly_client/app/providers.dart';
import 'package:freshly_client/features/booking/booking_draft.dart';
import 'package:freshly_client/widgets/main_scaffold.dart';
import 'package:freshly_client/features/discovery/feed_screen.dart'
    show currentPositionProvider;

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

Money usd(int minor) => Money(minor: minor, currency: 'USD');

Map<String, dynamic> _money(int minor) => {'minor': minor, 'currency': 'USD'};

ProviderSummary sampleProvider(
  String id,
  String name, {
  double rating = 4.9,
  int count = 127,
  int fromMinor = 800,
  bool online = true,
  bool backup = true,
  double km = 2.4,
  int? eta = 18,
  List<String> categories = const ['barber'],
  String venue = 'mobile',
  String? shopAddress,
}) =>
    ProviderSummary.fromJson({
      'providerId': id,
      'displayName': name,
      'avatarUrl': null,
      'distanceKm': km,
      'rating': rating,
      'ratingCount': count,
      'completedJobs': count * 3,
      'hasPowerBackup': backup,
      'isOnline': online,
      'fromPrice': _money(fromMinor),
      'categories': categories,
      'etaMinutes': eta,
      'venueMode': venue,
      'shopAddress': shopAddress,
    });

final sampleProviders = [
  sampleProvider('p1', 'Tendai Moyo'),
  sampleProvider('p2', 'Rudo Kanengoni',
      rating: 4.8,
      count: 64,
      fromMinor: 1500,
      backup: false,
      categories: ['braiding', 'hair'],
      km: 3.1,
      eta: 24),
  sampleProvider('p3', 'Farai Chikore',
      rating: 4.9, count: 211, fromMinor: 600, online: false, km: 1.2),
  sampleProvider('p4', 'Nyasha Nails',
      rating: 4.7,
      count: 38,
      fromMinor: 1200,
      categories: ['nails'],
      km: 4.6,
      eta: 31),
];

final sampleServices = [
  {
    'id': 's1',
    'name': 'Skin fade',
    'description': 'Clipper fade, line-up and a hot towel finish',
    'category': 'barber',
    'priceMinor': 1000,
    'currency': 'USD',
    'durationMinutes': 45,
    'requiresPower': true,
  },
  {
    'id': 's2',
    'name': 'Beard trim & shape',
    'description': 'Razor edge and beard oil',
    'category': 'beard',
    'priceMinor': 500,
    'currency': 'USD',
    'durationMinutes': 20,
    'requiresPower': false,
  },
  {
    'id': 's3',
    'name': 'Kids cut (under 12)',
    'description': 'Any style, patient hands',
    'category': 'barber',
    'priceMinor': 600,
    'currency': 'USD',
    'durationMinutes': 30,
    'requiresPower': true,
  },
];

Map<String, dynamic> sampleBookingJson(String status,
        {String id = 'b1', String ref = 'FR-7Q2K'}) =>
    {
      'id': id,
      'reference': ref,
      'status': status,
      'destinationAddress': '14 King George Rd, Avondale',
      'total': _money(1050),
      'providerId': 'p1',
      'providerName': 'Tendai Moyo',
      'serviceIds': ['s1'],
      'scheduledStart': DateTime(2026, 10, 18, 16).toIso8601String(),
      'createdAt': DateTime(2026, 10, 17, 9).toIso8601String(),
    };

class FakeApi extends FreshlyApi {
  FakeApi() : super(baseUrl: 'http://fake.invalid', session: SessionStore());

  @override
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
  }) async {
    var list = sampleProviders;
    if (requirePowerBackup) list = list.where((p) => p.hasPowerBackup).toList();
    if (venue == 'in_shop') {
      return [
        sampleProvider('s1', 'Sharp Cuts Avondale',
            venue: 'in_shop',
            shopAddress: 'Avondale Shopping Centre, Shop 12',
            fromMinor: 700,
            km: 0.8),
        sampleProvider('s2', 'Crowned Braids Studio',
            venue: 'in_shop',
            shopAddress: 'Sam Levy\'s Village, Borrowdale',
            categories: ['braiding'],
            fromMinor: 2500,
            km: 5.2),
      ];
    }
    return list;
  }

  @override
  Future<PriceQuote> quote({
    required String providerId,
    required List<String> serviceIds,
    required double lat,
    required double lng,
    String? promoCode,
  }) async =>
      PriceQuote.fromJson({
        'currency': 'USD',
        'subtotalMinor': 1500,
        'travelFeeMinor': 150,
        'serviceFeeMinor': 50,
        'discountMinor': 0,
        'totalMinor': 1700,
        'travelDistanceKm': 2.4,
        'breakdown': [
          {'label': 'Skin fade', 'amountMinor': 1000, 'kind': 'charge'},
          {'label': 'Beard trim & shape', 'amountMinor': 500, 'kind': 'charge'},
          {'label': 'Travel (2.4 km)', 'amountMinor': 150, 'kind': 'charge'},
          {'label': 'Platform fee', 'amountMinor': 50, 'kind': 'charge'},
        ],
      });

  @override
  Future<List<Market>> markets() async => [
        Market.fromJson({
          'code': 'ZW',
          'name': 'Zimbabwe',
          'currency': 'USD',
          'dialPrefix': '+263',
          'phoneLength': 9,
          'cancellationWindowMinutes': 120,
          'cancellationFeeBps': 5000,
        }),
      ];

  @override
  Future<List<CategorySummary>> catalogCategories() async => [
        for (final c in [
          'barber',
          'braiding',
          'hair',
          'nails',
          'beard',
          'locs'
        ])
          CategorySummary.fromJson(
              {'category': c, 'providerCount': c.length + 3}),
      ];

  @override
  Future<String> completionPin(String bookingId) async => '4827';

  @override
  Future<Booking> booking(String id) async =>
      Booking.fromJson(sampleBookingJson('authorized'));

  @override
  Future<GridStatus> gridStatus(String countryCode) async =>
      GridStatus.fromJson({
        'countryCode': countryCode,
        'stage': 2,
        'source': 'zesa',
        'nextWindow': {
          'start': DateTime(2026, 10, 17, 16).toIso8601String(),
          'end': DateTime(2026, 10, 17, 18).toIso8601String(),
        },
      });

  @override
  Future<List<Booking>> myBookings({String? status}) async => [
        Booking.fromJson(
            sampleBookingJson('en_route', id: 'b0', ref: 'FR-9LMA')),
        Booking.fromJson(sampleBookingJson('completed')),
        Booking.fromJson(
            sampleBookingJson('cancelled', id: 'b3', ref: 'FR-1ZZT')),
        Booking.fromJson(
            sampleBookingJson('completed', id: 'b2', ref: 'FR-3XHD')),
      ];

  @override
  Future<Map<String, dynamic>> providerProfile(String providerId) async => {
        'providerId': providerId,
        'displayName': 'Tendai Moyo',
        'bio': 'Clean fades and sharp line-ups, at your place or my chair in '
            'Avondale. Ten years cutting in Harare.',
        'rating': 4.9,
        'ratingCount': 127,
        'completedJobs': 342,
        'powerBackup': ['battery_clippers', 'portable_lights'],
        'isOnline': true,
        'portfolio': [],
        'services': sampleServices,
        'reviews': [
          {
            'rating': 5,
            'author': 'Kuda',
            'comment':
                'On time even with the power off. Best fade in Avondale.',
            'tags': ['On time', 'Great cut'],
          },
          {
            'rating': 5,
            'author': 'Nyasha',
            'comment': 'Came to the house for my boys, very patient with them.',
            'tags': ['Friendly'],
          },
        ],
      };
}

Position _position(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime(2026, 10, 17),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

final sampleArea = ServiceArea.fromJson({
  'id': 'a1',
  'slug': 'hre-metro',
  'name': 'Harare',
  'lat': -17.7932,
  'lng': 31.0361,
  'countryCode': 'ZW',
  'placeName': 'Avondale, Harare',
});

/// Firebase is never initialised in the tour, so phone sign-in is stubbed.
class FakePhoneAuth implements PhoneAuth {
  @override
  void Function(String idToken)? onAutoToken;
  @override
  void Function(PhoneAuthException error)? onAutoError;
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// No keychain in the tour: every read is empty, so auth settles on
/// signed-out instead of throwing on a missing platform channel.
class FakeSecureStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<String?>.value();
}

List<Override> baseOverrides() => [
      sessionStoreProvider.overrideWithValue(SessionStore(FakeSecureStorage())),
      phoneAuthProvider.overrideWithValue(FakePhoneAuth()),
      apiProvider.overrideWithValue(FakeApi()),
      currentPositionProvider
          .overrideWith((ref) async => _position(-17.7932, 31.0361)),
      serviceAreaProvider.overrideWith((ref) => sampleArea),
    ];

/// Renders [builder] as the app's first route at phone size and writes
/// out/[name].png. [height] lets a scrolling page be captured whole.
Future<void> shoot(
  WidgetTester tester,
  String name,
  Widget Function(BuildContext) builder, {
  double height = 844,
  List<Override> overrides = const [],
  ThemeMode mode = ThemeMode.light,
  List<RouteBase> extraRoutes = const [],
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
    ...extraRoutes,
    GoRoute(
        path: '/:rest(.*)',
        builder: (_, __) => const Scaffold(body: SizedBox())),
  ]);

  await tester.pumpWidget(ProviderScope(
    overrides: [...baseOverrides(), ...overrides],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: FreshlyTheme.light(),
      darkTheme: FreshlyTheme.dark(),
      themeMode: mode,
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
}

BookingDraft sampleDraft() => BookingDraft(
      providerId: 'p1',
      providerName: 'Tendai Moyo',
      services: sampleServices.take(2).map(ServiceItem.fromJson).toList(),
      destination: const GeoPoint(-17.7932, 31.0361),
      destinationAddress: '14 King George Rd, Avondale',
    );
