import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { EscrowService } from '../payments/escrow.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';
import { MarketsService } from '../markets/markets.service';

@Injectable()
export class AdminService {
  constructor(
    private readonly db: DatabaseService,
    private readonly escrow: EscrowService,
    private readonly markets: MarketsService,
  ) {}

  async getPulse() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [stats, gmv, supply] = await Promise.all([
      this.db.queryOne<Record<string, any>>(`
        SELECT
          COUNT(*) FILTER (WHERE created_at >= $1) as bookings_today,
          COUNT(*) FILTER (WHERE status = 'completed' AND created_at >= $1) as completed_today,
          COUNT(*) FILTER (WHERE status IN ('cancelled', 'expired') AND created_at >= $1) as failed_today
        FROM bookings
      `, [today]),
      // Per currency: rand and dollars do not add. Harare and Johannesburg
      // each get their own figure.
      this.db.query<{ currency: string; minor: string }>(`
        SELECT currency, SUM(total_minor) AS minor FROM bookings
         WHERE created_at >= $1 AND status = 'completed'
         GROUP BY currency ORDER BY currency
      `, [today]),
      this.db.queryOne<Record<string, any>>(`
        SELECT
          COUNT(*) FILTER (WHERE is_online = true) as online_providers,
          COUNT(*) FILTER (WHERE is_online = true AND kyc_status = 'verified') as verified_online,
          COUNT(*) FILTER (WHERE is_online = true AND EXISTS (
            SELECT 1 FROM bookings b WHERE b.provider_id = providers.id AND b.status IN ('accepted','en_route','arrived','in_progress')
          )) as busy_providers
        FROM providers
      `)
    ]);

    const bookingsToday = Number(stats?.bookings_today || 0);
    const completedToday = Number(stats?.completed_today || 0);
    const failedToday = Number(stats?.failed_today || 0);
    const totalEnded = completedToday + failedToday;

    const onlineProviders = Number(supply?.online_providers || 0);
    const busyProviders = Number(supply?.busy_providers || 0);
    const idleProviders = onlineProviders - busyProviders;

    return {
      gmvToday: gmv.map((g) => ({ currency: g.currency, minor: Number(g.minor) })),
      bookingsToday,
      completionRate: totalEnded > 0 ? (completedToday / totalEnded) * 100 : 0,
      onlineProviders,
      verifiedOnlineProviders: Number(supply?.verified_online || 0),
      idleProviders,
      demandIndex: onlineProviders > 0 ? (busyProviders / onlineProviders) * 10 : 0,
    };
  }

  async globalSearch(q: string) {
    const [providers, users, bookings] = await Promise.all([
      this.db.query(`
        SELECT id, display_name, phone_e164 as phone, 'provider' as type
        FROM providers p JOIN users u ON u.id = p.user_id
        WHERE display_name ILIKE '%' || $1 || '%' OR phone_e164 ILIKE '%' || $1 || '%'
        LIMIT 5
      `, [q]),
      this.db.query(`
        SELECT id, full_name as display_name, phone_e164 as phone, 'user' as type
        FROM users
        WHERE full_name ILIKE '%' || $1 || '%' OR phone_e164 ILIKE '%' || $1 || '%'
        LIMIT 5
      `, [q]),
      this.db.query(`
        SELECT id, reference as display_name, '' as phone, 'booking' as type
        FROM bookings
        WHERE reference ILIKE '%' || $1 || '%'
        LIMIT 5
      `, [q])
    ]);

    return [...providers, ...users, ...bookings];
  }

  async listDisputed() {
    const rows = await this.db.query<Record<string, any>>(`
      SELECT b.id, b.reference, b.status, b.created_at, b.total_minor, b.currency,
             u.full_name as client_name, p.display_name as provider_name
      FROM bookings b
      JOIN users u ON u.id = b.client_id
      LEFT JOIN providers p ON p.id = b.provider_id
      WHERE b.status = 'disputed'
      ORDER BY b.created_at DESC
    `);

    return rows.map((r) => ({
      id: r.id,
      reference: r.reference,
      status: r.status,
      createdAt: r.created_at.toISOString(),
      total: { minor: Number(r.total_minor), currency: r.currency },
      clientName: r.client_name,
      providerName: r.provider_name || 'Unassigned',
    }));
  }

  async resolveDispute(bookingId: string, decision: 'refund_client' | 'release_to_pro') {
    const booking = await this.db.queryOne<{ status: string }>(
      'SELECT status FROM bookings WHERE id = $1', [bookingId]
    );
    if (!booking) throw new NotFoundError('Booking', bookingId);

    if (decision === 'refund_client') {
      await this.escrow.release(bookingId, 'dispute_resolved_refund');
      await this.db.query("UPDATE bookings SET status = 'cancelled' WHERE id = $1", [bookingId]);
    } else {
      await this.escrow.capture(bookingId);
      await this.db.query("UPDATE bookings SET status = 'completed' WHERE id = $1", [bookingId]);
    }

    return { ok: true, status: decision === 'refund_client' ? 'cancelled' : 'completed' };
  }

  async getBadges() {
    const [kyc, credentials, sos, payoutAccounts, disputes] = await Promise.all([
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM kyc_submissions WHERE status = 'pending'"),
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM provider_credentials WHERE status = 'pending'"),
      // Every alert nobody has resolved yet, not only the ones still arming:
      // a dispatched emergency is the one that needs a person most.
      this.db.queryOne<{ count: string }>(
        "SELECT COUNT(*) FROM sos_events WHERE status IN ('armed','dispatched','acknowledged')",
      ),
      this.db.queryOne<{ count: string }>(
        'SELECT COUNT(*) FROM payout_accounts WHERE NOT is_verified AND is_default',
      ),
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM bookings WHERE status = 'disputed'"),
    ]);

    return {
      kyc: Number(kyc?.count || 0),
      credentials: Number(credentials?.count || 0),
      sos: Number(sos?.count || 0),
      payoutAccounts: Number(payoutAccounts?.count || 0),
      disputes: Number(disputes?.count || 0),
    };
  }

  async listMarkets() {
    return this.db.query('SELECT * FROM countries ORDER BY name');
  }

  /**
   * The columns an admin may change from the console. Column names used to
   * come straight from the request body into the SQL, which made every admin
   * token a way to run arbitrary SQL against `countries`.
   */
  private static readonly EDITABLE_MARKET_COLUMNS = new Set([
    'commission_bps', 'service_fee_minor', 'travel_fee_per_km_minor', 'travel_fee_free_km',
    'vat_bps', 'cancellation_window_minutes', 'cancellation_fee_bps', 'no_show_grace_minutes',
    'dispatch_offer_seconds', 'max_search_radius_km', 'min_payout_minor', 'is_live',
  ]);

  async updateMarket(code: string, updates: Partial<Record<string, any>>) {
    const keys = Object.keys(updates).filter((k) => AdminService.EDITABLE_MARKET_COLUMNS.has(k));
    const refused = Object.keys(updates).filter((k) => !AdminService.EDITABLE_MARKET_COLUMNS.has(k));
    if (refused.length) {
      throw new DomainError('market_field_not_editable', `These fields cannot be changed here: ${refused.join(', ')}`);
    }
    if (keys.length === 0) return { ok: true };

    const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
    const values = keys.map((k) => updates[k]);

    await this.db.query(
      `UPDATE countries SET ${setClause}, updated_at = now() WHERE code = $1`,
      [code, ...values],
    );
    await this.markets.refresh();

    return { ok: true };
  }

  /** Payout accounts waiting for a human: anything not auto-verified at creation. */
  async listUnverifiedPayoutAccounts() {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT a.id, a.method, a.institution_name, a.account_name, a.account_last4, a.currency,
              a.created_at, p.id AS provider_id, p.display_name, p.kyc_status, u.phone_e164,
              w.available_minor
         FROM payout_accounts a
         JOIN providers p ON p.id = a.provider_id
         JOIN users u ON u.id = p.user_id
         LEFT JOIN provider_wallets w ON w.provider_id = p.id
        WHERE NOT a.is_verified AND a.is_default
        ORDER BY a.created_at`,
    );
    return rows.map((r) => ({
      id: r.id,
      method: r.method,
      institutionName: r.institution_name,
      accountName: r.account_name,
      last4: r.account_last4,
      currency: r.currency,
      createdAt: r.created_at.toISOString(),
      provider: {
        id: r.provider_id,
        displayName: r.display_name,
        kycStatus: r.kyc_status,
        phone: r.phone_e164,
      },
      availableMinor: Number(r.available_minor ?? 0),
    }));
  }

  /**
   * Mark a payout account verified, or refuse it. The account-holder name
   * is what ops compares against the identity document; the number itself
   * stays encrypted and is never shown.
   */
  async reviewPayoutAccount(
    accountId: string,
    actorUserId: string,
    decision: 'verified' | 'rejected',
    reason?: string,
  ) {
    const account = await this.db.queryOne<{ id: string; provider_id: string; is_verified: boolean }>(
      'SELECT id, provider_id, is_verified FROM payout_accounts WHERE id = $1',
      [accountId],
    );
    if (!account) throw new NotFoundError('Payout account', accountId);

    await this.db.transaction(async (tx) => {
      if (decision === 'verified') {
        await tx.query('UPDATE payout_accounts SET is_verified = true WHERE id = $1', [accountId]);
      } else {
        // A refused account is removed as the default so the wallet says
        // "add a payout account" again instead of "still being verified".
        await tx.query(
          'UPDATE payout_accounts SET is_verified = false, is_default = false WHERE id = $1',
          [accountId],
        );
      }
      await tx.query(
        `INSERT INTO audit_log (actor_id, actor_role, action, entity_type, entity_id, before, after)
         VALUES ($1, 'admin', $2, 'payout_account', $3, $4::jsonb, $5::jsonb)`,
        [
          actorUserId,
          decision === 'verified' ? 'payout_account.verified' : 'payout_account.rejected',
          accountId,
          JSON.stringify({ isVerified: account.is_verified }),
          JSON.stringify({ decision, reason: reason ?? null, providerId: account.provider_id }),
        ],
      );
    });
    return { id: accountId, decision };
  }
}
