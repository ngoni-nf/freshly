import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { NotFoundError, OutsideServiceAreaError } from '../../common/errors/domain.errors';

export interface MarketConfig {
  code: 'ZA' | 'ZW';
  name: string;
  defaultCurrency: 'ZAR' | 'USD' | 'ZWG';
  supportedCurrencies: string[];
  dialPrefix: string;
  phoneNationalLength: number;
  timezone: string;
  commissionBps: number;
  serviceFeeMinor: number;
  travelFeePerKmMinor: number;
  travelFeeFreeKm: number;
  vatBps: number;
  vatLabel: string;
  taxAuthority: string | null;
  paymentProvider: string;
  kycProvider: string;
  sosProvider: string | null;
  gridStatusProvider: string | null;
  cancellationWindowMinutes: number;
  cancellationFeeBps: number;
  noShowGraceMinutes: number;
  /** Referral rewards are market data: turning them up must not be a deploy. */
  referralRefereeDiscountMinor: number;
  referralReferrerCreditMinor: number;
  referralCreditTtlDays: number;
  dispatchOfferSeconds: number;
  maxSearchRadiusKm: number;
  isLive: boolean;
}

/**
 * Market configuration is data, not code.
 *
 * Commission, VAT, travel tariffs, dispatch timings and which payment or
 * identity vendor to call are all rows in `countries`. Turning Zimbabwe on is
 * an UPDATE plus an already-written payment adapter — the alternative, country
 * conditionals sprinkled through the booking and payout paths, is how a
 * second market takes six months instead of six weeks.
 */
@Injectable()
export class MarketsService implements OnModuleInit {
  private readonly logger = new Logger(MarketsService.name);
  private cache = new Map<string, MarketConfig>();
  private settings = new Map<string, unknown>();

  constructor(private readonly db: DatabaseService) {}

  async onModuleInit(): Promise<void> {
    await this.refresh().catch((err) =>
      this.logger.warn(`market config not loaded at boot: ${err.message}`),
    );
  }

  async refresh(): Promise<void> {
    const rows = await this.db.query<Record<string, any>>('SELECT * FROM countries');
    this.cache = new Map(rows.map((r) => [r.code, mapMarket(r)]));

    const settings = await this.db.query<{ key: string; value: unknown }>(
      'SELECT key, value FROM platform_settings',
    );
    this.settings = new Map(settings.map((s) => [s.key, s.value]));
    this.logger.log(`loaded ${this.cache.size} markets, ${this.settings.size} settings`);
  }

  get(code: string): MarketConfig {
    const market = this.cache.get(code);
    if (!market) throw new NotFoundError('Market', code);
    return market;
  }

  liveMarkets(): MarketConfig[] {
    return [...this.cache.values()].filter((m) => m.isLive);
  }

  setting<T>(key: string, fallback: T): T {
    const value = this.settings.get(key);
    return value === undefined ? fallback : (value as T);
  }

  /**
   * The areas a new client can pick from at sign-up.
   *
   * Returns the centroid, because that is what discovery falls back to when
   * there is no usable GPS fix. Public: someone deciding whether to sign up is
   * entitled to know whether Freshly covers them before handing over a phone
   * number.
   */
  async liveServiceAreas(): Promise<
    Array<{ id: string; slug: string; name: string; countryCode: 'ZA' | 'ZW'; lat: number; lng: number }>
  > {
    const rows = await this.db.query<{
      id: string;
      slug: string;
      name: string;
      country_code: 'ZA' | 'ZW';
      lat: string;
      lng: string;
    }>(
      `SELECT id, slug, name, country_code,
              ST_Y(centroid::geometry) AS lat,
              ST_X(centroid::geometry) AS lng
         FROM service_areas
        WHERE is_live
        ORDER BY country_code, name`,
    );

    return rows.map((r) => ({
      id: r.id,
      slug: r.slug,
      name: r.name,
      countryCode: r.country_code,
      lat: Number(r.lat),
      lng: Number(r.lng),
    }));
  }

  /**
   * Suburb autocomplete.
   *
   * Only ever suggests somewhere we operate, because every place belongs to a
   * live area by construction. A suggestion we cannot serve is worse than no
   * suggestion — the customer discovers the refusal after choosing instead of
   * before, having already told us where they live.
   *
   * An empty query returns the busiest suburbs rather than nothing, so the
   * field is useful before the first keystroke.
   */
  async searchPlaces(
    query: string | undefined,
    limit = 8,
  ): Promise<
    Array<{
      id: string;
      name: string;
      postalCode: string | null;
      serviceAreaId: string;
      serviceAreaName: string;
      countryCode: 'ZA' | 'ZW';
      lat: number;
      lng: number;
    }>
  > {
    const term = (query ?? '').trim().toLowerCase();

    const rows = await this.db.query<{
      id: string;
      name: string;
      postal_code: string | null;
      service_area_id: string;
      area_name: string;
      country_code: 'ZA' | 'ZW';
      lat: string;
      lng: string;
    }>(
      // LIKE against the lowered name so the prefix index is usable. The
      // parameter is escaped for LIKE metacharacters below rather than
      // interpolated, so a name containing % cannot widen the search.
      `SELECT p.id, p.name, p.postal_code, p.service_area_id,
              a.name AS area_name, a.country_code,
              ST_Y(p.centroid::geometry) AS lat,
              ST_X(p.centroid::geometry) AS lng
         FROM places p
         JOIN service_areas a ON a.id = p.service_area_id
        WHERE p.is_active
          AND a.is_live
          AND ($1 = '' OR lower(p.name) LIKE $1 || '%')
        ORDER BY
          -- An exact match first, then the busiest. Someone who has typed
          -- "sandton" in full does not want Sandton Ext 4 above Sandton.
          (lower(p.name) = $1) DESC,
          p.popularity DESC,
          p.name ASC
        LIMIT $2`,
      [term.replace(/[%_\\]/g, '\\$&'), Math.min(limit, 25)],
    );

    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      postalCode: r.postal_code,
      serviceAreaId: r.service_area_id,
      serviceAreaName: r.area_name,
      countryCode: r.country_code,
      lat: Number(r.lat),
      lng: Number(r.lng),
    }));
  }

  /**
   * Resolve which country a coordinate belongs to, and refuse anything outside
   * a live service area. The pilot is geofenced deliberately: supply density
   * inside 10km beats thin coverage across a province.
   */
  async resolveServiceArea(
    lat: number,
    lng: number,
  ): Promise<{ serviceAreaId: string; countryCode: 'ZA' | 'ZW'; surgeBps: number }> {
    const row = await this.db.queryOne<{ id: string; country_code: 'ZA' | 'ZW'; surge_bps: number }>(
      `SELECT id, country_code, surge_bps
         FROM service_areas
        WHERE is_live
          AND ST_Covers(boundary, ST_SetSRID(ST_MakePoint($1, $2), 4326)::GEOGRAPHY)
        LIMIT 1`,
      [lng, lat],
    );
    if (!row) throw new OutsideServiceAreaError();
    return { serviceAreaId: row.id, countryCode: row.country_code, surgeBps: row.surge_bps };
  }

  /** Normalise a local number to E.164 for the given market. */
  toE164(input: string, countryCode: 'ZA' | 'ZW'): string {
    const market = this.get(countryCode);
    const digits = input.replace(/[^\d+]/g, '');

    if (digits.startsWith(market.dialPrefix)) {
      return digits;
    }
    const national = digits.replace(/^\+/, '').replace(/^0+/, '');
    if (national.length !== market.phoneNationalLength) {
      throw new NotFoundError(
        `A ${market.name} number must be ${market.phoneNationalLength} digits after the leading zero`,
      );
    }
    return `${market.dialPrefix}${national}`;
  }
}

function mapMarket(r: Record<string, any>): MarketConfig {
  return {
    code: r.code,
    name: r.name,
    defaultCurrency: r.default_currency,
    supportedCurrencies: r.supported_currencies,
    dialPrefix: r.dial_prefix,
    phoneNationalLength: r.phone_national_length,
    timezone: r.timezone,
    commissionBps: r.commission_bps,
    serviceFeeMinor: Number(r.service_fee_minor),
    travelFeePerKmMinor: Number(r.travel_fee_per_km_minor),
    travelFeeFreeKm: Number(r.travel_fee_free_km),
    vatBps: r.vat_bps,
    vatLabel: r.vat_label,
    taxAuthority: r.tax_authority,
    paymentProvider: r.payment_provider,
    kycProvider: r.kyc_provider,
    sosProvider: r.sos_provider,
    gridStatusProvider: r.grid_status_provider,
    cancellationWindowMinutes: r.cancellation_window_minutes,
    cancellationFeeBps: r.cancellation_fee_bps,
    noShowGraceMinutes: r.no_show_grace_minutes,
    referralRefereeDiscountMinor: Number(r.referral_referee_discount_minor ?? 0),
    referralReferrerCreditMinor: Number(r.referral_referrer_credit_minor ?? 0),
    referralCreditTtlDays: Number(r.referral_credit_ttl_days ?? 90),
    dispatchOfferSeconds: r.dispatch_offer_seconds,
    maxSearchRadiusKm: Number(r.max_search_radius_km),
    isLive: r.is_live,
  };
}
