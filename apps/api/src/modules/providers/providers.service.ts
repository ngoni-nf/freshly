import { HttpStatus, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { DomainError, KycRequiredError, NotFoundError } from '../../common/errors/domain.errors';
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
   * The provider's own portfolio, including items still awaiting moderation.
   *
   * Deliberately different from the public profile, which shows only approved
   * items. A provider who uploads a photo and cannot see it assumes the upload
   * failed and uploads it again; showing it with its status is the difference
   * between "in review" and "broken".
   */
  async myPortfolio(providerId: string) {
    const rows = await this.db.query<{
      id: string;
      media_key: string;
      ai_tags: string[];
      moderation_status: string;
      sort_order: number;
      created_at: Date;
    }>(
      `SELECT id, media_key, ai_tags, moderation_status, sort_order, created_at
         FROM portfolio_items
        WHERE provider_id = $1
        ORDER BY sort_order, created_at DESC`,
      [providerId],
    );

    return rows.map((r) => ({
      id: r.id,
      url: r.media_key,
      tags: r.ai_tags ?? [],
      moderationStatus: r.moderation_status,
      createdAt: r.created_at.toISOString(),
    }));
  }

  /**
   * Register an already-uploaded photo against the provider.
   *
   * The key is checked against the caller's own namespace rather than trusted.
   * Storage derives every key as `<ownerId>/<purpose>/<uuid>`, so a caller who
   * could name any key could claim someone else's photo as their own work —
   * or point their portfolio at an identity document.
   */
  async addPortfolioItem(
    providerId: string,
    userId: string,
    mediaKey: string,
    tags: string[],
  ) {
    if (!mediaKey.startsWith(`${userId}/portfolio/`)) {
      throw new DomainError(
        'invalid_media_key',
        'That upload does not belong to you',
        HttpStatus.FORBIDDEN,
      );
    }

    const row = await this.db.queryOne<{
      id: string;
      media_key: string;
      ai_tags: string[];
      moderation_status: string;
      created_at: Date;
    }>(
      // sort_order puts the newest first without renumbering every other row.
      `INSERT INTO portfolio_items (provider_id, media_key, ai_tags, sort_order)
       VALUES ($1, $2, $3,
               COALESCE((SELECT MIN(sort_order) - 1 FROM portfolio_items WHERE provider_id = $1), 0))
       RETURNING id, media_key, ai_tags, moderation_status, created_at`,
      [providerId, mediaKey, tags],
    );

    return {
      id: row!.id,
      url: row!.media_key,
      tags: row!.ai_tags ?? [],
      moderationStatus: row!.moderation_status,
      createdAt: row!.created_at.toISOString(),
    };
  }

  /**
   * Scoped to the caller's own provider id, so a valid item id belonging to
   * somebody else deletes nothing rather than deleting theirs.
   */
  async removePortfolioItem(providerId: string, itemId: string): Promise<{ ok: true }> {
    const row = await this.db.queryOne<{ id: string }>(
      'DELETE FROM portfolio_items WHERE id = $1 AND provider_id = $2 RETURNING id',
      [itemId, providerId],
    );
    if (!row) {
      throw new NotFoundError('portfolio_item', 'That photo is no longer there');
    }
    return { ok: true };
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
  /**
   * The whole roster, for the ops console.
   *
   * An empty query returns everyone rather than nothing: the first question an
   * operator has is "who have we got and what are they doing", and making them
   * guess a name before the screen shows anything answers the wrong one.
   *
   * "Online" and "on a job" are different states and the console needs both —
   * somebody online with no work is spare capacity, somebody mid-job is not,
   * and the two look identical without this.
   */
  async adminSearch(query: string | undefined, limit = 25) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT p.id, p.display_name, p.slug, p.country_code, p.kyc_status,
              p.is_suspended, p.is_online, p.rating, p.completed_jobs,
              p.categories, p.venue_mode, u.phone_e164,
              p.created_at,
              live.reference   AS live_reference,
              live.status      AS live_status,
              upcoming.count   AS upcoming_count
         FROM providers p
         JOIN users u ON u.id = p.user_id
         -- At most one job can be live for a provider at a time; the state
         -- machine does not permit two.
         LEFT JOIN LATERAL (
           SELECT b.reference, b.status
             FROM bookings b
            WHERE b.provider_id = p.id
              AND b.status IN ('accepted','en_route','arrived','in_progress')
            ORDER BY b.created_at DESC
            LIMIT 1
         ) live ON true
         LEFT JOIN LATERAL (
           SELECT count(*)::int AS count
             FROM bookings b
            WHERE b.provider_id = p.id
              AND b.scheduled_start > now()
              AND b.status NOT IN ('cancelled','expired','completed')
         ) upcoming ON true
        WHERE ($1::text IS NULL
               OR p.display_name ILIKE '%' || $1 || '%'
               OR u.phone_e164 ILIKE '%' || $1 || '%')
        ORDER BY p.is_suspended DESC, p.is_online DESC, p.display_name
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
      categories: r.categories ?? [],
      venueMode: r.venue_mode,
      joinedAt: r.created_at?.toISOString() ?? null,
      /** Null when they are not currently working. */
      activeJob: r.live_reference
        ? { reference: r.live_reference, status: r.live_status }
        : null,
      upcomingCount: Number(r.upcoming_count ?? 0),
    }));
  }

  /**
   * Everything booked ahead, across the marketplace.
   *
   * The console needs a diary as much as a roster: a scheduled job nobody has
   * accepted is the thing an operator wants to see before the day it happens,
   * not on it.
   */
  async adminSchedule(days = 14) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.status, b.booking_type, b.scheduled_start,
              b.created_at, b.total_minor, b.currency, b.destination_address,
              p.display_name AS provider_name, p.id AS provider_id,
              u.full_name AS client_name,
              COALESCE(
                (SELECT array_agg(bi.name_snapshot ORDER BY bi.name_snapshot)
                   FROM booking_items bi WHERE bi.booking_id = b.id AND NOT bi.is_addon),
                ARRAY[]::text[]) AS services
         FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
         JOIN users u ON u.id = b.client_id
        WHERE b.status NOT IN ('draft','cancelled','expired','completed')
          AND (b.scheduled_start IS NULL OR b.scheduled_start < now() + ($1 || ' days')::interval)
        ORDER BY COALESCE(b.scheduled_start, b.created_at) ASC
        LIMIT 200`,
      [String(days)],
    );

    return rows.map((r) => ({
      id: r.id,
      reference: r.reference,
      status: r.status,
      bookingType: r.booking_type,
      scheduledStart: r.scheduled_start?.toISOString() ?? null,
      createdAt: r.created_at.toISOString(),
      total: { minor: Number(r.total_minor), currency: r.currency },
      // A booking nobody has accepted yet is exactly what ops is looking for.
      providerName: r.provider_name ?? null,
      providerId: r.provider_id ?? null,
      clientName: firstNameOnly(r.client_name),
      services: r.services ?? [],
      destinationAddress: r.destination_address,
    }));
  }

  /**
   * A provider's own reviews.
   *
   * Published only. An unpublished review is one held back pending moderation
   * or a dispute, and showing a provider a complaint the platform has not yet
   * stood behind invites them to go and argue with the client about it.
   *
   * The client's first name only, matching the public profile. A provider
   * already knows who booked them; putting the full name here would make this
   * screen a way to read it off for clients they have forgotten.
   */
  async listMyReviews(providerId: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT r.id, r.rating, r.tags, r.comment, r.created_at,
              u.full_name, b.reference,
              COALESCE(
                (SELECT array_agg(bi.name_snapshot ORDER BY bi.name_snapshot)
                   FROM booking_items bi WHERE bi.booking_id = b.id AND NOT bi.is_addon),
                ARRAY[]::text[]) AS services
         FROM reviews r
         JOIN users u ON u.id = r.author_id
         LEFT JOIN bookings b ON b.id = r.booking_id
        WHERE r.subject_user_id = (SELECT user_id FROM providers WHERE id = $1)
          AND r.direction = 'client_to_provider'
          AND r.is_published
        ORDER BY r.created_at DESC
        LIMIT 100`,
      [providerId],
    );

    return rows.map((r) => ({
      id: r.id,
      rating: r.rating,
      tags: r.tags ?? [],
      comment: r.comment,
      author: firstNameOnly(r.full_name),
      reference: r.reference ?? null,
      services: r.services ?? [],
      createdAt: r.created_at.toISOString(),
    }));
  }

  /**
   * Work already done, and what the client thought of it.
   *
   * The rating is the point. A provider's average tells you nothing about
   * which job went wrong, and by the time an average moves the customer has
   * already gone. One-star and two-star jobs sort to the top for that reason:
   * the console exists to catch those while somebody can still be called.
   *
   * A booking with no review is shown rather than hidden — silence after a job
   * is itself worth seeing.
   */
  async adminCompleted(days = 30, limit = 100) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.completed_at, b.total_minor, b.currency,
              b.destination_address,
              p.id AS provider_id, p.display_name AS provider_name,
              p.rating AS provider_rating, p.rating_count AS provider_rating_count,
              u.full_name AS client_name,
              r.rating, r.tags, r.comment, r.created_at AS reviewed_at,
              COALESCE(
                (SELECT array_agg(bi.name_snapshot ORDER BY bi.name_snapshot)
                   FROM booking_items bi WHERE bi.booking_id = b.id),
                ARRAY[]::text[]) AS services
         FROM bookings b
         JOIN users u ON u.id = b.client_id
         LEFT JOIN providers p ON p.id = b.provider_id
         -- The client's view of the provider, not the other direction.
         LEFT JOIN reviews r
                ON r.booking_id = b.id AND r.direction = 'client_to_provider'
        WHERE b.status = 'completed'
          AND b.completed_at > now() - ($1 || ' days')::interval
        ORDER BY
          -- Unhappy first, then most recent.
          (r.rating IS NOT NULL AND r.rating <= 2) DESC,
          b.completed_at DESC
        LIMIT $2`,
      [String(days), limit],
    );

    return rows.map((r) => ({
      id: r.id,
      reference: r.reference,
      completedAt: r.completed_at?.toISOString() ?? null,
      total: { minor: Number(r.total_minor), currency: r.currency },
      clientName: firstNameOnly(r.client_name),
      providerId: r.provider_id,
      providerName: r.provider_name,
      providerRating: r.provider_rating === null ? null : Number(r.provider_rating),
      providerRatingCount: r.provider_rating_count ?? 0,
      services: r.services ?? [],
      destinationAddress: r.destination_address,
      review: r.rating
        ? {
            rating: r.rating,
            tags: r.tags ?? [],
            comment: r.comment,
            reviewedAt: r.reviewed_at.toISOString(),
          }
        : null,
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

  async listMyClients(providerId: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT DISTINCT u.id, u.full_name, u.avatar_url, u.phone_e164,
              MAX(b.created_at) as last_booking_at,
              COUNT(b.id) as booking_count
         FROM users u
         JOIN bookings b ON b.client_id = u.id
        WHERE b.provider_id = $1 AND b.status = 'completed'
        GROUP BY u.id
        ORDER BY last_booking_at DESC`,
      [providerId],
    );

    return rows.map((r) => ({
      id: r.id,
      fullName: r.full_name,
      avatarUrl: r.avatar_url,
      phone: r.phone_e164,
      lastBookingAt: r.last_booking_at.toISOString(),
      bookingCount: Number(r.booking_count),
    }));
  }

  /**
   * A client is only "yours" if they have actually booked you.
   *
   * Without this the endpoint reads any user row by id, so a provider could
   * walk ids and harvest the name and mobile number of every person on the
   * platform — including other providers' clients, and people who have never
   * booked anyone. The notes and history queries below were already scoped;
   * the identity itself was not, which made the scoping on the other two
   * beside the point.
   *
   * Completed rather than any status, matching listMyClients: a booking that
   * was cancelled before anyone met does not make someone your client.
   */
  private async assertIsMyClient(providerId: string, clientId: string): Promise<void> {
    const relationship = await this.db.queryOne<{ id: string }>(
      `SELECT id FROM bookings
        WHERE provider_id = $1 AND client_id = $2 AND status = 'completed'
        LIMIT 1`,
      [providerId, clientId],
    );
    // Deliberately the same error as a client who does not exist. Telling a
    // caller "that person exists but is not yours" is still an oracle for
    // whether an id belongs to a real user.
    if (!relationship) throw new NotFoundError('Client', clientId);
  }

  async clientDetail(providerId: string, clientId: string) {
    await this.assertIsMyClient(providerId, clientId);

    const user = await this.db.queryOne<Record<string, any>>(
      `SELECT id, full_name, avatar_url, phone_e164, rating, rating_count, created_at
         FROM users WHERE id = $1`,
      [clientId],
    );
    if (!user) throw new NotFoundError('Client', clientId);

    const history = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.status, b.created_at, b.total_minor, b.currency,
              ARRAY(SELECT name_snapshot FROM booking_items WHERE booking_id = b.id) as services
         FROM bookings b
        WHERE b.provider_id = $1 AND b.client_id = $2
        ORDER BY b.created_at DESC`,
      [providerId, clientId],
    );

    const note = await this.db.queryOne<{ notes: string }>(
      'SELECT notes FROM provider_client_notes WHERE provider_id = $1 AND client_user_id = $2',
      [providerId, clientId],
    );

    return {
      id: user.id,
      fullName: user.full_name,
      avatarUrl: user.avatar_url,
      phone: user.phone_e164,
      rating: Number(user.rating),
      ratingCount: user.rating_count,
      joinedAt: user.created_at.toISOString(),
      notes: note?.notes ?? '',
      history: history.map((h) => ({
        id: h.id,
        reference: h.reference,
        status: h.status,
        createdAt: h.created_at.toISOString(),
        total: { minor: Number(h.total_minor), currency: h.currency },
        services: h.services,
      })),
    };
  }

  async updateClientNotes(providerId: string, clientId: string, notes: string) {
    // Same gate as reading. Otherwise the table becomes free storage keyed to
    // any user id a provider cares to name.
    await this.assertIsMyClient(providerId, clientId);

    await this.db.query(
      `INSERT INTO provider_client_notes (provider_id, client_user_id, notes)
       VALUES ($1, $2, $3)
       ON CONFLICT (provider_id, client_user_id) DO UPDATE SET notes = EXCLUDED.notes, updated_at = now()`,
      [providerId, clientId, notes],
    );
    return { ok: true };
  }
}

/** Reviews and schedules show a first name only. Full names are not needed. */
function firstNameOnly(fullName: string | null): string {
  if (!fullName) return 'Freshly client';
  const [first] = fullName.trim().split(/\s+/);
  return first ?? 'Freshly client';
}
