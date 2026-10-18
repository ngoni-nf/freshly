import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { Client } from 'pg';
import { AppModule } from '../src/app.module';
import { AllExceptionsFilter } from '../src/common/filters/http-exception.filter';

/**
 * A Harare salon builds a team, hands a job to a stylist, and both tax
 * documents come out the other end.
 *
 * The things that must hold: the person doing the job is the one who runs
 * it, the salon is the one who gets paid, an unverified stylist can never be
 * sent to a door, and each party sees exactly the invoice addressed to them.
 *
 * Requires Postgres with PostGIS and Redis, like the other two suites.
 */
const DATABASE_URL = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';
const shouldRun = process.env.RUN_E2E === '1';
const maybeDescribe = shouldRun ? describe : describe.skip;

// Fresh numbers every run, as in provider-onboarding: completed bookings keep
// their people, so the last run's cannot be reused.
const RUN = String(Date.now() % 10_000_000).padStart(7, '0');
const SALON_PHONE = `+26371${RUN}`;
const STAFF_PHONE = `+26372${RUN}`;
const CLIENT_PHONE = `+26373${RUN}`;
const RIVAL_PHONE = `+26374${RUN}`;
const AVONDALE = { lat: -17.7932, lng: 31.0361 };

/** supertest leaves an unknown content type unparsed; collect the bytes. */
const binary = (res: request.Response, cb: (err: Error | null, body: Buffer) => void) => {
  const chunks: Buffer[] = [];
  res.on('data', (c: Buffer) => chunks.push(c));
  res.on('end', () => cb(null, Buffer.concat(chunks)));
};

maybeDescribe('salon staff and invoices (e2e)', () => {
  let app: INestApplication;
  let db: Client;
  let salonToken: string;
  let staffToken: string;
  let clientToken: string;
  let adminToken: string;
  let rivalToken: string;
  let salonId: string;
  let staffId: string;
  let serviceId: string;
  let inviteId: string;
  let bookingId: string;
  let invoices: Array<{ id: string; kind: string; number: string }>;

  const api = () => request(app.getHttpServer());

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();

    db = new Client({ connectionString: DATABASE_URL });
    await db.connect();

    salonToken = await signIn(app, SALON_PHONE);
    staffToken = await signIn(app, STAFF_PHONE);
    clientToken = await signIn(app, CLIENT_PHONE);
    rivalToken = await signIn(app, RIVAL_PHONE);
    adminToken = await signIn(app, '+27820000001', 'ZA');
  });

  afterAll(async () => {
    await db.end();
    await app.close();
  });

  it('tells each market which number to dial in an emergency', async () => {
    const res = await api().get('/markets').expect(200);
    const byCode = Object.fromEntries(res.body.map((m: { code: string; emergencyNumber: string }) => [m.code, m.emergencyNumber]));
    expect(byCode.ZA).toBe('10111');
    expect(byCode.ZW).toBe('999');
  });

  it('opens a salon in Avondale and a solo rival next door', async () => {
    const salon = await api()
      .post('/auth/become-provider')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({
        displayName: 'Avondale Cuts',
        businessMode: 'salon',
        categories: ['barber'],
        venueMode: 'both',
        shopAddress: '12 King George Rd, Avondale',
        ...AVONDALE,
      })
      .expect(201);
    salonToken = salon.body.accessToken;

    const me = await api().get('/providers/me').set('Authorization', `Bearer ${salonToken}`).expect(200);
    salonId = me.body.id;
    expect(me.body.businessMode).toBe('salon');

    await api()
      .post('/kyc/submissions')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({
        documentType: 'national_id', idNumber: '63-100001-A-47', fullName: 'Chipo Dube',
        documentFrontKey: 'kyc/test/front.jpg', selfieKey: 'kyc/test/selfie.jpg',
      })
      .expect(201);

    const all = [0, 1, 2, 3, 4, 5, 6].map((weekday) => ({ weekday, startsAt: '06:00', endsAt: '22:00' }));
    await api().put('/providers/me/availability/rules').set('Authorization', `Bearer ${salonToken}`).send({ rules: all }).expect(200);

    const inserted = await db.query(
      `INSERT INTO services (provider_id, name, category, venue_mode, price_minor, currency, duration_minutes, requires_power, sort_order)
       VALUES ($1, 'Skin fade', 'barber', 'mobile', 1000, 'USD', 45, true, 1) RETURNING id`,
      [salonId],
    );
    serviceId = inserted.rows[0].id;

    const rival = await api()
      .post('/auth/become-provider')
      .set('Authorization', `Bearer ${rivalToken}`)
      .send({ displayName: 'Rival Fades', businessMode: 'solo', categories: ['barber'], venueMode: 'mobile', ...AVONDALE })
      .expect(201);
    rivalToken = rival.body.accessToken;
  });

  it('refuses team management to anyone but a salon', async () => {
    const res = await api().get('/providers/me/staff').set('Authorization', `Bearer ${rivalToken}`).expect(403);
    expect(res.body.code).toBe('salon_only');
  });

  it('invites a number once, and not a number that already runs a business', async () => {
    const invite = await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: STAFF_PHONE })
      .expect(201);
    expect(invite.body.status).toBe('pending');
    inviteId = invite.body.id;

    const again = await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: STAFF_PHONE })
      .expect(409);
    expect(again.body.code).toBe('invite_pending');

    // A solo provider with no jobs is a half-finished sign-up and may be
    // invited; one with a business of their own may not. The rival has done
    // nothing yet, so make them look established first.
    await db.query('UPDATE providers SET completed_jobs = 3 WHERE user_id = (SELECT id FROM users WHERE phone_e164 = $1)', [RIVAL_PHONE]);
    const taken = await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: RIVAL_PHONE })
      .expect(409);
    expect(taken.body.code).toBe('has_own_business');

    const team = await api().get('/providers/me/staff').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(team.body).toHaveLength(1);
    expect(team.body[0]).toMatchObject({ id: inviteId, kind: 'invite', status: 'pending' });
    // Masked: the salon recognises the number, the API never echoes it whole.
    expect(team.body[0].phone).toBe(`+263 72 ••• ${RUN.slice(-4)}`);
    expect(team.body[0].phone).not.toContain(RUN.slice(0, 5));
  });

  it('lets the invitee see the salon and join it with a provider session', async () => {
    const none = await api().get('/auth/staff-invites').set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(none.body).toEqual([]);

    const mine = await api().get('/auth/staff-invites').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(mine.body).toHaveLength(1);
    expect(mine.body[0]).toMatchObject({ id: inviteId, salonName: 'Avondale Cuts' });
    expect(typeof mine.body[0].salonSuburb).toBe('string');

    // Somebody else's invitation is not found, not forbidden: an id is not
    // an oracle for whose it is.
    await api().post(`/auth/staff-invites/${inviteId}/accept`).set('Authorization', `Bearer ${clientToken}`).expect(404);

    // The partner app collects a name before anything else; the staff row
    // is named from it.
    await api()
      .post('/auth/profile')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ fullName: 'Tatenda Ncube', acceptTerms: true, acceptPrivacy: true })
      .expect(201);

    const joined = await api()
      .post(`/auth/staff-invites/${inviteId}/accept`)
      .set('Authorization', `Bearer ${staffToken}`)
      .expect(201);
    expect(joined.body.user.roles).toEqual(expect.arrayContaining(['client', 'provider']));
    expect(joined.body.accessToken).toBeTruthy();
    staffToken = joined.body.accessToken;

    const me = await api().get('/providers/me').set('Authorization', `Bearer ${staffToken}`).expect(200);
    staffId = me.body.id;
    expect(me.body.businessMode).toBe('salon_staff');
    expect(me.body.kycStatus).toBe('pending');
    expect(me.body.currency).toBe('USD');
    expect(me.body.serviceArea.name).toBe('Harare Metro');

    const team = await api().get('/providers/me/staff').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(team.body).toHaveLength(1);
    expect(team.body[0]).toMatchObject({ id: staffId, kind: 'staff', status: 'active', completedJobs: 0 });

    // Staff are not a business: the team screen is the salon's, not theirs.
    const refused = await api().get('/providers/me/staff').set('Authorization', `Bearer ${staffToken}`).expect(403);
    expect(refused.body.code).toBe('salon_only');

    const dup = await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: STAFF_PHONE })
      .expect(409);
    expect(dup.body.code).toBe('already_staff');
  });

  it('never shows a staff member in discovery, even once verified', async () => {
    await api()
      .post('/kyc/submissions')
      .set('Authorization', `Bearer ${staffToken}`)
      .send({
        documentType: 'national_id', idNumber: '63-100002-B-47', fullName: 'Tatenda Ncube',
        documentFrontKey: 'kyc/test/front.jpg', selfieKey: 'kyc/test/selfie.jpg',
      })
      .expect(201);
    await db.query(`UPDATE providers SET is_online = true WHERE id IN ($1, $2)`, [salonId, staffId]);

    const found = await api()
      .get('/discovery/providers')
      .query({ lat: AVONDALE.lat, lng: AVONDALE.lng, radiusKm: 10, limit: 50 })
      .set('Authorization', `Bearer ${clientToken}`)
      .expect(200);
    const ids = found.body.map((p: { providerId: string }) => p.providerId);
    expect(ids).toContain(salonId);
    expect(ids).not.toContain(staffId);

    // Back to pending so the next test can prove assign refuses an
    // unverified stylist before it accepts a verified one.
    await db.query(`UPDATE providers SET kyc_status = 'pending', is_online = false WHERE id = $1`, [staffId]);
  });

  it('books the salon, and only the salon can assign, only to verified staff', async () => {
    await api()
      .post('/auth/profile')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({ fullName: 'Rudo Chikore', acceptTerms: true, acceptPrivacy: true })
      .expect(201);

    const tomorrow = new Date();
    tomorrow.setUTCDate(tomorrow.getUTCDate() + 1);
    tomorrow.setUTCHours(10, 0, 0, 0);
    const key = `e2e-salon-${Date.now()}`;
    const booking = await api()
      .post('/bookings')
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', key)
      .send({
        providerId: salonId,
        serviceIds: [serviceId],
        destination: { lat: -17.81, lng: 31.05 },
        bookingType: 'scheduled',
        scheduledStart: tomorrow.toISOString(),
        destinationAddress: '14 King George Rd, Avondale',
      })
      .expect(201);
    bookingId = booking.body.id;
    expect(booking.body).toMatchObject({ assignedStaffId: null, assignedStaffName: null, reviewedByMe: false });

    await api()
      .post(`/bookings/${bookingId}/checkout`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', `${key}-pay`)
      .send({ method: 'ecocash' })
      .expect(201);

    // Unassigned, the job is the salon's alone.
    const notTheirs = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${staffToken}`).expect(404);
    expect(notTheirs.body.code).toBe('not_found');
    const sideways = await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ staffId })
      .expect(403);
    expect(sideways.body.code).toBe('not_your_booking');

    const unverified = await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ staffId })
      .expect(403);
    expect(unverified.body.code).toBe('staff_unverified');

    await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${salonToken}`)
      .send({})
      .expect(400);
    const stranger = await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ staffId: salonId })
      .expect(404);
    expect(stranger.body.code).toBe('staff_not_found');

    await db.query(`UPDATE providers SET kyc_status = 'verified', kyc_verified_at = now() WHERE id = $1`, [staffId]);
    const assigned = await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ staffId })
      .expect(201);
    expect(assigned.body).toEqual({ assignedStaffId: staffId });

    const forSalon = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(forSalon.body).toMatchObject({ assignedStaffId: staffId, assignedStaffName: 'Tatenda Ncube' });
    const forStaff = await api().get('/bookings').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(forStaff.body.map((b: { id: string }) => b.id)).toContain(bookingId);
    const forClient = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(forClient.body.assignedStaffName).toBe('Tatenda Ncube');

    const staffDiary = await api().get('/providers/me/schedule').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(staffDiary.body.map((b: { id: string }) => b.id)).toContain(bookingId);
    const salonDiary = await api().get('/providers/me/schedule').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(salonDiary.body.find((b: { id: string }) => b.id === bookingId).assignedStaffName).toBe('Tatenda Ncube');
    const rivalDiary = await api().get('/providers/me/schedule').set('Authorization', `Bearer ${rivalToken}`).expect(200);
    expect(rivalDiary.body.map((b: { id: string }) => b.id)).not.toContain(bookingId);
  });

  it('lets the stylist run the job and pays the salon, not the stylist', async () => {
    for (const status of ['en_route', 'arrived']) {
      await api()
        .post(`/bookings/${bookingId}/status`)
        .set('Authorization', `Bearer ${staffToken}`)
        .send({ status })
        .expect(201);
    }
    // Once on the way, the salon can no longer reshuffle it.
    const late = await api()
      .post(`/bookings/${bookingId}/assign`)
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ staffId: null })
      .expect(409);
    expect(late.body.code).toBe('booking_not_assignable');

    await api()
      .post(`/bookings/${bookingId}/chat`)
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ body: 'Outside now' })
      .expect(201);
    const chat = await api().get(`/bookings/${bookingId}/chat`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(chat.body.map((m: { body: string }) => m.body)).toContain('Outside now');

    const pin = await api().get(`/bookings/${bookingId}/pin`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    await api()
      .post(`/bookings/${bookingId}/verify-pin`)
      .set('Authorization', `Bearer ${rivalToken}`)
      .send({ pin: pin.body.pin })
      .expect(403);
    await api()
      .post(`/bookings/${bookingId}/verify-pin`)
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ pin: pin.body.pin })
      .expect(201);
    await api()
      .post(`/bookings/${bookingId}/complete`)
      .set('Authorization', `Bearer ${staffToken}`)
      .set('Idempotency-Key', `complete-${bookingId}`)
      .expect(201);

    const salonWallet = await api().get('/payouts/wallet').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(salonWallet.body.currency).toBe('USD');
    expect(salonWallet.body.availableMinor).toBeGreaterThan(0);
    const staffWallet = await api().get('/payouts/wallet').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(staffWallet.body.availableMinor).toBe(0);

    // The provider's earnings are credited against the salon; the stylist
    // never appears in the ledger at all.
    const ledger = await db.query(
      `SELECT counterparty_provider_id AS provider_id, SUM(signed_minor) AS net
         FROM ledger_entries WHERE booking_id = $1 GROUP BY counterparty_provider_id`,
      [bookingId],
    );
    expect(ledger.rows.map((r) => r.provider_id)).toContain(salonId);
    expect(ledger.rows.map((r) => r.provider_id)).not.toContain(staffId);
    const total = ledger.rows.reduce((acc, r) => acc + Number(r.net), 0);
    expect(total).toBe(0);

    const team = await api().get('/providers/me/staff').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(team.body.find((m: { id: string }) => m.id === staffId).completedJobs).toBe(1);
  });

  it('leaves two numbered invoices behind, each visible to the right people', async () => {
    const forSalon = await api().get(`/bookings/${bookingId}/invoices`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    invoices = forSalon.body;
    expect(invoices.map((i) => i.kind)).toEqual(['provider_to_client', 'platform_to_provider']);
    for (const inv of invoices) expect(inv.number).toMatch(/^FR-ZW-\d{4}-\d{6}$/);
    const seq = invoices.map((i) => Number(i.number.slice(-6)));
    expect(seq[1]).toBe(seq[0] + 1);
    expect(forSalon.body[0].currency).toBe('USD');
    // Skin fade plus travel, without our service fee; ours is 12.5% plus the fee.
    const booking = await db.query('SELECT total_minor, service_fee_minor, commission_minor FROM bookings WHERE id = $1', [bookingId]);
    const b = booking.rows[0];
    expect(forSalon.body[0].totalMinor).toBe(Number(b.total_minor) - Number(b.service_fee_minor));
    expect(forSalon.body[1].totalMinor).toBe(Number(b.commission_minor) + Number(b.service_fee_minor));

    const forClient = await api().get(`/bookings/${bookingId}/invoices`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(forClient.body.map((i: { kind: string }) => i.kind)).toEqual(['provider_to_client']);
    const forStaff = await api().get(`/bookings/${bookingId}/invoices`).set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(forStaff.body.map((i: { kind: string }) => i.kind)).toEqual(['provider_to_client']);
    const forAdmin = await api().get(`/bookings/${bookingId}/invoices`).set('Authorization', `Bearer ${adminToken}`).expect(200);
    expect(forAdmin.body).toHaveLength(2);
    await api().get(`/bookings/${bookingId}/invoices`).set('Authorization', `Bearer ${rivalToken}`).expect(403);

    // Nothing on a row identifies a person beyond a name and a phone's tail.
    const rows = await db.query('SELECT issuer_detail, recipient_detail FROM invoices WHERE booking_id = $1', [bookingId]);
    for (const r of rows.rows) {
      for (const detail of [r.issuer_detail, r.recipient_detail]) {
        if (detail) expect(detail).not.toMatch(/\+?263\d{6,}/);
      }
    }
  });

  it('renders each invoice as a PDF under the same rules', async () => {
    const [toClient, toProvider] = invoices;
    const pdf = await api()
      .get(`/invoices/${toProvider.id}.pdf`)
      .set('Authorization', `Bearer ${salonToken}`)
      .buffer(true)
      .parse(binary)
      .expect(200)
      .expect('Content-Type', /application\/pdf/);
    expect((pdf.body as Buffer).subarray(0, 4).toString()).toBe('%PDF');
    expect(pdf.headers['content-disposition']).toContain(`${toProvider.number}.pdf`);

    const clientPdf = await api()
      .get(`/invoices/${toClient.id}.pdf`)
      .set('Authorization', `Bearer ${clientToken}`)
      .buffer(true)
      .parse(binary)
      .expect(200);
    expect((clientPdf.body as Buffer).subarray(0, 4).toString()).toBe('%PDF');

    const refused = await api().get(`/invoices/${toProvider.id}.pdf`).set('Authorization', `Bearer ${clientToken}`).expect(403);
    expect(refused.body.code).toBe('not_your_booking');
    await api().get(`/invoices/${toProvider.id}.pdf`).set('Authorization', `Bearer ${rivalToken}`).expect(403);
    await api().get(`/invoices/00000000-0000-4000-8000-000000000000.pdf`).set('Authorization', `Bearer ${salonToken}`).expect(404);
  });

  it('flips reviewedByMe for whoever wrote the review', async () => {
    const before = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(before.body.reviewedByMe).toBe(false);

    await api()
      .post(`/bookings/${bookingId}/review`)
      .set('Authorization', `Bearer ${clientToken}`)
      .send({ rating: 5, tags: ['On time', 'Great cut'] })
      .expect(201);
    const afterClient = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${clientToken}`).expect(200);
    expect(afterClient.body.reviewedByMe).toBe(true);
    const salonView = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(salonView.body.reviewedByMe).toBe(false);

    // A stranger cannot rate someone else's client.
    const stranger = await api()
      .post(`/bookings/${bookingId}/review`)
      .set('Authorization', `Bearer ${rivalToken}`)
      .send({ rating: 1, tags: [] })
      .expect(403);
    expect(stranger.body.code).toBe('not_your_booking');

    await api()
      .post(`/bookings/${bookingId}/review`)
      .set('Authorization', `Bearer ${staffToken}`)
      .send({ rating: 5, tags: ['Friendly'] })
      .expect(201);
    const staffView = await api().get('/bookings').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(staffView.body.find((b: { id: string }) => b.id === bookingId).reviewedByMe).toBe(true);
  });

  it('removes a team member back to a solo row and cancels an open invitation', async () => {
    const extra = await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: '0779990001' })
      .expect(201);
    await api().delete(`/providers/me/staff/${extra.body.id}`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    // Cancelled, so it can be sent again.
    await api()
      .post('/providers/me/staff/invites')
      .set('Authorization', `Bearer ${salonToken}`)
      .send({ phone: '0779990001' })
      .expect(201);

    await api().delete(`/providers/me/staff/${staffId}`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    const me = await api().get('/providers/me').set('Authorization', `Bearer ${staffToken}`).expect(200);
    expect(me.body.businessMode).toBe('solo');
    expect(me.body.isOnline).toBe(false);
    await api().delete(`/providers/me/staff/${staffId}`).set('Authorization', `Bearer ${salonToken}`).expect(404);

    const team = await api().get('/providers/me/staff').set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(team.body.map((m: { id: string }) => m.id)).not.toContain(staffId);

    // The finished job keeps its history: who did it is still on the record.
    const done = await api().get(`/bookings/${bookingId}`).set('Authorization', `Bearer ${salonToken}`).expect(200);
    expect(done.body.assignedStaffId).toBe(staffId);
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
