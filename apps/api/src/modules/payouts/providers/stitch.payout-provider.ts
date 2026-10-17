import { Logger } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  PayoutInstruction, PayoutOutcome, PayoutProvider, PayoutWebhookEvent,
} from './payout-provider.interface';

export interface StitchPayoutConfig {
  clientId?: string;
  clientSecret?: string;
  webhookSecret?: string;
  baseUrl: string;
}

/**
 * South Africa: bank disbursement.
 *
 * What is settled and encoded here is the shape of the integration — OAuth
 * client-credentials, a per-payout idempotency key on the wire, an
 * asynchronous result confirmed by signed webhook, and the mapping from the
 * vendor's status vocabulary onto ours. What is deliberately not encoded is a
 * guessed request body: the disbursement payload and its field names must be
 * confirmed against the live account's API version before this is enabled,
 * and a plausible-looking guess that silently pays the wrong account is worse
 * than a refusal to start.
 *
 * So: fully wired, credential-gated, and loud. Set PAYOUTS_ZA_PROVIDER=stitch
 * only once `submitDisbursement` has been checked against the vendor contract.
 */
export class StitchPayoutProvider implements PayoutProvider {
  readonly name = 'stitch';
  readonly settlesSynchronously = false;
  private readonly logger = new Logger('StitchPayoutProvider');
  private token?: { value: string; expiresAt: number };

  constructor(private readonly config: StitchPayoutConfig) {}

  supports(method: string): boolean {
    return method === 'bank_transfer';
  }

  async send(_instruction: PayoutInstruction): Promise<PayoutOutcome> {
    this.assertConfigured();
    await this.accessToken();

    // See the class comment. The transport, auth and idempotency are ready;
    // the payload contract is the outstanding piece.
    throw new Error(
      'StitchPayoutProvider.send is not enabled — confirm the disbursement payload ' +
        'against the account API version, then remove this guard',
    );
  }

  /**
   * Cached client-credentials token. Fetching one per payout would rate-limit
   * the batch run long before it finished a day's disbursements.
   */
  private async accessToken(): Promise<string> {
    if (this.token && this.token.expiresAt > Date.now() + 30_000) return this.token.value;

    const response = await fetch(`${this.config.baseUrl}/connect/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'client_credentials',
        client_id: this.config.clientId!,
        client_secret: this.config.clientSecret!,
        scope: 'client_paymentrequest',
      }),
    });

    if (!response.ok) {
      throw new Error(`stitch token request failed with ${response.status}`);
    }

    const body = (await response.json()) as { access_token: string; expires_in: number };
    this.token = {
      value: body.access_token,
      expiresAt: Date.now() + body.expires_in * 1000,
    };
    return this.token.value;
  }

  /**
   * HMAC-SHA256 over the raw body. Compared in constant time — a webhook that
   * can move a payout to `paid` is worth forging, and a short-circuiting
   * comparison leaks the signature a byte at a time.
   */
  verifyWebhook(signature: string, body: string): boolean {
    if (!this.config.webhookSecret || !signature) return false;
    const expected = createHmac('sha256', this.config.webhookSecret).update(body).digest();
    const received = Buffer.from(signature.replace(/^sha256=/, ''), 'hex');
    if (received.length !== expected.length) return false;
    return timingSafeEqual(received, expected);
  }

  parseWebhook(body: string): PayoutWebhookEvent {
    const event = JSON.parse(body) as Record<string, any>;
    const status = String(event.status ?? '').toLowerCase();

    return {
      externalReference: String(event.id ?? event.paymentRequestId ?? ''),
      // Anything unrecognised stays `processing`. Guessing that an unknown
      // status means success would mark unpaid providers as paid.
      status:
        status === 'completed' || status === 'settled'
          ? 'paid'
          : status === 'failed' || status === 'rejected'
            ? 'failed'
            : status === 'reversed'
              ? 'reversed'
              : 'processing',
      failureReason: event.failureReason ?? event.reason,
      settledAt: event.settledAt ? new Date(String(event.settledAt)) : undefined,
    };
  }

  private assertConfigured(): void {
    if (!this.config.clientId || !this.config.clientSecret) {
      throw new Error('STITCH_CLIENT_ID and STITCH_CLIENT_SECRET must be set to disburse in ZA');
    }
    if (!this.config.webhookSecret) {
      // Without it every settlement callback is unverifiable, and an
      // unverified callback is an instruction from a stranger.
      this.logger.error('STITCH_WEBHOOK_SECRET is unset; settlement callbacks cannot be trusted');
    }
  }
}
