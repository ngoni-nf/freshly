import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { KycRequiredError, NotFoundError } from '../../common/errors/domain.errors';
import { MarketsService } from '../markets/markets.service';

@Injectable()
export class ProvidersService {
  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
    private readonly markets: MarketsService,
  ) {}

  async profile(providerId: string) {
    const provider = await this.db.queryOne<Record<string, any>>(
      `SELECT p.id, p.display_name, p.bio, p.categories, p.venue_mode, p.power_backup,
              p.has_power_backup, p.rating, p.rating_count, p.completed_jobs,
              p.travel_radius_km, p.is_online, p.shop_address, u.avatar_url
         FROM providers p
         JOIN users u ON u.id = p.user_id
        WHERE p.id = $1 AND NOT p.is_suspended AND p.kyc_status = 'verified'`,
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    const services = await this.db.query<Record<string, any>>(
      `SELECT id, name, description, category, price_minor, currency, duration_minutes, requires_power
         FROM services WHERE provider_id = $1 AND is_active ORDER BY sort_order, name`,
      [providerId],
    );

    const portfolio = await this.db.query<Record<string, any>>(
      `SELECT id, media_key, ai_tags FROM portfolio_items
        WHERE provider_id = $1 AND moderation_status = 'approved'
        ORDER BY sort_order LIMIT 20`,
      [providerId],
    );

    const reviews = await this.db.query<Record<string, any>>(
      `SELECT r.rating, r.tags, r.comment, r.created_at, u.full_name
         FROM reviews r JOIN users u ON u.id = r.author_id
        WHERE r.subject_user_id = (SELECT user_id FROM providers WHERE id = $1)
          AND r.is_published AND r.direction = 'client_to_provider'
        ORDER BY r.created_at DESC LIMIT 10`,
      [providerId],
    );

    return {
      id: provider.id,
      displayName: provider.display_name,
      bio: provider.bio,
      avatarUrl: provider.avatar_url,
      categories: provider.categories,
      venueMode: provider.venue_mode,
      powerBackup: provider.power_backup,
      hasPowerBackup: provider.has_power_backup,
      rating: Number(provider.rating),
      ratingCount: provider.rating_count,
      completedJobs: provider.completed_jobs,
      isOnline: provider.is_online,
      shopAddress: provider.shop_address,
      services: services.map((s) => ({
        id: s.id, name: s.name, description: s.description, category: s.category,
        priceMinor: Number(s.price_minor), currency: s.currency,
        durationMinutes: s.duration_minutes, requiresPower: s.requires_power,
      })),
      portfolio: portfolio.map((p) => ({ id: p.id, url: p.media_key, tags: p.ai_tags })),
      reviews: reviews.map((r) => ({
        rating: r.rating, tags: r.tags, comment: r.comment,
        author: firstNameOnly(r.full_name), createdAt: r.created_at.toISOString(),
      })),
    };
  }

  /**
   * Going online is gated on verification. An unverified provider appearing in
   * dispatch is the single worst failure mode this platform has — someone
   * unvetted arriving at a stranger's home — so the check lives here rather
   * than only in the search query.
   */
  async setPresence(providerId: string, isOnline: boolean) {
    const provider = await this.db.queryOne<{ kyc_status: string; is_suspended: boolean }>(
      'SELECT kyc_status, is_suspended FROM providers WHERE id = $1', [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);
    if (isOnline && (provider.kyc_status !== 'verified' || provider.is_suspended)) {
      throw new KycRequiredError();
    }

    await this.db.query('UPDATE providers SET is_online = $2 WHERE id = $1', [providerId, isOnline]);
    if (!isOnline) await this.redis.purgeLocation(providerId);
    return { isOnline };
  }

  /**
   * Position updates.
   *
   * The live breadcrumb goes to Redis with a TTL. Postgres holds only a coarse
   * last-known point for dispatch radius maths — never a trail, because a trail
   * of where a person has been is precisely the data neither POPIA nor the
   * Zimbabwe DPA lets you keep without a purpose.
   */
  async updateLocation(providerId: string, lat: number, lng: number, heading?: number, speedKph?: number) {
    const ttl = this.markets.setting<number>('tracking.retention_minutes', 60) * 60;
    await this.redis.recordLocation(providerId, { lat, lng, heading, speedKph }, ttl);
    await this.db.query(
      `UPDATE providers
          SET last_location = ST_SetSRID(ST_MakePoint($2, $3), 4326)::GEOGRAPHY,
              last_location_at = now()
        WHERE id = $1`,
      [providerId, lng, lat],
    );
    return { ok: true };
  }

  /** Operator search. Deliberately includes suspended and unverified people —
   * they are exactly who an operator is looking for. */
  async adminSearch(query: string | undefined, limit = 25) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT p.id, p.display_name, p.slug, p.country_code, p.kyc_status,
              p.is_suspended, p.is_online, p.rating, p.completed_jobs, u.phone_e164
         FROM providers p
         JOIN users u ON u.id = p.user_id
        WHERE ($1::text IS NULL
               OR p.display_name ILIKE '%' || $1 || '%'
               OR u.phone_e164 ILIKE '%' || $1 || '%')
        ORDER BY p.is_suspended DESC, p.display_name
        LIMIT $2`,
      [query ?? null, limit],
    );

    return rows.map((r) => ({
      id: r.id,
      displayName: r.display_name,
      slug: r.slug,
      countryCode: r.country_code,
      phone: r.phone_e164,
      kycStatus: r.kyc_status,
      isSuspended: r.is_suspended,
      isOnline: r.is_online,
      rating: Number(r.rating),
      completedJobs: r.completed_jobs,
    }));
  }

  /**
   * Suspend or reinstate a provider.
   *
   * Suspending takes them offline in the same statement. Leaving someone
   * online after a suspension, even for the seconds until a job notices, is
   * the whole reason the flag exists — and it is the same rule the KYC path
   * follows when verification is lost.
   */
  async setSuspension(
    providerId: string,
    suspended: boolean,
    reason: string,
    actorUserId: string,
  ) {
    const before = await this.db.queryOne<{ is_suspended: boolean }>(
      'SELECT is_suspended FROM providers WHERE id = $1',
      [providerId],
    );
    if (!before) throw new NotFoundError('Provider', providerId);

    await this.db.transaction(async (tx) => {
      await tx.query(
        `UPDATE providers
            SET is_suspended = $2,
                is_online = CASE WHEN $2 THEN false ELSE is_online END,
                updated_at = now()
          WHERE id = $1`,
        [providerId, suspended],
      );

      await tx.query(
        `INSERT INTO audit_log (actor_id, actor_role, action, entity_type, entity_id, before, after)
         VALUES ($1, 'admin', $2, 'provider', $3, $4::jsonb, $5::jsonb)`,
        [
          actorUserId,
          suspended ? 'provider.suspended' : 'provider.reinstated',
          providerId,
          JSON.stringify({ isSuspended: before.is_suspended }),
          JSON.stringify({ isSuspended: suspended, reason }),
        ],
      );

      await tx.emitEvent('provider', providerId, suspended ? 'provider.suspended' : 'provider.reinstated', {
        reason,
      });
    });

    if (suspended) await this.redis.purgeLocation(providerId);
    return { isSuspended: suspended };
  }

  async addAvailabilityBlock(providerId: string, start: Date, end: Date, reason: string) {
    await this.db.query(
      `INSERT INTO availability_blocks (provider_id, reason, period)
       VALUES ($1, $2, tstzrange($3, $4, '[)'))`,
      [providerId, reason, start, end],
    );
    return { ok: true };
  }

  async todaySchedule(providerId: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.status, b.scheduled_start, b.destination_address,
              b.provider_payout_minor, b.currency, u.full_name AS client_name
         FROM bookings b JOIN users u ON u.id = b.client_id
        WHERE b.provider_id = $1
          AND b.status IN ('accepted','en_route','arrived','in_progress')
        ORDER BY COALESCE(b.scheduled_start, b.created_at)`,
      [providerId],
    );
    return rows.map((r) => ({
      id: r.id, reference: r.reference, status: r.status,
      scheduledStart: r.scheduled_start?.toISOString() ?? null,
      destinationAddress: r.destination_address,
      clientName: firstNameOnly(r.client_name),
      payout: { minor: Number(r.provider_payout_minor), currency: r.currency },
    }));
  }
}

/** Reviews and schedules show a first name only. Full names are not needed. */
function firstNameOnly(fullName: string | null): string {
  if (!fullName) return 'Freshly client';
  const [first] = fullName.trim().split(/\s+/);
  return first ?? 'Freshly client';
}
