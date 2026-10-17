import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_client/features/home/dashboard_screen.dart';

import 'package:freshly_client/features/discovery/provider_screen.dart';

import 'package:freshly_client/features/booking/checkout_screen.dart';
import 'package:freshly_client/features/booking/logistics_screen.dart';

import 'package:freshly_client/features/booking/escrow_screen.dart';
import 'package:freshly_client/features/tracking/pin_screen.dart';

import 'package:freshly_client/features/auth/country_screen.dart';
import 'package:freshly_client/features/auth/otp_screen.dart';
import 'package:freshly_client/features/auth/permissions_screen.dart';
import 'package:freshly_client/features/auth/phone_screen.dart';
import 'package:freshly_client/features/auth/profile_screen.dart' as onboarding;
import 'package:freshly_client/features/auth/splash_screen.dart';

import 'package:freshly_client/features/discovery/catalog_screen.dart';
import 'package:freshly_client/features/discovery/feed_screen.dart';
import 'package:freshly_client/features/history/bookings_screen.dart';
import 'package:freshly_client/features/profile/profile_screen.dart' as account;

import 'harness.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('home', (tester) async {
    await shoot(tester, 'home', (_) => const DashboardScreen(),
        height: 1640, withNav: true);
  });

  testWidgets('provider', (tester) async {
    await shoot(
        tester, 'provider', (_) => const ProviderScreen(providerId: 'p1'),
        height: 1500, act: (t) async {
      await t.tap(find.text('Skin fade'));
    });
  });

  testWidgets('logistics', (tester) async {
    await shoot(
        tester, 'logistics', (_) => LogisticsScreen(draft: sampleDraft()),
        height: 1000);
  });

  testWidgets('checkout', (tester) async {
    await shoot(tester, 'checkout', (_) => CheckoutScreen(draft: sampleDraft()),
        height: 1200);
  });

  testWidgets('escrow', (tester) async {
    await shoot(tester, 'escrow', (_) => const EscrowScreen(bookingId: 'b1'));
  });

  testWidgets('pin', (tester) async {
    await shoot(tester, 'pin', (_) => const PinScreen(bookingId: 'b1'));
  });

  testWidgets('a1-splash', (tester) async {
    await shoot(tester, 'a1-splash', (_) => const SplashScreen());
  });
  testWidgets('a2-country', (tester) async {
    await shoot(tester, 'a2-country', (_) => const CountryScreen());
  });
  testWidgets('a3-phone', (tester) async {
    await shoot(tester, 'a3-phone', (_) => const PhoneScreen(),
        act: (t) async => t.enterText(find.byType(EditableText), '771234567'));
  });
  testWidgets('a4-otp', (tester) async {
    await shoot(tester, 'a4-otp',
        (_) => const OtpScreen(phone: '+263771234567', countryCode: 'ZW'),
        act: (t) async => t.enterText(find.byType(EditableText).first, '4827'));
  });
  testWidgets('a5-profile', (tester) async {
    await shoot(tester, 'a5-profile', (_) => const onboarding.ProfileScreen());
  });
  testWidgets('a6-permissions', (tester) async {
    await shoot(tester, 'a6-permissions', (_) => const PermissionsScreen());
  });

  testWidgets('feed', (tester) async {
    await shoot(tester, 'feed', (_) => const FeedScreen(query: {}));
  });
  testWidgets('catalog', (tester) async {
    await shoot(tester, 'catalog', (_) => const CatalogScreen());
  });
  testWidgets('bookings', (tester) async {
    await shoot(tester, 'bookings', (_) => const BookingsScreen());
  });
  testWidgets('account', (tester) async {
    await shoot(tester, 'account', (_) => const account.ProfileScreen());
  });
}
