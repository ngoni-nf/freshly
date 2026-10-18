import {
  BadRequestException,
  HttpStatus,
  Injectable,
  Logger,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
// jsonwebtoken 9 (pulled by @nestjs/jwt 11) narrowed expiresIn from a plain
// string to a `ms.StringValue` template. Our TTL is a runtime-valid duration
// string from config, so we borrow the library's own type for the cast rather
// than reaching for `any`.
import type { SignOptions } from 'jsonwebtoken';
import { randomBytes, randomInt } from 'node:crypto';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import { MarketsService } from '../markets/markets.service';
import { DomainError, NotFoundError, RateLimitedError } from '../../common/errors/domain.errors';
import { CommsService } from '../comms/comms.service';
import { FirebaseAuthService } from './firebase-auth.service';
import { AccountRole } from '../../common/decorators';

interface UserRow {
  id: string;
  /** Null for a social/email account that has not linked a number yet. */
  phone_e164: string | null;
  full_name: string;
  roles: AccountRole[];
  country_code: 'ZA' | 'ZW';
  status: string;
  consent_privacy_at: Date | null;
}

const USER_COLUMNS =
  'id, phone_e164, full_name, roles, country_code, status, consent_privacy_at';

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
  /** True for a social/email account with no verified number yet. The app
   *  routes to phone verification before it lets them book. */
  needsPhone: boolean;
  /** Null until the client has chosen where they want service. */
  serviceArea: {
    id: string;
    slug: string;
    name: string;
    lat: number;
    lng: number;
    /** The suburb they picked, when they picked one. Null if only an area. */
    placeId: string | null;
    placeName: string | null;
  } | null;
  user: {
    id: string;
    fullName: string;
    /** Null for a social/email account that has not linked a number yet. */
    phone: string | null;
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
    const locale = countryCode === 'ZA' ? 'en-ZA' : 'en-ZW';

    // Two doors into the same account. A phone-auth token brings a verified
    // number and is keyed on it, the way every account used to be. A Google or
    // email token brings none and is keyed on the Firebase uid; that account
    // exists but carries a null phone until link-phone fills it in.
    let user: UserRow | null;
    let isNewUser = false;

    if (identity.phoneE164) {
      user = await this.db.queryOne<UserRow>(
        `SELECT ${USER_COLUMNS} FROM users WHERE phone_e164 = $1`,
        [identity.phoneE164],
      );
      if (!user) {
        isNewUser = true;
        user = await this.db.queryOne<UserRow>(
          `INSERT INTO users (phone_e164, firebase_uid, country_code, full_name, email, phone_verified_at, locale)
           VALUES ($1, $2, $3, $4, $5, now(), $6)
           RETURNING ${USER_COLUMNS}`,
          [identity.phoneE164, identity.uid, countryCode, identity.name ?? '', identity.email ?? null, locale],
        );
      } else {
        this.assertActive(user);
        await this.db.query(
          `UPDATE users SET phone_verified_at = COALESCE(phone_verified_at, now()),
                  firebase_uid = COALESCE(firebase_uid, $2), last_seen_at = now()
             WHERE id = $1`,
          [user.id, identity.uid],
        );
      }
    } else {
      user = await this.db.queryOne<UserRow>(
        `SELECT ${USER_COLUMNS} FROM users WHERE firebase_uid = $1`,
        [identity.uid],
      );
      // Admin-invite by email: an account pre-provisioned with roles but no
      // phone and no firebase_uid is a pending invite. The first social sign-in
      // whose *verified* email matches it claims it, inheriting the roles. This
      // is scoped to invites only — an account with a phone or an already-linked
      // uid can never be claimed this way — so a Google email can never take
      // over a real user's account.
      if (!user && identity.email) {
        const invite = await this.db.queryOne<UserRow>(
          `SELECT ${USER_COLUMNS} FROM users
            WHERE email = $1 AND phone_e164 IS NULL AND firebase_uid IS NULL`,
          [identity.email],
        );
        if (invite) {
          this.assertActive(invite);
          user = await this.db.queryOne<UserRow>(
            `UPDATE users SET firebase_uid = $2, last_seen_at = now()
              WHERE id = $1 RETURNING ${USER_COLUMNS}`,
            [invite.id, identity.uid],
          );
        }
      }
      if (!user) {
        isNewUser = true;
        // No phone: the account is born unable to book until it links one.
        user = await this.db.queryOne<UserRow>(
          `INSERT INTO users (firebase_uid, country_code, full_name, email, locale)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING ${USER_COLUMNS}`,
          [identity.uid, countryCode, identity.name ?? '', identity.email ?? null, locale],
        );
      } else {
        this.assertActive(user);
        await this.db.query('UPDATE users SET last_seen_at = now() WHERE id = $1', [user.id]);
      }
    }

    await this.registerDevice(user!.id, device);

    return this.issueTokens(user!, isNewUser);
  }

  private assertActive(user: UserRow): void {
    if (user.status !== 'active') {
      throw new UnauthorizedException({
        code: 'account_suspended',
        message: 'This account is not active. Contact support.',
      });
    }
  }

  private async registerDevice(
    userId: string,
    device?: { platform: string; pushToken?: string },
  ): Promise<void> {
    if (!device?.platform) return;
    await this.db.query(
      `INSERT INTO devices (user_id, platform, push_token)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, push_token) DO UPDATE SET last_seen_at = now()`,
      [userId, device.platform, device.pushToken ?? null],
    );
  }

  /**
   * Attach a verified phone to a social/email account, the step that lets it
   * finally book. The number comes as a Firebase phone-auth token, so it is
   * proven the same way a phone sign-in proves it — we never take a phone on a
   * user's word.
   */
  async linkPhone(
    userId: string,
    phoneIdToken: string,
    _countryCode: 'ZA' | 'ZW',
  ): Promise<AuthResult> {
    const identity = await this.firebase.verifyIdToken(phoneIdToken);
    if (!identity.phoneE164) {
      throw new UnauthorizedException({
        code: 'not_a_phone_token',
        message: 'That verification did not carry a phone number',
      });
    }

    const me = await this.db.queryOne<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE id = $1`,
      [userId],
    );
    if (!me) throw new NotFoundError('User', userId);
    this.assertActive(me);

    // The number may already be somebody's whole account. Merging two histories
    // — bookings, wallet, roles — is not a thing to do silently, so refuse and
    // let support handle it rather than guess which account wins.
    const owner = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM users WHERE phone_e164 = $1',
      [identity.phoneE164],
    );
    if (owner && owner.id !== userId) {
      throw new DomainError(
        'phone_taken',
        'That number already belongs to another Freshly account.',
        HttpStatus.CONFLICT,
      );
    }

    const updated = await this.db.queryOne<UserRow>(
      `UPDATE users
          SET phone_e164 = $2, phone_verified_at = now(),
              firebase_uid = COALESCE(firebase_uid, $3), last_seen_at = now()
        WHERE id = $1
        RETURNING ${USER_COLUMNS}`,
      [userId, identity.phoneE164, identity.uid],
    );

    return this.issueTokens(updated!, false);
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
   * A signed-in person becomes a provider.
   *
   * Until now nothing created a `providers` row: a barber who installed the
   * partner app got a customer account and every provider screen answered
   * insufficient_role. This creates the row with kyc_status 'pending', adds
   * the role, and issues a fresh session, because the role and providerId
   * travel in the token and the old one would keep saying "client".
   *
   * The base location decides the service area, resolved in the database so
   * the sign-up and any later import agree on what "inside Harare" means. A
   * point outside every live area of the user's country is refused: a pro who
   * cannot be dispatched to is not a pro the app should show as one.
   *
   * Default working hours are written at the same time, because a scheduled
   * booking needs a rule for the weekday and "Pick a time" otherwise fails
   * for every new provider until they find the settings screen.
   */
  async becomeProvider(
    userId: string,
    input: {
      displayName: string;
      businessMode: 'solo' | 'salon';
      categories: string[];
      venueMode: 'mobile' | 'in_shop' | 'both';
      lat: number;
      lng: number;
      shopAddress?: string;
      travelRadiusKm?: number;
      powerBackup?: string[];
      bio?: string;
    },
  ): Promise<AuthResult> {
    const user = await this.db.queryOne<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE id = $1`,
      [userId],
    );
    if (!user) throw new NotFoundError('User', userId);
    if (user.status !== 'active') {
      throw new DomainError('account_not_active', 'This account cannot register as a provider', HttpStatus.FORBIDDEN);
    }

    const existing = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM providers WHERE user_id = $1',
      [userId],
    );
    if (existing) {
      throw new DomainError('already_provider', 'This account is already registered as a provider', HttpStatus.CONFLICT);
    }

    if (input.venueMode !== 'mobile' && !input.shopAddress) {
      throw new DomainError('shop_address_required', 'Tell clients where your shop is');
    }

    const area = await this.db.queryOne<{ id: string | null }>(
      'SELECT fn_service_area_for_point($1::country_code_enum, $2, $3) AS id',
      [user.country_code, input.lat, input.lng],
    );
    if (!area?.id) {
      throw new DomainError(
        'outside_service_area',
        'Freshly is not live where you are based yet',
        HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }

    const market = this.markets.get(user.country_code);
    const slug = await this.uniqueSlug(input.displayName);

    await this.db.transaction(async (tx) => {
      const provider = await tx.queryOne<{ id: string }>(
        `INSERT INTO providers (
           user_id, country_code, service_area_id, business_mode, display_name, slug, bio,
           categories, venue_mode, power_backup, base_location, last_location, last_location_at,
           shop_address, travel_radius_km, kyc_status, payout_currency)
         VALUES ($1, $2::country_code_enum, $3, $4::business_mode_enum, $5, $6, $7,
                 $8::service_category_enum[], $9::service_venue_enum, $10::power_backup_enum[],
                 ST_SetSRID(ST_MakePoint($11, $12), 4326)::geography,
                 ST_SetSRID(ST_MakePoint($11, $12), 4326)::geography, now(),
                 $13, $14, 'pending', $15::currency_code_enum)
         RETURNING id`,
        [
          userId, user.country_code, area.id, input.businessMode, input.displayName.trim(), slug,
          input.bio?.trim() || null, input.categories, input.venueMode, input.powerBackup ?? [],
          input.lng, input.lat, input.shopAddress?.trim() || null, input.travelRadiusKm ?? 10,
          market.defaultCurrency,
        ],
      );

      await tx.query(
        `UPDATE users SET roles = array_append(roles, 'provider'::account_role_enum)
          WHERE id = $1 AND NOT ('provider' = ANY(roles))`,
        [userId],
      );

      // Monday to Saturday, 08:00 to 18:00, editable from the availability
      // screen. Weekday 0 is Sunday.
      await tx.query(
        `INSERT INTO availability_rules (provider_id, weekday, starts_at, ends_at)
         SELECT $1, d, '08:00', '18:00' FROM generate_series(1, 6) AS d`,
        [provider!.id],
      );
    });

    return this.sessionFor(userId);
  }

  /**
   * A fresh session for an account whose roles just changed. The JWT carries
   * the roles and the provider id, so after any change to either the old
   * token is a lie and the caller needs a new one before the next request.
   */
  async sessionFor(userId: string): Promise<AuthResult> {
    const user = await this.db.queryOne<UserRow>(
      `SELECT ${USER_COLUMNS} FROM users WHERE id = $1`,
      [userId],
    );
    if (!user) throw new NotFoundError('User', userId);
    return this.issueTokens(user, false);
  }

  /** A readable, unique slug for the public profile URL. */
  private async uniqueSlug(displayName: string): Promise<string> {
    const base = displayName
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 60) || 'pro';
    for (let attempt = 0; attempt < 20; attempt++) {
      const candidate = attempt === 0 ? base : `${base}-${randomBytes(2).toString('hex')}`;
      const taken = await this.db.queryOne<{ id: string }>(
        'SELECT id FROM providers WHERE slug = $1',
        [candidate],
      );
      if (!taken) return candidate;
    }
    return `${base}-${randomBytes(4).toString('hex')}`;
  }

  /**
   * Where the client wants service.
   *
   * Validated against live areas rather than trusted, and required to be in
   * the user's own market — a South African account choosing a Zimbabwean area
   * would be priced in the wrong currency by every downstream quote.
   */
  /**
   * Where the user wants service.
   *
   * A place may be given instead of an area, and is the better answer: people
   * know they are in Rosebank, not in "Johannesburg North". The place decides
   * the area, so the two can never disagree, and both are stored — the area is
   * what dispatch and pricing need, the suburb is what we show back to them so
   * the choice reads as a preference rather than something they must re-derive.
   *
   * Callable at any time, not only at sign-up: changing it is the same
   * operation as setting it.
   */
  async setServiceArea(userId: string, serviceAreaId?: string, placeId?: string) {
    let placeRow: { id: string; name: string; service_area_id: string } | null = null;

    if (placeId) {
      placeRow = await this.db.queryOne<{ id: string; name: string; service_area_id: string }>(
        `SELECT p.id, p.name, p.service_area_id
           FROM places p
           JOIN service_areas a ON a.id = p.service_area_id
          WHERE p.id = $1 AND p.is_active AND a.is_live`,
        [placeId],
      );
      if (!placeRow) {
        throw new BadRequestException({
          code: 'place_not_live',
          message: 'Freshly is not open in that area yet',
        });
      }
      serviceAreaId = placeRow.service_area_id;
    }

    if (!serviceAreaId) {
      throw new BadRequestException({
        code: 'area_required',
        message: 'Choose where you want service',
      });
    }

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

    // Clears the suburb when only an area was given, so the two never drift
    // into claiming the user is in a suburb of somewhere they no longer are.
    await this.db.query(
      'UPDATE users SET preferred_service_area_id = $2, preferred_place_id = $3 WHERE id = $1',
      [userId, area.id, placeRow?.id ?? null],
    );

    return {
      id: area.id,
      slug: area.slug,
      name: area.name,
      countryCode: area.country_code,
      lat: Number(area.lat),
      lng: Number(area.lng),
      placeId: placeRow?.id ?? null,
      placeName: placeRow?.name ?? null,
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
      place_id: string | null;
      place_name: string | null;
      place_lat: string | null;
      place_lng: string | null;
    }>(
      // The suburb's centroid is the better origin when we have one: it is
      // where the user actually is, rather than the middle of a whole metro.
      `SELECT a.id, a.slug, a.name,
              ST_Y(a.centroid::geometry) AS lat,
              ST_X(a.centroid::geometry) AS lng,
              p.id   AS place_id,
              p.name AS place_name,
              ST_Y(p.centroid::geometry) AS place_lat,
              ST_X(p.centroid::geometry) AS place_lng
         FROM users u
         JOIN service_areas a ON a.id = u.preferred_service_area_id
         LEFT JOIN places p ON p.id = u.preferred_place_id AND p.is_active
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
      needsPhone: !user.phone_e164,
      serviceArea: area
        ? {
            id: area.id,
            slug: area.slug,
            name: area.name,
            // The suburb centroid when we have one: it is where the user
            // actually is, not the middle of an entire metro.
            lat: Number(area.place_lat ?? area.lat),
            lng: Number(area.place_lng ?? area.lng),
            placeId: area.place_id,
            placeName: area.place_name,
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
        expiresIn: (this.config.get<string>('JWT_ACCESS_TTL') ??
          '15m') as SignOptions['expiresIn'],
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
      place_id: string | null;
      place_name: string | null;
      place_lat: string | null;
      place_lng: string | null;
    }>(
      `SELECT a.id, a.slug, a.name,
              ST_Y(a.centroid::geometry) AS lat,
              ST_X(a.centroid::geometry) AS lng,
              p.id   AS place_id,
              p.name AS place_name,
              ST_Y(p.centroid::geometry) AS place_lat,
              ST_X(p.centroid::geometry) AS place_lng
         FROM users u
         JOIN service_areas a ON a.id = u.preferred_service_area_id
         LEFT JOIN places p ON p.id = u.preferred_place_id AND p.is_active
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
      needsPhone: !user.phone_e164,
      serviceArea: area
        ? {
            id: area.id,
            slug: area.slug,
            name: area.name,
            // The suburb centroid when we have one: it is where the user
            // actually is, not the middle of an entire metro.
            lat: Number(area.place_lat ?? area.lat),
            lng: Number(area.place_lng ?? area.lng),
            placeId: area.place_id,
            placeName: area.place_name,
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
