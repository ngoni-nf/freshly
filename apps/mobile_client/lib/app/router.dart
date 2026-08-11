import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/splash_screen.dart';
import '../features/auth/country_screen.dart';
import '../features/auth/area_screen.dart';
import '../features/auth/phone_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/permissions_screen.dart';
import '../features/home/dashboard_screen.dart';
import '../features/discovery/feed_screen.dart';
import '../features/discovery/provider_screen.dart';
import '../features/discovery/catalog_screen.dart';
import '../features/booking/booking_draft.dart';
import '../features/booking/logistics_screen.dart';
import '../features/booking/checkout_screen.dart';
import '../features/booking/escrow_screen.dart';
import '../features/tracking/tracking_screen.dart';
import '../features/tracking/pin_screen.dart';
import '../features/history/bookings_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.matchedLocation;
      final isAuthFlow = path.startsWith('/auth');

      return switch (auth) {
        AuthUnknown() => path == '/' ? null : '/',
        // Country first, so every later question is asked in the right market.
        AuthSignedOut() => isAuthFlow ? null : '/auth/country',
        AuthNeedsProfile() => path == '/auth/profile' ? null : '/auth/profile',
        // Onboarding is not finished until we know where they want service.
        // Permissions may follow, but that screen is skippable and this is not.
        AuthNeedsArea() => path == '/auth/area' || path == '/auth/permissions'
            ? null
            : '/auth/area',
        AuthSignedIn() => isAuthFlow || path == '/' ? '/home' : null,
      };
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/country', builder: (_, __) => const CountryScreen()),
      GoRoute(path: '/auth/phone', builder: (_, __) => const PhoneScreen()),
      GoRoute(path: '/auth/area', builder: (_, __) => const AreaScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (_, s) {
          final extra = s.extra! as Map<String, String>;
          return OtpScreen(
              phone: extra['phone']!, countryCode: extra['countryCode']!);
        },
      ),
      GoRoute(path: '/auth/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: '/auth/permissions',
          builder: (_, __) => const PermissionsScreen()),
      GoRoute(path: '/home', builder: (_, __) => const DashboardScreen()),
      GoRoute(
          path: '/discover',
          builder: (_, s) => FeedScreen(query: s.uri.queryParameters)),
      GoRoute(
        path: '/catalog',
        builder: (_, s) {
          final cat = s.uri.queryParameters['category'];
          return CatalogScreen(
            initialCategory: cat != null ? ServiceCategory.fromWire(cat) : null,
          );
        },
      ),
      GoRoute(
          path: '/provider/:id',
          builder: (_, s) =>
              ProviderScreen(providerId: s.pathParameters['id']!)),
      GoRoute(
          path: '/book/logistics',
          builder: (_, s) => LogisticsScreen(draft: s.extra! as BookingDraft)),
      GoRoute(
          path: '/book/checkout',
          builder: (_, s) => CheckoutScreen(draft: s.extra! as BookingDraft)),
      GoRoute(
          path: '/book/:id/escrow',
          builder: (_, s) => EscrowScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(
          path: '/track/:id',
          builder: (_, s) =>
              TrackingScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(
          path: '/track/:id/pin',
          builder: (_, s) => PinScreen(bookingId: s.pathParameters['id']!)),
      GoRoute(path: '/bookings', builder: (_, __) => const BookingsScreen()),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
