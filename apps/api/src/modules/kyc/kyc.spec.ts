import { createHmac } from 'node:crypto';
import { MockKycProvider } from './providers/mock.kyc-provider';
import { SmileIdKycProvider } from './providers/smileid.kyc-provider';
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
