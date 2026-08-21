import { createHmac } from 'node:crypto';
import { PaystackGateway } from './paystack.gateway';

describe('PaystackGateway', () => {
  const secretKey = 'sk_test_example';
  const gw = new PaystackGateway({ secretKey, baseUrl: 'https://api.paystack.co' });

  it('is honest that it cannot hold funds separately from capturing them', () => {
    // The whole escrow model reads this flag; a false positive here would let
    // the marketplace believe money was held when it was taken outright.
    expect(gw.supportsSeparateCapture).toBe(false);
  });

  it('verifies a sha512 signature over the raw body and rejects tampering', () => {
    const body = JSON.stringify({ event: 'charge.success', data: { reference: 'r1' } });
    const signature = createHmac('sha512', secretKey).update(body).digest('hex');

    expect(gw.verifyWebhook(signature, body)).toBe(true);
    expect(gw.verifyWebhook(signature, `${body}x`)).toBe(false);
  });

  it('fails webhook verification closed without a secret or without a signature', () => {
    const noKey = new PaystackGateway({ baseUrl: 'https://api.paystack.co' });
    const body = JSON.stringify({ event: 'charge.success' });
    const signature = createHmac('sha512', secretKey).update(body).digest('hex');

    expect(noKey.verifyWebhook(signature, body)).toBe(false);
    expect(gw.verifyWebhook('', body)).toBe(false);
  });

  it('refuses to reach Paystack without a secret key', async () => {
    const noKey = new PaystackGateway({ baseUrl: 'https://api.paystack.co' });
    await expect(
      noKey.authorize({
        bookingId: 'b1',
        amountMinor: 10000,
        currency: 'ZAR',
        method: 'card',
        customerReference: 'ref',
        idempotencyKey: 'idem-1',
      }),
    ).rejects.toThrow(/PAYSTACK_SECRET_KEY/);
  });
});
