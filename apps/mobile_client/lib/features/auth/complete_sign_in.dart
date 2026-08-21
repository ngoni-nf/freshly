import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/notifications.dart';
import '../../app/providers.dart';
import '../../app/router.dart';

/// Exchange a Firebase ID token for a Freshly session and route onward.
///
/// Shared by the two ways a number gets verified: the phone screen (Android
/// instant verification, no code typed) and the code screen (a code the user
/// entered). Both end here so session handling and navigation live in one
/// place.
///
/// Takes no BuildContext deliberately: verification can complete from a
/// detached callback (auto-retrieval fires on its own timer), so it reads the
/// platform from [defaultTargetPlatform] and navigates through the router
/// provider rather than a widget's context, which may be gone by then.
Future<void> completeFirebaseSignIn(
  WidgetRef ref,
  String idToken,
  String countryCode,
) async {
  final session = await ref.read(apiProvider).signInWithFirebase(
        idToken,
        countryCode,
        platform:
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        pushToken: ref.read(pushTokenProvider),
      );
  ref.read(authStateProvider.notifier).signedIn(session);
  ref
      .read(routerProvider)
      .go(session.profileComplete ? '/home' : '/auth/profile');
}
