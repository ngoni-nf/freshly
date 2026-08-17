/**
 * Push the API's secrets to Fly in one call.
 *
 * Reads .env, drops what belongs to the deployment rather than the app
 * (PORT, NODE_ENV, DATABASE_SSL live in fly.toml), and sets the rest as
 * secrets. One `flyctl secrets set` rather than twenty, because each call
 * restarts the machine.
 *
 * REDIS_URL is overridden from the argument, since the local one points at
 * WSL and would leave a deployed API trying to reach a laptop.
 *
 *   node scripts/fly-secrets.mjs <app-name> <upstash-rediss-url>
 */
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const [app, redisUrl] = process.argv.slice(2);
if (!app || !redisUrl) {
  console.error('usage: node scripts/fly-secrets.mjs <app-name> <rediss://...>');
  process.exit(1);
}
if (!redisUrl.startsWith('rediss://') && !redisUrl.startsWith('redis://')) {
  console.error('The Redis URL should start with rediss:// (TLS) from Upstash.');
  process.exit(1);
}

// In fly.toml, not secrets: they are not sensitive and belong with the deploy.
const DEPLOY_OWNED = new Set(['NODE_ENV', 'PORT', 'DATABASE_SSL', 'API_BASE_URL']);

const env = Object.fromEntries(
  fs.readFileSync(path.join(process.cwd(), '.env'), 'utf8')
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#') && l.includes('='))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])
    .filter(([k, v]) => v !== '' && !DEPLOY_OWNED.has(k)),
);

env.REDIS_URL = redisUrl;

// The console's origin, so the browser is allowed to call the API at all.
// Set now with a placeholder and corrected once the console is deployed —
// an empty allowlist in staging is permissive, in production it is not.
env.CORS_ORIGINS = env.CORS_ORIGINS || 'http://localhost:5173';

const pairs = Object.entries(env).map(([k, v]) => `${k}=${v}`);
console.log(`Setting ${pairs.length} secrets on ${app}:`);
for (const k of Object.keys(env)) {
  const sensitive = /SECRET|KEY|PASSWORD|URL/.test(k);
  console.log(`  ${k}${sensitive ? ' (hidden)' : ` = ${env[k]}`}`);
}

execFileSync(
  process.env.FLYCTL ?? 'flyctl',
  ['secrets', 'set', '--app', app, '--stage', ...pairs],
  { stdio: 'inherit' },
);
console.log('\nStaged. They apply on the next deploy.');
