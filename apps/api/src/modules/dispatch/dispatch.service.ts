import { Injectable, Logger, forwardRef, Inject } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../../common/database/database.service';
import { RedisService } from '../../common/redis/redis.service';
import { MarketsService } from '../markets/markets.service';
import { DispatchRaceLostError, NotFoundError } from '../../common/errors/domain.errors';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { PushService } from '../notifications/push.service';
import { estimateEta } from '../discovery/discovery.service';
import { formatMoney } from '../../common/money/money';

interface Candidate {
  provider_id: string;
  distance_km: string;
  rating: string;
}

/**
 * Dispatch.
 *
 * Offers go out in expanding waves rather than to everyone at once. Blasting
 * every provider in a 15km radius gets the job accepted fastest but trains
 * people to ignore notifications for trips they would never take, and it sends
 * a customer a barber from three suburbs away when there is one on their
 * street. Each wave widens the radius only after the closer providers have had
 * a genuine chance to respond.
 */
@Injectable()
export class DispatchService {
  private readonly logger = new Logger(DispatchService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly redis: RedisService,
    private readonly markets: MarketsService,
    @Inject(forwardRef(() => RealtimeGateway))
    private readonly realtime: RealtimeGateway,
    private readonly push: PushService,
  ) {}

  async startDispatch(bookingId: string): Promise<void> {
    await this.runWave(bookingId, 1);
  }

  private async runWave(bookingId: string, wave: number): Promise<void> {
    const booking = await this.db.queryOne<{
      id: string; reference: string; country_code: 'ZA' | 'ZW'; status: string;
      provider_payout_minor: string; currency: string; destination_address: string;
      power_backup_required: boolean; scheduled_start: Date | null;
      dest_lng: string; dest_lat: string; categories: string[];
      service_names: string[]; duration_minutes: number;
    }>(
      `SELECT b.id, b.reference, b.country_code, b.status, b.provider_payout_minor, b.currency,
              b.destination_address, b.power_backup_required, b.scheduled_start,
              ST_X(b.destination::geometry) AS dest_lng,
              ST_Y(b.destination::geometry) AS dest_lat,
              -- What was actually booked. Dispatch used to ignore this
              -- entirely, so a nail technician could be offered a barber job:
              -- they would accept, arrive, and be unable to do the work.
              COALESCE(
                (SELECT array_agg(DISTINCT s.category)
                   FROM booking_items bi
                   JOIN services s ON s.id = bi.service_id
                  WHERE bi.booking_id = b.id),
                ARRAY[]::service_category_enum[]
              ) AS categories,
              -- What the provider is actually being asked to do, and for how
              -- long. Payout and distance alone cannot answer "is this worth
              -- the drive": R78 for a twenty-minute line-up and R78 for a
              -- two-hour job are completely different propositions, and the
              -- name is the only thing that distinguishes them. name_snapshot
              -- rather than the live service row, so the offer says what was
              -- ordered even if the provider renames it later.
              COALESCE(
                (SELECT array_agg(bi.name_snapshot ORDER BY bi.name_snapshot)
                   FROM booking_items bi
                  WHERE bi.booking_id = b.id AND NOT bi.is_addon),
                ARRAY[]::text[]
              ) AS service_names,
              COALESCE(
                (SELECT SUM(bi.duration_minutes * bi.quantity)::int
                   FROM booking_items bi
                  WHERE bi.booking_id = b.id AND NOT bi.is_addon),
                0
              ) AS duration_minutes
         FROM bookings b WHERE b.id = $1`,
      [bookingId],
    );
    if (!booking || booking.status !== 'authorized') return;

    const radii = this.markets.setting<number[]>('dispatch.wave_radii_km', [3, 6, 10, 15]);
    const maxWaves = this.markets.setting<number>('dispatch.max_waves', radii.length);

    if (wave > maxWaves) {
      await this.expire(bookingId);
      return;
    }

    const market = this.markets.get(booking.country_code);
    const offerSeconds = market.dispatchOfferSeconds;
    const radiusKm = radii[Math.min(wave - 1, radii.length - 1)];

    // The destination is passed as coordinates rather than joined out of
    // bookings. Joining it made the planner consider the GIST index on
    // bookings.destination, and PostGIS's index support function then failed
    // outright with "no spatial operator found for 'st_dwithin'" — the
    // gist_geography_ops opfamily on this build is missing the member it looks
    // for. Dispatch is the wrong place to depend on that: we already have the
    // booking loaded, so there was never a reason to join back to it.
    const candidates = await this.db.query<Candidate>(
      `WITH target AS (
         SELECT ST_SetSRID(ST_MakePoint($2, $3), 4326)::GEOGRAPHY AS destination
       )
       SELECT p.id AS provider_id,
              ROUND((ST_Distance(COALESCE(p.last_location, p.base_location), t.destination) / 1000)::NUMERIC, 2) AS distance_km,
              p.rating
         FROM providers p
         CROSS JOIN target t
        WHERE p.is_online
          AND p.accepts_instant
          AND p.kyc_status = 'verified'
          AND NOT p.is_suspended
          AND ST_DWithin(COALESCE(p.last_location, p.base_location), t.destination, $4 * 1000)
          AND ($5 = false OR p.has_power_backup)
          -- Only offer the job to someone who does this kind of work. An empty
          -- array means we could not determine the category, and a booking
          -- nobody can be offered is worse than a slightly wide net.
          AND (cardinality($6::service_category_enum[]) = 0
               OR p.categories && $6::service_category_enum[])
          AND NOT EXISTS (
                SELECT 1 FROM dispatch_offers o
                 WHERE o.booking_id = $1 AND o.provider_id = p.id
              )
        ORDER BY p.rating DESC, ST_Distance(COALESCE(p.last_location, p.base_location), t.destination) ASC
        LIMIT 8`,
      [
        bookingId,
        Number(booking.dest_lng),
        Number(booking.dest_lat),
        radiusKm,
        booking.power_backup_required,
        booking.categories,
      ],
    );

    if (candidates.length === 0) {
      this.logger.log(`booking ${booking.reference} wave ${wave}: no candidates within ${radiusKm}km`);
      setTimeout(() => void this.runWave(bookingId, wave + 1), 2_000).unref();
      return;
    }

    const expiresAt = new Date(Date.now() + offerSeconds * 1_000);
    const payoutMinor = Number(booking.provider_payout_minor);

    for (const candidate of candidates) {
      const distanceKm = Number(candidate.distance_km);
      const etaMinutes = estimateEta(distanceKm);

      const offer = await this.db.queryOne<{ id: string }>(
        `INSERT INTO dispatch_offers
           (booking_id, provider_id, wave, distance_km, eta_minutes, payout_minor, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (booking_id, provider_id, wave) DO NOTHING
         RETURNING id`,
        [bookingId, candidate.provider_id, wave, distanceKm, etaMinutes, payoutMinor, expiresAt],
      );
      if (!offer) continue;

      this.realtime.emitToProvider(candidate.provider_id, 'dispatch.offer', {
        offerId: offer.id,
        bookingId,
        reference: booking.reference,
        serviceNames: booking.service_names ?? [],
        durationMinutes: booking.duration_minutes ?? 0,
        distanceKm,
        etaMinutes,
        payout: { minor: payoutMinor, currency: booking.currency },
        destinationAddress: maskAddress(booking.destination_address),
        scheduledStart: booking.scheduled_start?.toISOString() ?? null,
        expiresAt: expiresAt.toISOString(),
        clientRating: 5,
      });

      // The socket only reaches a foregrounded app, so without this the offer
      // is invisible to anyone whose phone is in their pocket. Deliberately
      // says nothing about who or where the client is: this lands on a lock
      // screen, and providers see the suburb only once they have accepted.
      // The job first, then the money. "Beard line-up · R78.25 · 4.1km" answers
      // "is this worth getting up for" from the lock screen; the amount alone
      // does not, because it means nothing without knowing the work behind it.
      const jobLabel = booking.service_names?.length
        ? booking.service_names.join(', ')
        : 'New job';
      void this.push.sendToProvider(candidate.provider_id, {
        title: `${jobLabel} nearby`,
        body: `${formatMoney(payoutMinor, booking.currency)} — ${distanceKm.toFixed(1)}km away, about ${etaMinutes} min`,
        data: { type: 'dispatch.offer', offerId: offer.id, bookingId },
        ttlSeconds: offerSeconds,
        urgent: true,
        channelId: 'freshly_dispatch',
      });
    }

    this.logger.log(
      `booking ${booking.reference} wave ${wave}: offered to ${candidates.length} providers within ${radiusKm}km`,
    );

    // Escalate once this wave has genuinely lapsed.
    setTimeout(() => void this.onWaveExpired(bookingId, wave), (offerSeconds + 2) * 1_000).unref();
  }

  private async onWaveExpired(bookingId: string, wave: number): Promise<void> {
    const booking = await this.db.queryOne<{ status: string }>(
      'SELECT status FROM bookings WHERE id = $1', [bookingId],
    );
    if (!booking || booking.status !== 'authorized') return;

    await this.db.query(
      `UPDATE dispatch_offers SET outcome = 'expired'
        WHERE booking_id = $1 AND wave = $2 AND outcome IS NULL`,
      [bookingId, wave],
    );
    await this.runWave(bookingId, wave + 1);
  }

  /**
   * Accept an offer.
   *
   * Two providers tapping accept in the same second is not hypothetical — it
   * is the normal case for a good job. A Redis lock decides the winner before
   * either transaction reaches the database, so the loser gets a clean
   * "someone else took it" instead of a constraint violation.
   */
  async respond(
    providerId: string,
    offerId: string,
    accept: boolean,
    reason?: string,
  ): Promise<{ bookingId: string; accepted: boolean }> {
    const offer = await this.db.queryOne<{
      id: string; booking_id: string; provider_id: string; expires_at: Date; outcome: string | null;
    }>(
      'SELECT id, booking_id, provider_id, expires_at, outcome FROM dispatch_offers WHERE id = $1',
      [offerId],
    );
    if (!offer) throw new NotFoundError('Offer', offerId);
    if (offer.provider_id !== providerId) throw new NotFoundError('Offer', offerId);

    if (!accept) {
      await this.db.query(
        `UPDATE dispatch_offers SET outcome = 'declined', responded_at = now(), decline_reason = $2
          WHERE id = $1 AND outcome IS NULL`,
        [offerId, reason ?? null],
      );
      return { bookingId: offer.booking_id, accepted: false };
    }

    if (offer.outcome !== null || offer.expires_at.getTime() < Date.now()) {
      throw new DispatchRaceLostError();
    }

    const holder = randomUUID();
    const won = await this.redis.acquireLock(`dispatch:${offer.booking_id}`, holder, 30);
    if (!won) throw new DispatchRaceLostError();

    try {
      return await this.db.transaction(async (tx) => {
        const booking = await tx.queryOne<{ status: string }>(
          'SELECT status FROM bookings WHERE id = $1 FOR UPDATE', [offer.booking_id],
        );
        if (!booking || booking.status !== 'authorized') throw new DispatchRaceLostError();

        await tx.query(
          `UPDATE bookings SET provider_id = $2, status = 'accepted' WHERE id = $1`,
          [offer.booking_id, providerId],
        );
        await tx.query(
          `UPDATE dispatch_offers SET outcome = 'accepted', responded_at = now() WHERE id = $1`,
          [offerId],
        );
        await tx.query(
          `UPDATE dispatch_offers SET outcome = 'superseded'
            WHERE booking_id = $1 AND id <> $2 AND outcome IS NULL`,
          [offer.booking_id, offerId],
        );
        await tx.emitEvent('booking', offer.booking_id, 'booking.accepted', { providerId });

        return { bookingId: offer.booking_id, accepted: true };
      });
    } finally {
      await this.redis.releaseLock(`dispatch:${offer.booking_id}`, holder);
    }
  }

  async cancelDispatch(bookingId: string): Promise<void> {
    const open = await this.db.query<{ provider_id: string; id: string }>(
      `UPDATE dispatch_offers SET outcome = 'superseded'
        WHERE booking_id = $1 AND outcome IS NULL
        RETURNING id, provider_id`,
      [bookingId],
    );
    for (const offer of open) {
      this.realtime.emitToProvider(offer.provider_id, 'dispatch.revoked', { offerId: offer.id });
    }
  }

  private async expire(bookingId: string): Promise<void> {
    await this.cancelDispatch(bookingId);
    await this.db.transaction(async (tx) => {
      await tx.query(`UPDATE bookings SET status = 'expired' WHERE id = $1 AND status = 'authorized'`, [bookingId]);
      await tx.emitEvent('booking', bookingId, 'booking.expired', {});
    });
    this.logger.warn(`booking ${bookingId} expired with no provider`);
  }
}

/**
 * Providers see the suburb, not the street, until they accept. The exact
 * address is part of what the client is trusting us with, and there is no
 * reason to hand it to eight people who did not take the job.
 */
function maskAddress(address: string): string {
  const parts = address.split(',').map((p) => p.trim()).filter(Boolean);
  return parts.length > 1 ? parts.slice(1).join(', ') : address;
}
