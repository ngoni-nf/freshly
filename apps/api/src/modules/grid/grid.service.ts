import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DatabaseService } from '../../common/database/database.service';
import { MarketsService } from '../markets/markets.service';

export interface GridStatusView {
  countryCode: 'ZA' | 'ZW';
  stage: number;
  source: string;
  effectiveFrom: string;
  effectiveTo: string | null;
  nextWindow: { start: string; end: string } | null;
  forcesPowerFilter: boolean;
}

/**
 * Load-shedding awareness.
 *
 * The upstream feeds are unreliable in exactly the conditions that matter, so
 * status is cached in Postgres and served from there. When the feed is stale
 * we report the last known stage rather than claiming the grid is fine —
 * a false "stage 0" sends a customer into a booking that cannot be fulfilled,
 * which is worse than an out-of-date warning.
 */
@Injectable()
export class GridService {
  private readonly logger = new Logger(GridService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
  ) {}

  async current(countryCode: 'ZA' | 'ZW'): Promise<GridStatusView> {
    const row = await this.db.queryOne<{
      stage: number;
      source: string;
      effective_from: Date;
      effective_to: Date | null;
    }>(
      `SELECT stage, source, effective_from, effective_to
         FROM grid_status
        WHERE country_code = $1
        ORDER BY effective_from DESC
        LIMIT 1`,
      [countryCode],
    );

    const stage = row?.stage ?? 0;
    const autoFilterStage = this.markets.setting<number>('loadshedding.auto_filter_stage', 4);

    const next = await this.db.queryOne<{ lower: Date; upper: Date }>(
      `SELECT lower(period) AS lower, upper(period) AS upper
         FROM grid_outage_windows
        WHERE upper(period) > now()
        ORDER BY lower(period) ASC
        LIMIT 1`,
    );

    return {
      countryCode,
      stage,
      source: row?.source ?? 'unknown',
      effectiveFrom: (row?.effective_from ?? new Date()).toISOString(),
      effectiveTo: row?.effective_to?.toISOString() ?? null,
      nextWindow: next
        ? { start: next.lower.toISOString(), end: next.upper.toISOString() }
        : null,
      forcesPowerFilter: stage >= autoFilterStage,
    };
  }

  /**
   * Poll the upstream grid feed. Runs every fifteen minutes because that is
   * how quickly a stage change actually propagates in practice; polling harder
   * burns the API quota without improving accuracy.
   */
  @Cron(CronExpression.EVERY_30_MINUTES)
  async refreshAll(): Promise<void> {
    for (const market of this.markets.liveMarkets()) {
      try {
        const stage = await this.fetchStage(market.code, market.gridStatusProvider);
        if (stage === null) continue;
        await this.db.query(
          `INSERT INTO grid_status (country_code, stage, source, effective_from)
           VALUES ($1, $2, $3, now())`,
          [market.code, stage, market.gridStatusProvider ?? 'manual'],
        );
      } catch (err) {
        this.logger.warn(`grid refresh failed for ${market.code}: ${(err as Error).message}`);
      }
    }
  }

  /**
   * Adapter seam. EskomSePush for South Africa, a ZESA feed for Zimbabwe.
   * Returning null means "we learned nothing", which deliberately leaves the
   * previous reading in place rather than overwriting it with a guess.
   */
  private async fetchStage(country: string, provider: string | null): Promise<number | null> {
    if (!provider || provider === 'manual') return null;
    this.logger.debug(`grid feed ${provider} for ${country} not configured; retaining last reading`);
    return null;
  }

  /** Admin override, used when a feed is down and ops know the real stage. */
  async setStage(countryCode: 'ZA' | 'ZW', stage: number, actorId: string): Promise<void> {
    await this.db.query(
      `INSERT INTO grid_status (country_code, stage, source, effective_from)
       VALUES ($1, $2, 'manual', now())`,
      [countryCode, stage],
    );
    await this.db.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, after)
       VALUES ($1, 'grid.set_stage', 'grid_status', $2)`,
      [actorId, JSON.stringify({ countryCode, stage })],
    );
  }
}
