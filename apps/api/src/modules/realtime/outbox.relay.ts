import { Injectable, Logger } from '@nestjs/common';
import { Interval } from '@nestjs/schedule';
import { DatabaseService } from '../../common/database/database.service';
import { RealtimeGateway } from './realtime.gateway';

/**
 * Transactional outbox relay.
 *
 * Domain events are written in the same transaction as the state change that
 * produced them, then published from here. That ordering is what makes
 * "the booking was accepted but nobody was told" impossible — the alternative,
 * emitting inside the request, loses the notification whenever the process
 * dies between commit and emit, which is exactly when it matters most.
 */
@Injectable()
export class OutboxRelay {
  private readonly logger = new Logger(OutboxRelay.name);
  private draining = false;

  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Interval(1_000)
  async drain(): Promise<void> {
    if (this.draining) return;
    this.draining = true;
    try {
      const events = await this.db.query<{
        id: string; aggregate_type: string; aggregate_id: string; event_type: string;
        payload: Record<string, unknown>; attempts: number;
      }>(
        `UPDATE outbox_events
            SET attempts = attempts + 1
          WHERE id IN (
            SELECT id FROM outbox_events
             WHERE published_at IS NULL AND available_at <= now()
             ORDER BY id
             LIMIT 50
             FOR UPDATE SKIP LOCKED
          )
          RETURNING id, aggregate_type, aggregate_id, event_type, payload, attempts`,
      );

      for (const event of events) {
        try {
          if (event.aggregate_type === 'booking') {
            this.realtime.emitToBooking(event.aggregate_id, 'booking.status', {
              bookingId: event.aggregate_id,
              status: event.event_type.replace('booking.', ''),
              providerLocation: null,
              etaMinutes: null,
              distanceRemainingKm: null,
              updatedAt: new Date().toISOString(),
            });
          }
          await this.db.query('UPDATE outbox_events SET published_at = now() WHERE id = $1', [event.id]);
        } catch (err) {
          // Exponential backoff, capped. A poisoned event should not spin.
          const delaySeconds = Math.min(300, 2 ** event.attempts);
          await this.db.query(
            `UPDATE outbox_events
                SET last_error = $2, available_at = now() + ($3 || ' seconds')::INTERVAL
              WHERE id = $1`,
            [event.id, (err as Error).message, delaySeconds],
          );
        }
      }
    } catch (err) {
      this.logger.warn(`outbox drain failed: ${(err as Error).message}`);
    } finally {
      this.draining = false;
    }
  }
}
