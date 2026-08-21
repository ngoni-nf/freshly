import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../common/database/database.service';
import { PiiCryptoService } from '../../common/crypto/pii-crypto.service';
import { DomainError, NotFoundError } from '../../common/errors/domain.errors';
import { KycCallbackEvent, KycOutcome, KycProvider, KycResult } from './providers/kyc-provider.interface';
import { MockKycProvider } from './providers/mock.kyc-provider';
import { SmileIdKycProvider } from './providers/smileid.kyc-provider';
import { SumsubKycProvider } from './providers/sumsub.kyc-provider';
import { StorageService } from '../storage/storage.service';

/** Vendor outcomes map onto the database enum; there is no third vocabulary. */
const OUTCOME_TO_STATUS: Record<KycOutcome, string> = {
  pending: 'pending',
  in_review: 'in_review',
  verified: 'verified',
  rejected: 'rejected',
};

@Injectable()
export class KycService {
  private readonly logger = new Logger(KycService.name);
  private readonly providers = new Map<string, KycProvider>();

  constructor(
    private readonly db: DatabaseService,
    private readonly config: ConfigService,
    private readonly crypto: PiiCryptoService,
    private readonly storage: StorageService,
  ) {
    this.providers.set('mock', new MockKycProvider());
    this.providers.set(
      'smileid',
      new SmileIdKycProvider({
        partnerId: this.config.get<string>('SMILE_ID_PARTNER_ID'),
        apiKey: this.config.get<string>('SMILE_ID_API_KEY'),
        callbackUrl: this.config.get<string>('SMILE_ID_CALLBACK_URL'),
        baseUrl: this.config.get<string>('SMILE_ID_BASE_URL') ?? 'https://api.smileidentity.com',
      }),
    );
    this.providers.set(
      'sumsub',
      new SumsubKycProvider({
        appToken: this.config.get<string>('SUMSUB_APP_TOKEN'),
        secretKey: this.config.get<string>('SUMSUB_SECRET_KEY'),
        webhookSecret: this.config.get<string>('SUMSUB_WEBHOOK_SECRET'),
        levelName: this.config.get<string>('SUMSUB_LEVEL_NAME') ?? 'basic-kyc-level',
        baseUrl: this.config.get<string>('SUMSUB_BASE_URL') ?? 'https://api.sumsub.com',
      }),
    );
  }

  private providerFor(): KycProvider {
    const configured = this.config.get<string>('KYC_PROVIDER') ?? 'mock';
    return this.providers.get(configured) ?? this.providers.get('mock')!;
  }

  async status(providerId: string) {
    const provider = await this.db.queryOne<{
      kyc_status: string;
      kyc_verified_at: Date | null;
      country_code: 'ZA' | 'ZW';
    }>('SELECT kyc_status, kyc_verified_at, country_code FROM providers WHERE id = $1', [providerId]);
    if (!provider) throw new NotFoundError('Provider', providerId);

    const submission = await this.db.queryOne<{
      id: string;
      document_type: string;
      id_number_last4: string | null;
      status: string;
      rejection_reason: string | null;
      created_at: Date;
    }>(
      `SELECT id, document_type, id_number_last4, status, rejection_reason, created_at
         FROM kyc_submissions WHERE provider_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [providerId],
    );

    return {
      status: provider.kyc_status,
      verifiedAt: provider.kyc_verified_at?.toISOString() ?? null,
      countryCode: provider.country_code,
      // The whole point of the screen: what to do next.
      canAcceptBookings: provider.kyc_status === 'verified',
      latestSubmission: submission
        ? {
            id: submission.id,
            documentType: submission.document_type,
            idNumberLast4: submission.id_number_last4,
            status: submission.status,
            rejectionReason: submission.rejection_reason,
            submittedAt: submission.created_at.toISOString(),
          }
        : null,
    };
  }

  /**
   * Submit documents for verification.
   *
   * The ID number is encrypted before it touches a disk and only its last four
   * digits are stored in the clear, which is all any screen ever needs to show
   * — POPIA s19 and the Zimbabwe DPA both require that, and a table dump is
   * the realistic breach, not a live attacker.
   */
  async submit(
    providerId: string,
    input: {
      documentType: string;
      idNumber: string;
      fullName: string;
      dateOfBirth?: string;
      documentFrontKey?: string;
      documentBackKey?: string;
      selfieKey?: string;
    },
  ) {
    const provider = await this.db.queryOne<{ country_code: 'ZA' | 'ZW'; kyc_status: string }>(
      'SELECT country_code, kyc_status FROM providers WHERE id = $1',
      [providerId],
    );
    if (!provider) throw new NotFoundError('Provider', providerId);

    if (provider.kyc_status === 'verified') {
      throw new DomainError(
        'kyc_already_verified',
        'Your identity is already verified',
        HttpStatus.CONFLICT,
      );
    }
    // A resubmission while one is genuinely in flight would create a second
    // job and a second bill for the same person.
    if (provider.kyc_status === 'pending' || provider.kyc_status === 'in_review') {
      const inFlight = await this.db.queryOne<{ id: string }>(
        `SELECT id FROM kyc_submissions
          WHERE provider_id = $1 AND status IN ('pending','in_review')
            AND created_at > now() - INTERVAL '24 hours'
          LIMIT 1`,
        [providerId],
      );
      if (inFlight) {
        throw new DomainError(
          'kyc_in_progress',
          'Your documents are still being checked',
          HttpStatus.CONFLICT,
        );
      }
    }

    const vendor = this.providerFor();
    if (!vendor.supports(provider.country_code)) {
      throw new DomainError(
        'kyc_unavailable',
        'Identity verification is not available in your country yet',
        HttpStatus.UNPROCESSABLE_ENTITY,
        { countryCode: provider.country_code, provider: vendor.name },
      );
    }

    const idNumber = input.idNumber.replace(/\s+/g, '');
    const submission = await this.db.queryOne<{ id: string }>(
      `INSERT INTO kyc_submissions
         (provider_id, document_type, id_number_enc, id_number_last4,
          document_front_key, document_back_key, selfie_key, external_provider, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
       RETURNING id`,
      [
        providerId,
        input.documentType,
        this.crypto.encrypt(idNumber),
        PiiCryptoService.last4(idNumber),
        input.documentFrontKey ?? null,
        input.documentBackKey ?? null,
        input.selfieKey ?? null,
        vendor.name,
      ],
    );

    await this.db.query(
      `UPDATE providers SET kyc_status = 'pending', updated_at = now() WHERE id = $1`,
      [providerId],
    );

    let result: KycResult;
    try {
      result = await vendor.submit({
        submissionId: submission!.id,
        providerId,
        countryCode: provider.country_code,
        documentType: input.documentType,
        idNumber,
        fullName: input.fullName,
        dateOfBirth: input.dateOfBirth,
        documentFrontKey: input.documentFrontKey,
        documentBackKey: input.documentBackKey,
        selfieKey: input.selfieKey,
        callbackUrl: this.config.get<string>('SMILE_ID_CALLBACK_URL'),
      });
    } catch (err) {
      // The submission row stays `pending` on purpose. It is the audit trail
      // that someone tried, and support needs to see it to explain the delay.
      this.logger.error(`kyc submit failed for ${providerId}: ${(err as Error).message}`);
      throw new DomainError(
        'kyc_submit_failed',
        'We could not submit your documents. Please try again shortly.',
        HttpStatus.BAD_GATEWAY,
      );
    }

    await this.applyOutcome(submission!.id, providerId, result);

    return {
      submissionId: submission!.id,
      status: OUTCOME_TO_STATUS[result.outcome],
      rejectionReason: result.rejectionReason ?? null,
    };
  }

  /**
   * Apply a verification result to both the submission and the provider.
   *
   * Losing verification takes the provider offline in the same transaction.
   * Leaving someone online with a revoked identity, even for the seconds until
   * a background job notices, is the failure this whole module exists to
   * prevent.
   */
  private async applyOutcome(
    submissionId: string,
    providerId: string,
    result: { outcome: KycOutcome; externalReference?: string; livenessScore?: number | null; faceMatchScore?: number | null; rejectionReason?: string; raw?: Record<string, unknown> },
  ): Promise<void> {
    const status = OUTCOME_TO_STATUS[result.outcome];

    await this.db.transaction(async (tx) => {
      await tx.query(
        `UPDATE kyc_submissions
            SET status = $2::kyc_status_enum,
                external_reference = COALESCE($3, external_reference),
                liveness_score = $4,
                face_match_score = $5,
                rejection_reason = $6,
                external_payload = COALESCE($7::jsonb, external_payload),
                reviewed_at = CASE WHEN $2 IN ('verified','rejected') THEN now() ELSE reviewed_at END
          WHERE id = $1`,
        [
          submissionId,
          status,
          result.externalReference ?? null,
          result.livenessScore ?? null,
          result.faceMatchScore ?? null,
          result.rejectionReason ?? null,
          result.raw ? JSON.stringify(result.raw) : null,
        ],
      );

      await tx.query(
        `UPDATE providers
            SET kyc_status = $2::kyc_status_enum,
                kyc_verified_at = CASE WHEN $2 = 'verified' THEN now() ELSE NULL END,
                is_online = CASE WHEN $2 = 'verified' THEN is_online ELSE false END,
                updated_at = now()
          WHERE id = $1`,
        [providerId, status],
      );

      await tx.emitEvent('provider', providerId, `kyc.${status}`, {
        submissionId,
        rejectionReason: result.rejectionReason ?? null,
      });
    });

    this.logger.log(`provider ${providerId} kyc -> ${status}`);
  }

  /** Asynchronous verification result, which is how most of them arrive. */
  async handleCallback(providerName: string, signature: string, rawBody: string) {
    const vendor = this.providers.get(providerName);
    if (!vendor) throw new NotFoundError('KYC provider', providerName);

    if (!vendor.verifyCallback(signature, rawBody)) {
      throw new DomainError(
        'invalid_signature',
        'Signature verification failed',
        HttpStatus.UNAUTHORIZED,
      );
    }

    const event: KycCallbackEvent = vendor.parseCallback(rawBody);

    const recorded = await this.db.query<{ id: string }>(
      `INSERT INTO gateway_webhooks (provider_name, event_id, event_type, payload, signature_valid, processed_at)
       VALUES ($1, $2, $3, $4, true, now())
       ON CONFLICT (provider_name, event_id) DO NOTHING
       RETURNING id`,
      [providerName, `${event.externalReference}:${event.outcome}`, `kyc.${event.outcome}`, rawBody],
    );
    if (!recorded.length) return { ok: true };

    const submission = await this.db.queryOne<{ id: string; provider_id: string }>(
      'SELECT id, provider_id FROM kyc_submissions WHERE external_reference = $1',
      [event.externalReference],
    );
    if (!submission) {
      this.logger.warn(`kyc callback for unknown reference ${event.externalReference}`);
      return { ok: true };
    }

    await this.applyOutcome(submission.id, submission.provider_id, event);
    return { ok: true };
  }

  /**
   * The review queue.
   *
   * `in_review` first and oldest first, because those are the ones a human has
   * been asked to decide and a provider is waiting on. `pending` is included
   * because a vendor callback that never arrives leaves a submission stuck
   * there forever, and nobody would otherwise notice.
   */
  async pending(limit = 50) {
    const rows = await this.db.query<Record<string, any>>(
      `SELECT s.id, s.status, s.document_type, s.id_number_last4, s.liveness_score,
              s.face_match_score, s.created_at, s.document_front_key, s.document_back_key,
              s.selfie_key, p.id AS provider_id, p.display_name, p.country_code, u.full_name
         FROM kyc_submissions s
         JOIN providers p ON p.id = s.provider_id
         JOIN users u ON u.id = p.user_id
        WHERE s.status IN ('pending', 'in_review')
        ORDER BY (s.status = 'in_review') DESC, s.created_at
        LIMIT $1`,
      [limit],
    );

    return rows.map((r) => ({
      id: r.id,
      providerId: r.provider_id,
      providerName: r.display_name,
      legalName: r.full_name,
      countryCode: r.country_code,
      status: r.status,
      documentType: r.document_type,
      idNumberLast4: r.id_number_last4,
      livenessScore: r.liveness_score === null ? null : Number(r.liveness_score),
      faceMatchScore: r.face_match_score === null ? null : Number(r.face_match_score),
      // Keys only. The reviewer asks for a signed URL separately, so a link to
      // somebody's passport is never sitting in a list response.
      hasDocuments: Boolean(r.document_front_key || r.selfie_key),
      submittedAt: r.created_at.toISOString(),
    }));
  }

  /**
   * Short-lived links to a submission's documents, for a reviewer.
   *
   * Separate from the provider-facing storage route, which only ever returns a
   * file to its owner. A reviewer legitimately needs to see someone else's ID,
   * so the check here is the role, and every issued link expires in minutes.
   */
  async documents(submissionId: string, reviewerUserId: string) {
    const row = await this.db.queryOne<{
      document_front_key: string | null;
      document_back_key: string | null;
      selfie_key: string | null;
    }>(
      `SELECT document_front_key, document_back_key, selfie_key
         FROM kyc_submissions WHERE id = $1`,
      [submissionId],
    );
    if (!row) throw new NotFoundError('KYC submission', submissionId);

    const wanted: Array<[string, string | null]> = [
      ['front', row.document_front_key],
      ['back', row.document_back_key],
      ['selfie', row.selfie_key],
    ];

    const links: Record<string, { url: string; expiresIn: number }> = {};
    for (const [label, key] of wanted) {
      if (!key) continue;
      links[label] = await this.storage.signDownload('kyc-documents', key);
    }

    // Looking at someone's identity document is an event worth recording.
    await this.db.query(
      `INSERT INTO audit_log (actor_id, actor_role, action, entity_type, entity_id, after)
       VALUES ($1, 'admin', 'kyc.documents_viewed', 'kyc_submission', $2, $3::jsonb)`,
      [reviewerUserId, submissionId, JSON.stringify({ viewed: Object.keys(links) })],
    );

    return links;
  }

  /**
   * Manual decision by a reviewer, for everything that lands in `in_review`.
   * Recorded against the reviewer's user id — an approval nobody is
   * accountable for is not a control.
   */
  async review(
    submissionId: string,
    reviewerUserId: string,
    decision: 'verified' | 'rejected',
    reason?: string,
  ) {
    const submission = await this.db.queryOne<{ id: string; provider_id: string; status: string }>(
      'SELECT id, provider_id, status FROM kyc_submissions WHERE id = $1',
      [submissionId],
    );
    if (!submission) throw new NotFoundError('KYC submission', submissionId);

    await this.db.query('UPDATE kyc_submissions SET reviewed_by = $2 WHERE id = $1', [
      submissionId,
      reviewerUserId,
    ]);
    await this.applyOutcome(submissionId, submission.provider_id, {
      outcome: decision,
      rejectionReason: reason,
    });

    await this.db.query(
      `INSERT INTO audit_log (actor_id, actor_role, action, entity_type, entity_id, before, after)
       VALUES ($1, 'admin', $2, 'kyc_submission', $3, $4::jsonb, $5::jsonb)`,
      [
        reviewerUserId,
        `kyc.${decision}`,
        submissionId,
        JSON.stringify({ status: submission.status }),
        JSON.stringify({ status: decision, reason: reason ?? null }),
      ],
    );

    return { status: decision };
  }
}
