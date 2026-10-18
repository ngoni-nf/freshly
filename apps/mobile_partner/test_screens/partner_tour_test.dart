import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_partner/features/availability/availability_screen.dart';
import 'package:freshly_partner/features/job/addon_screen.dart';
import 'package:freshly_partner/features/onboarding/business_setup_screen.dart';
import 'package:freshly_partner/features/support/support_screen.dart';
import 'package:freshly_partner/features/clients/client_detail_screen.dart';
import 'package:freshly_partner/features/clients/client_list_screen.dart';
import 'package:freshly_partner/features/dashboard/command_screen.dart';
import 'package:freshly_partner/features/dashboard/schedule_screen.dart';
import 'package:freshly_partner/features/dispatch/offer_overlay.dart';
import 'package:freshly_partner/features/job/job_screen.dart';
import 'package:freshly_partner/features/job/pin_pad_screen.dart';
import 'package:freshly_partner/features/onboarding/signin_screen.dart';
import 'package:freshly_partner/features/onboarding/verification_screen.dart';
import 'package:freshly_partner/features/profile/business_screen.dart';
import 'package:freshly_partner/features/profile/menu_screen.dart';
import 'package:freshly_partner/features/profile/portfolio_screen.dart';
import 'package:freshly_partner/features/profile/reviews_screen.dart';
import 'package:freshly_partner/features/reviews/rate_client_screen.dart';
import 'package:freshly_partner/features/staff/staff_invite_screen.dart';
import 'package:freshly_partner/features/staff/staff_screen.dart';
import 'package:freshly_partner/features/wallet/wallet_screen.dart';
import 'package:freshly_partner/widgets/sos_button.dart';
import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

import 'harness.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('signin', (t) async {
    await shoot(t, 'signin', (_) => const PartnerSignInScreen());
  });

  testWidgets('dashboard online', (t) async {
    await shoot(t, 'dashboard_online', (_) => const CommandScreen(),
        height: 1240, withNav: true, overrides: partnerOverrides(online: true));
  });

  testWidgets('dashboard offline', (t) async {
    await shoot(t, 'dashboard_offline', (_) => const CommandScreen(),
        withNav: true, overrides: partnerOverrides(empty: true));
  });

  testWidgets('dashboard pending', (t) async {
    await shoot(t, 'dashboard_pending', (_) => const CommandScreen(),
        withNav: true,
        overrides: partnerOverrides(kyc: 'pending', empty: true));
  });

  testWidgets('offer', (t) async {
    await shoot(t, 'offer', (_) => OfferOverlay(offer: sampleOffer()));
  });

  testWidgets('job en route', (t) async {
    await shoot(t, 'job_en_route', (_) => const JobScreen(bookingId: 'b1'));
  });

  testWidgets('job arrived', (t) async {
    await shoot(t, 'job_arrived', (_) => const JobScreen(bookingId: 'arrived'));
  });

  testWidgets('job working', (t) async {
    await shoot(t, 'job_working', (_) => const JobScreen(bookingId: 'working'));
  });

  testWidgets('pin pad', (t) async {
    await shoot(t, 'pin_pad', (_) => const PinPadScreen(bookingId: 'b1'),
        act: (t) async {
      await t.tap(find.text('4'));
      await t.pump();
      await t.tap(find.text('7'));
    });
  });

  testWidgets('wallet', (t) async {
    await shoot(t, 'wallet', (_) => const WalletScreen(),
        height: 1100, withNav: true);
  });

  testWidgets('wallet cash out', (t) async {
    await shoot(t, 'wallet_cashout', (_) => const WalletScreen(),
        act: (t) async {
      await t.tap(find.text('Cash out'));
    });
  });

  testWidgets('wallet blocked', (t) async {
    await shoot(t, 'wallet_blocked', (_) => const WalletScreen(),
        overrides: partnerOverrides(kyc: 'pending'));
  });

  testWidgets('availability', (t) async {
    await shoot(t, 'availability', (_) => const AvailabilityScreen(),
        height: 1500);
  });

  testWidgets('business setup', (t) async {
    await shoot(t, 'business_setup', (_) => const BusinessSetupScreen(),
        height: 1800);
  });

  testWidgets('addon', (t) async {
    await shoot(t, 'addon', (_) => const AddonScreen(bookingId: 'working'),
        act: (tester) async => tester.tap(find.text('Beard trim and shape')));
  });

  testWidgets('support', (t) async {
    await shoot(t, 'support', (_) => const SupportScreen(),
        act: (tester) async =>
            tester.tap(find.text('Cash-out still processing')));
  });

  testWidgets('schedule', (t) async {
    await shoot(t, 'schedule', (_) => const ScheduleScreen(), withNav: true);
  });

  testWidgets('business', (t) async {
    await shoot(t, 'business', (_) => const BusinessScreen(), withNav: true);
  });

  testWidgets('menu', (t) async {
    await shoot(t, 'menu', (_) => const MenuScreen());
  });

  testWidgets('portfolio empty', (t) async {
    await shoot(t, 'portfolio', (_) => const PortfolioScreen());
  });

  testWidgets('reviews', (t) async {
    await shoot(t, 'reviews', (_) => const ReviewsScreen());
  });

  testWidgets('clients', (t) async {
    await shoot(t, 'clients', (_) => const ClientListScreen());
  });

  testWidgets('client detail', (t) async {
    await shoot(
        t, 'client_detail', (_) => const ClientDetailScreen(clientId: 'c1'),
        height: 1000);
  });

  testWidgets('verification', (t) async {
    await shoot(t, 'verification', (_) => const VerificationScreen(),
        height: 1200);
  });

  testWidgets('job done', (t) async {
    await shoot(t, 'job_done', (_) => const JobScreen(bookingId: 'done'),
        height: 1100);
  });

  testWidgets('job done rated', (t) async {
    await shoot(
        t, 'job_done_rated', (_) => const JobScreen(bookingId: 'done_rated'),
        height: 1100);
  });

  testWidgets('job done as staff', (t) async {
    await shoot(t, 'job_done_staff', (_) => const JobScreen(bookingId: 'done'),
        height: 1100, overrides: partnerOverrides(businessMode: 'salon_staff'));
  });

  testWidgets('rate client', (t) async {
    await shoot(
        t, 'rate_client', (_) => const RateClientScreen(bookingId: 'done'),
        act: (t) async {
      await t.tap(find.byIcon(FreshlyIcons.star).at(3));
      await t.pump();
      await t.tap(find.text('On time'));
      await t.pump();
      await t.tap(find.text('Easy to find'));
    });
  });

  testWidgets('schedule as salon', (t) async {
    await shoot(t, 'schedule_salon', (_) => const ScheduleScreen(),
        height: 1500,
        withNav: true,
        overrides: partnerOverrides(businessMode: 'salon'));
  });

  testWidgets('job as salon', (t) async {
    await shoot(t, 'job_salon', (_) => const JobScreen(bookingId: 'b2'),
        overrides: partnerOverrides(businessMode: 'salon'));
  });

  testWidgets('assign sheet', (t) async {
    await shoot(t, 'assign_sheet', (_) => const JobScreen(bookingId: 'b2'),
        overrides: partnerOverrides(businessMode: 'salon'), act: (t) async {
      await t.tap(find.text('Change'));
    });
  });

  testWidgets('business as salon', (t) async {
    await shoot(t, 'business_salon', (_) => const BusinessScreen(),
        withNav: true, overrides: partnerOverrides(businessMode: 'salon'));
  });

  testWidgets('staff desk', (t) async {
    await shoot(t, 'staff', (_) => const StaffScreen(),
        overrides: partnerOverrides(businessMode: 'salon'));
  });

  testWidgets('staff invite sheet', (t) async {
    await shoot(t, 'staff_invite', (_) => const StaffScreen(),
        overrides: partnerOverrides(businessMode: 'salon'), act: (t) async {
      await t.tap(find.text('Invite by phone'));
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byType(TextField), '0787770003');
    });
  });

  testWidgets('staff remove', (t) async {
    await shoot(t, 'staff_remove', (_) => const StaffScreen(),
        overrides: partnerOverrides(businessMode: 'salon'), act: (t) async {
      await t.tap(find.byIcon(Icons.more_horiz).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Remove from team'));
    });
  });

  testWidgets('staff invites received', (t) async {
    await shoot(t, 'staff_invites', (_) => const StaffInviteScreen(),
        overrides: partnerOverrides(hasBusiness: false, invited: true));
  });

  testWidgets('menu remove', (t) async {
    await shoot(t, 'menu_remove', (_) => const MenuScreen(), act: (t) async {
      await t.tap(find.byIcon(Icons.more_horiz).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Remove from menu'));
    });
  });

  testWidgets('sos stand down', (t) async {
    await shoot(
        t,
        'sos_standdown',
        (_) => const Scaffold(
              body: JobScreen(bookingId: 'b1'),
              bottomSheet: SosActiveSheet(
                  sosId: 'sos1', dispatched: true, emergencyNumber: '999'),
            ));
  });

  testWidgets('sos countdown', (t) async {
    await shoot(t, 'sos', (_) => const JobScreen(bookingId: 'b1'),
        act: (t) async {
      await t.tap(find.text('SOS'));
      await t.pump(const Duration(milliseconds: 200));
    });
  });
}
