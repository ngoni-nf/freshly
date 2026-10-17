import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../features/availability/availability_screen.dart';
import '../features/dashboard/command_screen.dart';
import '../features/dispatch/offer_overlay.dart';
import '../features/job/addon_screen.dart';
import '../features/job/job_screen.dart';
import '../features/job/pin_pad_screen.dart';
import '../features/onboarding/business_setup_screen.dart';
import '../features/onboarding/signin_screen.dart';
import '../features/onboarding/verification_screen.dart';
import '../features/support/support_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/profile/business_edit_screen.dart';
import '../features/profile/business_screen.dart';
import '../features/profile/menu_screen.dart';
import '../features/profile/portfolio_screen.dart';
import '../features/clients/client_list_screen.dart';
import '../features/clients/client_detail_screen.dart';
import '../features/dashboard/schedule_screen.dart';
import '../features/profile/reviews_screen.dart';
import '../widgets/main_scaffold.dart';
import 'providers.dart';

final partnerRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(partnerAuthProvider);

  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final commandNavigatorKey = GlobalKey<NavigatorState>();
  final scheduleNavigatorKey = GlobalKey<NavigatorState>();
  final earningsNavigatorKey = GlobalKey<NavigatorState>();
  final businessNavigatorKey = GlobalKey<NavigatorState>();

  return GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavigatorKey,
    redirect: (context, state) {
      final signedOut = auth is PartnerSignedOut || auth is PartnerUnknown;
      final onSignIn = state.matchedLocation == '/signin';
      if (signedOut && !onSignIn) return '/signin';
      if (!signedOut && onSignIn) return '/';

      // A customer account can reach nothing in this app until it has a
      // business, so the set-up screen is the only place it can be, the same
      // way sign-in is the only place a signed-out one can be.
      final needsBusiness = auth is PartnerNeedsBusiness;
      final onSetup = state.matchedLocation == '/onboarding/business';
      if (needsBusiness && !onSetup) return '/onboarding/business';
      if (!needsBusiness && onSetup) return '/';
      return null;
    },
    routes: [
      // Wrapped once, above every route, so a dispatch offer interrupts
      // whatever the provider happens to be looking at.
      ShellRoute(
        builder: (context, state, child) => OfferListener(child: child),
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) =>
                MainScaffold(navigationShell: navigationShell),
            branches: [
              StatefulShellBranch(
                navigatorKey: commandNavigatorKey,
                routes: [
                  GoRoute(path: '/', builder: (_, __) => const CommandScreen()),
                ],
              ),
              StatefulShellBranch(
                navigatorKey: scheduleNavigatorKey,
                routes: [
                  GoRoute(
                      path: '/schedule',
                      builder: (_, __) => const ScheduleScreen()),
                ],
              ),
              StatefulShellBranch(
                navigatorKey: earningsNavigatorKey,
                routes: [
                  GoRoute(
                      path: '/wallet',
                      builder: (_, __) => const WalletScreen()),
                ],
              ),
              StatefulShellBranch(
                navigatorKey: businessNavigatorKey,
                routes: [
                  GoRoute(
                      path: '/business',
                      builder: (_, __) => const BusinessScreen()),
                ],
              ),
            ],
          ),

          GoRoute(
              path: '/signin', builder: (_, __) => const PartnerSignInScreen()),
          GoRoute(
              path: '/onboarding/business',
              builder: (_, __) => const BusinessSetupScreen()),
          GoRoute(
              path: '/verification',
              builder: (_, __) => const VerificationScreen()),
          GoRoute(
              path: '/business/edit',
              builder: (_, __) => const BusinessEditScreen()),
          GoRoute(
              path: '/support', builder: (_, __) => const SupportScreen()),
          GoRoute(
              path: '/availability',
              builder: (_, __) => const AvailabilityScreen()),
          GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
          GoRoute(
              path: '/portfolio', builder: (_, __) => const PortfolioScreen()),
          // The business screen already linked here; without the route the tap
          // fell through to the error page.
          GoRoute(
              path: '/reviews', builder: (_, __) => const ReviewsScreen()),
          GoRoute(
              path: '/clients', builder: (_, __) => const ClientListScreen()),
          GoRoute(
            path: '/clients/:id',
            builder: (_, s) =>
                ClientDetailScreen(clientId: s.pathParameters['id']!),
          ),
          // No parentNavigatorKey anywhere below. These routes sit inside the
          // OfferListener ShellRoute, which declares no navigator key of its
          // own, so a route pointing at rootNavigatorKey can never match it
          // and go_router asserts at construction — the app died on launch,
          // not on navigation. They are outside the StatefulShellRoute
          // branches already, so nothing shows a tab bar regardless, and
          // staying inside the shell is what keeps a dispatch offer able to
          // interrupt a job in progress.
          GoRoute(
            path: '/job/:id',
            builder: (_, s) => JobScreen(bookingId: s.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'pin',
                builder: (_, s) =>
                    PinPadScreen(bookingId: s.pathParameters['id']!),
              ),
              GoRoute(
                path: 'addon',
                builder: (_, s) =>
                    AddonScreen(bookingId: s.pathParameters['id']!),
              ),
              GoRoute(
                path: 'chat',
                builder: (context, s) {
                  final id = s.pathParameters['id']!;
                  final authState = ref.read(partnerAuthProvider);
                  final userId = switch (authState) {
                    PartnerReady(:final session) => session.userId,
                    PartnerPendingVerification(:final session) =>
                      session.userId,
                    _ => '',
                  };

                  return ChatScreen(
                    bookingId: id,
                    currentUserId: userId,
                    api: ref.read(apiProvider),
                    realtime: ref.read(realtimeProvider),
                    title: 'Message client',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
