import { HttpStatus, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';

/**
 * The service catalogue.
 *
 * Two audiences, one list. A client browses it to find "knotless braids"
 * across every provider who offers it; a provider builds their menu from it
 * instead of typing a name nobody else will match.
 */
@Injectable()
export class CatalogService {
  constructor(private readonly db: DatabaseService) {}

  /** Every specialization that has something bookable in it. */
  async categories() {
    const rows = await this.db.query<{ category: string; services: string; invasive: string }>(
      `SELECT category, COUNT(*) AS services,
              COUNT(*) FILTER (WHERE is_invasive) AS invasive
         FROM service_templates
        WHERE is_active
        GROUP BY category
        ORDER BY category`,
    );

    return rows.map((r) => ({
      category: r.category,
      serviceCount: Number(r.services),
      // Surfaced so the app can explain why some services are premises-only
      // rather than letting it look like an arbitrary restriction.
      licensedCount: Number(r.invasive),
    }));
  }

  async services(category?: string) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT id, category, slug, name, description, typical_duration_minutes,
              requires_power, is_invasive
         FROM service_templates
        WHERE is_active
          AND ($1::service_category_enum IS NULL OR category = $1::service_category_enum)
        ORDER BY category, sort_order, name`,
      [category ?? null],
    );

    return rows.map((r) => ({
      id: r.id,
      category: r.category,
      slug: r.slug,
      name: r.name,
      description: r.description,
      typicalDurationMinutes: r.typical_duration_minutes,
      requiresPower: r.requires_power,
      requiresLicence: r.is_invasive,
    }));
  }

  /**
   * A provider adds a service to their menu.
   *
   * The name, the category and whether it is invasive come from the template,
   * never from the request. This is the endpoint migration 009 was written for
   * — its comment says requires_credential must be derived from a template and
   * not from provider input, and until now nothing did the deriving.
   *
   * The database still has the final say: the credential trigger refuses an
   * invasive service from an unlicensed provider, and refuses any of them as a
   * mobile booking.
   */
  async addToMenu(
    providerId: string,
    input: { templateId: string; priceMinor: number; durationMinutes?: number; venueMode?: string },
  ) {
    const template = await this.db.queryOne<Record<string, any>>(
      'SELECT * FROM service_templates WHERE id = $1 AND is_active',
      [input.templateId],
    );
    if (!template) throw new NotFoundError('Service template', input.templateId);

    const provider = await this.db.queryOne<{ payout_currency: string; venue_mode: string }>(
      'SELECT payout_currency, venue_mode FROM providers WHERE id = $1',
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    // A provider who only works in shop cannot list a mobile service, whatever
    // the request says.
    const venue =
      provider.venue_mode === 'both' ? (input.venueMode ?? 'both') : provider.venue_mode;

    try {
      const row = await this.db.queryOne<{ id: string; requires_credential: boolean }>(
        `INSERT INTO services
           (provider_id, template_id, name, description, category, venue_mode,
            price_minor, currency, duration_minutes, requires_power)
         VALUES ($1, $2, $3, $4, $5::service_category_enum, $6::service_venue_enum,
                 $7, $8::currency_code_enum, $9, $10)
         RETURNING id, requires_credential`,
        [
          providerId,
          template.id,
          template.name,
          template.description,
          template.category,
          venue,
          input.priceMinor,
          provider.payout_currency,
          input.durationMinutes ?? template.typical_duration_minutes,
          template.requires_power,
        ],
      );

      return {
        id: row!.id,
        name: template.name,
        category: template.category,
        requiresCredential: row!.requires_credential,
      };
    } catch (err) {
      // The trigger raises check_violation for the two refusals that matter,
      // and its message is already written for a person.
      if ((err as { code?: string }).code === '23514') {
        throw new DomainError(
          'service_not_permitted',
          (err as Error).message.replace(/^[a-z_]+ /, ''),
          HttpStatus.CONFLICT,
        );
      }
      throw err;
    }
  }

  /** A provider's own menu, including anything currently withdrawn. */
  /**
   * Take a service off the menu.
   *
   * Deleted outright only when nothing has ever been booked against it.
   * A service that appears in a booking is referenced by `booking_items`, and
   * that row is part of an order somebody paid for — the price it charged and
   * the ledger entries that settled it. Deleting it would either fail on the
   * foreign key or, worse, take history with it.
   *
   * So a used service is deactivated instead. It stops being offered, which is
   * the only thing the provider asked for, and every past booking keeps its
   * own `name_snapshot` regardless.
   */
  async removeFromMenu(providerId: string, serviceId: string): Promise<{ ok: true }> {
    const service = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM services WHERE id = $1 AND provider_id = $2',
      [serviceId, providerId],
    );
    if (!service) throw new NotFoundError('Service', serviceId);

    const used = await this.db.queryOne<{ id: string }>(
      'SELECT id FROM booking_items WHERE service_id = $1 LIMIT 1',
      [serviceId],
    );

    if (used) {
      await this.db.query('UPDATE services SET is_active = false WHERE id = $1', [serviceId]);
    } else {
      await this.db.query('DELETE FROM services WHERE id = $1', [serviceId]);
    }
    return { ok: true };
  }

  async menu(providerId: string) {
    const rows = await this.db.query<Record<string, any>>(
      // Active only: this is what the provider currently offers, and a
      // deactivated service that stayed on the list would make removing one
      // look like it had failed.
      `SELECT s.id, s.name, s.category, s.price_minor, s.currency, s.duration_minutes,
              s.venue_mode, s.is_active, s.requires_credential, s.template_id
         FROM services s
        WHERE s.provider_id = $1 AND s.is_active
        ORDER BY s.category, s.sort_order, s.name`,
      [providerId],
    );

    return rows.map((r) => ({
      id: r.id,
      name: r.name,
      category: r.category,
      price: { minor: Number(r.price_minor), currency: r.currency },
      durationMinutes: r.duration_minutes,
      venueMode: r.venue_mode,
      isActive: r.is_active,
      requiresCredential: r.requires_credential,
      fromCatalogue: r.template_id !== null,
    }));
  }
}
