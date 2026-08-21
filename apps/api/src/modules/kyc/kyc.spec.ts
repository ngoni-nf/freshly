import { createHmac } from 'node:crypto';
import { MockKycProvider } from './providers/mock.kyc-provider';
import { SmileIdKycProvider } from './providers/smileid.kyc-provider';
import { SumsubKycProvider } from './providers/sumsub.kyc-provider';
import { KycSubmission } from './providers/kyc-provider.interface';

const submission = (idNumber: string): KycSubmission => ({
  submissionId: 'sub-1',
  providerId: 'prov-1',
  countryCode: 'ZA',
  documentType: 'national_id',
  idNumber,
  fullName: 'Sipho Ndlovu',
});

describe('MockKycProvider', () => {
  const provider = new MockKycProvider();

  it('verifies an ordinary document', async () => {
    const result = await provider.submit(submission('9202204720082'));
    expect(result.outcome).toBe('verified');
  });

  it('can reach the rejected and in_review branches deterministically', async () => {
    expect((await provider.submit(submission('9202204720080'))).outcome).toBe('rejected');
    expect((await provider.submit(submission('9202204720081'))).outcome).toBe('in_review');
  });

  it('gives a reason with a rejection, because the app has to show one', async () => {
    const result = await provider.submit(submission('9202204720080'));
    expect(result.rejectionReason).toBeTruthy();
  });
});

describe('SmileIdKycProvider', () => {
  const apiKey = 'test-api-key';
  const partnerId = '0001';
  const provider = new SmileIdKycProvider({
    partnerId,
    apiKey,
    callbackUrl: 'https://api.freshly.africa/kyc/callbacks/smileid',
    baseUrl: 'https://api.smileidentity.com',
  });

  const sign = (timestamp: string): string =>
    createHmac('sha256', apiKey).update(timestamp).update(partnerId).update('sid_request').digest('base64');

  it('accepts a correctly signed callback', () => {
    const timestamp = '2026-08-10T12:00:00.000Z';
    const body = JSON.stringify({ timestamp, SmileJobID: 'job-1', ResultCode: '1012' });
    expect(provider.verifyCallback(sign(timestamp), body)).toBe(true);
  });

  it('rejects a tampered signature, a wrong timestamp, and a missing one', () => {
    const timestamp = '2026-08-10T12:00:00.000Z';
    const body = JSON.stringify({ timestamp, SmileJobID: 'job-1', ResultCode: '1012' });

    expect(provider.verifyCallback(sign('2026-08-10T12:00:01.000Z'), body)).toBe(false);
    expect(provider.verifyCallback('', body)).toBe(false);
    expect(provider.verifyCallback(sign(timestamp), JSON.stringify({ SmileJobID: 'job-1' }))).toBe(false);
    expect(provider.verifyCallback(sign(timestamp), 'not json')).toBe(false);
  });

  it('maps known result codes onto our outcomes', () => {
    const parse = (code: string) =>
      provider.parseCallback(JSON.stringify({ SmileJobID: 'job-1', ResultCode: code })).outcome;

    expect(parse('1012')).toBe('verified');
    expect(parse('1013')).toBe('rejected');
    expect(parse('1014')).toBe('in_review');
  });

  /**
   * The important one. An unrecognised code must never mean "verified" — that
   * is how an unvetted person ends up dispatched to a customer's home.
   */
  it('sends anything unrecognised to a human, never to verified', () => {
    for (const code of ['', '9999', 'undefined', '0', 'null']) {
      const outcome = provider.parseCallback(
        JSON.stringify({ SmileJobID: 'job-1', ResultCode: code }),
      ).outcome;
      expect(outcome).toBe('in_review');
    }
  });

  it('normalises confidence reported on either scale', () => {
    const asFraction = provider.parseCallback(
      JSON.stringify({ SmileJobID: 'j', ResultCode: '1012', ConfidenceValue: 0.94 }),
    );
    const asPercent = provider.parseCallback(
      JSON.stringify({ SmileJobID: 'j', ResultCode: '1012', ConfidenceValue: 94 }),
    );

    expect(asFraction.faceMatchScore).toBeCloseTo(0.94);
    expect(asPercent.faceMatchScore).toBeCloseTo(0.94);
  });

  it('refuses to submit without credentials rather than failing open', async () => {
    const unconfigured = new SmileIdKycProvider({ baseUrl: 'https://api.smileidentity.com' });
    await expect(unconfigured.submit(submission('9202204720082'))).rejects.toThrow(
      /SMILE_ID_PARTNER_ID/,
    );
  });
});

describe('SumsubKycProvider', () => {
  const cfg = {
    appToken: 'app-tok',
    secretKey: 'sec',
    webhookSecret: 'whsec',
    levelName: 'basic-kyc-level',
    baseUrl: 'https://api.sumsub.com',
  };
  const provider = new SumsubKycProvider(cfg);

  const sign = (body: string, alg = 'HMAC_SHA256_HEX'): string => {
    const hash = alg === 'HMAC_SHA512_HEX' ? 'sha512' : 'sha256';
    return `${alg}:${createHmac(hash, cfg.webhookSecret).update(body).digest('hex')}`;
  };

  const reviewed = (answer: 'GREEN' | 'RED', rejectType?: 'FINAL' | 'RETRY') =>
    JSON.stringify({
      type: 'applicantReviewed',
      applicantId: 'app-123',
      reviewResult: { reviewAnswer: answer, reviewRejectType: rejectType },
    });

  it('accepts a correctly signed webhook and rejects a tampered body', () => {
    const body = reviewed('GREEN');
    expect(provider.verifyCallback(sign(body), body)).toBe(true);
    expect(provider.verifyCallback(sign(body), `${body} `)).toBe(false);
  });

  it('supports the sha512 digest variant', () => {
    const body = reviewed('GREEN');
    expect(provider.verifyCallback(sign(body, 'HMAC_SHA512_HEX'), body)).toBe(true);
  });

  it('fails closed when no webhook secret is configured', () => {
    const noSecret = new SumsubKycProvider({ ...cfg, webhookSecret: undefined });
    expect(noSecret.verifyCallback('HMAC_SHA256_HEX:deadbeef', '{}')).toBe(false);
  });

  it('maps a clean pass to verified and a final rejection to rejected', () => {
    expect(provider.parseCallback(reviewed('GREEN')).outcome).toBe('verified');
    expect(provider.parseCallback(reviewed('RED', 'FINAL')).outcome).toBe('rejected');
  });

  it('sends a retryable rejection and every ambiguous state to a human', () => {
    expect(provider.parseCallback(reviewed('RED', 'RETRY')).outcome).toBe('in_review');
    expect(
      provider.parseCallback(JSON.stringify({ type: 'applicantOnHold', applicantId: 'a' })).outcome,
    ).toBe('in_review');
    expect(
      provider.parseCallback(JSON.stringify({ type: 'somethingNew', applicantId: 'a' })).outcome,
    ).toBe('in_review');
  });

  it('treats a freshly created applicant as pending', () => {
    expect(
      provider.parseCallback(JSON.stringify({ type: 'applicantPending', applicantId: 'a' })).outcome,
    ).toBe('pending');
  });

  it('carries the applicant id through as the external reference', () => {
    expect(provider.parseCallback(reviewed('GREEN')).externalReference).toBe('app-123');
  });

  it('refuses to submit without credentials', async () => {
    const unconfigured = new SumsubKycProvider({ ...cfg, appToken: undefined });
    await expect(
      unconfigured.submit({
        submissionId: 's',
        providerId: 'p',
        countryCode: 'ZA',
        documentType: 'national_id',
        idNumber: 'x',
        fullName: 'Sipho Ndlovu',
      }),
    ).rejects.toThrow(/SUMSUB_APP_TOKEN/);
  });
});
