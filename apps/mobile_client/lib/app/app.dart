import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import 'notifications.dart';
import 'router.dart';

class FreshlyClientApp extends ConsumerStatefulWidget {
  const FreshlyClientApp({super.key});

  @override
  ConsumerState<FreshlyClientApp> createState() => _FreshlyClientAppState();
}

class _FreshlyClientAppState extends ConsumerState<FreshlyClientApp> {
  @override
  void initState() {
    super.initState();
    ref.read(pushNotificationProvider).initialize();
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
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child!,
        );
      },
    );
  }
}
