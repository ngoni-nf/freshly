/**
 * Identity verification.
 *
 * This is the check that decides whether a stranger may be dispatched to a
 * customer's home, so the states it can produce matter more than the vendor
 * behind it. In particular `in_review` is a first-class outcome, not an error:
 * most verifications that are neither a clean pass nor a clean fail end up
 * with a human, and a model that only knows verified/rejected will either
 * approve people it should not or reject people it should not.
 */

export type KycOutcome = 'pending' | 'in_review' | 'verified' | 'rejected';

export interface KycSubmission {
  submissionId: string;
  providerId: string;
  countryCode: 'ZA' | 'ZW';
  /** national_id | passport | drivers_licence */
  documentType: string;
  idNumber: string;
  fullName: string;
  dateOfBirth?: string;
  documentFrontKey?: string;
  documentBackKey?: string;
  selfieKey?: string;
  callbackUrl?: string;
}

export interface KycResult {
  externalReference: string;
  outcome: KycOutcome;
  /** 0..1. Null when the vendor did not run that check. */
  livenessScore?: number | null;
  faceMatchScore?: number | null;
  rejectionReason?: string;
  raw?: Record<string, unknown>;
}

export interface KycCallbackEvent {
  externalReference: string;
  outcome: KycOutcome;
  livenessScore?: number | null;
  faceMatchScore?: number | null;
  rejectionReason?: string;
}

export interface KycProvider {
  readonly name: string;
  /** Some rails answer in the request; most answer by callback minutes later. */
  readonly answersSynchronously: boolean;

  supports(countryCode: 'ZA' | 'ZW'): boolean;
  submit(submission: KycSubmission): Promise<KycResult>;
  verifyCallback(signature: string, body: string): boolean;
  parseCallback(body: string): KycCallbackEvent;
}
