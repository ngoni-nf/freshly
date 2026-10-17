import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../common/database/database.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';
import { LedgerService } from '../payments/ledger.service';
import { MarketsService } from '../markets/markets.service';
import { CommsService } from '../comms/comms.service';
import { PayoutBreakdown, PayoutPolicy } from './payout.policy';
import { PayoutProvider, PayoutWebhookEvent } from './providers/payout-provider.interface';
import { MockPayoutProvider } from './providers/mock.payout-provider';
import { StitchPayoutProvider } from './providers/stitch.payout-provider';
import { PaynowPayoutProvider } from './providers/paynow.payout-provider';
import { HttpStatus } from '@nestjs/common';

interface WalletRow {
  currency: string;
  available_minor: string;
  lifetime_earned_minor: string;
}

interface AccountRow {
  id: string;
  currency: string;
  method: string;
  institution_code: string | null;
  institution_name: string | null;
  account_name: string;
  account_number_enc: Buffer;
  account_last4: string;
  is_verified: boolean;
}

/**
 * Provider earnings, and getting them out of the platform.
 *
 * The shape of this module is dictated by one fact: a disbursement is not
 * confirmed when the API call returns. It is confirmed hours later by a
 * webhook, and it can fail then. So the balance is reserved first, the money
 * is sent second, and a failure afterwards writes a reversing ledger group and
 * puts the funds back — rather than the tempting alternative of holding a
 * database transaction open across a network call to a bank.
 */
const MOBILE_MONEY_METHODS = new Set(['ecocash', 'onemoney', 'innbucks']);

const DIAL_PREFIX: Record<'ZA' | 'ZW', string> = { ZA: '+27', ZW: '+263' };

/** "0771000001", "771000001" and "+263771000001" are one number in Zimbabwe. */
function sameNumber(typed: string, e164: string, country: 'ZA' | 'ZW'): boolean {
  const national = typed.replace(/\D/g, '').replace(/^0+/, '');
  const prefix = DIAL_PREFIX[country].slice(1);
  const typedE164 = national.startsWith(prefix) ? `+${national}` : `${DIAL_PREFIX[country]}${national}`;
  return typedE164 === e164;
}

@Injectable()
export class PayoutsService {
  private readonly logger = new Logger(PayoutsService.name);
  private readonly providers = new Map<string, PayoutProvider>();

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly crypto: PiiCryptoService,
    private readonly ledger: LedgerService,
    private readonly markets: MarketsService,
    private readonly comms: CommsService,
    private readonly policy: PayoutPolicy,
  ) {
    this.providers.set('mock', new MockPayoutProvider());

    this.providers.set(
      'stitch',
      new StitchPayoutProvider({
        clientId: this.config.get<string>('STITCH_CLIENT_ID'),
        clientSecret: this.config.get<string>('STITCH_CLIENT_SECRET'),
        webhookSecret: this.config.get<string>('STITCH_WEBHOOK_SECRET'),
        baseUrl: this.config.get<string>('STITCH_BASE_URL') ?? 'https://secure.stitch.money',
      }),
    );

    const paynowId = this.config.get<string>('PAYNOW_INTEGRATION_ID');
    const paynowKey = this.config.get<string>('PAYNOW_INTEGRATION_KEY');
    if (paynowId && paynowKey) {
      this.providers.set('paynow', new PaynowPayoutProvider(paynowId, paynowKey));
    }
  }

  private providerFor(countryCode: 'ZA' | 'ZW'): PayoutProvider {
    const configured =
      countryCode === 'ZA'
        ? this.config.get<string>('PAYOUTS_ZA_PROVIDER')
        : this.config.get<string>('PAYOUTS_ZW_PROVIDER');
    return this.providers.get(configured ?? 'mock') ?? this.providers.get('mock')!;
  }

  /**
   * What the provider has, what is still in escrow, and — the part support
   * gets asked about most — why they cannot cash out yet, if they cannot.
   */
  async wallet(providerId: string) {
    const provider = await this.db.queryOne<{
      country_code: 'ZA' | 'ZW';
      payout_currency: string;
      kyc_status: string;
      is_suspended: boolean;
    }>(
      'SELECT country_code, payout_currency, kyc_status, is_suspended FROM providers WHERE id = $1',
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    const wallet = await this.db.queryOne<WalletRow>(
      'SELECT currency, available_minor, lifetime_earned_minor FROM provider_wallets WHERE provider_id = $1',
      [providerId],
    );

    // Pending is derived from bookings in flight rather than stored. A second
    // copy of a number that can be computed is a number that will eventually
    // disagree with the first one, and this is the figure providers check
    // against their own diary.
    const pending = await this.db.queryOne<{ pending_minor: string | null }>(
      `SELECT COALESCE(SUM(b.provider_payout_minor), 0) AS pending_minor
         FROM bookings b
        WHERE b.provider_id = $1
          AND b.status IN ('accepted','en_route','arrived','in_progress','completed')
          AND EXISTS (
            SELECT 1 FROM payment_intents pi
             WHERE pi.booking_id = b.id AND pi.escrow_status = 'authorized'
          )`,
      [providerId],
    );

    const account = await this.defaultAccount(providerId);
    const currency = wallet?.currency ?? provider.payout_currency;
    const availableMinor = Number(wallet?.available_minor ?? 0);
    const minimumMinor = this.markets.get(provider.country_code).minPayoutMinor;

    return {
      currency,
      availableMinor,
      pendingMinor: Number(pending?.pending_minor ?? 0),
      lifetimeEarnedMinor: Number(wallet?.lifetime_earned_minor ?? 0),
      minimumMinor,
      instantFeeBps: this.markets.setting<number>('payout.instant_fee_bps', 150),
      account: account
        ? {
            id: account.id,
            method: account.method,
            institutionName: account.institution_name,
            last4: account.account_last4,
            isVerified: account.is_verified,
          }
        : null,
      // Stated positively so the app can show the reason instead of a disabled
      // button with no explanation.
      canCashOut:
        provider.kyc_status === 'verified' &&
        !provider.is_suspended &&
        !!account?.is_verified &&
        availableMinor >= minimumMinor,
      blockedReason: this.blockedReason(provider, account, availableMinor, minimumMinor),
    };
  }

  private blockedReason(
    provider: { kyc_status: string; is_suspended: boolean },
    account: AccountRow | null,
    availableMinor: number,
    minimumMinor: number,
  ): string | null {
    if (provider.is_suspended) return 'account_suspended';
    if (provider.kyc_status !== 'verified') return 'kyc_required';
    if (!account) return 'payout_account_missing';
    if (!account.is_verified) return 'payout_account_unverified';
    if (availableMinor < minimumMinor) return 'below_minimum';
    return null;
  }

  private defaultAccount(providerId: string): Promise<AccountRow | null> {
    return this.db.queryOne<AccountRow>(
      `SELECT id, currency, method, institution_code, institution_name, account_name,
              account_number_enc, account_last4, is_verified
         FROM payout_accounts
        WHERE provider_id = $1
        ORDER BY is_default DESC, created_at DESC
        LIMIT 1`,
      [providerId],
    );
  }

  async listAccounts(providerId: string) {
    const rows = await this.db.query<AccountRow & { is_default: boolean }>(
      `SELECT id, currency, method, institution_code, institution_name, account_name,
              account_last4, is_verified, is_default
         FROM payout_accounts WHERE provider_id = $1 ORDER BY is_default DESC, created_at DESC`,
      [providerId],
    );
    // The full account number is never returned, to anyone. It went in
    // encrypted and the only reason to decrypt it is to pay someone.
    return rows.map((r) => ({
      id: r.id,
      currency: r.currency,
      method: r.method,
      institutionName: r.institution_name,
      accountName: r.account_name,
      last4: r.account_last4,
      isVerified: r.is_verified,
      isDefault: r.is_default,
    }));
  }

  async addAccount(
    providerId: string,
    input: {
      method: string;
      accountNumber: string;
      accountName: string;
      institutionCode?: string;
      institutionName?: string;
    },
  ) {
    const provider = await this.db.queryOne<{
      country_code: 'ZA' | 'ZW'; payout_currency: string; phone_e164: string | null;
    }>(
      `SELECT p.country_code, p.payout_currency, u.phone_e164
         FROM providers p JOIN users u ON u.id = p.user_id WHERE p.id = $1`,
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    const gateway = this.providerFor(provider.country_code);
    if (!gateway.supports(input.method)) {
      throw new DomainError(
        'payout_method_unsupported',
        'That payout method is not available in your country yet',
        HttpStatus.UNPROCESSABLE_ENTITY,
        { method: input.method, provider: gateway.name },
      );
    }

    const digits = input.accountNumber.replace(/\s+/g, '');

    // A mobile-money wallet is addressed by a phone number. When it is the
    // number this provider already proved they hold at sign-in, the account
    // is theirs by construction and needs no second check. Anything else (a
    // bank account, somebody else's wallet) waits for ops to verify it.
    const ownsNumber =
      MOBILE_MONEY_METHODS.has(input.method) &&
      provider.phone_e164 != null &&
      sameNumber(digits, provider.phone_e164, provider.country_code);

    return this.db.transaction(async (tx) => {
      // One default at a time, enforced by clearing the others in the same
      // transaction rather than hoping the application always remembers.
      await tx.query('UPDATE payout_accounts SET is_default = false WHERE provider_id = $1', [
        providerId,
      ]);

      const row = await tx.queryOne<{ id: string }>(
        `INSERT INTO payout_accounts
           (provider_id, country_code, currency, method, institution_code, institution_name,
            account_name, account_number_enc, account_last4, is_verified, is_default)
         VALUES ($1, $2::country_code_enum, $3::currency_code_enum, $4, $5, $6, $7, $8, $9, $10, true)
         RETURNING id`,
        [
          providerId,
          provider.country_code,
          provider.payout_currency,
          input.method,
          input.institutionCode ?? null,
          input.institutionName ?? null,
          input.accountName,
          this.crypto.encrypt(digits),
          PiiCryptoService.last4(digits),
          ownsNumber,
        ],
      );

      return { id: row!.id, last4: PiiCryptoService.last4(digits), isVerified: ownsNumber };
    });
  }

  /**
   * Cash out.
   *
   * Three phases, deliberately not one: reserve the balance in a transaction,
   * send the instruction outside it, then record the outcome. Holding a row
   * lock on a provider's wallet across a call to a bank is how one slow
   * upstream turns into every provider in the country being unable to see
   * their earnings.
   */
  async request(
    providerId: string,
    amountMinor: number,
    instant: boolean,
    idempotencyKey: string,
  ) {
    const reserved = await this.reserve(providerId, amountMinor, instant, idempotencyKey);

    // Decrypt before anything else, and say plainly what is wrong if it fails.
    // Unreadable account data is a data problem, not a gateway problem, and
    // reporting it as "we could not reach the payout provider" sends whoever
    // is debugging it to the wrong system entirely.
    let accountNumber: string;
    try {
      accountNumber = this.crypto.decrypt(reserved.account.account_number_enc);
    } catch {
      await this.reverse(reserved.payoutId, 'payout account could not be decrypted');
      throw new DomainError(
        'payout_account_unreadable',
        'We could not read your payout account. Please add it again.',
        HttpStatus.CONFLICT,
        { accountId: reserved.account.id },
      );
    }

    const gateway = this.providerFor(reserved.countryCode);
    let outcome;
    try {
      outcome = await gateway.send({
        payoutId: reserved.payoutId,
        netMinor: reserved.breakdown.netMinor,
        currency: reserved.currency,
        method: reserved.account.method,
        accountNumber,
        accountName: reserved.account.account_name,
        institutionCode: reserved.account.institution_code ?? undefined,
        narrative: `Freshly earnings`,
        idempotencyKey,
      });
    } catch (err) {
      // The instruction never left. Put the money back before surfacing the
      // error, or the provider is short until someone notices.
      await this.reverse(reserved.payoutId, (err as Error).message);
      throw new DomainError(
        'payout_send_failed',
        'We could not reach the payout provider. Your balance is unchanged.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    if (outcome.status === 'failed') {
      await this.reverse(reserved.payoutId, outcome.failureReason ?? 'rejected by provider');
      throw new DomainError(
        'payout_rejected',
        outcome.failureReason ?? 'The payout was rejected. Your balance is unchanged.',
        HttpStatus.CONFLICT,
      );
    }

    await this.db.query(
      `UPDATE payouts
          SET status = $2::payout_status_enum,
              external_reference = $3,
              settled_at = $4
        WHERE id = $1`,
      [
        reserved.payoutId,
        outcome.status === 'paid' ? 'paid' : 'processing',
        outcome.externalReference,
        outcome.settledAt ?? (outcome.status === 'paid' ? new Date() : null),
      ],
    );

    return {
      id: reserved.payoutId,
      status: outcome.status,
      grossMinor: reserved.breakdown.grossMinor,
      feeMinor: reserved.breakdown.feeMinor,
      netMinor: reserved.breakdown.netMinor,
      currency: reserved.currency,
      accountLast4: reserved.account.account_last4,
    };
  }

  private async reserve(
    providerId: string,
    amountMinor: number,
    instant: boolean,
    idempotencyKey: string,
  ): Promise<{
    payoutId: string;
    breakdown: PayoutBreakdown;
    currency: string;
    countryCode: 'ZA' | 'ZW';
    account: AccountRow;
  }> {
    return this.db.transaction(async (tx) => {
      const provider = await tx.queryOne<{
        country_code: 'ZA' | 'ZW';
        payout_currency: string;
        kyc_status: string;
        is_suspended: boolean;
      }>(
        'SELECT country_code, payout_currency, kyc_status, is_suspended FROM providers WHERE id = $1',
        [providerId],
      );
      if (!provider) throw new NotFoundError('Provider', providerId);

      // Lock the wallet, not the provider row. Two concurrent cash-out taps
      // must serialise here or both will pass the balance check.
      const wallet = await tx.queryOne<WalletRow>(
        `SELECT currency, available_minor, lifetime_earned_minor
           FROM provider_wallets WHERE provider_id = $1 FOR UPDATE`,
        [providerId],
      );

      const account = await tx.queryOne<AccountRow>(
        `SELECT id, currency, method, institution_code, institution_name, account_name,
                account_number_enc, account_last4, is_verified
           FROM payout_accounts
          WHERE provider_id = $1
          ORDER BY is_default DESC, created_at DESC
          LIMIT 1`,
        [providerId],
      );

      const currency = wallet?.currency ?? provider.payout_currency;
      const breakdown = this.policy.assess({
        availableMinor: Number(wallet?.available_minor ?? 0),
        requestedMinor: amountMinor,
        walletCurrency: currency,
        accountCurrency: account?.currency ?? null,
        accountVerified: account?.is_verified ?? false,
        hasAccount: !!account,
        kycStatus: provider.kyc_status,
        isSuspended: provider.is_suspended,
        minimumMinor: this.markets.get(provider.country_code).minPayoutMinor,
        instantFeeBps: this.markets.setting<number>('payout.instant_fee_bps', 150),
        instant,
      });

      const payout = await tx.queryOne<{ id: string }>(
        `INSERT INTO payouts
           (provider_id, payout_account_id, amount_minor, fee_minor, currency, status, idempotency_key)
         VALUES ($1, $2, $3, $4, $5::currency_code_enum, 'queued', $6)
         RETURNING id`,
        [providerId, account!.id, breakdown.grossMinor, breakdown.feeMinor, currency, idempotencyKey],
      );

      // The CHECK (available_minor >= 0) on the wallet is the last line of
      // defence: even if the policy above were wrong, the database refuses to
      // let a provider withdraw money that is not there.
      await tx.query(
        'UPDATE provider_wallets SET available_minor = available_minor - $2, updated_at = now() WHERE provider_id = $1',
        [providerId, breakdown.grossMinor],
      );

      await this.ledger.write(tx, {
        currency,
        payoutId: payout!.id,
        entries: [
          {
            account: 'provider_payable',
            direction: 'debit',
            amountMinor: breakdown.grossMinor,
            description: 'Cash-out requested',
            providerId,
          },
          {
            account: 'bank_settlement',
            direction: 'credit',
            amountMinor: breakdown.netMinor,
            description: 'Sent to provider account',
            providerId,
          },
          {
            account: 'platform_commission',
            direction: 'credit',
            amountMinor: breakdown.feeMinor,
            description: 'Instant cash-out fee',
            providerId,
          },
        ],
      });

      await tx.emitEvent('payout', payout!.id, 'payout.queued', {
        providerId,
        grossMinor: breakdown.grossMinor,
        netMinor: breakdown.netMinor,
        currency,
      });

      return {
        payoutId: payout!.id,
        breakdown,
        currency,
        countryCode: provider.country_code,
        account: account!,
      };
    });
  }

  /**
   * Undo a reservation. Writes a mirror-image ledger group rather than
   * deleting the original entries — a ledger that can be edited after the
   * fact is not evidence of anything.
   */
  private async reverse(payoutId: string, reason: string): Promise<void> {
    await this.db.transaction(async (tx) => {
      const payout = await tx.queryOne<{
        provider_id: string;
        amount_minor: string;
        fee_minor: string;
        currency: string;
        status: string;
      }>(
        `SELECT provider_id, amount_minor, fee_minor, currency, status
           FROM payouts WHERE id = $1 FOR UPDATE`,
        [payoutId],
      );
      if (!payout) return;
      if (payout.status === 'reversed' || payout.status === 'paid') return;

      const grossMinor = Number(payout.amount_minor);
      const feeMinor = Number(payout.fee_minor);

      await tx.query(
        `UPDATE payouts SET status = 'reversed', failure_reason = $2 WHERE id = $1`,
        [payoutId, reason.slice(0, 500)],
      );

      await tx.query(
        `UPDATE provider_wallets
            SET available_minor = available_minor + $2, updated_at = now()
          WHERE provider_id = $1`,
        [payout.provider_id, grossMinor],
      );

      await this.ledger.write(tx, {
        currency: payout.currency,
        payoutId,
        entries: [
          {
            account: 'bank_settlement',
            direction: 'debit',
            amountMinor: grossMinor - feeMinor,
            description: `Payout reversed: ${reason}`,
            providerId: payout.provider_id,
          },
          {
            account: 'platform_commission',
            direction: 'debit',
            amountMinor: feeMinor,
            description: 'Cash-out fee refunded',
            providerId: payout.provider_id,
          },
          {
            account: 'provider_payable',
            direction: 'credit',
            amountMinor: grossMinor,
            description: 'Returned to balance',
            providerId: payout.provider_id,
          },
        ],
      });

      await tx.emitEvent('payout', payoutId, 'payout.reversed', { reason });
    });

    this.logger.warn(`payout ${payoutId} reversed: ${reason}`);
  }

  async history(providerId: string, limit = 30) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT p.id, p.amount_minor, p.fee_minor, p.currency, p.status, p.failure_reason,
              p.requested_at, p.settled_at, a.account_last4, a.method
         FROM payouts p
         JOIN payout_accounts a ON a.id = p.payout_account_id
        WHERE p.provider_id = $1
        ORDER BY p.requested_at DESC
        LIMIT $2`,
      [providerId, limit],
    );

    return rows.map((r) => ({
      id: r.id,
      grossMinor: Number(r.amount_minor),
      feeMinor: Number(r.fee_minor),
      netMinor: Number(r.amount_minor) - Number(r.fee_minor),
      currency: r.currency,
      status: r.status,
      failureReason: r.failure_reason,
      method: r.method,
      accountLast4: r.account_last4,
      requestedAt: r.requested_at.toISOString(),
      settledAt: r.settled_at?.toISOString() ?? null,
    }));
  }

  async earningsHistory(providerId: string, limit = 30) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT b.id, b.reference, b.completed_at, b.currency,
              b.subtotal_minor + b.addons_minor as service_minor,
              b.travel_fee_minor,
              b.commission_minor,
              b.provider_payout_minor as net_earnings
         FROM bookings b
        WHERE b.provider_id = $1 AND b.status = 'completed'
        ORDER BY b.completed_at DESC
        LIMIT $2`,
      [providerId, limit],
    );

    return rows.map((r) => ({
      bookingId: r.id,
      reference: r.reference,
      completedAt: r.completed_at.toISOString(),
      currency: r.currency,
      serviceMinor: Number(r.service_minor),
      travelMinor: Number(r.travel_fee_minor),
      commissionMinor: Number(r.commission_minor),
      netEarningsMinor: Number(r.net_earnings),
    }));
  }

  /**
   * Settlement callback. This is where a payout genuinely becomes final, and
   * where a failure hours after the fact puts the money back.
   */
  async handleWebhook(providerName: string, signature: string, rawBody: string) {
    const gateway = this.providers.get(providerName);
    if (!gateway) throw new NotFoundError('Payout provider', providerName);

    if (!gateway.verifyWebhook(signature, rawBody)) {
      // Never 200 an unverified callback: a bad signature is either a
      // misconfiguration or someone trying to mark their own payout paid.
      throw new DomainError('invalid_signature', 'Signature verification failed', HttpStatus.UNAUTHORIZED);
    }

    const event: PayoutWebhookEvent = gateway.parseWebhook(rawBody);

    // Record before acting, and let the UNIQUE (provider_name, event_id)
    // constraint absorb redelivery. Every gateway retries, and a replayed
    // "failed" callback must not reverse the same payout twice.
    const recorded = await this.db.query<{ id: string }>(
      `INSERT INTO gateway_webhooks (provider_name, event_id, event_type, payload, signature_valid, processed_at)
       VALUES ($1, $2, $3, $4, true, now())
       ON CONFLICT (provider_name, event_id) DO NOTHING
       RETURNING id`,
      // Keyed on reference *and* status: one payout legitimately produces a
      // `processing` then a `paid` callback, and keying on the reference alone
      // would silently swallow the one that matters.
      [providerName, `${event.externalReference}:${event.status}`, `payout.${event.status}`, rawBody],
    );
    if (!recorded.length) {
      this.logger.log(`ignoring replayed ${providerName} webhook ${event.externalReference}`);
      return { ok: true };
    }

    const payout = await this.db.queryOne<{ id: string; status: string }>(
      'SELECT id, status FROM payouts WHERE external_reference = $1',
      [event.externalReference],
    );
    if (!payout) {
      this.logger.warn(`webhook for unknown payout reference ${event.externalReference}`);
      return { ok: true };
    }

    if (event.status === 'paid') {
      await this.db.query(
        `UPDATE payouts SET status = 'paid', settled_at = $2 WHERE id = $1 AND status <> 'paid'`,
        [payout.id, event.settledAt ?? new Date()],
      );
      await this.notifySettled(payout.id);
    } else if (event.status === 'failed' || event.status === 'reversed') {
      await this.reverse(payout.id, event.failureReason ?? 'settlement failed');
    }

    return { ok: true };
  }

  private async notifySettled(payoutId: string): Promise<void> {
    const row = await this.db.queryOne<{ phone_e164: string; amount_minor: string; fee_minor: string; currency: string }>(
      `SELECT u.phone_e164, p.amount_minor, p.fee_minor, p.currency
         FROM payouts p
         JOIN providers pr ON pr.id = p.provider_id
         JOIN users u ON u.id = pr.user_id
        WHERE p.id = $1`,
      [payoutId],
    );
    if (!row) return;

    const netMinor = Number(row.amount_minor) - Number(row.fee_minor);
    await this.comms
      .notifyPayoutSettled(row.phone_e164, netMinor, row.currency)
      .catch((err) => this.logger.warn(`payout SMS failed: ${err.message}`));
  }
}
