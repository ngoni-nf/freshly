const fs = require('fs');
const { Client } = require('pg');

const env = Object.fromEntries(
  fs
    .readFileSync('.env', 'utf8')
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
);

const c = new Client({ connectionString: env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

let pass = 0;
let fail = 0;
const ok = (m) => { pass++; console.log(`  ok    ${m}`); };
const bad = (m) => { fail++; console.log(`  FAIL  ${m}`); };

async function expectReject(label, sql, params, matcher) {
  try {
    await c.query(sql, params);
    bad(`${label} — was ACCEPTED but should have been refused`);
  } catch (e) {
    if (matcher && !matcher.test(e.message)) bad(`${label} — refused for the wrong reason: ${e.message}`);
    else ok(`${label} — refused: ${e.message.slice(0, 70)}`);
  }
}

async function expectAccept(label, sql, params) {
  try {
    await c.query(sql, params);
    ok(label);
  } catch (e) {
    bad(`${label} — ${e.message}`);
  }
}

(async () => {
  await c.connect();
  const { rows } = await c.query("SELECT id FROM providers WHERE slug = 'sipho-m'");
  const provider = rows[0].id;
  const ins = `INSERT INTO services (provider_id, name, description, category, venue_mode, price_minor, currency, duration_minutes)
               VALUES ($1, $2, 'test', $3::service_category_enum, $4::service_venue_enum, 50000, 'ZAR', 120)`;

  console.log('\nUncredentialed provider');
  await expectReject('microblading, in shop', ins, [provider, 'Microblading full set', 'brows', 'in_shop'], /no verified/);
  await expectReject('microblading, mobile', ins, [provider, 'Microblading full set', 'brows', 'mobile'], /premises/);
  await expectReject('SMP filed under barber to dodge the rule', ins, [provider, 'Scalp micropigmentation', 'barber', 'mobile'], /premises|no verified/);
  await expectReject('laser filed under body_grooming', ins, [provider, 'Laser hair removal - full legs', 'body_grooming', 'in_shop'], /no verified/);

  console.log('\nOrdinary work in the same categories is untouched');
  await expectAccept('brow threading, mobile', ins, [provider, 'Brow threading and tint', 'brows', 'mobile']);
  await expectAccept('deep cleansing facial, mobile', ins, [provider, 'Deep cleansing facial', 'aesthetics', 'mobile']);
  await expectAccept('waxing, mobile', ins, [provider, 'Half leg wax', 'body_grooming', 'mobile']);

  console.log('\nWith a verified credential');
  await c.query(
    `INSERT INTO provider_credentials (provider_id, category, credential_kind, issuer, status)
     VALUES ($1, 'brows', 'skin_penetration_permit', 'City of Johannesburg', 'verified')`,
    [provider],
  );
  await expectAccept('microblading, in shop', ins, [provider, 'Microblading full set', 'brows', 'in_shop']);
  await expectReject('microblading, mobile — still premises-only', ins, [provider, 'Microblading touch up', 'brows', 'mobile'], /premises/);

  const flagged = await c.query(
    "SELECT requires_credential FROM services WHERE name = 'Microblading full set' AND provider_id = $1",
    [provider],
  );
  flagged.rows[0].requires_credential
    ? ok('trigger stamped requires_credential on the row')
    : bad('requires_credential was not stamped');

  console.log('\nDiscovery re-checks at read time');
  const visible = async () => {
    const r = await c.query(
      `SELECT 1 FROM fn_search_providers(-26.1076, 28.0473, 15, 'brows'::service_category_enum) WHERE provider_id = $1`,
      [provider],
    );
    return r.rowCount > 0;
  };
  (await visible()) ? ok('credentialed provider is discoverable for brows') : bad('should be discoverable');

  await c.query("UPDATE provider_credentials SET expires_on = CURRENT_DATE - 1 WHERE provider_id = $1", [provider]);
  // The ungated brow threading service keeps them visible, so check the gated
  // service specifically rather than the provider as a whole.
  const gated = await c.query(
    `SELECT COUNT(*)::int AS n FROM services s
      WHERE s.provider_id = $1 AND s.requires_credential
        AND fn_provider_has_credential(s.provider_id, s.category)`,
    [provider],
  );
  gated.rows[0].n === 0
    ? ok('an expired licence hides the gated service')
    : bad(`expired licence still passes: ${gated.rows[0].n} gated services still allowed`);

  console.log(`\n${pass} passed, ${fail} failed`);
  await c.end();
  process.exit(fail === 0 ? 0 : 1);
})();
