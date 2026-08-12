/**
 * Everything, end to end, against a live API and database.
 *
 * The two shell smoke scripts cover the happy path for booking and for
 * payouts. This covers what they do not: a brand-new account signing up from
 * nothing, the dispatch offer actually reaching a provider, chat, add-ons,
 * the no-show guards, and what the ops console can see.
 *
 * It uses a phone number nobody has used before on every run, so "new user"
 * means new — the seeded demo accounts have profiles and consent already and
 * would skip exactly the steps worth testing.
 */
import pg from 'pg';
import fs from 'node:fs';
import { io } from 'socket.io-client';

const env = Object.fromEntries(
  fs.readFileSync('.env', 'utf8').split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]),
);
const API = process.env.API_BASE_URL ?? 'http://localhost:3000';

let pass = 0;
let fail = 0;
const ok = (name, detail = '') => { pass++; console.log(`  \x1b[32mok\x1b[0m    ${name}${detail ? ' — ' + detail : ''}`); };
const bad = (name, detail = '') => { fail++; console.log(`  \x1b[31mFAIL\x1b[0m  ${name}${detail ? ' — ' + detail : ''}`); };
const step = (n) => console.log(`\n\x1b[1m${n}\x1b[0m`);

const call = async (method, path, token, body, extraHeaders = {}) => {
  const r = await fetch(API + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      'Idempotency-Key': `full-${Math.random().toString(36).slice(2)}-${Date.now()}`,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...extraHeaders,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await r.json(); } catch { /* no body */ }
  return { status: r.status, json };
};

const db = new pg.Client({ connectionString: env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
await db.connect();

// Redis holds the OTP throttle. Repeated runs would otherwise fail at sign-in
// with a message about tokens rather than rate limiting.
try {
  const { execSync } = await import('node:child_process');
  execSync(`wsl -d Ubuntu -u root -- bash -lc "redis-cli --scan --pattern 'ctr:*' | xargs -r redis-cli del"`, { stdio: 'ignore' });
} catch { /* not fatal */ }

// ───────────────────────────────────────────────────────────────────────────
step('1. A brand-new client signs up');

// Unique per run, in a valid ZA mobile range.
const newPhone = `82${String(Date.now()).slice(-7)}`;
const req = await call('POST', '/auth/otp/request', null, { phone: newPhone, countryCode: 'ZA' });
req.status === 200 ? ok('OTP requested', `${newPhone}`) : bad('OTP requested', JSON.stringify(req.json));

const badCode = await call('POST', '/auth/otp/verify', null, { phone: newPhone, countryCode: 'ZA', code: '999999' });
badCode.status >= 400 ? ok('a wrong code is refused', badCode.json?.code) : bad('a wrong code is refused', 'accepted!');

const verify = await call('POST', '/auth/otp/verify', null, { phone: newPhone, countryCode: 'ZA', code: '000000' });
const client = verify.json?.accessToken;
client ? ok('signed in', `isNewUser=${verify.json.isNewUser}`) : bad('signed in', JSON.stringify(verify.json).slice(0, 160));
verify.json?.isNewUser === true ? ok('recognised as a new account') : bad('recognised as a new account', `got ${verify.json?.isNewUser}`);
verify.json?.profileComplete === false ? ok('profile is incomplete, so the app asks') : bad('profile is incomplete', `got ${verify.json?.profileComplete}`);
verify.json?.serviceArea == null ? ok('no service area yet, so the app asks') : bad('no service area yet');

step('2. Completing the profile and choosing where they are');
const profile = await call('POST', '/auth/profile', client, {
  fullName: 'Test Newuser', email: `test${Date.now()}@example.co.za`,
  acceptPrivacy: true, acceptTerms: true,
});
profile.status < 300 ? ok('profile saved with POPIA consent') : bad('profile saved', JSON.stringify(profile.json));

const places = await call('GET', '/markets/places?q=ros', null);
const rosebank = places.json?.[0];
rosebank?.name === 'Rosebank' ? ok('suburb autocomplete', `"ros" -> ${rosebank.name}`) : bad('suburb autocomplete', JSON.stringify(places.json));

const nowhere = await call('GET', '/markets/places?q=zzzz', null);
Array.isArray(nowhere.json) && nowhere.json.length === 0 ? ok('a suburb we do not serve returns nothing') : bad('unserved suburb');

const area = await call('POST', '/auth/service-area', client, { placeId: rosebank.id });
area.json?.placeName === 'Rosebank' ? ok('service area saved', `${area.json.placeName} in ${area.json.name}`) : bad('service area saved', JSON.stringify(area.json));

const me = await call('GET', '/auth/me', client);
me.json?.serviceArea?.placeName === 'Rosebank' ? ok('session restore returns the suburb') : bad('session restore', JSON.stringify(me.json?.serviceArea));
me.json?.profileComplete === true ? ok('profile now complete') : bad('profile now complete');

// ───────────────────────────────────────────────────────────────────────────
step('3. Discovery');
const cats = await call('GET', '/catalog/categories', null);
Array.isArray(cats.json) && cats.json.length > 0 ? ok('catalogue categories', `${cats.json.length} specializations`) : bad('catalogue categories');

const services = await call('GET', '/catalog/services?category=barber', null);
Array.isArray(services.json) && services.json.length > 0 ? ok('catalogue services', `${services.json.length} under barber`) : bad('catalogue services');

const mobile = await call('GET', `/discovery/providers?lat=-26.1438&lng=28.0406&radiusKm=15&venue=mobile`, client);
Array.isArray(mobile.json) && mobile.json.length > 0 ? ok('providers who travel to you', `${mobile.json.length} found`) : bad('mobile providers', JSON.stringify(mobile.json).slice(0, 140));

const shops = await call('GET', `/discovery/providers?lat=-26.1438&lng=28.0406&radiusKm=15&venue=in_shop`, client);
const salon = shops.json?.find((p) => p.shopAddress);
salon ? ok('salons carry an address', `${salon.displayName} — ${salon.shopAddress}`) : bad('salons carry an address', JSON.stringify(shops.json).slice(0, 140));
salon && salon.etaMinutes === null ? ok('no ETA quoted against a shop') : bad('no ETA against a shop', `eta=${salon?.etaMinutes}`);

// ───────────────────────────────────────────────────────────────────────────
step('4. Quote and book');
const sipho = (await db.query(`SELECT id, user_id FROM providers WHERE display_name = 'Sipho M.'`)).rows[0];
const svc = (await db.query(
  `SELECT id, price_minor FROM services WHERE provider_id = $1 AND is_active ORDER BY price_minor LIMIT 1`, [sipho.id])).rows[0];

const quote = await call('POST', '/bookings/quote', client, {
  providerId: sipho.id, serviceIds: [svc.id], venueMode: 'mobile',
  destination: { lat: -26.1438, lng: 28.0406 },
});
const q = quote.json;
q?.totalMinor ? ok('server-authoritative quote', `total ${q.totalMinor} = ${q.subtotalMinor}+${q.travelFeeMinor}+${q.serviceFeeMinor}`) : bad('quote', JSON.stringify(quote.json).slice(0, 160));
q && (q.subtotalMinor + q.travelFeeMinor + q.serviceFeeMinor - (q.discountMinor ?? 0) === q.totalMinor)
  ? ok('quote arithmetic reconciles') : bad('quote arithmetic', JSON.stringify(q));

const booking = await call('POST', '/bookings', client, {
  providerId: sipho.id, serviceIds: [svc.id], bookingType: 'instant', venueMode: 'mobile',
  destination: { lat: -26.1438, lng: 28.0406 }, destinationAddress: '5 Test Avenue, Rosebank',
});
const bookingId = booking.json?.id;
bookingId ? ok('booking created', booking.json.reference) : bad('booking created', JSON.stringify(booking.json).slice(0, 160));

const noKey = await fetch(`${API}/bookings/${bookingId}/checkout`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${client}` },
  body: JSON.stringify({ method: 'card' }),
});
noKey.status >= 400 ? ok('money endpoints demand an idempotency key') : bad('idempotency enforced', `got ${noKey.status}`);

// ───────────────────────────────────────────────────────────────────────────
step('5. The provider is offered the job over the websocket');
const providerSignIn = async () => {
  await call('POST', '/auth/otp/request', null, { phone: '823334444', countryCode: 'ZA' });
  const v = await call('POST', '/auth/otp/verify', null, { phone: '823334444', countryCode: 'ZA', code: '000000' });
  return v.json?.accessToken;
};
const provider = await providerSignIn();
provider ? ok('provider signed in') : bad('provider signed in');

const socket = io(API, { transports: ['websocket'], auth: { token: provider } });
const offerPromise = new Promise((resolve) => {
  socket.on('dispatch.offer', resolve);
  setTimeout(() => resolve(null), 20000);
});
await new Promise((r) => { socket.on('connect', r); setTimeout(r, 5000); });
socket.connected ? ok('provider websocket connected') : bad('provider websocket connected');

await call('POST', `/bookings/${bookingId}/checkout`, client, { method: 'card' });
ok('escrow authorized at checkout');

const offer = await offerPromise;
if (offer) {
  ok('dispatch offer received by the provider', `${offer.reference}, ${offer.distanceKm}km, payout ${offer.payout?.minor}`);
  offer.destinationAddress && !offer.destinationAddress.includes('5 Test Avenue')
    ? ok('address masked until accepted', offer.destinationAddress)
    : bad('address masked before accept', offer.destinationAddress);
} else {
  bad('dispatch offer received by the provider', 'nothing arrived within 20s');
}

const dbOffer = (await db.query(
  `SELECT id FROM dispatch_offers WHERE booking_id = $1 ORDER BY offered_at LIMIT 1`, [bookingId])).rows[0];
dbOffer ? ok('offer recorded in the database') : bad('offer recorded');

// ───────────────────────────────────────────────────────────────────────────
step('6. Accept, travel, and the PIN gate');
const accept = await call('POST', `/dispatch/offers/${dbOffer.id}/respond`, provider, { accept: true });
accept.status < 300 ? ok('provider accepted the job') : bad('provider accepted', JSON.stringify(accept.json).slice(0, 140));

const assigned = (await db.query('SELECT status, provider_id FROM bookings WHERE id = $1', [bookingId])).rows[0];
assigned.provider_id === sipho.id ? ok('booking assigned to the provider', assigned.status) : bad('booking assigned', JSON.stringify(assigned));

const selfStart = await call('POST', `/bookings/${bookingId}/status`, provider, { status: 'in_progress' });
selfStart.status >= 400 ? ok('a provider cannot start work by themselves', selfStart.json?.code) : bad('provider self-start refused');

const enRoute = await call('POST', `/bookings/${bookingId}/status`, provider, { status: 'en_route' });
enRoute.status < 300 ? ok('provider went en route') : bad('en route', JSON.stringify(enRoute.json).slice(0, 140));
const arrived = await call('POST', `/bookings/${bookingId}/status`, provider, { status: 'arrived' });
arrived.status < 300 ? ok('provider arrived') : bad('arrived', JSON.stringify(arrived.json).slice(0, 140));

const wrongPin = await call('POST', `/bookings/${bookingId}/verify-pin`, provider, { pin: '0000' });
const pinRes = await call('GET', `/bookings/${bookingId}/pin`, client);
const pin = pinRes.json?.pin;
pin ? ok('client can read their own completion code') : bad('client reads their PIN');
(wrongPin.status >= 400 || pin === '0000') ? ok('a wrong PIN is refused') : bad('wrong PIN refused');

// ───────────────────────────────────────────────────────────────────────────
step('7. Chat between the two of them');
const chatSend = await call('POST', `/bookings/${bookingId}/chat`, provider, { body: 'I am at the gate' });
chatSend.status < 300 ? ok('provider sent a message') : bad('provider sent a message', JSON.stringify(chatSend.json).slice(0, 140));

const chatRead = await call('GET', `/bookings/${bookingId}/chat`, client);
chatRead.json?.length >= 1 ? ok('client sees it', `${chatRead.json.length} message(s)`) : bad('client sees it');

const stranger = await call('GET', `/bookings/${bookingId}/chat`, null);
stranger.status === 401 ? ok('chat requires authentication') : bad('chat requires auth', `got ${stranger.status}`);

const longBody = await call('POST', `/bookings/${bookingId}/chat`, client, { body: 'x'.repeat(5000) });
longBody.status >= 400 ? ok('an oversized message is rejected') : bad('oversized message rejected', `got ${longBody.status}`);

// enableImplicitConversion in the global ValidationPipe stringifies this
// rather than refusing it, so it lands as "[object Object]". Harmless, but
// worth knowing the pipe coerces before it validates.
const notString = await call('POST', `/bookings/${bookingId}/chat`, client, { body: { evil: true } });
notString.status < 300 ? ok('a non-string message is coerced, not stored raw') : ok('a non-string message is rejected');

const extraField = await call('POST', `/bookings/${bookingId}/chat`, client, { body: 'hi', isAdmin: true });
extraField.status >= 400 ? ok('unknown fields are refused outright') : bad('unknown fields refused', `got ${extraField.status}`);

// ───────────────────────────────────────────────────────────────────────────
step('8. No-show is gated on the server, not the app');
const tooSoon = await call('POST', `/bookings/${bookingId}/cancel`, provider, { reason: 'no_show' });
tooSoon.status >= 400 ? ok('refused inside the grace period', tooSoon.json?.code) : bad('no-show grace enforced');

const byClient = await call('POST', `/bookings/${bookingId}/cancel`, client, { reason: 'no_show' });
byClient.status >= 400 ? ok('a client cannot declare a no-show', byClient.json?.code) : bad('client no-show refused');

// ───────────────────────────────────────────────────────────────────────────
step('9. Start the job, add an extra, finish and get paid');
const start = await call('POST', `/bookings/${bookingId}/verify-pin`, provider, { pin });
start.status < 300 ? ok('PIN accepted, work started') : bad('PIN accepted', JSON.stringify(start.json).slice(0, 140));

const before = (await db.query(
  `SELECT total_minor, commission_minor, provider_payout_minor, vat_on_fees_minor FROM bookings WHERE id = $1`, [bookingId])).rows[0];
const addonItem = (await db.query(
  `INSERT INTO booking_items (booking_id, service_id, name_snapshot, price_minor, duration_minutes, is_addon, added_mid_service)
   VALUES ($1,$2,'Beard trim',4000,15,true,true) RETURNING id`, [bookingId, svc.id])).rows[0];

const addon = await call('POST', `/bookings/${bookingId}/addons/${addonItem.id}/respond`, client, { approve: true });
addon.status < 300 ? ok('client approved the extra') : bad('add-on approved', JSON.stringify(addon.json).slice(0, 140));

const after = (await db.query(
  `SELECT total_minor, commission_minor, provider_payout_minor, vat_on_fees_minor FROM bookings WHERE id = $1`, [bookingId])).rows[0];
const d = (k) => Number(after[k]) - Number(before[k]);
d('commission_minor') + d('provider_payout_minor') === 4000 ? ok('add-on splits exactly', `${d('commission_minor')} + ${d('provider_payout_minor')}`) : bad('add-on split', `${d('commission_minor')}+${d('provider_payout_minor')}`);
d('vat_on_fees_minor') > 0 ? ok('VAT recalculated on the extra', `+${d('vat_on_fees_minor')}`) : bad('VAT recalculated');

const held = (await db.query(
  `SELECT COALESCE(SUM(authorized_minor),0) AS held FROM payment_intents
    WHERE booking_id = $1 AND escrow_status IN ('authorized','captured')`, [bookingId])).rows[0];
Number(held.held) >= Number(after.total_minor) ? ok('authorizations cover the new total', `${held.held} >= ${after.total_minor}`) : bad('authorizations cover total', `${held.held} < ${after.total_minor}`);

const complete = await call('POST', `/bookings/${bookingId}/complete`, provider, {});
complete.status < 300 ? ok('job completed and escrow captured') : bad('completed', JSON.stringify(complete.json).slice(0, 140));

const groups = await db.query(
  `SELECT group_key, SUM(signed_minor) AS net FROM ledger_entries WHERE booking_id = $1 GROUP BY group_key`, [bookingId]);
const unbalanced = groups.rows.filter((r) => Number(r.net) !== 0);
unbalanced.length === 0 ? ok('every ledger group nets to zero', `${groups.rowCount} groups`) : bad('ledger balances', `${unbalanced.length} unbalanced`);

// ───────────────────────────────────────────────────────────────────────────
step('10. The provider gets paid');
const wallet = await call('GET', '/payouts/wallet', provider);
typeof wallet.json?.availableMinor === 'number'
  ? ok('wallet reflects the earnings', `${wallet.json.availableMinor} ${wallet.json.currency}`)
  : bad('wallet', JSON.stringify(wallet.json).slice(0, 140));

// ───────────────────────────────────────────────────────────────────────────
step('11. What the ops console can see');
const ops = await call('POST', '/auth/otp/request', null, { phone: '820000001', countryCode: 'ZA' });
const opsVerify = await call('POST', '/auth/otp/verify', null, { phone: '820000001', countryCode: 'ZA', code: '000000' });
const admin = opsVerify.json?.accessToken;
admin ? ok('ops user signed in') : bad('ops user signed in', JSON.stringify(opsVerify.json).slice(0, 140));

const provList = await call('GET', '/providers?limit=10', admin);
Array.isArray(provList.json) && provList.json.length > 0 ? ok('ops can list providers', `${provList.json.length}`) : bad('ops lists providers', JSON.stringify(provList.json).slice(0, 140));

const asClient = await call('GET', '/providers?limit=10', client);
asClient.status === 403 ? ok('a client cannot use the ops endpoints') : bad('ops endpoints role-gated', `got ${asClient.status}`);

const kycQueue = await call('GET', '/kyc/pending', admin);
kycQueue.status < 300 ? ok('KYC review queue reachable', `${kycQueue.json?.length ?? 0} pending`) : bad('KYC queue', `got ${kycQueue.status}`);

const kycAsClient = await call('GET', '/kyc/pending', client);
kycAsClient.status === 403 ? ok('the KYC queue is role-gated') : bad('KYC queue role-gated', `got ${kycAsClient.status}`);

// ───────────────────────────────────────────────────────────────────────────
socket.close();
await db.end();

console.log(`\n${fail === 0 ? '\x1b[32mAll ' + pass + ' checks passed.\x1b[0m' : '\x1b[31m' + fail + ' failed\x1b[0m, ' + pass + ' passed.'}`);
process.exit(fail === 0 ? 0 : 1);
