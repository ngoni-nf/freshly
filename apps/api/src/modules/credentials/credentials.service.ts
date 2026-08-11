import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../../common/database/database.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';

/**
 * Professional credentials for invasive services.
 *
 * KYC answers "who is this person". This answers "may they do that to
 * somebody". They are separate gates because they fail separately: a provider
 * with impeccable identity documents and no aesthetics qualification is
 * exactly who must not be dispatched to perform microneedling.
 *
 * The enforcement lives in the database — `trg_service_credential_guard` — for
 * the same reason the booking state machine does. This service is the way a
 * provider submits one and an admin reviews it; it is not the thing standing
 * between an unqualified person and a customer's face.
 */
@Injectable()
export class CredentialsService {
  private readonly logger = new Logger(CredentialsService.name);

  constructor(
    private readonly db: DatabaseService,
    private readonly crypto: PiiCryptoService,
  ) {}

  /**
   * What the provider holds, and what their market would require of them.
   * Returned together so the app can say "you need X to list Y" rather than
   * only refusing the listing later.
   */
  async status(providerId: string) {
    const provider = await this.db.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM providers WHERE id = $1',
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    const held = await this.db.query<Record<string, any>>(
      `SELECT id, category, credential_kind, issuer, reference_last4, status,
              expires_on, rejection_reason, created_at
         FROM provider_credentials
        WHERE provider_id = $1
        ORDER BY created_at DESC`,
      [providerId],
    );

    const rules = await this.db.query<Record<string, any>>(
      `SELECT category, credential_kind, regulator, in_shop_only, rationale
         FROM service_category_rules
        WHERE country_code = $1
        ORDER BY category`,
      [provider.country_code],
    );

    // Services already listed that are gated, and whether they are currently
    // covered. This is the number that matters: a lapsed licence silently
    // removes these from search.
    const gatedServices = await this.db.query<Record<string, any>>(
      `SELECT s.id, s.name, s.category,
              fn_provider_has_credential(s.provider_id, s.category) AS covered
         FROM services s
        WHERE s.provider_id = $1 AND s.requires_credential AND s.is_active`,
      [providerId],
    );

    return {
      countryCode: provider.country_code,
      credentials: held.map((c) => ({
        id: c.id,
        category: c.category,
        credentialKind: c.credential_kind,
        issuer: c.issuer,
        referenceLast4: c.reference_last4,
        status: c.status,
        expiresOn: c.expires_on ? c.expires_on.toISOString().slice(0, 10) : null,
        rejectionReason: c.rejection_reason,
        submittedAt: c.created_at.toISOString(),
      })),
      regulatedCategories: rules.map((r) => ({
        category: r.category,
        credentialKind: r.credential_kind,
        regulator: r.regulator,
        inShopOnly: r.in_shop_only,
        rationale: r.rationale,
      })),
      gatedServices: gatedServices.map((s) => ({
        id: s.id,
        name: s.name,
        category: s.category,
        covered: s.covered,
      })),
      // Listed separately because this is the actionable one: services the
      // provider is offering that their paperwork no longer covers.
      uncoveredServices: gatedServices.filter((s) => !s.covered).map((s) => s.name),
    };
  }

  async submit(
    providerId: string,
    input: {
      category: string;
      credentialKind: string;
      issuer?: string;
      reference?: string;
      documentKey?: string;
      expiresOn?: string;
    },
  ) {
    const provider = await this.db.queryOne<{ country_code: 'ZA' | 'ZW' }>(
      'SELECT country_code FROM providers WHERE id = $1',
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    // Refuse credentials for categories the market does not regulate, rather
    // than accumulating paperwork nobody will ever read.
    const rule = await this.db.queryOne<{ credential_kind: string | null }>(
      `SELECT credential_kind FROM service_category_rules
        WHERE country_code = $1 AND category = $2::service_category_enum`,
      [provider.country_code, input.category],
    );
    if (!rule) {
      throw new DomainError(
        'category_not_regulated',
        'That category does not require a credential in your country',
        HttpStatus.UNPROCESSABLE_ENTITY,
        { category: input.category },
      );
    }

    const reference = input.reference?.replace(/\s+/g, '');

    const row = await this.db.queryOne<{ id: string }>(
      `INSERT INTO provider_credentials
         (provider_id, category, credential_kind, issuer, reference_enc, reference_last4,
          document_key, expires_on, status)
       VALUES ($1, $2::service_category_enum, $3, $4, $5, $6, $7, $8, 'pending')
       ON CONFLICT (provider_id, category, credential_kind) DO UPDATE
         SET issuer = EXCLUDED.issuer,
             reference_enc = EXCLUDED.reference_enc,
             reference_last4 = EXCLUDED.reference_last4,
             document_key = EXCLUDED.document_key,
             expires_on = EXCLUDED.expires_on,
             status = 'pending',
             rejection_reason = NULL,
             reviewed_by = NULL,
             reviewed_at = NULL,
             created_at = now()
       RETURNING id`,
      [
        providerId,
        input.category,
        input.credentialKind,
        input.issuer ?? null,
        reference ? this.crypto.encrypt(reference) : null,
        reference ? PiiCryptoService.last4(reference) : null,
        input.documentKey ?? null,
        input.expiresOn ?? null,
      ],
    );

    this.logger.log(`credential submitted: provider ${providerId}, ${input.category}`);
    return { id: row!.id, status: 'pending' };
  }

  /**
   * A human decision, recorded against the reviewer. Nobody is auto-approved:
   * verifying a practitioner registration means looking it up on a regulator's
   * roll, which is not something to fake with a mock adapter.
   */
  async review(
    credentialId: string,
    reviewerUserId: string,
    decision: 'verified' | 'rejected',
    reason?: string,
  ) {
    const credential = await this.db.queryOne<{
      id: string;
      provider_id: string;
      category: string;
      status: string;
    }>('SELECT id, provider_id, category, status FROM provider_credentials WHERE id = $1', [
      credentialId,
    ]);
    if (!credential) throw new NotFoundError('Credential', credentialId);

    await this.db.transaction(async (tx) => {
      await tx.query(
        `UPDATE provider_credentials
            SET status = $2::credential_status_enum,
                rejection_reason = $3,
                reviewed_by = $4,
                reviewed_at = now()
          WHERE id = $1`,
        [credentialId, decision, reason ?? null, reviewerUserId],
      );

      // Withdrawing a credential must take the work off the market in the same
      // transaction. Discovery re-checks anyway, but a provider should not see
      // a live listing they are no longer allowed to fulfil.
      if (decision === 'rejected') {
        await tx.query(
          `UPDATE services
              SET is_active = false, updated_at = now()
            WHERE provider_id = $1 AND category = $2::service_category_enum
              AND requires_credential`,
          [credential.provider_id, credential.category],
        );
      }

      await tx.query(
        `INSERT INTO audit_log (actor_id, actor_role, action, entity_type, entity_id, before, after)
         VALUES ($1, 'admin', $2, 'provider_credential', $3, $4::jsonb, $5::jsonb)`,
        [
          reviewerUserId,
          `credential.${decision}`,
          credentialId,
          JSON.stringify({ status: credential.status }),
          JSON.stringify({ status: decision, reason: reason ?? null }),
        ],
      );

      await tx.emitEvent('provider', credential.provider_id, `credential.${decision}`, {
        credentialId,
        category: credential.category,
      });
    });

    this.logger.log(`credential ${credentialId} -> ${decision} by ${reviewerUserId}`);
    return { status: decision };
  }

  /** Queue for whoever is doing the verifying. */
  async pending(limit = 50) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT c.id, c.category, c.credential_kind, c.issuer, c.reference_last4, c.expires_on,
              c.created_at, p.display_name, p.country_code
         FROM provider_credentials c
         JOIN providers p ON p.id = c.provider_id
        WHERE c.status = 'pending'
        ORDER BY c.created_at
        LIMIT $1`,
      [limit],
    );

    return rows.map((r) => ({
      id: r.id,
      providerName: r.display_name,
      countryCode: r.country_code,
      category: r.category,
      credentialKind: r.credential_kind,
      issuer: r.issuer,
      referenceLast4: r.reference_last4,
      expiresOn: r.expires_on ? r.expires_on.toISOString().slice(0, 10) : null,
      submittedAt: r.created_at.toISOString(),
    }));
  }
}
