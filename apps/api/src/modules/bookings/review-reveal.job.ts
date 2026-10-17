import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DatabaseService } from '../../common/database/database.service';
import { MarketsService } from '../markets/markets.service';

/**
 * Reviews are double-blind: neither side sees the other's until both have
 * written one, so a provider cannot answer a low rating with a lower one.
 * The other half of that rule is a deadline. Without it a client whose
 * provider never rates them would wait forever, and the public profile would
 * show a rating with no words under it. After `review.reveal_window_hours`
 * whatever exists is published.
 */
@Injectable()
export class ReviewRevealJob {
  private readonly logger = new Logger(ReviewRevealJob.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
  ) {}

  @Cron(CronExpression.EVERY_HOUR)
  async publishOverdue(): Promise<number> {
    const hours = this.markets.setting<number>('review.reveal_window_hours', 336);
    try {
      const row = await this.db.queryOne<{ n: number }>(
        'SELECT fn_publish_overdue_reviews($1) AS n',
        [hours],
      );
      const n = Number(row?.n ?? 0);
      if (n > 0) this.logger.log(`published ${n} review(s) past the ${hours}h reveal window`);
      return n;
    } catch (err) {
      this.logger.warn(`review reveal failed: ${(err as Error).message}`);
      return 0;
    }
  }
}
