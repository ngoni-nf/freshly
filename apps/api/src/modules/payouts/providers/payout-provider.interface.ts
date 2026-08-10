/**
 * Paying providers out is a different rail from taking money in, and it is
 * worth a separate interface rather than another method on PaymentGateway.
 *
 * The card acquirer that authorises a client's checkout is rarely the same
 * vendor that pushes a bank EFT or an EcoCash disbursement, the settlement
 * timelines differ by days, and payouts fail asynchronously — hours later, by
 * webhook, long after the HTTP call returned success. Modelling that as
 * "gateway.payout()" hides the part that actually causes incidents.
 */

export interface PayoutInstruction {
  payoutId: string;
  /** Net amount that must land in the provider's account, fee already deducted. */
  netMinor: number;
  currency: string;
  /** bank_transfer | ecocash | onemoney | innbucks */
  method: string;
  accountNumber: string;
  accountName: string;
  /** Bank branch or mobile network operator code, where the rail needs one. */
  institutionCode?: string;
  /** Shown on the provider's bank statement; keep it short and recognisable. */
  narrative: string;
  idempotencyKey: string;
}

export interface PayoutOutcome {
  externalReference: string;
  /**
   * `processing` is the normal answer. Almost no disbursement rail can confirm
   * settlement synchronously, so the webhook is the real source of truth and
   * the request path must not pretend otherwise.
   */
  status: 'processing' | 'paid' | 'failed';
  failureReason?: string;
  settledAt?: Date;
  raw?: Record<string, unknown>;
}

export interface PayoutWebhookEvent {
  externalReference: string;
  status: 'processing' | 'paid' | 'failed' | 'reversed';
  failureReason?: string;
  settledAt?: Date;
}

export interface PayoutProvider {
  readonly name: string;
  /** Rails that settle while the request is open can skip the pending state. */
  readonly settlesSynchronously: boolean;

  supports(method: string): boolean;
  send(instruction: PayoutInstruction): Promise<PayoutOutcome>;
  verifyWebhook(signature: string, body: string): boolean;
  parseWebhook(body: string): PayoutWebhookEvent;
}
