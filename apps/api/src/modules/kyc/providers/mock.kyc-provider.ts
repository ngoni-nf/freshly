import { Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  KycCallbackEvent, KycProvider, KycResult, KycSubmission,
} from './kyc-provider.interface';

/**
 * Local development and tests.
 *
 * The last digit of the ID number selects the outcome, so every branch —
 * including the manual-review branch that is easiest to leave untested — can
 * be reached deliberately from the app or a spec:
 *
 *   ends in 0  rejected
 *   ends in 1  in_review
 *   otherwise  verified
 */
export class MockKycProvider implements KycProvider {
  readonly name = 'mock';
  readonly answersSynchronously = true;
  private readonly logger = new Logger('MockKycProvider');

  supports(): boolean {
    return true;
  }

  async submit(submission: KycSubmission): Promise<KycResult> {
    const lastDigit = submission.idNumber.trim().slice(-1);
    const reference = `mockkyc_${randomUUID()}`;

    if (lastDigit === '0') {
      return {
        externalReference: reference,
        outcome: 'rejected',
        livenessScore: 0.21,
        faceMatchScore: 0.34,
        rejectionReason: 'The selfie did not match the document photo',
      };
    }

    if (lastDigit === '1') {
      return {
        externalReference: reference,
        outcome: 'in_review',
        livenessScore: 0.72,
        faceMatchScore: 0.66,
      };
    }

    this.logger.log(`verified provider ${submission.providerId} (${submission.documentType})`);
    return {
      externalReference: reference,
      outcome: 'verified',
      livenessScore: 0.97,
      faceMatchScore: 0.95,
    };
  }

  verifyCallback(): boolean {
    return true;
  }

  parseCallback(body: string): KycCallbackEvent {
    const parsed = JSON.parse(body) as Record<string, unknown>;
    return {
      externalReference: String(parsed.reference ?? ''),
      outcome: (parsed.outcome as KycCallbackEvent['outcome']) ?? 'in_review',
      rejectionReason: parsed.rejectionReason as string | undefined,
    };
  }
}
