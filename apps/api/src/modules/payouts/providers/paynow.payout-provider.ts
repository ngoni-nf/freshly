import { Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import {
  PayoutInstruction, PayoutOutcome, PayoutProvider, PayoutWebhookEvent,
} from './payout-provider.interface';

/**
 * Zimbabwe: EcoCash, OneMoney and InnBucks disbursement.
 *
 * The collection side of Paynow is already modelled in PaynowGateway, and the
 * same structural problem applies going out: a mobile money push is a single
 * irreversible instruction to a phone number. There is no hold, no void, and
 * no recall — if the number is wrong the money is gone and recovery is a
 * support conversation with the network, not an API call.
 *
 * That is why the provider's number is verified before it can be a payout
 * destination rather than at the moment of paying out, and why this adapter
 * refuses to send until the trust-account arrangement it settles from exists.
 */
export class PaynowPayoutProvider implements PayoutProvider {
  readonly name = 'paynow';
  readonly settlesSynchronously = false;
  private readonly logger = new Logger('PaynowPayoutProvider');

  constructor(
    private readonly integrationId: string,
    private readonly integrationKey: string,
  ) {}

  supports(method: string): boolean {
    return method === 'ecocash' || method === 'onemoney' || method === 'innbucks';
  }

  async send(instruction: PayoutInstruction): Promise<PayoutOutcome> {
    this.logger.warn(
      `refusing payout ${instruction.payoutId}: ZW disbursement settles from the platform trust account, which is not yet established`,
    );
    throw new Error(
      'PaynowPayoutProvider.send is not enabled — an RBZ-compliant trust account and ' +
        'a confirmed disbursement contract are prerequisites, not code',
    );
  }

  /** Paynow signs with an uppercase MD5 of the payload concatenated with the key. */
  verifyWebhook(signature: string, body: string): boolean {
    const expected = createHash('md5').update(`${body}${this.integrationKey}`).digest('hex').toUpperCase();
    return expected === signature?.toUpperCase();
  }

  parseWebhook(body: string): PayoutWebhookEvent {
    const params = new URLSearchParams(body);
    const status = (params.get('status') ?? '').toLowerCase();

    return {
      externalReference: params.get('paynowreference') ?? params.get('reference') ?? '',
      status:
        status === 'paid' || status === 'delivered'
          ? 'paid'
          : status === 'cancelled' || status === 'failed'
            ? 'failed'
            : 'processing',
      failureReason: params.get('reason') ?? undefined,
    };
  }
}
