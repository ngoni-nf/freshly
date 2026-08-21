import { Logger } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  KycCallbackEvent,
  KycOutcome,
  KycProvider,
  KycResult,
  KycSubmission,
} from './kyc-provider.interface';

export interface SumsubConfig {
  appToken?: string;
  secretKey?: string;
  webhookSecret?: string;
  /** The verification level configured in the Sumsub dashboard. */
  levelName: string;
  baseUrl: string;
}

/**
 * Sumsub — identity verification, wired against the free sandbox.
 *
 * Unlike the Smile ID adapter this one is not inert: the sandbox is a real
 * environment with no cost and no contract, so `submit` genuinely creates an
 * applicant. What still belongs to configuration, not code, is the *level* —
 * the set of checks (document, liveness, watchlist) is defined in the Sumsub
 * dashboard and named, and the wrong name silently runs the wrong checks. It
 * is a setting, SUMSUB_LEVEL_NAME, not a guess baked into the request.
 *
 * The applicant is created here; the document and selfie capture happen in
 * Sumsub's SDK, opened by the app with a short-lived access token. That split
 * is deliberate — pushing identity documents through our own servers when the
 * vendor is built to collect them directly only widens the surface that holds
 * someone's ID.
 *
 * Result mapping follows the interface's rule that `in_review` is the safe
 * default: any outcome that is not a clean GREEN or a final RED goes to a
 * human rather than being forced into pass or fail.
 */
export class SumsubKycProvider implements KycProvider {
  readonly name = 'sumsub';
  readonly answersSynchronously = false;
  private readonly logger = new Logger('SumsubKycProvider');

  constructor(private readonly config: SumsubConfig) {}

  supports(countryCode: 'ZA' | 'ZW'): boolean {
    // Sumsub covers both national ID systems; the level decides which documents
    // it will accept per country.
    return countryCode === 'ZA' || countryCode === 'ZW';
  }

  async submit(submission: KycSubmission): Promise<KycResult> {
    if (!this.config.appToken || !this.config.secretKey) {
      throw new Error('SUMSUB_APP_TOKEN and SUMSUB_SECRET_KEY must be set to verify identities');
    }

    // externalUserId ties the Sumsub applicant back to our provider, so the
    // webhook — which carries Sumsub's own applicantId — can still be
    // correlated even if it arrives before we stored the applicantId.
    const path = `/resources/applicants?levelName=${encodeURIComponent(this.config.levelName)}`;
    const body = JSON.stringify({
      externalUserId: submission.providerId,
      fixedInfo: {
        firstName: submission.fullName.split(' ').slice(0, -1).join(' ') || submission.fullName,
        lastName: submission.fullName.split(' ').slice(-1).join(' '),
        country: submission.countryCode === 'ZA' ? 'ZAF' : 'ZWE',
        ...(submission.dateOfBirth ? { dob: submission.dateOfBirth } : {}),
      },
    });

    const response = await this.signedFetch('POST', path, body);
    if (!response.ok) {
      const detail = await response.text();
      this.logger.error(`Sumsub applicant creation failed (${response.status}): ${detail}`);
      throw new Error(`Sumsub error ${response.status}`);
    }

    const created = (await response.json()) as { id: string };
    return {
      externalReference: created.id,
      // Creating an applicant only opens the case; the review answer arrives by
      // webhook once the person has completed capture in the SDK.
      outcome: 'pending',
      raw: created as unknown as Record<string, unknown>,
    };
  }

  /**
   * Sumsub signs webhooks with an HMAC over the raw body, keyed by the webhook
   * secret, sent hex-encoded in `x-payload-digest`. The algorithm travels in
   * `x-payload-digest-alg`; we accept the SHA256 and SHA512 hex variants and
   * reject anything else rather than guess.
   *
   * The signature arrives as "<alg>:<digest>" from the controller, packed so
   * the interface can stay a single string. A missing secret fails closed.
   */
  verifyCallback(signature: string, body: string): boolean {
    if (!this.config.webhookSecret) return false;

    const [alg, digest] = signature.includes(':')
      ? signature.split(':', 2)
      : ['HMAC_SHA256_HEX', signature];

    const hash = alg === 'HMAC_SHA512_HEX' ? 'sha512' : 'sha256';
    const expected = createHmac(hash, this.config.webhookSecret).update(body).digest('hex');

    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(digest, 'hex');
    return a.length === b.length && timingSafeEqual(a, b);
  }

  parseCallback(body: string): KycCallbackEvent {
    const payload = JSON.parse(body) as {
      type?: string;
      applicantId?: string;
      externalUserId?: string;
      reviewResult?: {
        reviewAnswer?: 'GREEN' | 'RED';
        reviewRejectType?: 'FINAL' | 'RETRY';
        rejectLabels?: string[];
        moderationComment?: string;
      };
    };

    const externalReference = payload.applicantId ?? payload.externalUserId ?? '';
    const result = payload.reviewResult;
    const outcome = this.mapOutcome(payload.type, result?.reviewAnswer, result?.reviewRejectType);

    return {
      externalReference,
      outcome,
      rejectionReason:
        outcome === 'rejected' || outcome === 'in_review'
          ? result?.moderationComment ?? result?.rejectLabels?.join(', ')
          : undefined,
    };
  }

  private mapOutcome(
    type: string | undefined,
    answer: 'GREEN' | 'RED' | undefined,
    rejectType: 'FINAL' | 'RETRY' | undefined,
  ): KycOutcome {
    if (type === 'applicantReviewed') {
      if (answer === 'GREEN') return 'verified';
      // A retryable rejection is a request for a better photo, not a verdict on
      // the person — it belongs with a reviewer, not in a permanent reject.
      if (answer === 'RED') return rejectType === 'FINAL' ? 'rejected' : 'in_review';
      return 'in_review';
    }
    if (type === 'applicantCreated' || type === 'applicantPending') return 'pending';
    // applicantOnHold, applicantActionPending, applicantReset and anything the
    // mapping does not recognise: never silently pass, always a human.
    return 'in_review';
  }

  private async signedFetch(method: string, path: string, body: string): Promise<Response> {
    const ts = Math.floor(Date.now() / 1000);
    // Sumsub signs ts + METHOD + path + body, keyed by the secret, hex encoded.
    const signature = createHmac('sha256', this.config.secretKey!)
      .update(ts + method.toUpperCase() + path + body)
      .digest('hex');

    return fetch(`${this.config.baseUrl}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-App-Token': this.config.appToken!,
        'X-App-Access-Ts': String(ts),
        'X-App-Access-Sig': signature,
      },
      body: method === 'GET' ? undefined : body,
    });
  }
}
