import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../features/auth/lock_screen.dart';
import 'biometric_lock.dart';
import 'notifications.dart';
import 'providers.dart';
import 'router.dart';

class FreshlyClientApp extends ConsumerStatefulWidget {
  const FreshlyClientApp({super.key});

  @override
  ConsumerState<FreshlyClientApp> createState() => _FreshlyClientAppState();
}

class _FreshlyClientAppState extends ConsumerState<FreshlyClientApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(pushNotificationProvider).initialize();
    hydrateBiometricLock(ref);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cover the app the moment it leaves the foreground, so the last screen is
    // already hidden in the task switcher and behind whatever unlock the next
    // resume demands.
    if (state == AppLifecycleState.paused && ref.read(lockEnabledProvider)) {
      ref.read(appLockedProvider.notifier).state = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Freshly',
      debugShowCheckedModeBanner: false,
      theme: FreshlyTheme.light(),
      darkTheme: FreshlyTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', 'ZA'),
        Locale('en', 'ZW'),
        Locale('af'),
        Locale('zu'),
        Locale('xh'),
        Locale('sn'),
        Locale('nd'),
      ],
      builder: (context, child) {
        // Clamp accessibility scaling: past 1.3 the checkout total wraps and a
        // customer can no longer see what they are about to be charged.
        final scale = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3);
        final scaled = MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child!,
        );
        // The lock rides above the whole navigator as an overlay rather than a
        // route, so unlocking returns the user exactly where they were and the
        // router never has to know the app can be covered.
        return Consumer(
          builder: (context, ref, _) {
            final signedIn = ref.watch(authStateProvider) is AuthSignedIn;
            final locked = ref.watch(appLockedProvider);
            final enabled = ref.watch(lockEnabledProvider);
            return Stack(
              children: [
                scaled,
                if (signedIn && enabled && locked)
                  const Positioned.fill(child: LockScreen()),
              ],
            );
          },
        );
      },
    );
  }
}
