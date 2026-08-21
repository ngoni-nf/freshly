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

export interface PaystackConfig {
  secretKey?: string;
  baseUrl: string;
}

/**
 * Paystack, for South Africa.
 *
 * Honest about what it is: Paystack collects immediately. It has no card
 * authorise-then-hold, so `supportsSeparateCapture` is false and escrow here is
 * the trust-account variety the interface already allows — the money lands in
 * the platform's Paystack balance at checkout, the ledger holds it, and it is
 * released to the provider on the client's PIN as an internal movement. If the
 * job never happens it is refunded through Paystack. That is a weaker guarantee
 * than a true hold (the funds are actually taken up front), and it is the
 * correct trade for a market where the rails do not hold — pretending otherwise
 * would be the dangerous choice.
 *
 * Amounts are already in minor units everywhere in this system, which is also
 * what Paystack expects (kobo/cents), so nothing is converted.
 */
export class PaystackGateway implements PaymentGateway {
  readonly name = 'paystack';
  readonly supportsSeparateCapture = false;
  private readonly logger = new Logger('PaystackGateway');

  constructor(private readonly config: PaystackConfig) {}

  /**
   * Start a collection. Paystack returns a URL the customer approves; the money
   * is confirmed by the charge.success webhook, so this is `pending` until then
   * rather than a synchronous hold.
   */
  async authorize(request: AuthorizeRequest): Promise<AuthorizeResult> {
    const body = JSON.stringify({
      amount: request.amountMinor,
      currency: request.currency,
      reference: request.idempotencyKey,
      // Paystack keys transactions to an email; the booking reference stands in
      // where we hold no email, and metadata carries the real correlation.
      email: `${request.customerReference}@bookings.freshly.africa`,
      metadata: { bookingId: request.bookingId, customerReference: request.customerReference },
      ...(request.returnUrl ? { callback_url: request.returnUrl } : {}),
    });

    const response = await this.call('POST', '/transaction/initialize', body);
    const json = (await response.json()) as {
      status: boolean;
      message: string;
      data?: { reference: string; authorization_url: string; access_code: string };
    };

    if (!response.ok || !json.status || !json.data) {
      return {
        gatewayReference: request.idempotencyKey,
        status: 'failed',
        failureMessage: json.message ?? `Paystack error ${response.status}`,
      };
    }

    return {
      gatewayReference: json.data.reference,
      status: 'pending',
      redirectUrl: json.data.authorization_url,
      raw: json.data as unknown as Record<string, unknown>,
    };
  }

  /**
   * The money is already in the platform balance by the time a PIN releases it,
   * so capture is an internal event, not a Paystack call. We confirm the
   * transaction actually succeeded rather than assume it, then report the
   * amount so the ledger releases exactly what was collected.
   */
  async capture(gatewayReference: string, amountMinor: number): Promise<CaptureResult> {
    const response = await this.call(
      'GET',
      `/transaction/verify/${encodeURIComponent(gatewayReference)}`,
      '',
    );
    const json = (await response.json()) as {
      status: boolean;
      data?: { status: string; amount: number };
    };

    if (!response.ok || !json.status || json.data?.status !== 'success') {
      return {
        capturedMinor: 0,
        status: 'failed',
        failureMessage: `Transaction ${gatewayReference} has not been paid`,
      };
    }

    // Never release more than was actually collected.
    const captured = Math.min(amountMinor, json.data.amount);
    return { capturedMinor: captured, status: 'captured' };
  }

  /** No hold to release; if money was collected it must come back. */
  async void(gatewayReference: string): Promise<void> {
    await this.refund(gatewayReference, 0);
  }

  /**
   * A zero amount refunds the whole transaction — Paystack's own default — which
   * is what a void needs. A positive amount refunds exactly that much.
   */
  async refund(gatewayReference: string, amountMinor: number): Promise<RefundResult> {
    const body = JSON.stringify({
      transaction: gatewayReference,
      ...(amountMinor > 0 ? { amount: amountMinor } : {}),
    });
    const response = await this.call('POST', '/refund', body);
    const json = (await response.json()) as {
      status: boolean;
      message: string;
      data?: { amount: number };
    };

    if (!response.ok || !json.status) {
      return { refundedMinor: 0, status: 'failed', failureMessage: json.message };
    }
    return { refundedMinor: json.data?.amount ?? amountMinor, status: 'refunded' };
  }

  /**
   * Provider payout via Paystack Transfers: name the destination account as a
   * recipient, then send to it. Both steps are idempotent on our key, and the
   * transfer settles asynchronously — transfer.success/failed arrives by
   * webhook — so this returns `processing`, never a premature `paid`.
   */
  async payout(request: PayoutRequest): Promise<PayoutResult> {
    const recipientBody = JSON.stringify({
      type: 'nuban',
      name: request.accountName,
      account_number: request.accountNumber,
      bank_code: request.institutionCode,
      currency: request.currency,
    });
    const recipientRes = await this.call('POST', '/transferrecipient', recipientBody);
    const recipientJson = (await recipientRes.json()) as {
      status: boolean;
      message: string;
      data?: { recipient_code: string };
    };
    if (!recipientRes.ok || !recipientJson.status || !recipientJson.data) {
      return {
        externalReference: request.idempotencyKey,
        status: 'failed',
        failureMessage: recipientJson.message ?? 'Could not register the payout account',
      };
    }

    const transferBody = JSON.stringify({
      source: 'balance',
      amount: request.amountMinor,
      recipient: recipientJson.data.recipient_code,
      reference: request.idempotencyKey,
      reason: `Freshly payout ${request.payoutId}`,
    });
    const transferRes = await this.call('POST', '/transfer', transferBody);
    const transferJson = (await transferRes.json()) as {
      status: boolean;
      message: string;
      data?: { transfer_code: string; status: string };
    };
    if (!transferRes.ok || !transferJson.status || !transferJson.data) {
      return {
        externalReference: request.idempotencyKey,
        status: 'failed',
        failureMessage: transferJson.message ?? 'Transfer was rejected',
      };
    }

    return {
      externalReference: transferJson.data.transfer_code,
      status: transferJson.data.status === 'success' ? 'paid' : 'processing',
    };
  }

  /**
   * Paystack signs the raw body with HMAC-SHA512 keyed by the secret key, hex
   * encoded, in x-paystack-signature. A missing secret fails closed.
   */
  verifyWebhook(signature: string, body: string): boolean {
    if (!this.config.secretKey || !signature) return false;
    const expected = createHmac('sha512', this.config.secretKey).update(body).digest('hex');
    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(signature, 'hex');
    return a.length === b.length && timingSafeEqual(a, b);
  }

  private async call(method: string, path: string, body: string): Promise<Response> {
    if (!this.config.secretKey) {
      throw new Error('PAYSTACK_SECRET_KEY must be set to reach Paystack');
    }
    return fetch(`${this.config.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.config.secretKey}`,
        'Content-Type': 'application/json',
      },
      body: method === 'GET' ? undefined : body,
    });
  }
}
