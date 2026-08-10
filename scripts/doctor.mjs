#!/usr/bin/env node
/**
 * Preflight check.
 *
 * Every one of these is something that has actually broken a first run:
 * a missing install, no container runtime, PostGIS absent from an otherwise
 * healthy PostgreSQL, or a Flutter SDK the IDE cannot see. Finding out in one
 * command beats discovering them one stack trace at a time.
 *
 *   npm run doctor
 */
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

const GREEN = '\x1b[32m', RED = '\x1b[31m', AMBER = '\x1b[33m', DIM = '\x1b[2m', OFF = '\x1b[0m';
let failures = 0;

function report(ok, label, detail, optional = false) {
  if (ok) {
    console.log(`  ${GREEN}ok${OFF}    ${label}${detail ? `  ${DIM}${detail}${OFF}` : ''}`);
  } else if (optional) {
    console.log(`  ${AMBER}note${OFF}  ${label}  ${DIM}${detail}${OFF}`);
  } else {
    failures += 1;
    console.log(`  ${RED}FAIL${OFF}  ${label}  ${detail}`);
  }
}

function version(command) {
  try {
    return execSync(command, { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim().split('\n')[0];
  } catch {
    return null;
  }
}

console.log('\nFreshly preflight\n');

// ── Toolchain ────────────────────────────────────────────────────────────────
const node = process.versions.node;
report(Number(node.split('.')[0]) >= 20, 'Node 20 or newer', `v${node}`);

report(existsSync(join(ROOT, 'node_modules')), 'npm dependencies installed', 'run: npm install');

const flutter = version('flutter --version');
report(Boolean(flutter), 'Flutter on PATH', flutter ?? 'install Flutter, or add it to PATH');

// ── Container runtime, either will do ────────────────────────────────────────
const docker = version('docker --version');
const podman = version('podman --version');
report(
  Boolean(docker || podman),
  'container runtime',
  docker ?? podman ?? 'install Docker Desktop, or use a local PostgreSQL — see START_HERE.md',
);

// ── Database ─────────────────────────────────────────────────────────────────
const url = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';
let pg = null;
try {
  pg = (await import('pg')).default;
} catch {
  /* reported above as a missing install */
}

if (pg) {
  const client = new pg.Client({ connectionString: url, connectionTimeoutMillis: 2500 });
  try {
    await client.connect();
    report(true, 'PostgreSQL reachable', url.replace(/:\/\/[^@]*@/, '://***@'));
    try {
      const { rows } = await client.query('SELECT postgis_version() AS v');
      report(true, 'PostGIS installed', rows[0].v);
    } catch {
      report(
        false,
        'PostGIS installed',
        'required for every spatial query. Windows: Application Stack Builder -> Spatial Extensions -> PostGIS',
      );
    }
    const { rows: migrated } = await client
      .query('SELECT COUNT(*)::int AS n FROM schema_migrations')
      .catch(() => ({ rows: [{ n: 0 }] }));
    report(migrated[0].n > 0, 'migrations applied', `${migrated[0].n} applied — run: npm run db:reset`, migrated[0].n === 0);
    await client.end();
  } catch (err) {
    const hint = /password authentication failed|role .* does not exist/i.test(err.message)
      ? 'the server is up but the freshly role is missing — run: npm run db:bootstrap'
      : 'run: npm run infra:up, or start your local PostgreSQL';
    report(false, 'PostgreSQL reachable', `${err.message} — ${hint}`);
  }
}

// ── Redis ────────────────────────────────────────────────────────────────────
try {
  const { default: Redis } = await import('ioredis');
  const redis = new Redis(process.env.REDIS_URL ?? 'redis://localhost:6379', {
    lazyConnect: true, maxRetriesPerRequest: 1, retryStrategy: () => null,
  });
  // ioredis emits 'error' as well as rejecting connect(); without a listener
  // Node prints its own dump before we get to say anything useful.
  redis.on('error', () => {});
  await redis.connect();
  report(true, 'Redis reachable', await redis.ping());
  redis.disconnect();
} catch (err) {
  report(
    false,
    'Redis reachable',
    'needed for dispatch and live tracking. No Docker? In WSL: sudo apt install redis-server && redis-server --daemonize yes',
  );
}

console.log(
  failures === 0
    ? `\n${GREEN}Ready.${OFF} Start the API with: npm run api:dev\n`
    : `\n${RED}${failures} check${failures === 1 ? '' : 's'} failed.${OFF} Fix the above, then run npm run doctor again.\n`,
);
process.exit(failures === 0 ? 0 : 1);
