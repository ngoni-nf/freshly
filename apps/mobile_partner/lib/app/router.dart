import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
