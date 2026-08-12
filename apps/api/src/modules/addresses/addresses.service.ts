import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { NotFoundError } from '../../common/errors/domain.errors';
import { MarketsService } from '../markets/markets.service';

export interface AddressInput {
  label: string;
  formatted: string;
  lat: number;
  lng: number;
  unitNotes?: string;
  accessNotes?: string;
  isDefault?: boolean;
}

/**
 * Places somebody books to, saved.
 *
 * `saved_addresses` has been in the schema since the first migration with no
 * endpoints, so every booking has required a fresh GPS fix — which is wrong
 * whenever the job is not where the phone is. Booking for your mother, or at
 * the office, meant fighting the location picker.
 *
 * The address is validated against the geofence on the way in rather than at
 * checkout. Letting somebody save "Mom's" and only discovering at payment that
 * we do not serve it is the same failure the suburb autocomplete was built to
 * avoid, one screen later.
 *
 * Access notes matter more here than they look: "buzzer 4B, dog in the yard"
 * is the difference between a provider arriving and a provider standing at a
 * gate. They are handed over only once a booking is accepted.
 */
@Injectable()
export class AddressesService {
  constructor(
    private readonly db: DatabaseService,
    private readonly markets: MarketsService,
  ) {}

  async list(userId: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT id, label, formatted, unit_notes, access_notes, is_default,
              ST_Y(location::geometry) AS lat,
              ST_X(location::geometry) AS lng
         FROM saved_addresses
        WHERE user_id = $1
        ORDER BY is_default DESC, label`,
      [userId],
    );
    return rows.map((r) => this.toAddress(r));
  }

  async create(userId: string, input: AddressInput) {
    // Throws if the point is outside every live area, with the same error the
    // rest of the product uses for it.
    await this.markets.resolveServiceArea(input.lat, input.lng);

    return this.db.transaction(async (tx) => {
      if (input.isDefault) {
        await tx.query(
          'UPDATE saved_addresses SET is_default = false WHERE user_id = $1',
          [userId],
        );
      }

      const row = await tx.queryOne<Record<string, any>>(
        `INSERT INTO saved_addresses
           (user_id, label, formatted, unit_notes, access_notes, location, is_default)
         VALUES ($1, $2, $3, $4, $5,
                 ST_SetSRID(ST_MakePoint($6, $7), 4326)::geography,
                 -- The first address saved becomes the default, because a
                 -- default nobody chose is better than none at all.
                 COALESCE($8, NOT EXISTS (SELECT 1 FROM saved_addresses WHERE user_id = $1)))
         RETURNING id, label, formatted, unit_notes, access_notes, is_default,
                   ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng`,
        [
          userId, input.label, input.formatted, input.unitNotes ?? null,
          input.accessNotes ?? null, input.lng, input.lat, input.isDefault ?? null,
        ],
      );
      return this.toAddress(row!);
    });
  }

  async update(userId: string, id: string, input: Partial<AddressInput>) {
    const existing = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM saved_addresses WHERE id = $1 AND user_id = $2',
      [id, userId],
    );
    if (!existing) throw new NotFoundError('Address', id);

    if (input.lat !== undefined && input.lng !== undefined) {
      await this.markets.resolveServiceArea(input.lat, input.lng);
    }

    return this.db.transaction(async (tx) => {
      if (input.isDefault) {
        await tx.query(
          'UPDATE saved_addresses SET is_default = false WHERE user_id = $1',
          [userId],
        );
      }

      const row = await tx.queryOne<Record<string, any>>(
        `UPDATE saved_addresses SET
           label        = COALESCE($3, label),
           formatted    = COALESCE($4, formatted),
           unit_notes   = COALESCE($5, unit_notes),
           access_notes = COALESCE($6, access_notes),
           is_default   = COALESCE($7, is_default),
           location     = CASE WHEN $8::numeric IS NULL THEN location
                          ELSE ST_SetSRID(ST_MakePoint($8, $9), 4326)::geography END
         WHERE id = $1 AND user_id = $2
         RETURNING id, label, formatted, unit_notes, access_notes, is_default,
                   ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng`,
        [
          id, userId, input.label ?? null, input.formatted ?? null,
          input.unitNotes ?? null, input.accessNotes ?? null,
          input.isDefault ?? null, input.lng ?? null, input.lat ?? null,
        ],
      );
      return this.toAddress(row!);
    });
  }

  async remove(userId: string, id: string): Promise<{ ok: true }> {
    const row = await this.db.queryOne<{ id: string; is_default: boolean }>(
      'DELETE FROM saved_addresses WHERE id = $1 AND user_id = $2 RETURNING id, is_default',
      [id, userId],
    );
    if (!row) throw new NotFoundError('Address', id);

    // Never leave somebody with addresses but no default.
    if (row.is_default) {
      await this.db.query(
        `UPDATE saved_addresses SET is_default = true
          WHERE id = (SELECT id FROM saved_addresses WHERE user_id = $1 ORDER BY label LIMIT 1)`,
        [userId],
      );
    }
    return { ok: true };
  }

  private toAddress(r: Record<string, any>) {
    return {
      id: r.id,
      label: r.label,
      formatted: r.formatted,
      unitNotes: r.unit_notes,
      accessNotes: r.access_notes,
      isDefault: r.is_default,
      lat: Number(r.lat),
      lng: Number(r.lng),
    };
  }
}
