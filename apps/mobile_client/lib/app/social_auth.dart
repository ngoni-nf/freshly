import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'phone_auth.dart' show PhoneAuthException;

/// Google and email/password sign-in through Firebase.
///
/// Each one ends the same way as phone sign-in: a Firebase ID token the backend
/// exchanges for a Freshly session. These carry no phone, so the session comes
/// back with needsPhone and the app routes to link-phone before booking.
class SocialAuth {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Returns a Firebase ID token, or null if the user backed out of the Google
  /// chooser — a cancel is not an error to shout about.
  Future<String?> google() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return null;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      final result = await _auth.signInWithCredential(credential);
      return result.user?.getIdToken();
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthException(e.code, e.message ?? 'Google sign-in failed');
    } catch (e) {
      // GoogleSignIn throws a plain PlatformException when the OAuth client is
      // not yet configured (no SHA registered, no client id). Surface it as a
      // message rather than letting it crash the button.
      throw PhoneAuthException('google_unavailable',
          'Google sign-in is not available yet. Use your phone or email.');
    }
  }

  /// Sign in, or create the account if it does not exist yet — one field fewer
  /// than making the user pick "sign up" vs "sign in" before they have typed
  /// anything.
  Future<String> email(String email, String password) async {
    try {
      UserCredential result;
      try {
        result = await _auth.signInWithEmailAndPassword(
            email: email, password: password);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          result = await _auth.createUserWithEmailAndPassword(
              email: email, password: password);
        } else {
          rethrow;
        }
      }
      final token = await result.user?.getIdToken();
      if (token == null) {
        throw PhoneAuthException('no_token', 'Could not complete sign-in');
      }
      return token;
    } on FirebaseAuthException catch (e) {
      throw PhoneAuthException(e.code, _friendly(e.code, e.message));
    }
  }

  String _friendly(String code, String? fallback) {
    switch (code) {
      case 'invalid-email':
        return 'That email address does not look right';
      case 'wrong-password':
      case 'invalid-credential':
        return 'That password is not correct';
      case 'weak-password':
        return 'Choose a password of at least six characters';
      case 'email-already-in-use':
        return 'That email is already registered';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a little while.';
      default:
        return fallback ?? 'Sign-in failed';
    }
  }
}

final socialAuthProvider = Provider<SocialAuth>((ref) => SocialAuth());
