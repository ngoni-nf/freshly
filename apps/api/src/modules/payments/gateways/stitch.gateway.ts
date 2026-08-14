import { Logger } from '@nestjs/common';
import { createHmac, timingSafeEqual } from 'node:crypto';
import {
  AuthorizeRequest,
  AuthorizeResult,
  CaptureResult,
  PaymentGateway,
  PayoutRequest,
  PayoutResult,
  RefundResult,
} from './gateway.interface';

/**
 * Stitch, for South Africa.
 *
 * Structurally complete and deliberately inert, the same way PaynowGateway is.
 * Enabling it is deleting the guard below once the contract details are
 * confirmed — not writing an integration.
 *
 * What is still outstanding, and why none of it can be guessed:
 *
 *   - Whether the merchant account is provisioned for card authorise-then-hold
 *     or only for instant EFT collection. The entire escrow promise rests on
 *     holding funds and releasing them on the client's PIN, and Stitch's
 *     PayShap and instant-EFT rails collect immediately. A gateway that cannot
 *     hold is not usable here regardless of how good the API is.
 *   - The webhook signing secret and which header carries it.
 *   - The disbursement product for payouts, which is a separate agreement to
 *     the collection one and is FICA-gated.
 *
 * A plausible-looking guess would authorise real money against a real card and
 * fail in a way that looks like a Stitch outage rather than our mistake. The
 * refusal is the safer failure.
 */
export class StitchGateway implements PaymentGateway {
  readonly name = 'stitch';

  /**
   * Claimed, not verified. Stitch's card product supports it; whether this
   * merchant account is enabled for it is one of the open questions above, and
   * it is asserted here only so the selection logic treats it as a candidate
   * once someone turns it on.
   */
  readonly supportsSeparateCapture = true;

  private readonly logger = new Logger('StitchGateway');

  constructor(private readonly config: { clientId: string; clientSecret: string }) {
    this.logger.warn(
      'Stitch adapter constructed but inert: confirm card authorise-then-capture, ' +
        'the webhook signing secret, and the disbursement agreement before enabling',
    );
  }

  private refuse(operation: string): never {
    throw new Error(
      `Stitch ${operation} is not enabled. Confirm the merchant contract details ` +
        'and remove this guard deliberately, rather than shipping a guessed payload.',
    );
  }

  async authorize(_request: AuthorizeRequest): Promise<AuthorizeResult> {
    this.refuse('authorize');
  }

  async capture(_gatewayReference: string, _amountMinor: number): Promise<CaptureResult> {
    this.refuse('capture');
  }

  async void(_gatewayReference: string): Promise<void> {
    this.refuse('void');
  }

  async refund(_gatewayReference: string, _amountMinor: number): Promise<RefundResult> {
    this.refuse('refund');
  }

  async payout(_request: PayoutRequest): Promise<PayoutResult> {
    this.refuse('payout');
  }

  /**
   * The one method that is real, because it can be: HMAC verification needs
   * only the secret, and getting it wrong silently accepts forged callbacks.
   * Compared in constant time — a byte-by-byte compare leaks the signature one
   * character at a time to anyone willing to measure.
   */
  verifyWebhook(signature: string, body: string): boolean {
    if (!signature || !this.config.clientSecret) return false;

    const expected = createHmac('sha256', this.config.clientSecret)
      .update(body, 'utf8')
      .digest('hex');

    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(signature, 'utf8');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  }
}
