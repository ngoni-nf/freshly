import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';
import { RedisService } from '../../common/redis/redis.service';
import { AuthResult, AuthService } from '../auth/auth.service';
import { CommsService } from '../comms/comms.service';
import { MarketsService } from '../markets/markets.service';
import { OPEN_STATUSES } from '../bookings/bookings.service';

interface SalonRow {
  id: string;
  display_name: string;
  business_mode: string;
  country_code: 'ZA' | 'ZW';
  service_area_id: string | null;
  venue_mode: string;
  shop_address: string | null;
  categories: string[];
  payout_currency: string;
  is_suspended: boolean;
}

/**
 * A salon's team.
 *
 * A staff member is a provider row in their own right, because everything
 * that makes a provider safe to send to a door — identity verification,
 * suspension, a device to push to — is keyed on `providers.id`. What makes
 * them staff rather than a business is that the row is `salon_staff` and
 * points at the salon: they take no bookings of their own, hold no menu, do
 * not appear in discovery, and the money for every job they do lands in the
 * salon's wallet because the booking's `provider_id` never stops being the
 * salon.
 *
 * Invitations go by phone number so a salon can invite someone who has never
 * installed the app; the invite is matched to them the first time they sign
 * in with that number.
 */
@Injectable()
export class StaffService {
  private readonly logger = new Logger(StaffService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
    private readonly markets: MarketsService,
    private readonly auth: AuthService,
    private readonly comms: CommsService,
  ) {}

  // ─── Salon side ────────────────────────────────────────────────────────────

  async list(salonProviderId: string) {
    const salon = await this.requireSalon(salonProviderId);
    const market = this.markets.get(salon.country_code);

    const staff = await this.db.query<Record<string, any>>(
      `SELECT s.id, s.display_name, s.kyc_status, s.is_suspended, u.phone_e164,
              (SELECT count(*)::int FROM bookings b
                WHERE b.assigned_staff_id = s.id
                  AND b.status NOT IN ('draft','pending_auth','cancelled','expired')
                  AND COALESCE(b.scheduled_start, b.created_at)
                        >= date_trunc('week', now() AT TIME ZONE $2) AT TIME ZONE $2
                  AND COALESCE(b.scheduled_start, b.created_at)
                        <  (date_trunc('week', now() AT TIME ZONE $2) + INTERVAL '7 days') AT TIME ZONE $2
              ) AS jobs_this_week,
              (SELECT count(*)::int FROM bookings b
                WHERE b.assigned_staff_id = s.id AND b.status = 'completed') AS completed_jobs
         FROM providers s
         JOIN users u ON u.id = s.user_id
        WHERE s.salon_parent_id = $1 AND s.business_mode = 'salon_staff'
        ORDER BY s.display_name`,
      [salonProviderId, market.timezone],
    );
    const invites = await this.db.query<{ id: string; phone_e164: string }>(
      `SELECT id, phone_e164 FROM staff_invites
        WHERE salon_provider_id = $1 AND status = 'pending'
        ORDER BY created_at`,
      [salonProviderId],
    );

    return [
      ...staff.map((s) => ({
        id: s.id,
        kind: 'staff' as const,
        displayName: s.display_name,
        phone: maskPhone(s.phone_e164, market.dialPrefix),
        status: 'active' as const,
        kycStatus: s.kyc_status,
        isSuspended: s.is_suspended,
        jobsThisWeek: Number(s.jobs_this_week ?? 0),
        completedJobs: Number(s.completed_jobs ?? 0),
      })),
      ...invites.map((i) => ({
        id: i.id,
        kind: 'invite' as const,
        displayName: null,
        phone: maskPhone(i.phone_e164, market.dialPrefix),
        status: 'pending' as const,
        kycStatus: null,
        isSuspended: false,
        jobsThisWeek: 0,
        completedJobs: 0,
      })),
    ];
  }

  async invite(salonProviderId: string, phone: string) {
    const salon = await this.requireSalon(salonProviderId);
    const e164 = this.markets.toE164(phone, salon.country_code);

    const existing = await this.db.queryOne<{
      provider_id: string | null; business_mode: string | null; salon_parent_id: string | null;
      completed_jobs: number | null; user_id: string;
    }>(
      `SELECT u.id AS user_id, p.id AS provider_id, p.business_mode, p.salon_parent_id, p.completed_jobs
         FROM users u LEFT JOIN providers p ON p.user_id = u.id
        WHERE u.phone_e164 = $1`,
      [e164],
    );
    if (existing?.provider_id) {
      if (existing.business_mode === 'salon_staff' && existing.salon_parent_id === salonProviderId) {
        throw new DomainError('already_staff', 'That person is already on your team', HttpStatus.CONFLICT);
      }
      if (hasOwnBusiness(existing)) {
        throw new DomainError(
          'has_own_business',
          'That number belongs to a professional who already works elsewhere on Freshly',
          HttpStatus.CONFLICT,
        );
      }
    }

    const pending = await this.db.queryOne<{ id: string }>(
      `SELECT id FROM staff_invites
        WHERE salon_provider_id = $1 AND phone_e164 = $2 AND status = 'pending'`,
      [salonProviderId, e164],
    );
    if (pending) {
      throw new DomainError('invite_pending', 'That number has already been invited', HttpStatus.CONFLICT);
    }

    const row = await this.db.queryOne<{ id: string }>(
      `INSERT INTO staff_invites (salon_provider_id, phone_e164) VALUES ($1, $2) RETURNING id`,
      [salonProviderId, e164],
    );

    // Best effort: the invite is matched on sign-in whether or not the text
    // arrives, and a salon should not be told "invite failed" because an SMS
    // gateway hiccupped.
    void this.comms
      .notifyStaffInvite(e164, salon.display_name)
      .catch((err: unknown) => this.logger.warn(`staff invite sms to ...${e164.slice(-4)} failed: ${String(err)}`));

    return { id: row!.id, status: 'pending' as const };
  }

  /**
   * One endpoint for both because the list mixes the two and the app should
   * not have to remember which kind a row was. Removing a person is not a
   * delete: their provider row is their identity and verification history,
   * so it becomes a solo row with nothing attached, offline, and any job they
   * had not yet finished goes back to the salon's own diary.
   */
  async remove(salonProviderId: string, id: string): Promise<{ ok: true }> {
    await this.requireSalon(salonProviderId);

    const invite = await this.db.queryOne<{ id: string }>(
      `UPDATE staff_invites SET status = 'cancelled'
        WHERE id = $1 AND salon_provider_id = $2 AND status = 'pending'
        RETURNING id`,
      [id, salonProviderId],
    );
    if (invite) return { ok: true };

    const removed = await this.db.transaction(async (tx) => {
      const staff = await tx.queryOne<{ id: string }>(
        `UPDATE providers
            SET business_mode = 'solo', salon_parent_id = NULL, is_online = false, updated_at = now()
          WHERE id = $1 AND salon_parent_id = $2 AND business_mode = 'salon_staff'
          RETURNING id`,
        [id, salonProviderId],
      );
      if (!staff) return null;
      await tx.query(
        `UPDATE bookings SET assigned_staff_id = NULL, updated_at = now()
          WHERE assigned_staff_id = $1 AND status = ANY($2::booking_status_enum[])`,
        [id, OPEN_STATUSES],
      );
      return staff.id;
    });
    if (!removed) throw new NotFoundError('Staff member', id);

    await this.redis.purgeLocation(removed);
    return { ok: true };
  }

  // ─── Invitee side ──────────────────────────────────────────────────────────

  async pendingFor(userId: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT i.id, p.display_name AS salon_name,
              COALESCE(
                (SELECT pl.name FROM places pl
                  WHERE pl.service_area_id = p.service_area_id AND pl.is_active
                  ORDER BY pl.centroid <-> p.base_location LIMIT 1),
                a.name) AS salon_suburb
         FROM staff_invites i
         JOIN users u ON u.phone_e164 = i.phone_e164
         JOIN providers p ON p.id = i.salon_provider_id
         LEFT JOIN service_areas a ON a.id = p.service_area_id
        WHERE u.id = $1 AND i.status = 'pending' AND NOT p.is_suspended
        ORDER BY i.created_at DESC`,
      [userId],
    );
    return rows.map((r) => ({
      id: r.id,
      salonName: r.salon_name,
      salonSuburb: r.salon_suburb ?? null,
    }));
  }

  /**
   * Joining a salon is a sign-up: it ends with a session carrying the
   * provider role, exactly as become-provider does, so the app routes to the
   * same place either way.
   */
  async accept(userId: string, inviteId: string): Promise<AuthResult> {
    const user = await this.db.queryOne<{
      phone_e164: string | null; full_name: string; status: string; country_code: 'ZA' | 'ZW';
    }>(
      'SELECT phone_e164, full_name, status, country_code FROM users WHERE id = $1',
      [userId],
    );
    if (!user) throw new NotFoundError('User', userId);
    if (user.status !== 'active') {
      throw new DomainError('account_not_active', 'This account cannot join a salon', HttpStatus.FORBIDDEN);
    }

    // Matched on the number, so an invite id guessed from elsewhere is simply
    // not found rather than a way to join a salon that did not ask for you.
    const invite = await this.db.queryOne<{ id: string; salon_provider_id: string }>(
      `SELECT id, salon_provider_id FROM staff_invites
        WHERE id = $1 AND status = 'pending' AND phone_e164 = $2`,
      [inviteId, user.phone_e164],
    );
    if (!invite) throw new NotFoundError('Invitation', inviteId);

    const salon = await this.requireSalon(invite.salon_provider_id);
    if (salon.is_suspended) {
      throw new DomainError('salon_suspended', 'That salon is not taking bookings right now', HttpStatus.CONFLICT);
    }
    // The staff member will be dispatched inside the salon's market and paid
    // through its wallet; an account from the other country has the wrong
    // currency and the wrong phone prefix for both.
    if (salon.country_code !== user.country_code) {
      throw new DomainError('market_mismatch', 'That salon is in a different country from your account', HttpStatus.UNPROCESSABLE_ENTITY);
    }

    const existing = await this.db.queryOne<{
      provider_id: string; business_mode: string; salon_parent_id: string | null; completed_jobs: number;
    }>(
      'SELECT id AS provider_id, business_mode, salon_parent_id, completed_jobs FROM providers WHERE user_id = $1',
      [userId],
    );
    const alreadyHere = existing?.business_mode === 'salon_staff' && existing.salon_parent_id === salon.id;
    if (existing && !alreadyHere && hasOwnBusiness(existing)) {
      throw new DomainError(
        'has_own_business',
        'You already run a business on Freshly. Contact support to move it under a salon.',
        HttpStatus.CONFLICT,
      );
    }

    await this.db.transaction(async (tx) => {
      let providerId: string;
      if (!existing) {
        const created = await tx.queryOne<{ id: string }>(
          `INSERT INTO providers (
             user_id, country_code, service_area_id, business_mode, salon_parent_id, display_name,
             categories, venue_mode, base_location, last_location, last_location_at,
             shop_address, kyc_status, payout_currency)
           SELECT $1, p.country_code, p.service_area_id, 'salon_staff', p.id, $2,
                  p.categories, p.venue_mode, p.base_location, p.base_location, now(),
                  p.shop_address, 'pending', p.payout_currency
             FROM providers p WHERE p.id = $3
           RETURNING id`,
          [userId, user.full_name?.trim() || 'Team member', salon.id],
        );
        providerId = created!.id;
        await tx.query(
          `UPDATE users SET roles = array_append(roles, 'provider'::account_role_enum)
            WHERE id = $1 AND NOT ('provider' = ANY(roles))`,
          [userId],
        );
      } else {
        // A solo row with no completed jobs, or a staff row this salon
        // already has: either way it now belongs to this salon. Verification
        // is kept; it is about the person, not the business.
        providerId = existing.provider_id;
        await tx.query(
          `UPDATE providers p
              SET business_mode = 'salon_staff', salon_parent_id = s.id, is_online = false,
                  country_code = s.country_code, service_area_id = s.service_area_id,
                  base_location = s.base_location, payout_currency = s.payout_currency,
                  updated_at = now()
             FROM providers s
            WHERE p.id = $1 AND s.id = $2`,
          [providerId, salon.id],
        );
      }

      await tx.query(
        `UPDATE staff_invites SET status = 'accepted', accepted_at = now(), accepted_provider_id = $2
          WHERE id = $1`,
        [invite.id, providerId],
      );
    });

    return this.auth.sessionFor(userId);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  private async requireSalon(providerId: string): Promise<SalonRow> {
    const salon = await this.db.queryOne<SalonRow>(
      `SELECT id, display_name, business_mode, country_code, service_area_id, venue_mode,
              shop_address, categories, payout_currency, is_suspended
         FROM providers WHERE id = $1`,
      [providerId],
    );
    if (!salon) throw new NotFoundError('Provider', providerId);
    if (salon.business_mode !== 'salon') {
      throw new DomainError('salon_only', 'Staff management is for salons', HttpStatus.FORBIDDEN);
    }
    return salon;
  }
}

/**
 * Someone with a business of their own cannot be folded into a salon: a salon
 * is a business, a staff member of another salon is spoken for, and a solo
 * provider with completed jobs has a reputation and a wallet history that
 * would be orphaned by the conversion. A solo row that never did a job is
 * just a half-finished sign-up and may be converted.
 */
function hasOwnBusiness(p: { business_mode: string | null; completed_jobs: number | null }): boolean {
  if (p.business_mode === 'salon') return true;
  if (p.business_mode === 'salon_staff') return true;
  return Number(p.completed_jobs ?? 0) > 0;
}

/** "+263 77 ••• 0003": enough for the salon to recognise a number, not to dial it. */
export function maskPhone(e164: string, dialPrefix: string): string {
  const national = e164.startsWith(dialPrefix) ? e164.slice(dialPrefix.length) : e164.replace(/^\+\d{1,3}/, '');
  if (national.length < 6) return `${dialPrefix} •••`;
  return `${dialPrefix} ${national.slice(0, 2)} ••• ${national.slice(-4)}`;
}
