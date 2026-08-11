import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { MarketsService } from '../markets/markets.service';
import { GridService } from '../grid/grid.service';
import { SearchProvidersDto } from './discovery.controller';

export interface ProviderSearchResult {
  providerId: string;
  displayName: string;
  avatarUrl: string | null;
  distanceKm: number;
  rating: number;
  ratingCount: number;
  completedJobs: number;
  hasPowerBackup: boolean;
  isOnline: boolean;
  fromPrice: { minor: number; currency: string };
  categories: string[];
  venueMode: 'mobile' | 'in_shop' | 'both';
  businessMode: 'solo' | 'salon' | 'salon_staff';
  /** Null unless this provider actually receives clients somewhere. */
  shopAddress: string | null;
  etaMinutes: number | null;
}

/** Rough urban average once traffic, gates and parking are accounted for. */
const CITY_SPEED_KPH = 22;

@Injectable()
export class DiscoveryService {
  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
    private readonly grid: GridService,
  ) {}

  async searchProviders(query: SearchProvidersDto): Promise<ProviderSearchResult[]> {
    // Resolving the area does two things: it rejects coordinates outside a
    // live metro before we spend a spatial query on them, and it tells us
    // which country's rules apply to everything downstream.
    const area = await this.markets.resolveServiceArea(query.lat, query.lng);
    const market = this.markets.get(area.countryCode);
    const gridStatus = await this.grid.current(area.countryCode);

    const radiusKm = Math.min(query.radiusKm ?? 10, market.maxSearchRadiusKm);
    const requirePower = Boolean(query.requirePowerBackup) || gridStatus.forcesPowerFilter;

    const rows = await this.db.query<{
      provider_id: string;
      display_name: string;
      distance_km: string;
      rating: string;
      rating_count: number;
      completed_jobs: number;
      has_power_backup: boolean;
      is_online: boolean;
      from_price_minor: string;
      currency: string;
      categories: string[];
      venue_mode: 'mobile' | 'in_shop' | 'both';
      business_mode: 'solo' | 'salon' | 'salon_staff';
      shop_address: string | null;
    }>(
      `SELECT * FROM fn_search_providers($1, $2, $3, $4::service_category_enum, $5::service_venue_enum,
                                          $6, $7, $8, $9, $10, $11)`,
      [
        query.lat,
        query.lng,
        radiusKm,
        query.category ?? null,
        query.venue ?? null,
        query.maxPriceMinor ?? null,
        query.minRating ?? 0,
        requirePower,
        Boolean(query.instantOnly),
        query.limit ?? 20,
        query.offset ?? 0,
      ],
    );

    return rows.map((r) => {
      const distanceKm = Number(r.distance_km);
      return {
        providerId: r.provider_id,
        displayName: r.display_name,
        avatarUrl: null,
        distanceKm,
        rating: Number(r.rating),
        ratingCount: r.rating_count,
        completedJobs: r.completed_jobs,
        hasPowerBackup: r.has_power_backup,
        isOnline: r.is_online,
        fromPrice: { minor: Number(r.from_price_minor), currency: r.currency },
        categories: r.categories ?? [],
        venueMode: r.venue_mode,
        // A salon is a place you go to and a solo provider is a person who
        // comes to you. The app cannot present the choice sensibly without
        // being told which it is looking at.
        businessMode: r.business_mode,
        shopAddress: r.shop_address,
        // Only quote an ETA for someone who could actually leave now, and only
        // for work they would travel to do — an ETA against a salon address
        // reads as "they are coming to you", which is the opposite of the truth.
        etaMinutes: r.is_online && r.venue_mode !== 'in_shop' ? estimateEta(distanceKm) : null,
      };
    });
  }
}

export function estimateEta(distanceKm: number): number {
  const travelMinutes = (distanceKm / CITY_SPEED_KPH) * 60;
  // Five minutes of preparation: packing a kit and getting to the car is not
  // free, and an ETA that ignores it is wrong on every single short trip.
  return Math.max(3, Math.round(travelMinutes + 5));
}
