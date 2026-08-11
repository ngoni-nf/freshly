import { BadRequestException, Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { randomBytes, randomInt } from 'node:crypto';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import { MarketsService } from '../markets/markets.service';
import { RateLimitedError } from '../../common/errors/domain.errors';
import { CommsService } from '../comms/comms.service';
import { FirebaseAuthService } from './firebase-auth.service';
import { AccountRole } from '../../common/decorators';

interface UserRow {
  id: string;
  phone_e164: string;
  full_name: string;
  roles: AccountRole[];
  country_code: 'ZA' | 'ZW';
  status: string;
  consent_privacy_at: Date | null;
}

/** Seconds until the token expires, taken from its own claims. */
function expiresInSeconds(accessToken: string): number {
  try {
    const payload = JSON.parse(
      Buffer.from(accessToken.split('.')[1], 'base64url').toString(),
    ) as { exp?: number; iat?: number };
    if (payload.exp && payload.iat) return payload.exp - payload.iat;
  } catch {
    // A token we just signed should always parse; if it somehow does not,
    // a conservative answer is better than a confident wrong one.
  }
  return 900;
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  isNewUser: boolean;
  profileComplete: boolean;
  /** Null until the client has chosen where they want service. */
  serviceArea: { id: string; slug: string; name: string; lat: number; lng: number } | null;
  user: {
    id: string;
    fullName: string;
    phone: string;
    roles: AccountRole[];
    countryCode: 'ZA' | 'ZW';
  };
}

/**
 * Phone-first authentication.
 *
 * Passwords are deliberately absent. In both target markets the phone number
 * is the durable identity — it is what the payment rail, the ID document and
 * the customer's own memory all agree on — and a password is one more thing to
 * phish, reset and support.
 */
@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
    private readonly crypto: PiiCryptoService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly markets: MarketsService,
    private readonly comms: CommsService,
    private readonly firebase: FirebaseAuthService,
  ) {}

  /**
   * Exchange a verified Firebase ID token for a Freshly session.
   *
   * The phone number arrives already proven, so there is no code to check.
   * Everything after that — finding or creating the user, reading their roles,
   * refusing a suspended account — is identical to the OTP path, because
   * those are our decisions, not Firebase's.
   */
  async signInWithFirebase(
    idToken: string,
    countryCode: 'ZA' | 'ZW',
    device?: { platform: string; pushToken?: string },
  ): Promise<AuthResult> {
    const identity = await this.firebase.verifyIdToken(idToken);
    const e164 = identity.phoneE164;

    let user = await this.db.queryOne<UserRow>(
      `SELECT id, phone_e164, full_name, roles, country_code, status, consent_privacy_at
         FROM users WHERE phone_e164 = $1`,
      [e164],
    );
    const isNewUser = !user;

    if (!user) {
      user = await this.db.queryOne<UserRow>(
        `INSERT INTO users (phone_e164, country_code, full_name, email, phone_verified_at, locale)
         VALUES ($1, $2, $3, $4, now(), $5)
         RETURNING id, phone_e164, full_name, roles, country_code, status, consent_privacy_at`,
        [
          e164,
          countryCode,
          identity.name ?? '',
          identity.email ?? null,
          countryCode === 'ZA' ? 'en-ZA' : 'en-ZW',
        ],
      );
    } else if (user.status !== 'active') {
      throw new UnauthorizedException({
        code: 'account_suspended',
        message: 'This account is not active. Contact support.',
      });
    } else {
      await this.db.query(
        'UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, now()), last_seen_at = now() WHERE id = $1',
        [user.id],
      );
    }

    if (device?.platform) {
      await this.db.query(
        `INSERT INTO devices (user_id, platform, push_token)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, push_token) DO UPDATE SET last_seen_at = now()`,
        [user!.id, device.platform, device.pushToken ?? null],
      );
    }

    return this.issueTokens(user!, isNewUser);
  }

  async requestOtp(phone: string, countryCode: 'ZA' | 'ZW'): Promise<{ sent: boolean; retryAfter: number }> {
    const e164 = this.markets.toE164(phone, countryCode);

    // Two throttles: per number, and per number per hour. The first stops a
    // fat-fingered retry loop, the second stops SMS-pumping fraud, which is a
    // real and expensive attack on any OTP endpoint in this region.
    const perMinute = await this.redis.incrementWindow(`otp:min:${e164}`, 60);
    if (perMinute > 2) throw new RateLimitedError(60);
    const perHour = await this.redis.incrementWindow(`otp:hr:${e164}`, 3600);
    if (perHour > 8) throw new RateLimitedError(3600);

    const devBypass = this.config.get<boolean>('OTP_DEV_BYPASS');
    const code = devBypass ? '000000' : String(randomInt(0, 1_000_000)).padStart(6, '0');
    const ttl = this.config.get<number>('OTP_TTL_SECONDS') ?? 300;

    await this.db.query(
      `INSERT INTO auth_challenges (phone_e164, code_hash, max_attempts, expires_at)
       VALUES ($1, $2, $3, now() + ($4 || ' seconds')::INTERVAL)`,
      [e164, this.crypto.hash(code), this.config.get<number>('OTP_MAX_ATTEMPTS') ?? 5, ttl],
    );

    if (devBypass) {
      this.logger.warn(`OTP dev bypass active — code for ${e164} is 000000`);
    } else {
      await this.comms.sendOtp(e164, code, countryCode);
    }

    return { sent: true, retryAfter: 60 };
  }

  async verifyOtp(
    phone: string,
    countryCode: 'ZA' | 'ZW',
    code: string,
    device?: { platform: string; pushToken?: string },
  ): Promise<AuthResult> {
    const e164 = this.markets.toE164(phone, countryCode);

    const challenge = await this.db.queryOne<{
      id: string;
      code_hash: string;
      attempts: number;
      max_attempts: number;
    }>(
      `SELECT id, code_hash, attempts, max_attempts
         FROM auth_challenges
        WHERE phone_e164 = $1 AND consumed_at IS NULL AND expires_at > now()
        ORDER BY created_at DESC
        LIMIT 1`,
      [e164],
    );

    if (!challenge) {
      throw new UnauthorizedException({
        code: 'otp_expired',
        message: 'That code has expired. Request a new one.',
      });
    }
    if (challenge.attempts >= challenge.max_attempts) {
      throw new UnauthorizedException({
        code: 'otp_locked',
        message: 'Too many incorrect attempts. Request a new code.',
      });
    }

    if (!this.crypto.verifyHash(code, challenge.code_hash)) {
      await this.db.query('UPDATE auth_challenges SET attempts = attempts + 1 WHERE id = $1', [
        challenge.id,
      ]);
      throw new UnauthorizedException({ code: 'otp_invalid', message: 'That code is not correct' });
    }

    await this.db.query('UPDATE auth_challenges SET consumed_at = now() WHERE id = $1', [challenge.id]);

    let user = await this.db.queryOne<UserRow>(
      `SELECT id, phone_e164, full_name, roles, country_code, status, consent_privacy_at
         FROM users WHERE phone_e164 = $1`,
      [e164],
    );
    const isNewUser = !user;

    if (!user) {
      user = await this.db.queryOne<UserRow>(
        `INSERT INTO users (phone_e164, country_code, full_name, phone_verified_at, locale)
         VALUES ($1, $2, '', now(), $3)
         RETURNING id, phone_e164, full_name, roles, country_code, status, consent_privacy_at`,
        [e164, countryCode, countryCode === 'ZA' ? 'en-ZA' : 'en-ZW'],
      );
    } else {
      if (user.status !== 'active') {
        throw new UnauthorizedException({
          code: 'account_suspended',
          message: 'This account is not active. Contact support.',
        });
      }
      await this.db.query(
        'UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, now()), last_seen_at = now() WHERE id = $1',
        [user.id],
      );
    }

    if (device?.platform) {
      await this.db.query(
        `INSERT INTO devices (user_id, platform, push_token)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id, push_token) DO UPDATE SET last_seen_at = now()`,
        [user!.id, device.platform, device.pushToken ?? null],
      );
    }

    return this.issueTokens(user!, isNewUser);
  }

  async completeProfile(
    userId: string,
    input: { fullName: string; email?: string; acceptPrivacy: boolean; acceptTerms: boolean; acceptMarketing?: boolean },
  ): Promise<{ ok: true }> {
    if (!input.acceptPrivacy || !input.acceptTerms) {
      throw new BadRequestException({
        code: 'consent_required',
        message: 'You must accept the terms and privacy notice to continue',
      });
    }
    await this.db.query(
      `UPDATE users
          SET full_name = $2,
              email = COALESCE($3, email),
              consent_privacy_at = now(),
              consent_terms_at = now(),
              consent_marketing_at = CASE WHEN $4 THEN now() ELSE consent_marketing_at END,
              consent_version = 'v1'
        WHERE id = $1`,
      [userId, input.fullName, input.email ?? null, input.acceptMarketing ?? false],
    );
    return { ok: true };
  }

  /**
   * Where the client wants service.
   *
   * Validated against live areas rather than trusted, and required to be in
   * the user's own market — a South African account choosing a Zimbabwean area
   * would be priced in the wrong currency by every downstream quote.
   */
  async setServiceArea(userId: string, serviceAreaId: string) {
    const area = await this.db.queryOne<{
      id: string;
      slug: string;
      name: string;
      country_code: 'ZA' | 'ZW';
      lat: string;
      lng: string;
    }>(
      `SELECT a.id, a.slug, a.name, a.country_code,
              ST_Y(a.centroid::geometry) AS lat,
              ST_X(a.centroid::geometry) AS lng
         FROM service_areas a
        WHERE a.id = $1 AND a.is_live`,
      [serviceAreaId],
    );
    if (!area) {
      throw new BadRequestException({
        code: 'area_not_live',
        message: 'Freshly is not open in that area yet',
      });
    }

    const user = await this.db.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM users WHERE id = $1',
      [userId],
    );
    if (user && user.country_code !== area.country_code) {
      throw new BadRequestException({
        code: 'area_wrong_country',
        message: 'That area is in a different country to your account',
      });
    }

    await this.db.query('UPDATE users SET preferred_service_area_id = $2 WHERE id = $1', [
      userId,
      area.id,
    ]);

    return {
      id: area.id,
      slug: area.slug,
      name: area.name,
      countryCode: area.country_code,
      lat: Number(area.lat),
      lng: Number(area.lng),
    };
  }

  async refresh(refreshToken: string): Promise<AuthResult> {
    const hash = this.crypto.hash(refreshToken);
    const row = await this.db.queryOne<{ user_id: string; id: string }>(
      `SELECT id, user_id FROM refresh_tokens
        WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`,
      [hash],
    );
    if (!row) {
      throw new UnauthorizedException({ code: 'invalid_refresh', message: 'Please sign in again' });
    }

    // Rotate: a refresh token is single-use, so a stolen one is detectable.
    await this.db.query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [row.id]);

    const user = await this.db.queryOne<UserRow>(
      `SELECT id, phone_e164, full_name, roles, country_code, status, consent_privacy_at
         FROM users WHERE id = $1`,
      [row.user_id],
    );
    if (!user) throw new UnauthorizedException({ code: 'invalid_refresh', message: 'Please sign in again' });

    return this.issueTokens(user, false);
  }

  /**
   * The current user, for restoring a session on app launch.
   *
   * Returns roles and profile state from the database rather than decoding
   * them from the JWT: a provider verified since their token was issued, or
   * suspended since, must be seen as they are now, not as they were up to
   * fifteen minutes ago.
   */
  async me(userId: string) {
    const user = await this.db.queryOne<UserRow & { avatar_url: string | null }>(
      `SELECT id, phone_e164, full_name, roles, country_code, status,
              consent_privacy_at, avatar_url
         FROM users WHERE id = $1`,
      [userId],
    );
    if (!user) {
      throw new UnauthorizedException({ code: 'user_not_found', message: 'Please sign in again' });
    }
    if (user.status !== 'active') {
      throw new UnauthorizedException({
        code: 'account_suspended',
        message: 'This account is not active. Contact support.',
      });
    }

    const provider = await this.db.queryOne<{ id: string; kyc_status: string; is_online: boolean }>(
      'SELECT id, kyc_status, is_online FROM providers WHERE user_id = $1 LIMIT 1',
      [userId],
    );

    // Returned so the app can restore the chosen area at launch instead of
    // re-asking, and so discovery has an origin before any GPS fix arrives.
    const area = await this.db.queryOne<{
      id: string;
      slug: string;
      name: string;
      lat: string;
      lng: string;
    }>(
      `SELECT a.id, a.slug, a.name,
              ST_Y(a.centroid::geometry) AS lat,
              ST_X(a.centroid::geometry) AS lng
         FROM users u
         JOIN service_areas a ON a.id = u.preferred_service_area_id
        WHERE u.id = $1`,
      [userId],
    );

    return {
      id: user.id,
      fullName: user.full_name,
      phone: user.phone_e164,
      roles: user.roles,
      countryCode: user.country_code,
      avatarUrl: user.avatar_url,
      profileComplete: Boolean(user.full_name) && Boolean(user.consent_privacy_at),
      serviceArea: area
        ? {
            id: area.id,
            slug: area.slug,
            name: area.name,
            lat: Number(area.lat),
            lng: Number(area.lng),
          }
        : null,
      provider: provider
        ? { id: provider.id, kycStatus: provider.kyc_status, isOnline: provider.is_online }
        : null,
    };
  }

  /// FCM reissues a registration token whenever the app is restored, reinstalled
  /// or its data cleared, so the one captured at sign-in goes stale while the
  /// session is still perfectly valid. A provider whose token has rotated stops
  /// being offered work and has no way to tell.
  async registerPushToken(
    userId: string,
    platform: 'ios' | 'android' | 'web',
    pushToken: string,
  ): Promise<{ ok: true }> {
    // A handset is not a person. When someone signs in on a phone their
    // colleague used, FCM hands the app the same token, and leaving the old row
    // in place sends that colleague's job offers — with the client's name on
    // them — to whoever is holding it now.
    await this.db.query('DELETE FROM devices WHERE push_token = $1 AND user_id <> $2', [
      pushToken,
      userId,
    ]);
    await this.db.query(
      `INSERT INTO devices (user_id, platform, push_token)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, push_token)
       DO UPDATE SET platform = EXCLUDED.platform, last_seen_at = now()`,
      [userId, platform, pushToken],
    );
    return { ok: true };
  }

  async logout(userId: string): Promise<{ ok: true }> {
    await this.db.query(
      'UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
      [userId],
    );
    // Otherwise a signed-out provider keeps being pinged for jobs they can no
    // longer see, and a signed-out client keeps getting booking updates.
    await this.db.query('DELETE FROM devices WHERE user_id = $1', [userId]);
    return { ok: true };
  }

  private async issueTokens(user: UserRow, isNewUser: boolean): Promise<AuthResult> {
    const provider = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM providers WHERE user_id = $1 LIMIT 1',
      [user.id],
    );

    const accessToken = await this.jwt.signAsync(
      {
        sub: user.id,
        phone: user.phone_e164,
        roles: user.roles,
        country: user.country_code,
        providerId: provider?.id,
      },
      {
        secret: this.config.getOrThrow<string>('JWT_SECRET'),
        expiresIn: this.config.get<string>('JWT_ACCESS_TTL') ?? '15m',
      },
    );

    const refreshToken = randomBytes(48).toString('base64url');
    await this.db.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, now() + INTERVAL '30 days')`,
      [user.id, this.crypto.hash(refreshToken)],
    );

    // Returned with the session so the app can route straight to the right
    // screen. Without it, a returning client would be sent through area
    // selection again on every sign-in, or the app would need a second round
    // trip before it could decide.
    const area = await this.db.queryOne<{
      id: string;
      slug: string;
      name: string;
      lat: string;
      lng: string;
    }>(
      `SELECT a.id, a.slug, a.name,
              ST_Y(a.centroid::geometry) AS lat,
              ST_X(a.centroid::geometry) AS lng
         FROM users u
         JOIN service_areas a ON a.id = u.preferred_service_area_id
        WHERE u.id = $1`,
      [user.id],
    );

    return {
      accessToken,
      refreshToken,
      // Read from the token rather than hardcoded. It said 900 regardless of
      // JWT_ACCESS_TTL, so changing the TTL made the API lie to the client
      // about when its token dies.
      expiresIn: expiresInSeconds(accessToken),
      isNewUser,
      profileComplete: Boolean(user.full_name) && Boolean(user.consent_privacy_at),
      serviceArea: area
        ? {
            id: area.id,
            slug: area.slug,
            name: area.name,
            lat: Number(area.lat),
            lng: Number(area.lng),
          }
        : null,
      user: {
        id: user.id,
        fullName: user.full_name,
        phone: user.phone_e164,
        roles: user.roles,
        countryCode: user.country_code,
      },
    };
  }
}
