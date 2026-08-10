import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface VerifiedIdentity {
  uid: string;
  phoneE164: string;
  email?: string;
  name?: string;
}

/**
 * Firebase as an identity provider, not as the session.
 *
 * The app signs in with Firebase phone auth and sends us the resulting ID
 * token. We verify it, then issue our own JWT carrying the user's roles.
 *
 * Keeping the two separate matters. Firebase knows who owns a phone number;
 * it does not and should not know that this person is a verified provider
 * cleared to accept jobs, or that they are suspended pending a dispute. That
 * lives in our database. A Firebase outage therefore stops new sign-ins but
 * leaves every existing session working, and no Firebase misconfiguration can
 * hand somebody a role.
 */
@Injectable()
export class FirebaseAuthService {
  private readonly logger = new Logger(FirebaseAuthService.name);
  private app: unknown | null = null;
  readonly enabled: boolean;

  constructor(private readonly config: ConfigService) {
    this.enabled = Boolean(this.config.get<boolean>('FIREBASE_ENABLED'));
    if (!this.enabled) {
      this.logger.log('Firebase sign-in disabled; using the built-in OTP flow');
    }
  }

  private async admin(): Promise<any> {
    if (this.app) return this.app;

    // Imported lazily through a non-literal specifier so the compiler does not
    // require firebase-admin to be installed. A deployment running the OTP
    // flow should not have to carry the dependency at all, and TypeScript
    // would otherwise fail the build for a package it never calls.
    const appModule = 'firebase-admin/app';
    const authModule = 'firebase-admin/auth';
    const firebase: any = await import(appModule);
    const { getAuth }: any = await import(authModule);

    const raw = this.config.get<string>('FIREBASE_SERVICE_ACCOUNT_JSON');
    const existing = firebase.getApps();

    const app = existing.length
      ? existing[0]
      : firebase.initializeApp({
          projectId: this.config.getOrThrow<string>('FIREBASE_PROJECT_ID'),
          credential: raw
            ? firebase.cert(JSON.parse(raw))
            : firebase.applicationDefault(),
        });

    this.app = { app, auth: getAuth(app) };
    return this.app;
  }

  async verifyIdToken(idToken: string): Promise<VerifiedIdentity> {
    if (!this.enabled) {
      throw new UnauthorizedException({
        code: 'firebase_disabled',
        message: 'Firebase sign-in is not enabled on this environment',
      });
    }

    try {
      const { auth } = await this.admin();
      // checkRevoked forces a lookup against Firebase rather than trusting the
      // signature alone, so a token issued before a user was disabled or had
      // their sessions revoked is rejected rather than honoured for its
      // remaining hour.
      const decoded = await auth.verifyIdToken(idToken, true);

      const phone = decoded.phone_number as string | undefined;
      if (!phone) {
        throw new UnauthorizedException({
          code: 'phone_required',
          message: 'Sign in with your mobile number',
        });
      }

      return {
        uid: decoded.uid,
        phoneE164: phone,
        email: decoded.email,
        name: decoded.name,
      };
    } catch (err) {
      if (err instanceof UnauthorizedException) throw err;
      this.logger.warn(`Firebase token rejected: ${(err as Error).message}`);
      throw new UnauthorizedException({
        code: 'invalid_firebase_token',
        message: 'That sign-in could not be verified. Please try again.',
      });
    }
  }
}
