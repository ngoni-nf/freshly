import { Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  AuthorizeRequest, AuthorizeResult, CaptureResult, PaymentGateway,
  PayoutRequest, PayoutResult, RefundResult,
} from './gateway.interface';

/**
 * In-memory gateway for local development and tests.
 *
 * It models the states that actually cause bugs — declines, expiries, partial
 * captures — rather than always succeeding, because a mock that never fails
 * lets broken error handling ship. Card numbers are irrelevant; the amount
 * drives the outcome so tests can be deterministic.
 */
export class MockGateway implements PaymentGateway {
  readonly name = 'mock';
  readonly supportsSeparateCapture = true;
  private readonly logger = new Logger('MockGateway');
  private readonly holds = new Map<string, { amountMinor: number; captured: number; voided: boolean }>();

  async authorize(request: AuthorizeRequest): Promise<AuthorizeResult> {
    // Amounts ending in 13 decline, so the failure path is exercisable.
    if (request.amountMinor % 100 === 13) {
      return {
        gatewayReference: `mock_${randomUUID()}`,
        status: 'failed',
        failureCode: 'insufficient_funds',
        failureMessage: 'The bank declined this payment',
      };
    }

    const reference = `mock_${randomUUID()}`;
    this.holds.set(reference, { amountMinor: request.amountMinor, captured: 0, voided: false });
    this.logger.log(`authorized ${request.amountMinor} ${request.currency} as ${reference}`);

    return {
      gatewayReference: reference,
      status: 'authorized',
      authorizationExpiresAt: new Date(Date.now() + 7 * 24 * 3_600_000),
    };
  }

  async capture(gatewayReference: string, amountMinor: number): Promise<CaptureResult> {
    const hold = this.holds.get(gatewayReference);
    if (!hold) return { capturedMinor: 0, status: 'failed', failureMessage: 'unknown authorisation' };
    if (hold.voided) return { capturedMinor: 0, status: 'failed', failureMessage: 'authorisation was voided' };
    if (amountMinor > hold.amountMinor - hold.captured) {
      return { capturedMinor: 0, status: 'failed', failureMessage: 'capture exceeds the authorised amount' };
    }
    hold.captured += amountMinor;
    return { capturedMinor: amountMinor, status: 'captured' };
  }

  async void(gatewayReference: string): Promise<void> {
    const hold = this.holds.get(gatewayReference);
    if (hold) hold.voided = true;
  }

  async refund(gatewayReference: string, amountMinor: number): Promise<RefundResult> {
    const hold = this.holds.get(gatewayReference);
    if (!hold || amountMinor > hold.captured) {
      return { refundedMinor: 0, status: 'failed', failureMessage: 'refund exceeds the captured amount' };
    }
    hold.captured -= amountMinor;
    return { refundedMinor: amountMinor, status: 'refunded' };
  }

  async payout(_request: PayoutRequest): Promise<PayoutResult> {
    return { externalReference: `mockpo_${randomUUID()}`, status: 'paid' };
  }

  verifyWebhook(): boolean {
    return true;
  }
}
