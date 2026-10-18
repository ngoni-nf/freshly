import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_client/app/notification_prefs.dart';
import 'package:freshly_client/app/notifications.dart' show showInAppBanner;
import 'package:freshly_client/features/history/booking_detail_screen.dart';
import 'package:freshly_client/features/home/dashboard_screen.dart';
import 'package:freshly_client/features/profile/legal_screen.dart';
import 'package:freshly_client/features/profile/notifications_screen.dart';
import 'package:freshly_client/features/reviews/review_screen.dart';
import 'package:freshly_client/features/support/support_screen.dart';
import 'package:freshly_client/features/tracking/sos_button.dart';
import 'package:permission_handler/permission_handler.dart'
    show PermissionStatus;

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
    await shoot(tester, 'account', (_) => const account.ProfileScreen(),
        height: 1100);
  });

  testWidgets('booking-detail-live', (tester) async {
    await shoot(tester, 'booking-detail-live',
        (_) => const BookingDetailScreen(bookingId: 'b0'),
        height: 1100);
  });
  testWidgets('booking-detail-completed', (tester) async {
    await shoot(tester, 'booking-detail-completed',
        (_) => const BookingDetailScreen(bookingId: 'b2'),
        height: 1200);
  });
  testWidgets('booking-detail-rated', (tester) async {
    await shoot(tester, 'booking-detail-rated',
        (_) => const BookingDetailScreen(bookingId: 'b4'),
        height: 1200);
  });

  testWidgets('review', (tester) async {
    await shoot(tester, 'review', (_) => const ReviewScreen(bookingId: 'b2'),
        height: 1000, act: (t) async {
      await t.tap(find.byTooltip('4 stars'));
      await t.pump();
      await t.tap(find.text('On time'));
      await t.pump();
      await t.tap(find.text('Great cut'));
    });
  });
  testWidgets('review-sent', (tester) async {
    await shoot(
        tester, 'review-sent', (_) => const ReviewScreen(bookingId: 'b2'),
        act: (t) async {
      await t.tap(find.byTooltip('5 stars'));
      await t.pump();
      await t.tap(find.text('Submit review'));
    });
  });

  testWidgets('support', (tester) async {
    await shoot(
        tester, 'support', (_) => const SupportScreen(initialTicketId: 't1'),
        height: 1000);
  });
  testWidgets('support-new', (tester) async {
    await shoot(tester, 'support-new', (_) => const SupportScreen(),
        act: (t) async {
      await t.tap(find.text('New request'));
    });
  });

  testWidgets('sos-active', (tester) async {
    await shoot(tester, 'sos-active', (_) => const _SosHost(), act: (t) async {
      final context = t.element(find.byType(_SosHost));
      // ignore: unawaited_futures
      SosActiveSheet.show(context,
          sosId: 'sos1', dispatched: true, emergencyNumber: '999');
    });
  });
  testWidgets('sos-stood-down', (tester) async {
    await shoot(tester, 'sos-stood-down', (_) => const _SosHost(),
        act: (t) async {
      final context = t.element(find.byType(_SosHost));
      // ignore: unawaited_futures
      SosActiveSheet.show(context,
          sosId: 'sos1', dispatched: true, emergencyNumber: '999');
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      await t.tap(find.text('I am safe now'));
    });
  });

  testWidgets('notifications', (tester) async {
    await shoot(tester, 'notifications', (_) => const NotificationsScreen(),
        height: 1200,
        overrides: [
          notificationPermissionProvider
              .overrideWith((ref) async => PermissionStatus.granted),
          // Hive is not open in the tour; show the phone-with-storage state.
          notificationPrefsProvider.overrideWith(_SavedPrefs.new),
        ]);
  });
  testWidgets('notifications-off', (tester) async {
    await shoot(tester, 'notifications-off', (_) => const NotificationsScreen(),
        height: 1200,
        overrides: [
          notificationPermissionProvider
              .overrideWith((ref) async => PermissionStatus.permanentlyDenied),
        ]);
  });

  testWidgets('legal-privacy', (tester) async {
    await shoot(tester, 'legal-privacy',
        (_) => const LegalScreen(doc: LegalDoc.privacy),
        height: 1400);
  });
  testWidgets('legal-terms', (tester) async {
    await shoot(
        tester, 'legal-terms', (_) => const LegalScreen(doc: LegalDoc.terms),
        height: 1700);
  });

  testWidgets('push-banner', (tester) async {
    await shoot(tester, 'push-banner', (_) => const DashboardScreen(),
        withNav: true, act: (t) async {
      showInAppBanner(
        title: 'Tendai is on the way',
        body: 'About 18 minutes. Have your code ready.',
        onOpen: () {},
      );
    });
    // The banner's own hide timer must fire before the test ends.
    await tester.pump(const Duration(seconds: 9));
  });
}

class _SavedPrefs extends NotificationPrefsNotifier {
  @override
  NotificationPrefs build() => const NotificationPrefs();
}

/// Something with a Scaffold for the SOS sheet to sit on. The tracking
/// screen itself needs a Google Map, which the tour cannot draw.
class _SosHost extends StatelessWidget {
  const _SosHost();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: SosButton(bookingId: 'b1')),
    );
  }
}
