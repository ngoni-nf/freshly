import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { EscrowService } from '../payments/escrow.service';
import { NotFoundError } from '../../common/errors/domain.errors';

@Injectable()
export class AdminService {
  constructor(
    private readonly db: DatabaseService,
    private readonly escrow: EscrowService,
  ) {}

  async getPulse() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const [stats, supply] = await Promise.all([
      this.db.queryOne<Record<string, any>>(`
        SELECT
          COUNT(*) FILTER (WHERE created_at >= $1) as bookings_today,
          SUM(total_minor) FILTER (WHERE created_at >= $1 AND status = 'completed') as gmv_today,
          COUNT(*) FILTER (WHERE status = 'completed' AND created_at >= $1) as completed_today,
          COUNT(*) FILTER (WHERE status IN ('cancelled', 'expired') AND created_at >= $1) as failed_today
        FROM bookings
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
      gmvTodayMinor: Number(stats?.gmv_today || 0),
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
    const [kyc, credentials, sos, disputes] = await Promise.all([
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM kyc_submissions WHERE status = 'pending'"),
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM provider_credentials WHERE status = 'pending'"),
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM sos_alerts WHERE status = 'armed'"),
      this.db.queryOne<{ count: string }>("SELECT COUNT(*) FROM bookings WHERE status = 'disputed'"),
    ]);

    return {
      kyc: Number(kyc?.count || 0),
      credentials: Number(credentials?.count || 0),
      sos: Number(sos?.count || 0),
      disputes: Number(disputes?.count || 0),
    };
  }

  async listMarkets() {
    return this.db.query('SELECT * FROM countries ORDER BY name');
  }

  async updateMarket(code: string, updates: Partial<Record<string, any>>) {
    const keys = Object.keys(updates);
    if (keys.length === 0) return;

    const setClause = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
    const values = Object.values(updates);

    await this.db.query(
      `UPDATE countries SET ${setClause}, updated_at = now() WHERE code = $1`,
      [code, ...values]
    );

    return { ok: true };
  }
}
