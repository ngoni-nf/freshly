import { Logger } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  KycCallbackEvent, KycOutcome, KycProvider, KycResult, KycSubmission,
} from './kyc-provider.interface';

export interface SmileIdConfig {
  partnerId?: string;
  apiKey?: string;
  callbackUrl?: string;
  baseUrl: string;
}

/**
 * Smile ID — identity verification across both markets.
 *
 * Chosen because it queries the actual national registries: Home Affairs in
 * South Africa and the Registrar General in Zimbabwe. A vendor that only OCRs
 * the document and compares a selfie will happily verify a well-made forgery,
 * which for a service that sends someone into a customer's home is not a
 * theoretical distinction.
 *
 * The signature scheme and the result-code mapping are implemented here. The
 * request body is not sent blind: enabling this provider requires confirming
 * the job payload against the partner account's configured product, because
 * the fields differ per product and a wrong one fails open — returning a
 * "success" that verified nothing.
 */
export class SmileIdKycProvider implements KycProvider {
  readonly name = 'smileid';
  readonly answersSynchronously = false;
  private readonly logger = new Logger('SmileIdKycProvider');

  constructor(private readonly config: SmileIdConfig) {}

  supports(countryCode: 'ZA' | 'ZW'): boolean {
    return countryCode === 'ZA' || countryCode === 'ZW';
  }

  async submit(_submission: KycSubmission): Promise<KycResult> {
    if (!this.config.partnerId || !this.config.apiKey) {
      throw new Error('SMILE_ID_PARTNER_ID and SMILE_ID_API_KEY must be set to verify identities');
    }
    if (!this.config.callbackUrl) {
      // Without a callback the result never arrives and every provider sits in
      // `pending` forever, unable to work and unable to see why.
      throw new Error('SMILE_ID_CALLBACK_URL must be set; results arrive asynchronously');
    }

    this.signature();

    throw new Error(
      'SmileIdKycProvider.submit is not enabled — confirm the job payload against the ' +
        'partner account product configuration, then remove this guard',
    );
  }

  /**
   * Smile ID signs with an HMAC-SHA256 over timestamp, partner id and a fixed
   * literal, keyed by the API key, base64 encoded. The same construction is
   * used to authenticate our requests and to verify their callbacks.
   */
  private signature(timestamp = new Date().toISOString()): { signature: string; timestamp: string } {
    const mac = createHmac('sha256', this.config.apiKey!)
      .update(timestamp)
      .update(String(this.config.partnerId))
      .update('sid_request')
      .digest('base64');
    return { signature: mac, timestamp };
  }

  verifyCallback(signature: string, body: string): boolean {
    if (!this.config.apiKey || !signature) return false;

    let timestamp: string;
    try {
      timestamp = String((JSON.parse(body) as Record<string, unknown>).timestamp ?? '');
    } catch {
      return false;
    }
    if (!timestamp) return false;

    const expected = Buffer.from(this.signature(timestamp).signature, 'base64');
    const received = Buffer.from(signature, 'base64');
    if (received.length !== expected.length) return false;
    return timingSafeEqual(received, expected);
  }

  parseCallback(body: string): KycCallbackEvent {
    const event = JSON.parse(body) as Record<string, any>;
    const resultCode = String(event.ResultCode ?? event.result_code ?? '');

    return {
      externalReference: String(event.SmileJobID ?? event.job_id ?? ''),
      outcome: mapResultCode(resultCode),
      livenessScore: toScore(event.LivenessScore ?? event.liveness_score),
      faceMatchScore: toScore(event.ConfidenceValue ?? event.confidence),
      rejectionReason: event.ResultText ?? event.result_text,
    };
  }
}

/**
 * Anything unrecognised becomes `in_review`, never `verified`.
 *
 * The failure mode that matters is a new or misread code being treated as a
 * pass — that puts an unvetted person in front of a customer. Sending an
 * unknown code to a human costs someone ten minutes.
 */
function mapResultCode(code: string): KycOutcome {
  switch (code) {
    case '1012':
    case '0810':
    case '1020':
      return 'verified';
    case '1013':
    case '0811':
    case '1022':
      return 'rejected';
    case '1014':
    case '0812':
      return 'in_review';
    default:
      return 'in_review';
  }
}

function toScore(value: unknown): number | null {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  // Vendors report confidence as either 0..1 or 0..100 depending on product.
  return n > 1 ? n / 100 : n;
}
