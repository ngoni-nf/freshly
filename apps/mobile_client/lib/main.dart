import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local cache for the last discovery feed and the user's recent bookings.
  // Data is expensive in both markets; a warm start should render something
  // useful before a single byte moves over the network.
  await Hive.initFlutter();
  await Hive.openBox<String>('freshly_cache');

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const ProviderScope(child: FreshlyClientApp()));
}
