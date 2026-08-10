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
import { readFileSync, readdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

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

const url = process.env.DATABASE_URL ?? 'postgres://freshly:freshly@localhost:5432/freshly';
const client = new pg.Client({
  connectionString: url,
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
});

const sha = (s) => createHash('sha256').update(s).digest('hex').slice(0, 16);
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
