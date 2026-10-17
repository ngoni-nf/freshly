import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/http-exception.filter';

/**
 * A barber in Harare, from a phone number to being paid.
 *
 * The QA pass of 17 October found that none of this was possible: a new
 * number got a customer account and every provider screen answered
 * insufficient_role; a payout account could never become verified; and
 * "Pick a time" failed for every real provider because nothing wrote working
 * hours. Each step here is one of those, in order.
 *
 * Requires Postgres with PostGIS and Redis, like the booking flow.
 */
const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';
const shouldRun = process.env.RUN_E2E === '1';
const maybeDescribe = shouldRun ? describe : describe.skip;

// Fresh numbers every run: a booking keeps its client row, so the people
// from the last run cannot be deleted and must simply not be reused.
const RUN = String(Date.now() % 10_000_000).padStart(7, '0');
const PRO_PHONE = `+26377${RUN}`;
const CLIENT_PHONE = `+26378${RUN}`;
const PRO_NATIONAL = `077${RUN}`;
const AVONDALE = { lat: -17.7932, lng: 31.0361 };

maybeDescribe('provider onboarding (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let proToken: string;
  let clientToken: string;
  let adminToken: string;
  let providerId: string;
  let serviceId: string;
  let secondServiceId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();

    db = new Client({ connectionString: DATABASE_URL });
    await db.connect();

    proToken = await signIn(app, PRO_PHONE);
    clientToken = await signIn(app, CLIENT_PHONE);
    adminToken = await signIn(app, '+27820000001', 'ZA');
  });

  afterAll(async () => {
    await db.end();
    await app.close();
  });

  it('starts as a customer: provider screens are refused', async () => {
    const me = await request(app.getHttpServer())
      .get('/auth/me')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    expect(me.body.roles).toEqual(['client']);
    expect(me.body.provider).toBeNull();

    await request(app.getHttpServer())
      .post('/providers/me/presence')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ isOnline: true })
      .expect(403);
  });

  it('refuses a base outside every live area', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/become-provider')
      .set('Authorization', `Bearer ${proToken}`)
      .send({
        displayName: 'Tendai Moyo',
        businessMode: 'solo',
        categories: ['barber'],
        venueMode: 'mobile',
        lat: -20.15, // Bulawayo is configured but not live
        lng: 28.58,
      })
      .expect(422);
    expect(res.body.code).toBe('outside_service_area');
  });

  it('becomes a provider and gets a session that says so', async () => {
    const res = await request(app.getHttpServer())
      .post('/auth/become-provider')
      .set('Authorization', `Bearer ${proToken}`)
      .send({
        displayName: 'Tendai Moyo',
        businessMode: 'solo',
        categories: ['barber', 'beard'],
        venueMode: 'mobile',
        ...AVONDALE,
        travelRadiusKm: 12,
        powerBackup: ['battery_clippers'],
        bio: 'Fades and line-ups in Avondale.',
      })
      .expect(201);

    expect(res.body.user.roles).toEqual(expect.arrayContaining(['client', 'provider']));
    proToken = res.body.accessToken;

    const me = await request(app.getHttpServer())
      .get('/providers/me')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    providerId = me.body.id;
    expect(me.body.kycStatus).toBe('pending');
    expect(me.body.currency).toBe('USD');
    expect(me.body.serviceArea.name).toBe('Harare Metro');

    // Doing it twice is a conflict, not a second provider.
    await request(app.getHttpServer())
      .post('/auth/become-provider')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ displayName: 'Again', businessMode: 'solo', categories: ['barber'], venueMode: 'mobile', ...AVONDALE })
      .expect(409);
  });

  it('has working hours from day one and can change them', async () => {
    const rules = await request(app.getHttpServer())
      .get('/providers/me/availability/rules')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    expect(rules.body).toHaveLength(6);
    expect(rules.body[0]).toEqual({ weekday: 1, startsAt: '08:00', endsAt: '18:00' });

    await request(app.getHttpServer())
      .put('/providers/me/availability/rules')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ rules: [{ weekday: 1, startsAt: '18:00', endsAt: '09:00' }] })
      .expect(400);

    // Every day, so the scheduled booking below works whatever day CI runs.
    const all = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, startsAt: '06:00', endsAt: '22:00' }));
    const saved = await request(app.getHttpServer())
      .put('/providers/me/availability/rules')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ rules: all })
      .expect(200);
    expect(saved.body).toHaveLength(7);
  });

  it('cannot go online until verified, then can', async () => {
    await request(app.getHttpServer())
      .post('/providers/me/presence')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ isOnline: true })
      .expect(403);

    // No documents is not a submission.
    await request(app.getHttpServer())
      .post('/kyc/submissions')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ documentType: 'national_id', idNumber: '63-123456-K-47', fullName: 'Tendai Moyo' })
      .expect(400);

    const kyc = await request(app.getHttpServer())
      .post('/kyc/submissions')
      .set('Authorization', `Bearer ${proToken}`)
      .send({
        documentType: 'national_id',
        idNumber: '63-123456-K-47',
        fullName: 'Tendai Moyo',
        documentFrontKey: 'kyc/test/front.jpg',
        selfieKey: 'kyc/test/selfie.jpg',
      })
      .expect(201);
    expect(kyc.body.status).toBe('verified');

    await request(app.getHttpServer())
      .post('/providers/me/presence')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ isOnline: true })
      .expect(201);
  });

  it('edits the business and adds a menu', async () => {
    const updated = await request(app.getHttpServer())
      .patch('/providers/me')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ bio: 'Ten years cutting in Harare.', travelRadiusKm: 15 })
      .expect(200);
    expect(updated.body.travelRadiusKm).toBe(15);
    expect(updated.body.bio).toBe('Ten years cutting in Harare.');

    await request(app.getHttpServer())
      .patch('/providers/me')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ venueMode: 'in_shop' })
      .expect(400); // a shop needs an address

    const inserted = await db.query(
      `INSERT INTO services (provider_id, name, category, venue_mode, price_minor, currency, duration_minutes, requires_power, sort_order)
       VALUES ($1, 'Skin fade', 'barber', 'mobile', 1000, 'USD', 45, true, 1),
              ($1, 'Beard trim', 'beard', 'mobile', 500, 'USD', 20, false, 2)
       RETURNING id`,
      [providerId],
    );
    serviceId = inserted.rows[0].id;
    secondServiceId = inserted.rows[1].id;
  });

  it('can be booked for a time, suggests an extra mid-job, and is paid in dollars', async () => {
    await request(app.getHttpServer())
      .post('/auth/profile')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({ fullName: 'Rudo Chikore', acceptTerms: true, acceptPrivacy: true })
      .expect(201);

    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(10, 0, 0, 0);

    const key = `e2e-zw-${Date.now()}`;
    const booking = await request(app.getHttpServer())
      .post('/bookings')
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', key)
      .send({
        providerId,
        serviceIds: [serviceId],
        destination: { lat: -17.81, lng: 31.05 },
        bookingType: 'scheduled',
        scheduledStart: tomorrow.toISOString(),
        destinationAddress: '14 King George Rd, Avondale',
      })
      .expect(201);
    const bookingId = booking.body.id as string;
    expect(booking.body.total.currency).toBe('USD');

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/checkout`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', `${key}-pay`)
      .send({ method: 'ecocash' })
      .expect(201);

    await db.query(`UPDATE bookings SET status = 'accepted' WHERE id = $1`, [bookingId]);
    for (const status of ['en_route', 'arrived']) {
      await request(app.getHttpServer())
        .post(`/bookings/${bookingId}/status`)
        .set('Authorization', `Bearer ${proToken}`)
        .send({ status })
        .expect(201);
    }

    // An extra cannot be suggested before the job has started.
    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/addons`)
      .set('Authorization', `Bearer ${proToken}`)
      .send({ serviceId: secondServiceId })
      .expect(400);

    const pin = await request(app.getHttpServer())
      .get(`/bookings/${bookingId}/pin`)
      .set('Authorization', `Bearer ${clientToken}`)
      .expect(200);
    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/verify-pin`)
      .set('Authorization', `Bearer ${proToken}`)
      .send({ pin: pin.body.pin })
      .expect(201);

    const addon = await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/addons`)
      .set('Authorization', `Bearer ${proToken}`)
      .send({ serviceId: secondServiceId })
      .expect(201);
    expect(addon.body.priceMinor).toBe(500);

    // The client approves it; the hold grows by exactly the add-on.
    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/addons/${addon.body.itemId}/respond`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', `${key}-addon`)
      .send({ approve: true })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/complete`)
      .set('Authorization', `Bearer ${proToken}`)
      .set('Idempotency-Key', `complete-${bookingId}`)
      .expect(201);

    const net = await db.query(
      `SELECT currency, SUM(signed_minor) AS net FROM ledger_entries WHERE booking_id = $1 GROUP BY currency`,
      [bookingId],
    );
    expect(net.rows).toHaveLength(1);
    expect(net.rows[0].currency).toBe('USD');
    expect(Number(net.rows[0].net)).toBe(0);

    const wallet = await request(app.getHttpServer())
      .get('/payouts/wallet')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    expect(wallet.body.currency).toBe('USD');
    // Zimbabwe's own minimum, not the rand one.
    expect(wallet.body.minimumMinor).toBe(2000);
    expect(wallet.body.blockedReason).toBe('payout_account_missing');
  });

  it("verifies an EcoCash wallet on the provider's own number automatically", async () => {
    const someoneElse = await request(app.getHttpServer())
      .post('/payouts/accounts')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ method: 'ecocash', accountNumber: '0779999999', accountName: 'Tendai Moyo' })
      .expect(201);
    expect(someoneElse.body.isVerified).toBe(false);

    const queue = await request(app.getHttpServer())
      .get('/admin/payout-accounts/pending')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(queue.body.map((a: { id: string }) => a.id)).toContain(someoneElse.body.id);

    const own = await request(app.getHttpServer())
      .post('/payouts/accounts')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ method: 'ecocash', accountNumber: PRO_NATIONAL, accountName: 'Tendai Moyo' })
      .expect(201);
    expect(own.body.isVerified).toBe(true);

    const wallet = await request(app.getHttpServer())
      .get('/payouts/wallet')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    expect(wallet.body.account.isVerified).toBe(true);
    expect(wallet.body.blockedReason).toBe('below_minimum');
  });

  it('lets ops verify a bank account by hand', async () => {
    const bank = await request(app.getHttpServer())
      .post('/payouts/accounts')
      .set('Authorization', `Bearer ${proToken}`)
      .send({ method: 'bank_transfer', accountNumber: '1234567890', accountName: 'Tendai Moyo', institutionName: 'CBZ' })
      .expect(201);
    expect(bank.body.isVerified).toBe(false);

    await request(app.getHttpServer())
      .post(`/admin/payout-accounts/${bank.body.id}/review`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ decision: 'verified' })
      .expect(201);

    const wallet = await request(app.getHttpServer())
      .get('/payouts/wallet')
      .set('Authorization', `Bearer ${proToken}`)
      .expect(200);
    expect(wallet.body.account.last4).toBe('7890');
    expect(wallet.body.account.isVerified).toBe(true);
  });

  it('counts the ops queues without touching a table that does not exist', async () => {
    const badges = await request(app.getHttpServer())
      .get('/admin/stats/badges')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(typeof badges.body.sos).toBe('number');
    expect(typeof badges.body.payoutAccounts).toBe('number');

    const pulse = await request(app.getHttpServer())
      .get('/admin/stats/pulse')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(Array.isArray(pulse.body.gmvToday)).toBe(true);

    // Column names are not free text.
    await request(app.getHttpServer())
      .post('/admin/markets/ZW')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ 'is_live = false; --': true })
      .expect(400);
  });
});

async function signIn(app: INestApplication, phone: string, countryCode = 'ZW'): Promise<string> {
  await request(app.getHttpServer())
    .post('/auth/otp/request')
    .send({ phone, countryCode })
    .expect(200);
  const res = await request(app.getHttpServer())
    .post('/auth/otp/verify')
    .send({ phone, countryCode, code: '000000' })
    .expect(200);
  return res.body.accessToken;
}
