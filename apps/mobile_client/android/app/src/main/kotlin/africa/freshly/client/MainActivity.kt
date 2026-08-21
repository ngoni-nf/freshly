package africa.freshly.client

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth shows the system
// biometric prompt as a fragment and crashes on a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity()
