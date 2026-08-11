import { BadRequestException, ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { DatabaseService } from '../../common/database/database.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import {
  DomainError, IllegalTransitionError, NotFoundError, RateLimitedError,
} from '../../common/errors/domain.errors';
import { RedisService } from '../../common/redis/redis.service';

/**
 * Five guesses at a four-digit code, then a fifteen-minute cool-off. Enough
 * for a client reading it out over a noisy shop; nowhere near enough to walk
 * ten thousand combinations.
 */
const PIN_MAX_ATTEMPTS = 5;
const PIN_ATTEMPT_WINDOW_SECONDS = 900;
import { MarketsService } from '../markets/markets.service';
import { PricingService, Quote } from '../pricing/pricing.service';
import { EscrowService } from '../payments/escrow.service';
import { DispatchService } from '../dispatch/dispatch.service';
import { CreateBookingDto, QuoteBookingDto } from './dto/bookings.dto';

interface ServiceRow {
  id: string;
  name: string;
  price_minor: string;
  duration_minutes: number;
  currency: string;
  requires_power: boolean;
  provider_id: string;
}

@Injectable()
export class BookingsService {
  private readonly logger = new Logger(BookingsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
    private readonly pricing: PricingService,
    private readonly escrow: EscrowService,
    private readonly dispatch: DispatchService,
    private readonly crypto: PiiCryptoService,
    private readonly redis: RedisService,
  ) {}

  // ─── Quoting ───────────────────────────────────────────────────────────────

  async quote(dto: QuoteBookingDto): Promise<Quote> {
    const { services, provider, area, market, distanceKm } = await this.resolveContext(dto);

    const discountMinor = dto.promoCode
      ? await this.resolvePromo(dto.promoCode, market.code, services)
      : 0;

    return this.pricing.quote({
      market,
      services: services.map((s) => ({
        id: s.id, name: s.name, priceMinor: Number(s.price_minor), durationMinutes: s.duration_minutes,
      })),
      travelDistanceKm: distanceKm,
      venueMode: dto.venueMode ?? 'mobile',
      surgeBps: area.surgeBps,
      discountMinor,
      commissionBpsOverride: provider.commission_bps_override,
    });
  }

  private async resolveContext(dto: QuoteBookingDto) {
    const provider = await this.db.queryOne<{
      id: string; country_code: 'ZA' | 'ZW'; commission_bps_override: number | null;
      base_location: unknown; kyc_status: string; is_suspended: boolean;
    }>(
      `SELECT id, country_code, commission_bps_override, kyc_status, is_suspended
         FROM providers WHERE id = $1`,
      [dto.providerId],
    );
    if (!provider) throw new NotFoundError('Provider', dto.providerId);
    if (provider.is_suspended || provider.kyc_status !== 'verified') {
      throw new DomainError('provider_unavailable', 'This professional is not currently taking bookings');
    }

    const services = await this.db.query<ServiceRow>(
      `SELECT id, name, price_minor, duration_minutes, currency, requires_power, provider_id
         FROM services
        WHERE id = ANY($1::uuid[]) AND provider_id = $2 AND is_active`,
      [dto.serviceIds, dto.providerId],
    );
    if (services.length !== dto.serviceIds.length) {
      throw new NotFoundError('One or more services');
    }

    const area = await this.markets.resolveServiceArea(dto.destination.lat, dto.destination.lng);
    const market = this.markets.get(area.countryCode);

    // Straight-line distance from the provider's base, inflated to approximate
    // a road route. A routing API would be more accurate, but this is on the
    // hot path for every quote and a 30% correction is close enough to price
    // fairly without a per-request external call.
    const row = await this.db.queryOne<{ km: string }>(
      `SELECT ST_Distance(
                COALESCE(last_location, base_location),
                ST_SetSRID(ST_MakePoint($2, $3), 4326)::GEOGRAPHY
              ) / 1000 AS km
         FROM providers WHERE id = $1`,
      [dto.providerId, dto.destination.lng, dto.destination.lat],
    );
    const distanceKm = Math.round(Number(row?.km ?? 0) * 1.3 * 100) / 100;

    return { services, provider, area, market, distanceKm };
  }

  private async resolvePromo(code: string, countryCode: string, services: ServiceRow[]): Promise<number> {
    const promo = await this.db.queryOne<{
      discount_bps: number | null; discount_minor: string | null; max_discount_minor: string | null;
      min_spend_minor: string; max_redemptions: number | null; redemption_count: number;
    }>(
      `SELECT discount_bps, discount_minor, max_discount_minor, min_spend_minor,
              max_redemptions, redemption_count
         FROM promo_codes
        WHERE upper(code) = upper($1) AND is_active
          AND (country_code IS NULL OR country_code = $2::country_code_enum)
          AND valid_from <= now() AND (valid_to IS NULL OR valid_to > now())`,
      [code, countryCode],
    );
    if (!promo) throw new DomainError('promo_invalid', 'That promo code is not valid');
    if (promo.max_redemptions !== null && promo.redemption_count >= promo.max_redemptions) {
      throw new DomainError('promo_exhausted', 'That promo code has been fully redeemed');
    }

    const subtotal = services.reduce((sum, s) => sum + Number(s.price_minor), 0);
    if (subtotal < Number(promo.min_spend_minor)) {
      throw new DomainError('promo_min_spend', 'Your order does not meet the minimum for this code');
    }

    let discount = promo.discount_minor
      ? Number(promo.discount_minor)
      : Math.round((subtotal * (promo.discount_bps ?? 0)) / 10_000);
    if (promo.max_discount_minor) discount = Math.min(discount, Number(promo.max_discount_minor));
    return discount;
  }

  // ─── Creation ──────────────────────────────────────────────────────────────

  async create(clientId: string, dto: CreateBookingDto) {
    if (dto.bookingType === 'scheduled' && !dto.scheduledStart) {
      throw new BadRequestException({
        code: 'slot_required', message: 'Choose a date and time for a scheduled booking',
      });
    }

    const { services, area, market, distanceKm } = await this.resolveContext(dto);
    const quote = await this.quote(dto);

    const durationMinutes = services.reduce((sum, s) => sum + s.duration_minutes, 0);
    const scheduledStart = dto.scheduledStart ? new Date(dto.scheduledStart) : null;
    const scheduledEnd = scheduledStart
      ? new Date(scheduledStart.getTime() + durationMinutes * 60_000)
      : null;

    if (scheduledStart && scheduledStart.getTime() < Date.now() - 60_000) {
      throw new BadRequestException({ code: 'slot_in_past', message: 'Choose a time in the future' });
    }

    if (scheduledStart) {
      const available = await this.db.queryOne<{ ok: boolean }>(
        'SELECT fn_provider_is_available($1, $2, $3) AS ok',
        [dto.providerId, scheduledStart, scheduledEnd],
      );
      if (!available?.ok) {
        throw new DomainError('slot_unavailable', 'That time is no longer available', 409);
      }
    }

    // The PIN is generated once, hashed, and never stored in the clear. The
    // client fetches it over an authenticated call; the provider only ever
    // submits a candidate for comparison.
    const pin = String(randomInt(0, 10_000)).padStart(4, '0');
    const gridStage = 0;

    return this.db.transaction(async (tx) => {
      const booking = await tx.queryOne<{ id: string; reference: string }>(
        `INSERT INTO bookings (
            country_code, service_area_id, client_id, provider_id, booking_type, venue_mode,
            status, scheduled_start, scheduled_end, duration_minutes,
            destination, destination_address, destination_notes, travel_distance_km,
            currency, subtotal_minor, travel_fee_minor, service_fee_minor, discount_minor,
            surge_bps, total_minor, commission_bps, commission_minor, vat_on_fees_minor,
            provider_payout_minor, completion_pin_hash, completion_pin_enc,
            grid_stage_at_booking, power_backup_required, expires_at
         ) VALUES (
            $1::country_code_enum, $2, $3, $4, $5::booking_type_enum, $6::service_venue_enum,
            'draft', $7, $8, $9,
            ST_SetSRID(ST_MakePoint($10, $11), 4326)::GEOGRAPHY, $12, $13, $14,
            $15::currency_code_enum, $16, $17, $18, $19,
            $20, $21, $22, $23, $24,
            $25, $26, $27, $28, $29, now() + INTERVAL '20 minutes'
         ) RETURNING id, reference`,
        [
          area.countryCode, area.serviceAreaId, clientId, dto.providerId, dto.bookingType,
          dto.venueMode ?? 'mobile',
          scheduledStart, scheduledEnd, durationMinutes,
          dto.destination.lng, dto.destination.lat, dto.destinationAddress,
          dto.destinationNotes ?? null, distanceKm,
          quote.currency, quote.subtotalMinor, quote.travelFeeMinor, quote.serviceFeeMinor,
          quote.discountMinor, quote.surgeBps, quote.totalMinor, quote.commissionBps,
          quote.commissionMinor, quote.vatOnFeesMinor, quote.providerPayoutMinor,
          this.crypto.hash(pin), this.crypto.encrypt(pin), gridStage,
          services.some((s) => s.requires_power),
        ],
      );

      for (const service of services) {
        await tx.query(
          `INSERT INTO booking_items (booking_id, service_id, name_snapshot, price_minor, duration_minutes)
           VALUES ($1, $2, $3, $4, $5)`,
          [booking!.id, service.id, service.name, Number(service.price_minor), service.duration_minutes],
        );
      }

      await tx.query(`UPDATE bookings SET status = 'pending_auth' WHERE id = $1`, [booking!.id]);

      return {
        id: booking!.id,
        reference: booking!.reference,
        status: 'pending_auth',
        destinationAddress: dto.destinationAddress,
        total: { minor: quote.totalMinor, currency: quote.currency },
        providerId: dto.providerId,
        providerName: null,
        scheduledStart: scheduledStart?.toISOString() ?? null,
        createdAt: new Date().toISOString(),
      };
    });
  }

  // ─── Checkout ──────────────────────────────────────────────────────────────

  async checkout(clientId: string, bookingId: string, method: string, idempotencyKey: string) {
    const booking = await this.requireOwnedBooking(bookingId, clientId);
    if (booking.status !== 'pending_auth') {
      throw new IllegalTransitionError(booking.status, 'authorized');
    }

    const result = await this.escrow.authorize(bookingId, method, idempotencyKey);

    // Instant bookings go straight to dispatch; scheduled ones are assigned to
    // the chosen provider and wait for their slot.
    if (result.status === 'authorized') {
      if (booking.booking_type === 'instant') {
        await this.dispatch.startDispatch(bookingId);
      } else {
        await this.db.query(
          `UPDATE bookings SET status = 'accepted' WHERE id = $1 AND status = 'authorized'`,
          [bookingId],
        );
      }
    }

    return { status: result.status, redirectUrl: result.redirectUrl, bookingId };
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  async advanceStatus(providerId: string, bookingId: string, to: 'en_route' | 'arrived' | 'in_progress') {
    const booking = await this.db.queryOne<{ status: string; provider_id: string }>(
      'SELECT status, provider_id FROM bookings WHERE id = $1', [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);
    if (booking.provider_id !== providerId) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'This booking is not assigned to you' });
    }

    // in_progress is reachable only through PIN verification. Letting a
    // provider self-declare it would make the completion code decorative.
    if (to === 'in_progress') {
      throw new DomainError('pin_required', 'Enter the client\'s 4-digit code to start the service');
    }

    await this.db.transaction(async (tx) => {
      await tx.query('UPDATE bookings SET status = $2::booking_status_enum WHERE id = $1', [bookingId, to]);
      await tx.emitEvent('booking', bookingId, `booking.${to}`, { providerId });
    });

    return { status: to };
  }

  async verifyPin(providerId: string, bookingId: string, pin: string) {
    const booking = await this.db.queryOne<{
      status: string; provider_id: string; completion_pin_hash: string; pin_verified_at: Date | null;
    }>(
      `SELECT status, provider_id, completion_pin_hash, pin_verified_at
         FROM bookings WHERE id = $1`,
      [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);
    if (booking.provider_id !== providerId) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'This booking is not assigned to you' });
    }

    // Rate limited per booking, before the code is even compared.
    //
    // The PIN is four digits and it is the only thing standing between a
    // provider and the customer's money. Unlimited guesses reduce "the client
    // authorises release" to a formality — ten thousand combinations at the
    // global 120 requests a minute is a little over an hour of trying.
    //
    // Counted in Redis, so if Redis is unavailable this throws and the
    // verification fails closed. For a control of this kind that is the
    // correct direction to fail.
    const attempts = await this.redis.incrementWindow(
      `pin:${bookingId}`,
      PIN_ATTEMPT_WINDOW_SECONDS,
    );
    if (attempts > PIN_MAX_ATTEMPTS) {
      this.logger.warn(
        `pin attempts exhausted on booking ${bookingId} by provider ${providerId}`,
      );
      throw new RateLimitedError(PIN_ATTEMPT_WINDOW_SECONDS);
    }

    if (!this.crypto.verifyHash(pin, booking.completion_pin_hash)) {
      throw new DomainError(
        'pin_invalid',
        `That code does not match. ${PIN_MAX_ATTEMPTS - attempts} attempt(s) left, then ask the client to reopen their app.`,
        400,
      );
    }

    await this.db.transaction(async (tx) => {
      await tx.query(
        `UPDATE bookings SET pin_verified_at = now(), status = 'in_progress' WHERE id = $1`,
        [bookingId],
      );
      await tx.emitEvent('booking', bookingId, 'booking.started', { providerId });
    });

    // Only a correct code clears the counter, so a provider cannot reset their
    // own budget by guessing until one happens to land.
    await this.redis.client.del(`ctr:pin:${bookingId}`);

    return { status: 'in_progress' };
  }

  /** The provider marks the job finished; this is what triggers escrow capture. */
  async complete(providerId: string, bookingId: string) {
    const booking = await this.db.queryOne<{ status: string; provider_id: string }>(
      'SELECT status, provider_id FROM bookings WHERE id = $1', [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);
    if (booking.provider_id !== providerId) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'This booking is not assigned to you' });
    }
    if (booking.status !== 'in_progress') {
      throw new IllegalTransitionError(booking.status, 'completed');
    }

    await this.escrow.capture(bookingId);
    await this.db.transaction(async (tx) => {
      await tx.query(`UPDATE bookings SET status = 'completed' WHERE id = $1`, [bookingId]);
      await tx.emitEvent('booking', bookingId, 'booking.completed', { providerId });
    });

    return { status: 'completed' };
  }

  async cancel(userId: string, bookingId: string, reason: string) {
    const booking = await this.db.queryOne<{
      status: string; client_id: string; provider_id: string | null; country_code: 'ZA' | 'ZW';
      total_minor: string; service_fee_minor: string; scheduled_start: Date | null;
    }>(
      `SELECT status, client_id, provider_id, country_code, total_minor, service_fee_minor, scheduled_start
         FROM bookings WHERE id = $1`,
      [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);

    const isClient = booking.client_id === userId;
    if (!isClient && booking.provider_id !== userId) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'Not permitted' });
    }
    if (['completed', 'cancelled', 'expired'].includes(booking.status)) {
      throw new IllegalTransitionError(booking.status, 'cancelled');
    }

    const market = this.markets.get(booking.country_code);
    const minutesUntilStart = booking.scheduled_start
      ? Math.round((booking.scheduled_start.getTime() - Date.now()) / 60_000)
      : null;

    const outcome = this.pricing.cancellationFee(
      market,
      { totalMinor: Number(booking.total_minor), serviceFeeMinor: Number(booking.service_fee_minor) },
      {
        minutesUntilStart,
        providerEnRoute: ['en_route', 'arrived'].includes(booking.status),
        cancelledBy: isClient ? 'client' : 'provider',
      },
    );

    await this.escrow.captureCancellationFee(bookingId, outcome.feeMinor, outcome.reason);
    await this.dispatch.cancelDispatch(bookingId);

    await this.db.transaction(async (tx) => {
      await tx.query(
        `UPDATE bookings
            SET status = 'cancelled', cancelled_by = $2::cancelled_by_enum,
                cancellation_reason = $3, cancellation_fee_minor = $4
          WHERE id = $1`,
        [bookingId, isClient ? 'client' : 'provider', reason, outcome.feeMinor],
      );
      await tx.emitEvent('booking', bookingId, 'booking.cancelled', {
        cancelledBy: isClient ? 'client' : 'provider', feeMinor: outcome.feeMinor, reason: outcome.reason,
      });
    });

    return { status: 'cancelled', feeMinor: outcome.feeMinor, refundMinor: outcome.refundMinor };
  }

  // ─── Reads ─────────────────────────────────────────────────────────────────

  /**
   * Return the client's own completion code.
   *
   * Only the owning client can reach this, and only while the job is live —
   * there is no reason to hand out a release code for a booking that is
   * finished, and every reason not to.
   */
  async completionPin(clientId: string, bookingId: string): Promise<{ pin: string }> {
    await this.requireOwnedBooking(bookingId, clientId);

    const row = await this.db.queryOne<{ completion_pin_enc: Buffer | null; status: string }>(
      'SELECT completion_pin_enc, status FROM bookings WHERE id = $1',
      [bookingId],
    );
    if (!row?.completion_pin_enc) {
      throw new NotFoundError('Completion code', bookingId);
    }
    if (['completed', 'cancelled', 'expired'].includes(row.status)) {
      throw new DomainError('booking_closed', 'This booking is already closed');
    }

    return { pin: this.crypto.decrypt(row.completion_pin_enc) };
  }

  async findOne(userId: string, bookingId: string) {
    const row = await this.db.queryOne<Record<string, any>>(
      `SELECT b.id, b.reference, b.status, b.booking_type, b.venue_mode, b.scheduled_start,
              b.destination_address, b.total_minor, b.currency, b.provider_id, b.created_at,
              p.display_name AS provider_name,
              ARRAY(SELECT service_id FROM booking_items WHERE booking_id = b.id AND NOT is_addon) AS service_ids
         FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
        WHERE b.id = $1 AND (b.client_id = $2 OR p.user_id = $2)`,
      [bookingId, userId],
    );
    if (!row) throw new NotFoundError('Booking', bookingId);
    return mapBooking(row);
  }

  async listMine(userId: string, status?: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.status, b.booking_type, b.venue_mode, b.scheduled_start,
              b.destination_address, b.total_minor, b.currency, b.provider_id, b.created_at,
              p.display_name AS provider_name
         FROM bookings b
         LEFT JOIN providers p ON p.id = b.provider_id
        WHERE (b.client_id = $1 OR p.user_id = $1)
          AND ($2::text IS NULL OR b.status = $2::booking_status_enum)
        ORDER BY b.created_at DESC
        LIMIT 50`,
      [userId, status ?? null],
    );
    return rows.map(mapBooking);
  }

  async review(userId: string, bookingId: string, rating: number, tags: string[], comment?: string) {
    const booking = await this.db.queryOne<{ client_id: string; provider_id: string | null; status: string }>(
      'SELECT client_id, provider_id, status FROM bookings WHERE id = $1', [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);
    if (booking.status !== 'completed') {
      throw new DomainError('not_reviewable', 'You can review a booking once it is completed');
    }

    const isClient = booking.client_id === userId;
    const subject = await this.db.queryOne<{ user_id: string }>(
      'SELECT user_id FROM providers WHERE id = $1', [booking.provider_id],
    );

    await this.db.query(
      `INSERT INTO reviews (booking_id, direction, author_id, subject_user_id, rating, tags, comment)
       VALUES ($1, $2::review_direction_enum, $3, $4, $5, $6, $7)
       ON CONFLICT (booking_id, direction) DO NOTHING`,
      [
        bookingId,
        isClient ? 'client_to_provider' : 'provider_to_client',
        userId,
        isClient ? subject!.user_id : booking.client_id,
        rating, tags, comment ?? null,
      ],
    );

    // Publish both sides only once both exist. Holding them back is what stops
    // a provider from retaliating against a low rating they can already see.
    await this.db.query(
      `UPDATE reviews SET is_published = true, published_at = now()
        WHERE booking_id = $1
          AND (SELECT COUNT(*) FROM reviews WHERE booking_id = $1) = 2`,
      [bookingId],
    );

    return { ok: true };
  }

  private async requireOwnedBooking(bookingId: string, clientId: string) {
    const booking = await this.db.queryOne<{ id: string; status: string; booking_type: string; client_id: string }>(
      'SELECT id, status, booking_type, client_id FROM bookings WHERE id = $1', [bookingId],
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);
    if (booking.client_id !== clientId) {
      throw new ForbiddenException({ code: 'not_your_booking', message: 'Not permitted' });
    }
    return booking;
  }
}

function mapBooking(r: Record<string, any>) {
  return {
    id: r.id,
    reference: r.reference,
    status: r.status,
    bookingType: r.booking_type,
    venueMode: r.venue_mode,
    scheduledStart: r.scheduled_start?.toISOString() ?? null,
    destinationAddress: r.destination_address,
    total: { minor: Number(r.total_minor), currency: r.currency },
    providerId: r.provider_id,
    providerName: r.provider_name ?? null,
    serviceIds: r.service_ids ?? [],
    createdAt: r.created_at.toISOString(),
  };
}
