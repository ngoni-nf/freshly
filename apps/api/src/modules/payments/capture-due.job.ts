import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { DatabaseService } from '../../common/database/database.service';
import { MarketsService } from '../markets/markets.service';
import { EscrowService } from './escrow.service';

/**
 * Captures completed bookings once `escrow.capture_delay_minutes` has passed.
 *
 * With the delay at zero this never finds anything: BookingsService.complete
 * captures immediately. With a delay, the window is the client's chance to
 * open a dispute before money moves, so a booking with an open dispute is
 * skipped and picked up again when the dispute is resolved (resolution
 * captures or refunds explicitly).
 */
@Injectable()
export class CaptureDueJob {
  private readonly logger = new Logger(CaptureDueJob.name);
  private running = false;

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
    private readonly escrow: EscrowService,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async run(): Promise<number> {
    if (this.running) return 0;
    this.running = true;
    try {
      const delayMinutes = this.markets.setting<number>('escrow.capture_delay_minutes', 0);
      if (delayMinutes <= 0) return 0;

      const due = await this.db.query<{ id: string }>(
        `SELECT b.id FROM bookings b
          WHERE b.status = 'completed'
            AND b.completed_at <= now() - make_interval(mins => $1)
            AND EXISTS (SELECT 1 FROM payment_intents pi
                         WHERE pi.booking_id = b.id AND pi.escrow_status = 'authorized')
            AND NOT EXISTS (SELECT 1 FROM disputes d
                             WHERE d.booking_id = b.id
                               AND d.status IN ('open','awaiting_evidence','under_review'))
          ORDER BY b.completed_at
          LIMIT 50`,
        [delayMinutes],
      );

      let captured = 0;
      for (const row of due) {
        try {
          await this.escrow.capture(row.id);
          captured += 1;
        } catch (err) {
          // One bad capture must not stop the rest; it is retried next minute.
          this.logger.warn(`capture of ${row.id} failed: ${(err as Error).message}`);
        }
      }
      if (captured > 0) this.logger.log(`captured ${captured} booking(s) past the ${delayMinutes}-minute window`);
      return captured;
    } finally {
      this.running = false;
    }
  }
}
