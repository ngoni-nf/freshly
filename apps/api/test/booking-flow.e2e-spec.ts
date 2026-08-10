import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/http-exception.filter';

/**
 * End-to-end walk of the money path.
 *
 * This is the test that matters. Unit tests prove the pricing arithmetic; this
 * proves that a real booking moves through the state machine, that escrow is
 * held and not taken, that the completion PIN actually gates capture, and that
 * the ledger nets to zero afterwards. Every one of those is a property you
 * cannot verify by reading code.
 *
 * Requires Postgres with PostGIS and Redis. Skips cleanly when they are absent
 * so `npm test` still works on a laptop with nothing running.
 */
const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';

/**
 * Opt in explicitly rather than probing asynchronously: a top-level await
 * cannot gate a describe block under CommonJS, and silently skipping in CI
 * would be worse than not having the test at all.
 *
 *   RUN_E2E=1 npm run test:e2e
 */
const shouldRun = process.env.RUN_E2E === '1';
const maybeDescribe = shouldRun ? describe : describe.skip;

if (!shouldRun) {
  // eslint-disable-next-line no-console
  console.log('e2e skipped — set RUN_E2E=1 with Postgres/PostGIS and Redis running');
}

maybeDescribe('booking flow (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let clientToken: string;
  let providerToken: string;
  let providerId: string;
  let serviceIds: string[];

  const DESTINATION = { lat: -26.1076, lng: 28.0473 };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();

    db = new Client({ connectionString: DATABASE_URL });
    await db.connect();

    const provider = await db.query(
      `SELECT p.id, p.user_id FROM providers p WHERE p.slug = 'sipho-m'`,
    );
    providerId = provider.rows[0].id;

    const services = await db.query(
      `SELECT id FROM services WHERE provider_id = $1 ORDER BY sort_order LIMIT 2`,
      [providerId],
    );
    serviceIds = services.rows.map((r) => r.id);

    clientToken = await signIn(app, '+27821112222');
    providerToken = await signIn(app, '+27823334444');
  });

  afterAll(async () => {
    await db?.end();
    await app?.close();
  });

  it('quotes a booking with the fees the market defines', async () => {
    const res = await request(app.getHttpServer())
      .post('/bookings/quote')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({ providerId, serviceIds, destination: DESTINATION })
      .expect(201);

    expect(res.body.currency).toBe('ZAR');
    expect(res.body.serviceFeeMinor).toBe(1000);
    // The quote must already reconcile before a cent is authorised.
    expect(
      res.body.commissionMinor + res.body.providerPayoutMinor + res.body.serviceFeeMinor,
    ).toBe(res.body.totalMinor);
  });

  it('refuses to create a booking twice for one idempotency key', async () => {
    const key = `e2e-${Date.now()}`;
    const payload = {
      providerId, serviceIds, destination: DESTINATION,
      bookingType: 'instant', destinationAddress: '12 Oak Avenue, Sandton',
    };

    const first = await request(app.getHttpServer())
      .post('/bookings')
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', key)
      .send(payload)
      .expect(201);

    const replay = await request(app.getHttpServer())
      .post('/bookings')
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', key)
      .send(payload)
      .expect(201);

    expect(replay.body.id).toBe(first.body.id);

    const count = await db.query('SELECT COUNT(*) FROM bookings WHERE reference = $1', [
      first.body.reference,
    ]);
    expect(Number(count.rows[0].count)).toBe(1);
  });

  it('walks a booking from checkout to capture and leaves a balanced ledger', async () => {
    const key = `e2e-flow-${Date.now()}`;

    const created = await request(app.getHttpServer())
      .post('/bookings')
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', key)
      .send({
        providerId, serviceIds, destination: DESTINATION,
        bookingType: 'instant', destinationAddress: '12 Oak Avenue, Sandton',
      })
      .expect(201);

    const bookingId = created.body.id as string;

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/checkout`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', `${key}-pay`)
      .send({ method: 'card' })
      .expect(201);

    // Money is held, not taken.
    const held = await db.query(
      `SELECT escrow_status, authorized_minor, captured_minor
         FROM payment_intents WHERE booking_id = $1`,
      [bookingId],
    );
    expect(held.rows[0].escrow_status).toBe('authorized');
    expect(Number(held.rows[0].captured_minor)).toBe(0);

    // Assign directly: dispatch timing is covered by its own test.
    await db.query(
      `UPDATE bookings SET provider_id = $2, status = 'accepted' WHERE id = $1`,
      [bookingId, providerId],
    );

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/status`)
      .set('Authorization', `Bearer ${providerToken}`)
      .send({ status: 'en_route' })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/status`)
      .set('Authorization', `Bearer ${providerToken}`)
      .send({ status: 'arrived' })
      .expect(201);

    // A wrong PIN must not start the job, and must not release money.
    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/verify-pin`)
      .set('Authorization', `Bearer ${providerToken}`)
      .send({ pin: '0000' })
      .expect(400);

    const pinRes = await request(app.getHttpServer())
      .get(`/bookings/${bookingId}/pin`)
      .set('Authorization', `Bearer ${clientToken}`)
      .expect(200);
    expect(pinRes.body.pin).toMatch(/^\d{4}$/);

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/verify-pin`)
      .set('Authorization', `Bearer ${providerToken}`)
      .send({ pin: pinRes.body.pin })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/bookings/${bookingId}/complete`)
      .set('Authorization', `Bearer ${providerToken}`)
      .set('Idempotency-Key', `${key}-done`)
      .expect(201);

    const captured = await db.query(
      `SELECT escrow_status, captured_minor FROM payment_intents WHERE booking_id = $1`,
      [bookingId],
    );
    expect(captured.rows[0].escrow_status).toBe('captured');

    // The property the whole ledger design exists for.
    const balance = await db.query(
      `SELECT currency, SUM(signed_minor) AS net
         FROM ledger_entries WHERE booking_id = $1
        GROUP BY currency`,
      [bookingId],
    );
    for (const row of balance.rows) {
      expect(Number(row.net)).toBe(0);
    }

    const wallet = await db.query(
      'SELECT available_minor FROM provider_wallets WHERE provider_id = $1',
      [providerId],
    );
    expect(Number(wallet.rows[0].available_minor)).toBeGreaterThan(0);
  });

  it('rejects an illegal state transition at the database', async () => {
    const created = await db.query(
      `SELECT id FROM bookings WHERE status = 'completed' ORDER BY created_at DESC LIMIT 1`,
    );
    if (!created.rows.length) return;

    await expect(
      db.query(`UPDATE bookings SET status = 'en_route' WHERE id = $1`, [created.rows[0].id]),
    ).rejects.toThrow(/illegal booking transition/);
  });

  it('does not let one client read another client\'s booking', async () => {
    const other = await db.query(
      `SELECT id FROM bookings WHERE client_id <> (SELECT id FROM users WHERE phone_e164 = '+27821112222') LIMIT 1`,
    );
    if (!other.rows.length) return;

    await request(app.getHttpServer())
      .get(`/bookings/${other.rows[0].id}`)
      .set('Authorization', `Bearer ${clientToken}`)
      .expect(404);
  });

  it('never returns a completion code to anyone but the owning client', async () => {
    const booking = await db.query(
      `SELECT id FROM bookings WHERE status IN ('accepted','en_route','arrived') LIMIT 1`,
    );
    if (!booking.rows.length) return;

    await request(app.getHttpServer())
      .get(`/bookings/${booking.rows[0].id}/pin`)
      .set('Authorization', `Bearer ${providerToken}`)
      .expect(403);
  });
});

async function signIn(app: INestApplication, phone: string): Promise<string> {
  await request(app.getHttpServer())
    .post('/auth/otp/request')
    .send({ phone, countryCode: 'ZA' })
    .expect(200);

  const res = await request(app.getHttpServer())
    .post('/auth/otp/verify')
    .send({ phone, countryCode: 'ZA', code: '000000' })
    .expect(200);

  return res.body.accessToken;
}
