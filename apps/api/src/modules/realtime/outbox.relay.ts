import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
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
export class OutboxRelay implements OnModuleDestroy {
  private readonly logger = new Logger(OutboxRelay.name);
  private draining = false;
  private stopped = false;

  // The interval keeps firing while Nest tears modules down, and a drain that
  // starts after the pool has closed logs a failed UPDATE on every e2e run.
  // Nothing is lost by stopping early: an unmarked event is retried next boot.
  onModuleDestroy(): void {
    this.stopped = true;
  }

  constructor(
    private readonly db: DatabaseService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Interval(1_000)
  async drain(): Promise<void> {
    if (this.draining || this.stopped) return;
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
            this.publishBookingEvent(event.aggregate_id, event.event_type, event.payload);
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

  /**
   * Only a real state change is a `booking.status` update. Everything that
   * happens to a booking used to be sent that way, so `booking.started`
   * reached the apps as status "started" and `booking.addon_approved` as
   * "addon_approved", neither of which exists; the tracking screen showed
   * "Draft". Those now go out under their own names with their payload.
   */
  private publishBookingEvent(bookingId: string, eventType: string, payload: Record<string, unknown>): void {
    const status = BOOKING_STATUS_EVENTS[eventType];
    if (status) {
      this.realtime.emitToBooking(bookingId, 'booking.status', {
        bookingId,
        status,
        providerLocation: null,
        etaMinutes: null,
        distanceRemainingKm: null,
        updatedAt: new Date().toISOString(),
      });
      return;
    }
    const name = NAMED_BOOKING_EVENTS[eventType] ?? eventType;
    this.realtime.emitToBooking(bookingId, name, { bookingId, ...payload });
  }
}

/** Outbox event types that are a booking status, and the status they carry. */
const BOOKING_STATUS_EVENTS: Record<string, string> = {
  'booking.pending_auth': 'pending_auth',
  'booking.authorized': 'authorized',
  'booking.accepted': 'accepted',
  'booking.en_route': 'en_route',
  'booking.arrived': 'arrived',
  'booking.started': 'in_progress',
  'booking.in_progress': 'in_progress',
  'booking.completed': 'completed',
  'booking.cancelled': 'cancelled',
  'booking.expired': 'expired',
  'booking.disputed': 'disputed',
};

/** Outbox event types the apps listen for under a different name. */
const NAMED_BOOKING_EVENTS: Record<string, string> = {
  'booking.addon_requested': 'addon.requested',
};
