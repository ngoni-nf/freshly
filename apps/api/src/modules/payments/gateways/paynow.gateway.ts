import { Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import {
  AuthorizeRequest, AuthorizeResult, CaptureResult, PaymentGateway,
  PayoutRequest, PayoutResult, RefundResult,
} from './gateway.interface';

/**
 * Zimbabwe: Paynow, covering EcoCash, OneMoney, InnBucks and USD cards.
 *
 * Paynow has no authorise-then-capture primitive — a mobile money push either
 * collects or it does not. That is a genuine structural difference from the
 * South African rails, and pretending otherwise would silently break the
 * escrow guarantee in the second market.
 *
 * The honest workaround, and what this adapter is built for: collect into a
 * platform-held trust account at checkout and treat release as an internal
 * ledger movement rather than a gateway capture. The customer protection is
 * the same, but it is the platform holding the funds, not the processor —
 * which has real regulatory weight and needs an RBZ-compliant trust
 * arrangement in place before Zimbabwe goes live. It is deliberately visible
 * here rather than buried.
 */
export class PaynowGateway implements PaymentGateway {
  readonly name = 'paynow';
  readonly supportsSeparateCapture = false;
  private readonly logger = new Logger('PaynowGateway');

  constructor(
    private readonly integrationId: string,
    private readonly integrationKey: string,
  ) {}

  async authorize(request: AuthorizeRequest): Promise<AuthorizeResult> {
    // Collection is immediate; escrow becomes a trust-account balance that the
    // ledger tracks, and 'authorized' here means "collected and held by us".
    this.logger.warn(
      `paynow collects immediately; booking ${request.bookingId} funds are held in trust, not by the processor`,
    );
    throw new Error('PaynowGateway.authorize is not implemented — configure trust account settlement first');
  }

  async capture(): Promise<CaptureResult> {
    // Nothing to capture at the gateway: releasing funds is an internal
    // ledger transfer plus a payout instruction.
    return { capturedMinor: 0, status: 'failed', failureMessage: 'paynow does not support deferred capture' };
  }

  async void(): Promise<void> {
    throw new Error('paynow authorisations cannot be voided; issue a refund instead');
  }

  async refund(): Promise<RefundResult> {
    throw new Error('PaynowGateway.refund is not implemented');
  }

  async payout(_request: PayoutRequest): Promise<PayoutResult> {
    throw new Error('PaynowGateway.payout is not implemented');
  }

  /** Paynow signs with an uppercase MD5 of the concatenated values plus the key. */
  verifyWebhook(signature: string, body: string): boolean {
    const expected = createHash('md5').update(`${body}${this.integrationKey}`).digest('hex').toUpperCase();
    return expected === signature?.toUpperCase();
  }
}
