import 'package:firebase_auth/firebase_auth.dart';

/// Firebase phone verification, wrapped so the screens never touch the plugin
/// directly.
///
/// Firebase proves the person holds the number and hands back an ID token; the
/// backend exchanges that for a Freshly session carrying roles and status.
/// Firebase is the identity, never the session — see FirebaseAuthService on the
/// API side.
class PhoneAuthException implements Exception {
  PhoneAuthException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'PhoneAuthException($code): $message';
}

class PhoneAuth {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;
  int? _resendToken;

  /// Android can verify a number without the user ever typing a code (instant
  /// verification or SMS auto-retrieval). That can land while the phone screen
  /// is still up or after the code screen opens, so whichever screen is active
  /// sets these and the completion is always caught.
  void Function(String idToken)? onAutoToken;
  void Function(PhoneAuthException error)? onAutoError;

  Future<void> sendCode(
    String e164, {
    required void Function() onCodeSent,
    bool resend = false,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: e164,
      timeout: const Duration(seconds: 60),
      forceResendingToken: resend ? _resendToken : null,
      verificationCompleted: (PhoneAuthCredential cred) async {
        try {
          onAutoToken?.call(await _signIn(cred));
        } on PhoneAuthException catch (e) {
          onAutoError?.call(e);
        }
      },
      verificationFailed: (FirebaseAuthException e) => onAutoError?.call(
        PhoneAuthException(e.code, _friendly(e.code, e.message)),
      ),
      codeSent: (String id, int? token) {
        _verificationId = id;
        _resendToken = token;
        onCodeSent();
      },
      codeAutoRetrievalTimeout: (String id) => _verificationId = id,
    );
  }

  /// Confirm a code the user typed, returning a Firebase ID token.
  Future<String> confirm(String smsCode) async {
    final id = _verificationId;
    if (id == null) {
      throw PhoneAuthException('no_code', 'Request a code first');
    }
    return _signIn(
      PhoneAuthProvider.credential(verificationId: id, smsCode: smsCode),
    );
  }

  Future<String> _signIn(PhoneAuthCredential cred) async {
    try {
      final result = await _auth.signInWithCredential(cred);
      final token = await result.user?.getIdToken();
      if (token == null) {
        throw PhoneAuthException('no_token', 'Could not verify that sign-in');
      }
      return token;
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthException(e.code, _friendly(e.code, e.message));
    }
  }

  String _friendly(String code, String? fallback) {
    switch (code) {
      case 'invalid-verification-code':
        return 'That code is not correct';
      case 'session-expired':
        return 'That code has expired. Request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a little while.';
      case 'invalid-phone-number':
        return 'That does not look like a valid mobile number';
      default:
        return fallback ?? 'Verification failed';
    }
  }
}
