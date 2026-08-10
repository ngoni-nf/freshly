import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { DatabaseService, TransactionContext } from '../../common/database/database.service';
import { PaymentError } from '../../common/errors/domain.errors';
import { PaymentGateway } from './gateways/gateway.interface';
import { MockGateway } from './gateways/mock.gateway';
import { PaynowGateway } from './gateways/paynow.gateway';
import { MarketsService } from '../markets/markets.service';

interface BookingMoney {
  id: string;
  currency: string;
  total_minor: string;
  commission_minor: string;
  service_fee_minor: string;
  provider_payout_minor: string;
  vat_on_fees_minor: string;
  travel_fee_minor: string;
  provider_id: string | null;
  client_id: string;
}

/**
 * Escrow and the double-entry ledger.
 *
 * Every movement of money writes balanced ledger entries inside the same
 * transaction as the state change it represents. Reconciliation then reduces
 * to one query — sum the signed amounts per group and expect zero — instead of
 * a spreadsheet and a bad afternoon.
 */
@Injectable()
export class EscrowService {
  private readonly logger = new Logger(EscrowService.name);
  private readonly gateways = new Map<string, PaymentGateway>();

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly markets: MarketsService,
  ) {
    this.gateways.set('mock', new MockGateway());
    const paynowId = this.config.get<string>('PAYNOW_INTEGRATION_ID');
    const paynowKey = this.config.get<string>('PAYNOW_INTEGRATION_KEY');
    if (paynowId && paynowKey) {
      this.gateways.set('paynow', new PaynowGateway(paynowId, paynowKey));
    }
  }

  private gatewayFor(countryCode: 'ZA' | 'ZW'): PaymentGateway {
    const configured =
      countryCode === 'ZA'
        ? this.config.get<string>('PAYMENTS_ZA_PROVIDER')
        : this.config.get<string>('PAYMENTS_ZW_PROVIDER');

    const gateway = this.gateways.get(configured ?? 'mock') ?? this.gateways.get('mock')!;
    if (!gateway.supportsSeparateCapture) {
      // Loud, because the entire customer-protection promise depends on it.
      this.logger.warn(
        `gateway ${gateway.name} cannot hold an authorisation; escrow for ${countryCode} relies on trust-account settlement`,
      );
    }
    return gateway;
  }

  /**
   * Hold the money. Nothing is taken from the customer here; the funds are
   * reserved against their instrument and released automatically if no
   * provider ever accepts.
   */
  async authorize(
    bookingId: string,
    method: string,
    idempotencyKey: string,
  ): Promise<{ status: string; redirectUrl?: string; gatewayReference: string }> {
    const booking = await this.db.queryOne<BookingMoney & { country_code: 'ZA' | 'ZW'; reference: string }>(
      `SELECT id, reference, country_code, currency, total_minor, commission_minor,
              service_fee_minor, provider_payout_minor, vat_on_fees_minor, travel_fee_minor,
              provider_id, client_id
         FROM bookings WHERE id = $1`,
      [bookingId],
    );
    if (!booking) throw new PaymentError('Booking not found');

    const gateway = this.gatewayFor(booking.country_code);
    const result = await gateway.authorize({
      bookingId,
      amountMinor: Number(booking.total_minor),
      currency: booking.currency,
      method,
      customerReference: booking.reference,
      idempotencyKey,
    });

    if (result.status === 'failed') {
      await this.db.query(
        `INSERT INTO payment_intents
           (booking_id, provider_name, method, gateway_reference, escrow_status, currency,
            authorized_minor, idempotency_key, failure_code, failure_message, gateway_payload)
         VALUES ($1,$2,$3::payment_method_enum,$4,'failed',$5::currency_code_enum,0,$6,$7,$8,$9)`,
        [
          bookingId, gateway.name, method, result.gatewayReference, booking.currency,
          idempotencyKey, result.failureCode ?? null, result.failureMessage ?? null,
          JSON.stringify(result.raw ?? {}),
        ],
      );
      throw new PaymentError(result.failureMessage ?? 'Your payment was declined', {
        code: result.failureCode,
      });
    }

    await this.db.transaction(async (tx) => {
      await tx.query(
        `INSERT INTO payment_intents
           (booking_id, provider_name, method, gateway_reference, escrow_status, currency,
            authorized_minor, authorization_expires_at, idempotency_key, gateway_payload)
         VALUES ($1,$2,$3::payment_method_enum,$4,$5::escrow_status_enum,$6::currency_code_enum,$7,$8,$9,$10)`,
        [
          bookingId, gateway.name, method, result.gatewayReference,
          result.status === 'authorized' ? 'authorized' : 'authorizing',
          booking.currency, Number(booking.total_minor),
          result.authorizationExpiresAt ?? null, idempotencyKey,
          JSON.stringify(result.raw ?? {}),
        ],
      );

      if (result.status === 'authorized') {
        const group = randomUUID();
        // The customer's instrument is debited into escrow. Nothing is
        // recognised as revenue yet — that only happens on capture.
        await this.writeEntries(tx, group, booking.currency, bookingId, [
          { account: 'client_source', direction: 'debit', amountMinor: Number(booking.total_minor), description: 'Funds held at checkout' },
          { account: 'escrow', direction: 'credit', amountMinor: Number(booking.total_minor), description: 'Escrow hold' },
        ]);

        await tx.query(
          `UPDATE bookings SET status = 'authorized' WHERE id = $1 AND status = 'pending_auth'`,
          [bookingId],
        );
        await tx.emitEvent('booking', bookingId, 'booking.authorized', {
          totalMinor: Number(booking.total_minor),
          currency: booking.currency,
        });
      }
    });

    return {
      status: result.status,
      redirectUrl: result.redirectUrl,
      gatewayReference: result.gatewayReference,
    };
  }

  /**
   * Take the money and split it. Called only after the client's PIN has been
   * verified, so the customer is the one who authorises release.
   */
  async capture(bookingId: string): Promise<{ capturedMinor: number }> {
    return this.db.transaction(async (tx) => {
      const booking = await tx.queryOne<BookingMoney & { country_code: 'ZA' | 'ZW' }>(
        `SELECT id, country_code, currency, total_minor, commission_minor, service_fee_minor,
                provider_payout_minor, vat_on_fees_minor, travel_fee_minor, provider_id, client_id
           FROM bookings WHERE id = $1 FOR UPDATE`,
        [bookingId],
      );
      if (!booking) throw new PaymentError('Booking not found');

      const intent = await tx.queryOne<{ id: string; gateway_reference: string; escrow_status: string; authorized_minor: string }>(
        `SELECT id, gateway_reference, escrow_status, authorized_minor
           FROM payment_intents WHERE booking_id = $1 FOR UPDATE`,
        [bookingId],
      );
      if (!intent) throw new PaymentError('No payment was recorded for this booking');

      // Capturing twice is the classic double-charge. The row is locked and
      // the state checked inside the same transaction.
      if (intent.escrow_status === 'captured') {
        return { capturedMinor: Number(intent.authorized_minor) };
      }
      if (intent.escrow_status !== 'authorized') {
        throw new PaymentError(`Cannot capture a payment in state ${intent.escrow_status}`);
      }

      const gateway = this.gatewayFor(booking.country_code);
      const totalMinor = Number(booking.total_minor);
      const result = await gateway.capture(intent.gateway_reference, totalMinor);
      if (result.status === 'failed') {
        throw new PaymentError(result.failureMessage ?? 'Could not capture the payment');
      }

      await tx.query(
        `UPDATE payment_intents
            SET escrow_status = 'captured', captured_minor = $2, updated_at = now()
          WHERE id = $1`,
        [intent.id, result.capturedMinor],
      );

      const commission = Number(booking.commission_minor);
      const serviceFee = Number(booking.service_fee_minor);
      const payout = Number(booking.provider_payout_minor);
      const vat = Number(booking.vat_on_fees_minor);

      // Guard the arithmetic before it reaches the ledger. If these ever
      // disagree the correct behaviour is to fail the capture, not to write
      // an unbalanced set of entries and discover it at month end.
      if (commission + serviceFee + payout !== totalMinor) {
        throw new PaymentError('Booking totals do not reconcile; refusing to capture', {
          totalMinor, commission, serviceFee, payout,
        });
      }

      const group = randomUUID();
      await this.writeEntries(tx, group, booking.currency, bookingId, [
        { account: 'escrow', direction: 'debit', amountMinor: totalMinor, description: 'Escrow released on completion' },
        { account: 'provider_payable', direction: 'credit', amountMinor: payout, description: 'Provider earnings', providerId: booking.provider_id },
        { account: 'platform_commission', direction: 'credit', amountMinor: commission, description: 'Marketplace commission' },
        { account: 'platform_service_fee', direction: 'credit', amountMinor: serviceFee, description: 'Platform service fee' },
      ]);

      if (vat > 0) {
        const taxGroup = randomUUID();
        await this.writeEntries(tx, taxGroup, booking.currency, bookingId, [
          { account: 'platform_commission', direction: 'debit', amountMinor: vat, description: 'VAT on platform revenue' },
          { account: 'tax_payable', direction: 'credit', amountMinor: vat, description: 'VAT payable' },
        ]);
      }

      if (booking.provider_id) {
        await tx.query(
          `INSERT INTO provider_wallets (provider_id, currency, available_minor, lifetime_earned_minor)
           VALUES ($1, $2::currency_code_enum, $3, $3)
           ON CONFLICT (provider_id) DO UPDATE
             SET available_minor = provider_wallets.available_minor + EXCLUDED.available_minor,
                 lifetime_earned_minor = provider_wallets.lifetime_earned_minor + EXCLUDED.available_minor,
                 updated_at = now()`,
          [booking.provider_id, booking.currency, payout],
        );
        await tx.query(
          'UPDATE providers SET completed_jobs = completed_jobs + 1 WHERE id = $1',
          [booking.provider_id],
        );
      }

      await tx.emitEvent('booking', bookingId, 'booking.captured', {
        capturedMinor: result.capturedMinor,
        payoutMinor: payout,
      });

      return { capturedMinor: result.capturedMinor };
    }, 'REPEATABLE READ');
  }

  /** Release a hold without taking anything — expiry, or a provider cancellation. */
  async release(bookingId: string, reason: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      const intent = await tx.queryOne<{ id: string; gateway_reference: string; escrow_status: string; authorized_minor: string; currency: string }>(
        `SELECT id, gateway_reference, escrow_status, authorized_minor, currency
           FROM payment_intents WHERE booking_id = $1 FOR UPDATE`,
        [bookingId],
      );
      if (!intent || intent.escrow_status !== 'authorized') return;

      const booking = await tx.queryOne<{ country_code: 'ZA' | 'ZW' }>(
        'SELECT country_code FROM bookings WHERE id = $1', [bookingId],
      );
      await this.gatewayFor(booking!.country_code).void(intent.gateway_reference);

      await tx.query(
        `UPDATE payment_intents SET escrow_status = 'released', updated_at = now() WHERE id = $1`,
        [intent.id],
      );

      const group = randomUUID();
      await this.writeEntries(tx, group, intent.currency, bookingId, [
        { account: 'escrow', direction: 'debit', amountMinor: Number(intent.authorized_minor), description: `Hold released: ${reason}` },
        { account: 'client_source', direction: 'credit', amountMinor: Number(intent.authorized_minor), description: 'Returned to customer' },
      ]);

      await tx.emitEvent('booking', bookingId, 'escrow.released', { reason });
    });
  }

  /** Partial capture for a cancellation fee; the balance goes back to the client. */
  async captureCancellationFee(bookingId: string, feeMinor: number, reason: string): Promise<void> {
    if (feeMinor <= 0) return this.release(bookingId, reason);

    await this.db.transaction(async (tx) => {
      const intent = await tx.queryOne<{ id: string; gateway_reference: string; escrow_status: string; authorized_minor: string; currency: string }>(
        `SELECT id, gateway_reference, escrow_status, authorized_minor, currency
           FROM payment_intents WHERE booking_id = $1 FOR UPDATE`,
        [bookingId],
      );
      if (!intent || intent.escrow_status !== 'authorized') return;

      const booking = await tx.queryOne<{ country_code: 'ZA' | 'ZW'; provider_id: string | null }>(
        'SELECT country_code, provider_id FROM bookings WHERE id = $1', [bookingId],
      );

      const gateway = this.gatewayFor(booking!.country_code);
      const captured = await gateway.capture(intent.gateway_reference, feeMinor);
      if (captured.status === 'failed') throw new PaymentError('Could not capture the cancellation fee');

      await tx.query(
        `UPDATE payment_intents
            SET escrow_status = 'partially_captured', captured_minor = $2, updated_at = now()
          WHERE id = $1`,
        [intent.id, feeMinor],
      );

      // The provider keeps most of a cancellation fee — they lost the slot and
      // possibly the fuel. The platform takes nothing beyond its own costs.
      const providerShare = Math.round(feeMinor * 0.8);
      const platformShare = feeMinor - providerShare;
      const group = randomUUID();

      await this.writeEntries(tx, group, intent.currency, bookingId, [
        { account: 'escrow', direction: 'debit', amountMinor: feeMinor, description: `Cancellation fee: ${reason}` },
        { account: 'provider_payable', direction: 'credit', amountMinor: providerShare, description: 'Cancellation compensation', providerId: booking!.provider_id },
        { account: 'platform_commission', direction: 'credit', amountMinor: platformShare, description: 'Cancellation handling' },
      ]);

      const remainder = Number(intent.authorized_minor) - feeMinor;
      if (remainder > 0) {
        const refundGroup = randomUUID();
        await this.writeEntries(tx, refundGroup, intent.currency, bookingId, [
          { account: 'escrow', direction: 'debit', amountMinor: remainder, description: 'Balance returned' },
          { account: 'client_source', direction: 'credit', amountMinor: remainder, description: 'Returned to customer' },
        ]);
      }

      if (booking!.provider_id && providerShare > 0) {
        await tx.query(
          `INSERT INTO provider_wallets (provider_id, currency, available_minor, lifetime_earned_minor)
           VALUES ($1, $2::currency_code_enum, $3, $3)
           ON CONFLICT (provider_id) DO UPDATE
             SET available_minor = provider_wallets.available_minor + EXCLUDED.available_minor,
                 updated_at = now()`,
          [booking!.provider_id, intent.currency, providerShare],
        );
      }
    });
  }

  /**
   * Write a balanced set of entries and assert the balance in the database.
   * The assertion is not defensive programming for its own sake — it is the
   * only thing standing between a bad refactor and a ledger nobody can close.
   */
  private async writeEntries(
    tx: TransactionContext,
    groupKey: string,
    currency: string,
    bookingId: string,
    entries: Array<{
      account: string;
      direction: 'debit' | 'credit';
      amountMinor: number;
      description: string;
      providerId?: string | null;
    }>,
  ): Promise<void> {
    for (const entry of entries) {
      if (entry.amountMinor <= 0) continue;
      await tx.query(
        `INSERT INTO ledger_entries
           (booking_id, account, direction, amount_minor, currency, description, group_key, counterparty_provider_id)
         VALUES ($1, $2::ledger_account_enum, $3::ledger_direction_enum, $4, $5::currency_code_enum, $6, $7, $8)`,
        [bookingId, entry.account, entry.direction, entry.amountMinor, currency, entry.description, groupKey, entry.providerId ?? null],
      );
    }
    await tx.query('SELECT fn_assert_ledger_balanced($1)', [groupKey]);
  }
}
