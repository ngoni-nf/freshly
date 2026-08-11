#!/usr/bin/env node
/**
 * Minimal, dependency-light migration runner.
 *
 * Deliberately not a framework: migrations are plain .sql files applied in
 * filename order inside a transaction, with a checksum recorded so an already
 * applied file cannot be edited underneath you without a loud failure.
 *
 *   node infra/db/migrate.mjs up      apply pending migrations
 *   node infra/db/migrate.mjs seed    apply seeds/*.sql (idempotent-ish, dev only)
 *   node infra/db/migrate.mjs reset   drop and recreate the public schema
 *   node infra/db/migrate.mjs status  list applied vs pending
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * Load .env before anything reads process.env.
 *
 * The API gets this for free from @nestjs/config; this script is standalone
 * and did not, so `npm run db:reset` silently ignored the configured database
 * and tried a localhost default instead — reporting an authentication failure
 * against a server the user never intended to use, which is a genuinely
 * confusing way to fail. Parsed by hand to keep the runner dependency-light.
 */
function loadDotEnv(path) {
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    // A real environment variable always wins over the file, so CI and
    // one-off overrides behave the way everyone expects.
    if (process.env[key] !== undefined) continue;
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

// Imported dynamically so a missing dependency produces an instruction rather
// than a twenty-line ERR_MODULE_NOT_FOUND stack, which tells a newcomer
// nothing about what to do next.
let pg;
try {
  pg = (await import('pg')).default;
} catch {
  console.error(
    '\n  The "pg" package is not installed.\n' +
    '  Run this first, from the repository root:\n\n' +
    '      npm install\n',
  );
  process.exit(1);
}

const HERE = dirname(fileURLToPath(import.meta.url));
const MIGRATIONS = join(HERE, 'migrations');
const SEEDS = join(HERE, 'seeds');

// infra/db -> repository root, so this works from any working directory.
loadDotEnv(resolve(HERE, '..', '..', '.env'));

const url = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';
const client = new pg.Client({
  connectionString: url,
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
});

/**
 * Line endings are normalised before hashing.
 *
 * The checksum exists to catch an applied migration being edited underneath
 * you. It should not fire because git rewrote the file: with core.autocrlf=true
 * on Windows, a checkout converts every .sql to CRLF and the runner then
 * refuses to apply anything, claiming history was modified when nothing was.
 * .gitattributes now pins these files to LF as well; this is the belt to that
 * pair of braces, and it keeps checksums portable across platforms.
 */
const sha = (s) =>
  createHash('sha256').update(s.replace(/\r\n/g, '\n')).digest('hex').slice(0, 16);
const sqlFiles = (dir) => readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();

async function ensureRegistry() {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename    TEXT PRIMARY KEY,
      checksum    TEXT NOT NULL,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
      duration_ms INT NOT NULL
    )`);
}

async function up() {
  await ensureRegistry();
  const { rows } = await client.query('SELECT filename, checksum FROM schema_migrations');
  const applied = new Map(rows.map((r) => [r.filename, r.checksum]));

  for (const file of sqlFiles(MIGRATIONS)) {
    const body = readFileSync(join(MIGRATIONS, file), 'utf8');
    const checksum = sha(body);

    if (applied.has(file)) {
      if (applied.get(file) !== checksum) {
        throw new Error(
          `Migration ${file} was modified after it was applied. ` +
          `Write a new migration instead of editing history.`
        );
      }
      console.log(`  skip   ${file}`);
      continue;
    }

    const started = Date.now();
    await client.query('BEGIN');
    try {
      await client.query(body);
      const ms = Date.now() - started;
      await client.query(
        'INSERT INTO schema_migrations (filename, checksum, duration_ms) VALUES ($1,$2,$3)',
        [file, checksum, ms]
      );
      await client.query('COMMIT');
      console.log(`  apply  ${file}  (${ms}ms)`);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`  FAILED ${file}\n         ${err.message}`);
      throw err;
    }
  }
}

async function seed() {
  for (const file of sqlFiles(SEEDS)) {
    const body = readFileSync(join(SEEDS, file), 'utf8');
    await client.query('BEGIN');
    try {
      await client.query(body);
      await client.query('COMMIT');
      console.log(`  seed   ${file}`);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`  FAILED ${file}\n         ${err.message}`);
      throw err;
    }
  }
}

async function reset() {
  if (process.env.NODE_ENV === 'production') {
    throw new Error('reset is refused when NODE_ENV=production');
  }
  await client.query('DROP SCHEMA IF EXISTS public CASCADE; CREATE SCHEMA public;');
  console.log('  schema dropped and recreated');
}

async function status() {
  await ensureRegistry();
  const { rows } = await client.query(
    'SELECT filename, applied_at FROM schema_migrations ORDER BY filename'
  );
  const applied = new Set(rows.map((r) => r.filename));
  for (const f of sqlFiles(MIGRATIONS)) {
    console.log(`  ${applied.has(f) ? 'applied' : 'PENDING'}  ${f}`);
  }
}

const commands = { up, seed, reset, status };
const cmd = process.argv[2] ?? 'up';

if (!commands[cmd]) {
  console.error(`Unknown command "${cmd}". Use: ${Object.keys(commands).join(' | ')}`);
  process.exit(1);
}

try {
  try {
    await client.connect();
  } catch (err) {
    const target = url.replace(/:\/\/[^@]*@/, '://***@');
    console.error(
      `\n  Cannot reach PostgreSQL at ${target}\n` +
      `  ${err.message}\n\n` +
      '  Start it with one of:\n' +
      '      npm run infra:up            (Docker or Podman, includes PostGIS)\n' +
      '      pg_ctl start                (a local PostgreSQL install)\n\n' +
      '  A local install also needs the PostGIS extension. On Windows that is\n' +
      '  the "Application Stack Builder" that ships with the PostgreSQL\n' +
      '  installer: Spatial Extensions -> PostGIS.\n',
    );
    process.exit(1);
  }
  if (cmd === 'reset') {
    await reset();
    await up();
    await seed();
  } else {
    await commands[cmd]();
  }
  console.log('done.');
} catch (err) {
  console.error(err.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
