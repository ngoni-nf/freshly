import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../features/availability/availability_screen.dart';
import '../features/dashboard/command_screen.dart';
import '../features/dispatch/offer_overlay.dart';
import '../features/job/job_screen.dart';
import '../features/job/pin_pad_screen.dart';
import '../features/onboarding/signin_screen.dart';
import '../features/onboarding/verification_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/profile/menu_screen.dart';
import '../features/profile/portfolio_screen.dart';
import '../features/clients/client_list_screen.dart';
import '../features/clients/client_detail_screen.dart';
import 'providers.dart';

final partnerRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(partnerAuthProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final signedOut = auth is PartnerSignedOut || auth is PartnerUnknown;
      final onSignIn = state.matchedLocation == '/signin';
      if (signedOut && !onSignIn) return '/signin';
      if (!signedOut && onSignIn) return '/';
      return null;
    },
    routes: [
      // Wrapped once, above every route, so a dispatch offer interrupts
      // whatever the provider happens to be looking at.
      ShellRoute(
        builder: (context, state, child) => OfferListener(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const CommandScreen()),
          GoRoute(
              path: '/signin', builder: (_, __) => const PartnerSignInScreen()),
          GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
          GoRoute(path: '/menu', builder: (_, __) => const MenuScreen()),
          GoRoute(path: '/portfolio', builder: (_, __) => const PortfolioScreen()),
          GoRoute(path: '/clients', builder: (_, __) => const ClientListScreen()),
          GoRoute(
            path: '/clients/:id',
            builder: (_, s) => ClientDetailScreen(clientId: s.pathParameters['id']!),
          ),
          GoRoute(
              path: '/verification',
              builder: (_, __) => const VerificationScreen()),
          GoRoute(
              path: '/availability',
              builder: (_, __) => const AvailabilityScreen()),
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
                path: 'chat',
                builder: (context, s) {
                  final id = s.pathParameters['id']!;
                  // PartnerAuthState is a plain sealed class, so this is a
                  // pattern match rather than a freezed maybeWhen. A provider
                  // still in verification can already be on a job, so both
                  // signed-in states carry a session worth reading.
                  final userId = switch (ref.read(partnerAuthProvider)) {
                    PartnerReady(:final session) => session.userId,
                    PartnerPendingVerification(:final session) => session.userId,
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
