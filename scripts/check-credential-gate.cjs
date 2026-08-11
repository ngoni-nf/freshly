const fs = require('fs');
const { Client } = require('pg');

// A real environment variable wins, so this runs in CI where there is no .env.
const fromFile = fs.existsSync('.env')
  ? Object.fromEntries(
      fs
        .readFileSync('.env', 'utf8')
        .split(/\r?\n/)
        .filter((l) => l && !l.startsWith('#') && l.includes('='))
        .map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1).trim()]),
    )
  : {};
const env = { ...fromFile, ...process.env };

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

  // Everything this script creates is tagged with a run id and removed at the
  // end, so it can be run repeatedly against the same database. The previous
  // version tripped over its own leftovers on a second run — a unique
  // violation on provider_credentials — and looked like a real regression.
  const runId = Date.now().toString(36);
  const tag = (name) => `${name} [check ${runId}]`;

  // Start uncredentialed whatever happened last time. The first assertions are
  // about a provider who holds no licence, so an leftover credential from an
  // interrupted run would make them silently pass for the wrong reason.
  const cleanup = async () => {
    await c.query('DELETE FROM services WHERE provider_id = $1 AND name LIKE $2', [
      provider,
      '%[check %',
    ]);
    await c.query(
      `DELETE FROM provider_credentials
        WHERE provider_id = $1 AND category = 'brows' AND credential_kind = 'skin_penetration_permit'`,
      [provider],
    );
  };
  await cleanup();

  const ins = `INSERT INTO services (provider_id, name, description, category, venue_mode, price_minor, currency, duration_minutes)
               VALUES ($1, $2, 'test', $3::service_category_enum, $4::service_venue_enum, 50000, 'ZAR', 120)`;

  console.log('\nUncredentialed provider');
  await expectReject('microblading, in shop', ins, [provider, tag('Microblading full set'), 'brows', 'in_shop'], /no verified/);
  await expectReject('microblading, mobile', ins, [provider, tag('Microblading full set'), 'brows', 'mobile'], /premises/);
  await expectReject('SMP filed under barber to dodge the rule', ins, [provider, tag('Scalp micropigmentation'), 'barber', 'mobile'], /premises|no verified/);
  await expectReject('laser filed under body_grooming', ins, [provider, tag('Laser hair removal - full legs'), 'body_grooming', 'in_shop'], /no verified/);

  console.log('\nOrdinary work in the same categories is untouched');
  await expectAccept('brow threading, mobile', ins, [provider, tag('Brow threading and tint'), 'brows', 'mobile']);
  await expectAccept('deep cleansing facial, mobile', ins, [provider, tag('Deep cleansing facial'), 'aesthetics', 'mobile']);
  await expectAccept('waxing, mobile', ins, [provider, tag('Half leg wax'), 'body_grooming', 'mobile']);

  console.log('\nWith a verified credential');
  await c.query(
    `INSERT INTO provider_credentials (provider_id, category, credential_kind, issuer, status)
     VALUES ($1, 'brows', 'skin_penetration_permit', 'City of Johannesburg', 'verified')
     ON CONFLICT (provider_id, category, credential_kind) DO UPDATE
       SET status = 'verified', expires_on = NULL`,
    [provider],
  );
  await expectAccept('microblading, in shop', ins, [provider, tag('Microblading full set'), 'brows', 'in_shop']);
  await expectReject('microblading, mobile — still premises-only', ins, [provider, tag('Microblading touch up'), 'brows', 'mobile'], /premises/);

  const flagged = await c.query(
    'SELECT requires_credential FROM services WHERE provider_id = $1 AND name = $2',
    [provider, tag('Microblading full set')],
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

  // Leave the database as we found it, so a developer's demo data is not
  // littered with test services.
  await cleanup();

  console.log(`\n${pass} passed, ${fail} failed`);
  await c.end();
  process.exit(fail === 0 ? 0 : 1);
})();
