export interface AuthorizeRequest {
  bookingId: string;
  amountMinor: number;
  currency: string;
  method: string;
  customerReference: string;
  idempotencyKey: string;
  returnUrl?: string;
}

export interface AuthorizeResult {
  gatewayReference: string;
  status: 'authorized' | 'pending' | 'failed';
  /** Present when the method needs the customer to approve in another app. */
  redirectUrl?: string;
  authorizationExpiresAt?: Date;
  failureCode?: string;
  failureMessage?: string;
  raw?: Record<string, unknown>;
}

export interface CaptureResult {
  capturedMinor: number;
  status: 'captured' | 'failed';
  failureMessage?: string;
}

export interface RefundResult {
  refundedMinor: number;
  status: 'refunded' | 'failed';
  failureMessage?: string;
}

export interface PayoutRequest {
  payoutId: string;
  amountMinor: number;
  currency: string;
  method: string;
  accountNumber: string;
  accountName: string;
  institutionCode?: string;
  idempotencyKey: string;
}

export interface PayoutResult {
  externalReference: string;
  status: 'processing' | 'paid' | 'failed';
  failureMessage?: string;
}

/**
 * Every payment provider is reduced to this interface.
 *
 * Authorize-then-capture is the whole safety model: money is held at checkout
 * and only taken once the client releases it with their PIN. Any gateway that
 * cannot hold an authorisation separately from capturing it is not usable for
 * this marketplace, which is a real constraint when selecting providers in
 * both markets — several local rails only do immediate collection.
 */
export interface PaymentGateway {
  readonly name: string;
  readonly supportsSeparateCapture: boolean;

  authorize(request: AuthorizeRequest): Promise<AuthorizeResult>;
  capture(gatewayReference: string, amountMinor: number): Promise<CaptureResult>;
  /** Release an authorisation without taking anything. */
  void(gatewayReference: string): Promise<void>;
  refund(gatewayReference: string, amountMinor: number): Promise<RefundResult>;
  payout(request: PayoutRequest): Promise<PayoutResult>;
  verifyWebhook(signature: string, body: string): boolean;
}
