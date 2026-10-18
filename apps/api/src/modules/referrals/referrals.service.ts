import { Injectable, Logger } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { DatabaseService, TransactionContext } from '../../common/database/database.service';
import { DomainError } from '../../common/errors/domain.errors';
import { MarketsService } from '../markets/markets.service';

/**
 * Referrals.
 *
 * The reward is earned on the referee's first completed booking, never on
 * signup. A signup costs nothing to fake; a completed booking needs a provider
 * to have arrived, a card to have been authorised and captured, and the
 * client's PIN. That single choice is most of the fraud control.
 *
 * Rewards are credits spent as a discount on a later booking. A discount is
 * already part of the quote and moves no money by itself, so nothing here can
 * unbalance the ledger — which cash rewards or wallet top-ups would.
 */
@Injectable()
export class ReferralsService {
  private readonly logger = new Logger(ReferralsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
  ) {}

  /**
   * Unambiguous when read aloud or typed from a screenshot, which is how these
   * actually travel. No O/0, I/1, S/5 — a code somebody mistypes is a referral
   * that silently does not happen.
   */
  private static readonly ALPHABET = 'ABCDEFGHJKLMNPQRTUVWXY2346789';

  private newCode(): string {
    let out = '';
    for (let i = 0; i < 6; i += 1) {
      out += ReferralsService.ALPHABET[randomInt(0, ReferralsService.ALPHABET.length)];
    }
    return out;
  }

  /** Generated on first ask. Most people never share one. */
  async myCode(userId: string): Promise<{ code: string; refereeDiscountMinor: number; currency: string }> {
    const user = await this.db.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM users WHERE id = $1',
      [userId],
    );
    const market = this.markets.get(user!.country_code);

    const existing = await this.db.queryOne<{ code: string }>(
      'SELECT code FROM referral_codes WHERE user_id = $1',
      [userId],
    );
    if (existing) {
      return {
        code: existing.code,
        refereeDiscountMinor: market.referralRefereeDiscountMinor,
        currency: market.defaultCurrency,
      };
    }

    // Retry on collision rather than pre-checking. At six characters from a
    // 29-letter alphabet a clash is vanishingly rare, and the unique index is
    // the only thing that can decide it without a race.
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const code = this.newCode();
      try {
        await this.db.query(
          'INSERT INTO referral_codes (user_id, code) VALUES ($1, $2)',
          [userId, code],
        );
        return {
          code,
          refereeDiscountMinor: market.referralRefereeDiscountMinor,
          currency: market.defaultCurrency,
        };
      } catch (err) {
        if ((err as { code?: string }).code !== '23505') throw err;
      }
    }
    throw new DomainError('code_generation_failed', 'Please try again');
  }

  /**
   * Claim a code. Only ever before the referee's first booking — the invite is
   * for new customers, and letting an existing one claim later turns it into a
   * discount everybody eventually finds.
   */
  async claim(userId: string, rawCode: string): Promise<{ discountMinor: number; currency: string }> {
    const code = rawCode.trim().toUpperCase();

    const owner = await this.db.queryOne<{ user_id: string }>(
      'SELECT user_id FROM referral_codes WHERE upper(code) = $1',
      [code],
    );
    if (!owner) {
      throw new DomainError('referral_code_invalid', 'That invite code is not valid');
    }
    if (owner.user_id === userId) {
      throw new DomainError('referral_self', 'You cannot use your own invite code');
    }

    const existing = await this.db.queryOne<{ referee_user_id: string }>(
      'SELECT referee_user_id FROM referrals WHERE referee_user_id = $1',
      [userId],
    );
    if (existing) {
      throw new DomainError('referral_already_used', 'You have already used an invite code');
    }

    const booked = await this.db.queryOne<{ id: string }>(
      `SELECT id FROM bookings WHERE client_id = $1 AND status <> 'draft' LIMIT 1`,
      [userId],
    );
    if (booked) {
      throw new DomainError(
        'referral_not_new_customer',
        'Invite codes are for your first booking',
      );
    }

    const user = await this.db.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM users WHERE id = $1',
      [userId],
    );
    const market = this.markets.get(user!.country_code);

    await this.db.transaction(async (tx) => {
      await tx.query(
        'INSERT INTO referrals (referee_user_id, referrer_user_id) VALUES ($1, $2)',
        [userId, owner.user_id],
      );
      // The referee's side is granted immediately: it is a discount they can
      // only spend by booking, so there is nothing to farm.
      if (market.referralRefereeDiscountMinor > 0) {
        await this.grantCredit(
          tx, userId, market.referralRefereeDiscountMinor,
          market.defaultCurrency, 'referral_welcome', market.referralCreditTtlDays,
        );
      }
    });

    return {
      discountMinor: market.referralRefereeDiscountMinor,
      currency: market.defaultCurrency,
    };
  }

  /**
   * Called when a booking completes. The referrer is paid here and only here.
   *
   * Runs inside the caller's transaction so the reward and the completion
   * commit together — a reward granted against a booking that then rolled back
   * is free money.
   */
  async onBookingCompleted(tx: TransactionContext, clientId: string, bookingId: string): Promise<void> {
    const referral = await tx.queryOne<{ referrer_user_id: string }>(
      `SELECT referrer_user_id FROM referrals
        WHERE referee_user_id = $1 AND status = 'pending'
        FOR UPDATE`,
      [clientId],
    );
    if (!referral) return;

    const referrer = await tx.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM users WHERE id = $1',
      [referral.referrer_user_id],
    );
    if (!referrer) return;
    const market = this.markets.get(referrer.country_code);

    await tx.query(
      `UPDATE referrals
          SET status = 'qualified', qualified_at = now(), qualifying_booking_id = $2
        WHERE referee_user_id = $1`,
      [clientId, bookingId],
    );

    if (market.referralReferrerCreditMinor > 0) {
      await this.grantCredit(
        tx, referral.referrer_user_id, market.referralReferrerCreditMinor,
        market.defaultCurrency, 'referral_reward', market.referralCreditTtlDays,
      );
    }

    this.logger.log(`referral qualified: ${referral.referrer_user_id} earned credit from ${bookingId}`);
  }

  private async grantCredit(
    tx: TransactionContext,
    userId: string,
    amountMinor: number,
    currency: string,
    reason: string,
    ttlDays: number,
  ): Promise<void> {
    await tx.query(
      `INSERT INTO user_credits (user_id, amount_minor, currency, reason, expires_at)
       VALUES ($1, $2, $3::currency_code_enum, $4, now() + ($5 || ' days')::interval)`,
      [userId, amountMinor, currency, reason, String(ttlDays)],
    );
  }

  /** What is spendable right now. Expired and consumed credit is excluded. */
  async balance(userId: string): Promise<{ amountMinor: number; currency: string | null }> {
    const row = await this.db.queryOne<{ total: string; currency: string | null }>(
      `SELECT COALESCE(SUM(amount_minor), 0) AS total, MIN(currency) AS currency
         FROM user_credits
        WHERE user_id = $1
          AND consumed_at IS NULL
          AND (expires_at IS NULL OR expires_at > now())`,
      [userId],
    );
    return { amountMinor: Number(row?.total ?? 0), currency: row?.currency ?? null };
  }

  /**
   * Spend credit against a booking, capped at the amount owed.
   *
   * Oldest first, so the credit closest to expiring goes before one with
   * longer to run. Capped because a credit larger than the bill must not
   * produce a negative total — that is a refund, and this is a discount.
   */
  async consumeForBooking(
    tx: TransactionContext,
    userId: string,
    bookingId: string,
    maxMinor: number,
  ): Promise<number> {
    if (maxMinor <= 0) return 0;

    const credits = await tx.query<{ id: string; amount_minor: string }>(
      `SELECT id, amount_minor FROM user_credits
        WHERE user_id = $1 AND consumed_at IS NULL
          AND (expires_at IS NULL OR expires_at > now())
        ORDER BY created_at ASC
        FOR UPDATE`,
      [userId],
    );

    let applied = 0;
    for (const credit of credits) {
      if (applied >= maxMinor) break;
      const value = Number(credit.amount_minor);
      // Partial spend is deliberately not supported: a credit is consumed
      // whole or left alone. Splitting one would need a second row and a
      // remainder to reconcile, for a rand or two of extra precision.
      if (applied + value > maxMinor) continue;
      await tx.query(
        'UPDATE user_credits SET consumed_at = now(), consumed_booking_id = $2 WHERE id = $1',
        [credit.id, bookingId],
      );
      applied += value;
    }
    return applied;
  }

  /** For the share sheet: how many have actually converted. */
  async summary(userId: string) {
    const rows = await this.db.query<{ status: string; n: string }>(
      `SELECT status, COUNT(*) AS n FROM referrals WHERE referrer_user_id = $1 GROUP BY status`,
      [userId],
    );
    const counts = Object.fromEntries(rows.map((r) => [r.status, Number(r.n)]));
    const balance = await this.balance(userId);
    return {
      invited: (counts.pending ?? 0) + (counts.qualified ?? 0),
      completed: counts.qualified ?? 0,
      creditMinor: balance.amountMinor,
      currency: balance.currency,
    };
  }
}
