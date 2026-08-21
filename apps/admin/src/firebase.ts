import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, signInWithPopup } from 'firebase/auth';

/**
 * Firebase for the ops console — Google sign-in only.
 *
 * These values are the public web config; Firebase intends them to ship in the
 * browser. The real controls are the authorised-domains list (this origin is on
 * it) and, on our side, that a Google identity gets a session but only the
 * roles the database grants — so signing in proves who you are, never that you
 * are an operator.
 */
const app = initializeApp({
  apiKey: 'AIzaSyBdpy31dR3rny269j4orPqeNmfNVwKRq2I',
  authDomain: 'freshly-146c6.firebaseapp.com',
  projectId: 'freshly-146c6',
  storageBucket: 'freshly-146c6.firebasestorage.app',
  messagingSenderId: '188466084733',
  appId: '1:188466084733:web:90817f4ec5d74935a02a14',
});

const auth = getAuth(app);

/** Run the Google popup and return a Firebase ID token for the backend. */
export async function googleIdToken(): Promise<string> {
  const provider = new GoogleAuthProvider();
  const result = await signInWithPopup(auth, provider);
  return result.user.getIdToken();
}
