import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../common/database/database.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';
import { MarketsService } from '../markets/markets.service';
import { CommsService } from '../comms/comms.service';
import { AuraSosProvider, MockSosProvider, SosProvider } from './providers/sos-provider.interface';

/**
 * The emergency path.
 *
 * Rules that shape every decision in this file:
 *
 *   1. It never throws on the transmit path. An exception here reaches a
 *      person in trouble as a red snackbar. Failures are recorded and the
 *      response degrades to "dial this number", which always works.
 *   2. The alert is written to the database before anything external is
 *      called. If the response provider is down, there must still be a record
 *      that someone pressed the button.
 *   3. The counterparty is notified to nobody and the location is shared with
 *      no one except responders and the user's own emergency contacts.
 */
@Injectable()
export class SafetyService {
  private readonly logger = new Logger(SafetyService.name);
  private readonly provider: SosProvider;

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly markets: MarketsService,
    private readonly comms: CommsService,
  ) {
    const configured = this.config.get<string>('SOS_PROVIDER') ?? 'mock';
    const apiKey = this.config.get<string>('AURA_API_KEY');
    this.provider =
      configured === 'aura' && apiKey
        ? new AuraSosProvider(apiKey, this.config.get<string>('AURA_BASE_URL')!)
        : new MockSosProvider();
    this.logger.log(`sos provider: ${this.provider.name}`);
  }

  private emergencyNumber(countryCode: 'ZA' | 'ZW'): string {
    return this.markets.setting<string>(
      `safety.emergency_number.${countryCode}`,
      countryCode === 'ZA' ? '10111' : '995',
    );
  }

  async trigger(
    userId: string,
    input: {
      bookingId?: string;
      lat: number;
      lng: number;
      accuracyM?: number;
      batteryPct?: number;
    },
  ) {
    const user = await this.db.queryOne<{
      full_name: string | null;
      phone_e164: string;
      country_code: 'ZA' | 'ZW';
    }>('SELECT full_name, phone_e164, country_code FROM users WHERE id = $1', [userId]);
    if (!user) throw new NotFoundError('User', userId);

    const booking = input.bookingId
      ? await this.db.queryOne<{
          reference: string;
          client_id: string;
          provider_id: string | null;
          destination_address: string | null;
        }>(
          'SELECT reference, client_id, provider_id, destination_address FROM bookings WHERE id = $1',
          [input.bookingId],
        )
      : null;

    const actor: 'client' | 'provider' = booking && booking.client_id !== userId ? 'provider' : 'client';

    // Recorded first, and unconditionally. Everything after this is best
    // effort; this row is the one thing that must exist.
    const event = await this.db.queryOne<{ id: string }>(
      `INSERT INTO sos_events
         (booking_id, triggered_by_user_id, actor, status, trigger_location, accuracy_m, battery_pct)
       VALUES ($1, $2, $3::sos_actor_enum, 'armed',
               ST_SetSRID(ST_MakePoint($4, $5), 4326)::GEOGRAPHY, $6, $7)
       RETURNING id`,
      [
        input.bookingId ?? null,
        userId,
        actor,
        input.lng,
        input.lat,
        input.accuracyM ?? null,
        input.batteryPct ?? null,
      ],
    );

    const emergencyNumber = this.emergencyNumber(user.country_code);
    const sosId = event!.id;

    let accepted = false;
    try {
      const result = await this.provider.dispatch({
        sosId,
        countryCode: user.country_code,
        lat: input.lat,
        lng: input.lng,
        accuracyM: input.accuracyM,
        personName: user.full_name ?? 'Freshly user',
        personPhone: user.phone_e164,
        context: booking
          ? `Freshly booking ${booking.reference}, ${actor} raised the alert. Address: ${booking.destination_address ?? 'unknown'}`
          : `Freshly ${actor} raised an alert outside a booking`,
      });
      accepted = result.accepted;

      await this.db.query(
        `UPDATE sos_events
            SET status = $2::sos_status_enum,
                external_provider = $3,
                external_reference = NULLIF($4, ''),
                dispatched_at = CASE WHEN $2 = 'dispatched' THEN now() ELSE NULL END
          WHERE id = $1`,
        [sosId, accepted ? 'dispatched' : 'armed', this.provider.name, result.externalReference],
      );
    } catch (err) {
      this.logger.error(`sos dispatch failed for ${sosId}: ${(err as Error).message}`);
    }

    await this.alertEmergencyContacts(userId, sosId, input.lat, input.lng).catch((err) =>
      this.logger.error(`emergency contact alert failed: ${err.message}`),
    );

    await this.db.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('sos', $1, 'sos.triggered', $2)`,
      [sosId, JSON.stringify({ bookingId: input.bookingId ?? null, actor, dispatched: accepted })],
    );

    return {
      id: sosId,
      status: accepted ? 'dispatched' : 'armed',
      dispatched: accepted,
      emergencyNumber,
      // Said plainly rather than reassuringly. If no response service took
      // this, the person needs to know to dial, not to sit and wait.
      message: accepted
        ? 'Your location has been sent to the response team.'
        : `We logged your alert and told your emergency contacts. Call ${emergencyNumber} now if you are in danger.`,
    };
  }

  private async alertEmergencyContacts(
    userId: string,
    sosId: string,
    lat: number,
    lng: number,
  ): Promise<void> {
    const contacts = await this.db.query<{ name: string; phone_e164: string }>(
      'SELECT name, phone_e164 FROM emergency_contacts WHERE user_id = $1',
      [userId],
    );
    if (!contacts.length) return;

    const user = await this.db.queryOne<{ full_name: string | null }>(
      'SELECT full_name FROM users WHERE id = $1',
      [userId],
    );
    const who = user?.full_name ?? 'Someone you know';
    const mapLink = `https://maps.google.com/?q=${lat},${lng}`;

    await Promise.all(
      contacts.map((c) =>
        this.comms
          .sendSafetyAlert(c.phone_e164, who, mapLink)
          .catch((err) => this.logger.warn(`contact ${c.name} not reached: ${err.message}`)),
      ),
    );
    this.logger.log(`sos ${sosId}: notified ${contacts.length} emergency contacts`);
  }

  /**
   * Cancel an alert that was already transmitted. Only the person who raised
   * it may stand it down — a provider cancelling a client's alarm is exactly
   * the scenario the alarm exists for.
   */
  async abort(sosId: string, userId: string) {
    const event = await this.db.queryOne<{ triggered_by_user_id: string; status: string }>(
      'SELECT triggered_by_user_id, status FROM sos_events WHERE id = $1',
      [sosId],
    );
    if (!event) throw new NotFoundError('SOS event', sosId);
    if (event.triggered_by_user_id !== userId) {
      throw new DomainError(
        'not_your_alert',
        'Only the person who raised this alert can stand it down',
        HttpStatus.FORBIDDEN,
      );
    }
    if (event.status === 'resolved' || event.status === 'aborted') {
      return { status: event.status };
    }

    await this.db.query(
      `UPDATE sos_events SET status = 'aborted', resolved_at = now(), resolution_notes = 'Stood down by the person who raised it'
        WHERE id = $1`,
      [sosId],
    );
    await this.db.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('sos', $1, 'sos.aborted', '{}'::jsonb)`,
      [sosId],
    );

    return { status: 'aborted' };
  }

  async listEmergencyContacts(userId: string) {
    const rows = await this.db.query<{ id: string; name: string; phone_e164: string; relationship: string | null; notify_on_trip: boolean }>(
      'SELECT id, name, phone_e164, relationship, notify_on_trip FROM emergency_contacts WHERE user_id = $1 ORDER BY created_at',
      [userId],
    );
    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      phone: r.phone_e164,
      relationship: r.relationship,
      notifyOnTrip: r.notify_on_trip,
    }));
  }

  async addEmergencyContact(
    userId: string,
    countryCode: 'ZA' | 'ZW',
    input: { name: string; phone: string; relationship?: string; notifyOnTrip?: boolean },
  ) {
    const e164 = this.markets.toE164(input.phone, countryCode);
    const row = await this.db.queryOne<{ id: string }>(
      `INSERT INTO emergency_contacts (user_id, name, phone_e164, relationship, notify_on_trip)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id`,
      [userId, input.name, e164, input.relationship ?? null, input.notifyOnTrip ?? false],
    );
    return { id: row!.id, phone: e164 };
  }

  // ─── Operator board ───────────────────────────────────────────────────────

  /**
   * Everything still open, worst case first.
   *
   * Coordinates rather than a suburb: this is the one place in the system that
   * needs to say exactly where somebody is, and the masking that protects a
   * client's address elsewhere would be actively harmful here. Phone numbers
   * for the same reason — the first thing an operator does is ring them.
   */
  async activeAlerts() {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT s.id, s.status, s.actor, s.created_at, s.dispatched_at, s.acknowledged_at,
              s.accuracy_m, s.battery_pct, s.vehicle_description,
              s.external_provider, s.external_reference,
              ST_Y(s.trigger_location::geometry) AS lat,
              ST_X(s.trigger_location::geometry) AS lng,
              u.full_name, u.phone_e164,
              b.reference AS booking_reference, b.destination_address,
              p.display_name AS counterparty_name
         FROM sos_events s
         JOIN users u ON u.id = s.triggered_by_user_id
         LEFT JOIN bookings b ON b.id = s.booking_id
         LEFT JOIN providers p ON p.id = b.provider_id
        WHERE s.status IN ('armed','dispatched','acknowledged')
        ORDER BY s.created_at ASC`,
    );

    return rows.map((r) => this.toAlert(r));
  }

  async alertHistory() {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT s.id, s.status, s.actor, s.created_at, s.dispatched_at, s.acknowledged_at,
              s.resolved_at, s.resolution_notes, s.accuracy_m, s.battery_pct,
              s.vehicle_description, s.external_provider, s.external_reference,
              ST_Y(s.trigger_location::geometry) AS lat,
              ST_X(s.trigger_location::geometry) AS lng,
              u.full_name, u.phone_e164,
              b.reference AS booking_reference, b.destination_address,
              p.display_name AS counterparty_name
         FROM sos_events s
         JOIN users u ON u.id = s.triggered_by_user_id
         LEFT JOIN bookings b ON b.id = s.booking_id
         LEFT JOIN providers p ON p.id = b.provider_id
        WHERE s.status NOT IN ('armed','dispatched','acknowledged')
        ORDER BY s.created_at DESC
        LIMIT 100`,
    );

    return rows.map((r) => ({
      ...this.toAlert(r),
      resolvedAt: r.resolved_at?.toISOString() ?? null,
      resolutionNotes: r.resolution_notes ?? null,
    }));
  }

  private toAlert(r: Record<string, any>) {
    return {
      id: r.id,
      status: r.status,
      actor: r.actor,
      createdAt: r.created_at.toISOString(),
      dispatchedAt: r.dispatched_at?.toISOString() ?? null,
      acknowledgedAt: r.acknowledged_at?.toISOString() ?? null,
      location: { lat: Number(r.lat), lng: Number(r.lng) },
      accuracyM: r.accuracy_m === null ? null : Number(r.accuracy_m),
      batteryPct: r.battery_pct,
      vehicleDescription: r.vehicle_description,
      externalProvider: r.external_provider,
      externalReference: r.external_reference,
      personName: r.full_name,
      personPhone: r.phone_e164,
      counterpartyName: r.counterparty_name ?? null,
      bookingReference: r.booking_reference ?? null,
      destinationAddress: r.destination_address ?? null,
    };
  }

  /**
   * An operator takes it. Recorded so two people do not both assume the other
   * is handling it, which is the failure mode of every shared alert queue.
   */
  async acknowledge(alertId: string, staffUserId: string) {
    const row = await this.db.queryOne<{ id: string }>(
      `UPDATE sos_events
          SET status = 'acknowledged', acknowledged_at = COALESCE(acknowledged_at, now())
        WHERE id = $1 AND status IN ('armed','dispatched')
        RETURNING id`,
      [alertId],
    );
    if (!row) throw new NotFoundError('Alert', alertId);

    await this.db.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, entity_id, after)
       VALUES ($1, 'sos.acknowledged', 'sos_event', $2, '{"status":"acknowledged"}'::jsonb)`,
      [staffUserId, alertId],
    );
    return { ok: true };
  }

  async resolve(alertId: string, staffUserId: string, notes: string) {
    const row = await this.db.queryOne<{ id: string }>(
      `UPDATE sos_events
          SET status = 'resolved', resolved_at = now(), resolution_notes = $2
        WHERE id = $1 AND status <> 'resolved'
        RETURNING id`,
      [alertId, notes],
    );
    if (!row) throw new NotFoundError('Alert', alertId);

    await this.db.query(
      `INSERT INTO audit_log (actor_id, action, entity_type, entity_id, after)
       VALUES ($1, 'sos.resolved', 'sos_event', $2,
               jsonb_build_object('status', 'resolved', 'notes', $3::text))`,
      [staffUserId, alertId, notes],
    );
    return { ok: true };
  }
}
