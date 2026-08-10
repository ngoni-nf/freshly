import { Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  PayoutInstruction, PayoutOutcome, PayoutProvider, PayoutWebhookEvent,
} from './payout-provider.interface';

/**
 * Local development and tests.
 *
 * It answers `processing` rather than `paid`, because that is what every real
 * disbursement rail does and a mock that settles instantly lets the whole
 * webhook path ship untested. The amount drives the outcome so tests stay
 * deterministic without stubbing HTTP.
 */
export class MockPayoutProvider implements PayoutProvider {
  readonly name = 'mock';
  readonly settlesSynchronously = false;
  private readonly logger = new Logger('MockPayoutProvider');

  supports(): boolean {
    return true;
  }

  async send(instruction: PayoutInstruction): Promise<PayoutOutcome> {
    // Amounts ending in 13 are rejected, mirroring MockGateway, so the
    // reversal path is exercisable from a test or by hand in the app.
    if (instruction.netMinor % 100 === 13) {
      return {
        externalReference: `mockpo_${randomUUID()}`,
        status: 'failed',
        failureReason: 'The receiving bank rejected the account number',
      };
    }

    this.logger.log(
      `payout ${instruction.payoutId}: ${instruction.netMinor} ${instruction.currency} via ${instruction.method}`,
    );
    return { externalReference: `mockpo_${randomUUID()}`, status: 'processing' };
  }

  verifyWebhook(): boolean {
    return true;
  }

  parseWebhook(body: string): PayoutWebhookEvent {
    const parsed = JSON.parse(body) as Record<string, unknown>;
    return {
      externalReference: String(parsed.reference ?? ''),
      status: (parsed.status as PayoutWebhookEvent['status']) ?? 'processing',
      failureReason: parsed.failureReason as string | undefined,
      settledAt: parsed.settledAt ? new Date(String(parsed.settledAt)) : undefined,
    };
  }
}
