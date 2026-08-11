import { Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, PoolClient, QueryResultRow, types as pgTypes } from 'pg';
import { parse as parsePostgresArray } from 'postgres-array';

export const PG_POOL = Symbol('PG_POOL');

/**
 * Thin typed wrapper over pg.
 *
 * No ORM. The domain here is spatial, financial and transactional; the queries
 * that matter (radius search, escrow capture, ledger writes) are hand-written
 * anyway, and an ORM would only obscure the isolation levels and row locks
 * this system depends on.
 */
@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly logger = new Logger(DatabaseService.name);

  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params: unknown[] = [],
  ): Promise<T[]> {
    const started = Date.now();
    try {
      const result = await this.pool.query<T>(text, params as never[]);
      const ms = Date.now() - started;
      if (ms > 250) {
        this.logger.warn(`slow query ${ms}ms: ${text.slice(0, 120).replace(/\s+/g, ' ')}`);
      }
      return result.rows;
    } catch (err) {
      this.logger.error(`query failed: ${text.slice(0, 200).replace(/\s+/g, ' ')}`);
      throw err;
    }
  }

  async queryOne<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params: unknown[] = [],
  ): Promise<T | null> {
    const rows = await this.query<T>(text, params);
    return rows[0] ?? null;
  }

  /**
   * Run work inside a transaction. Anything that touches money must go through
   * here — the callback receives the client so every statement shares the
   * same transaction, including SELECT ... FOR UPDATE row locks.
   */
  async transaction<T>(
    fn: (tx: TransactionContext) => Promise<T>,
    isolation: 'READ COMMITTED' | 'REPEATABLE READ' | 'SERIALIZABLE' = 'READ COMMITTED',
  ): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query(`BEGIN ISOLATION LEVEL ${isolation}`);
      const result = await fn(new TransactionContext(client));
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }
  }

  async healthy(): Promise<boolean> {
    try {
      await this.pool.query('SELECT 1');
      return true;
    } catch {
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}

export class TransactionContext {
  constructor(private readonly client: PoolClient) {}

  async query<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params: unknown[] = [],
  ): Promise<T[]> {
    const result = await this.client.query<T>(text, params as never[]);
    return result.rows;
  }

  async queryOne<T extends QueryResultRow = QueryResultRow>(
    text: string,
    params: unknown[] = [],
  ): Promise<T | null> {
    const rows = await this.query<T>(text, params);
    return rows[0] ?? null;
  }

  /** Lock a row for the remainder of the transaction. */
  async lockForUpdate<T extends QueryResultRow = QueryResultRow>(
    table: string,
    id: string,
  ): Promise<T | null> {
    if (!/^[a-z_][a-z0-9_]*$/.test(table)) {
      throw new Error(`refusing to lock unsafe table identifier "${table}"`);
    }
    return this.queryOne<T>(`SELECT * FROM ${table} WHERE id = $1 FOR UPDATE`, [id]);
  }

  /**
   * Publish a domain event in the same transaction as the state change.
   * The relay picks it up afterwards; nothing is lost if the process dies
   * between the commit and the notification.
   */
  async emitEvent(
    aggregateType: string,
    aggregateId: string,
    eventType: string,
    payload: Record<string, unknown>,
  ): Promise<void> {
    await this.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ($1, $2, $3, $4)`,
      [aggregateType, aggregateId, eventType, JSON.stringify(payload)],
    );
  }
}

/**
 * Teach pg how to read arrays of our own enum types.
 *
 * node-postgres ships parsers for the built-in array types only. An
 * account_role_enum[] has an OID it has never seen, so it hands back the raw
 * literal — `roles` arrived at the mobile app as the string "{client}" rather
 * than ["client"], and AuthSession.fromJson died on the cast. Every enum array
 * in the schema had the same latent problem: roles, categories, power_backup.
 *
 * Registered once, from the catalogue, so a new enum array added later is
 * covered without anyone remembering this exists.
 */
async function registerEnumArrayParsers(pool: Pool, logger: Logger): Promise<void> {
  const { rows } = await pool.query<{ typarray: string; typname: string }>(
    `SELECT t.typarray, t.typname
       FROM pg_type t
       JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE t.typtype = 'e' AND t.typarray <> 0 AND n.nspname = 'public'`,
  );

  for (const row of rows) {
    pgTypes.setTypeParser(Number(row.typarray), (value: string) => parsePostgresArray(value));
  }
  logger.log(`registered array parsers for ${rows.length} enum types`);
}

export async function createPool(config: ConfigService): Promise<Pool> {
  // Prefer a pooler endpoint when one is configured. Migrations deliberately
  // do not: they issue DDL and CREATE EXTENSION, which a transaction-mode
  // pooler such as Supabase's port 6543 will reject.
  const connectionString =
    config.get<string>('DATABASE_POOL_URL') ?? config.getOrThrow<string>('DATABASE_URL');

  const pool = new Pool({
    connectionString,
    ssl: config.get<boolean>('DATABASE_SSL') ? { rejectUnauthorized: false } : undefined,
    max: config.get<number>('DATABASE_POOL_MAX') ?? 20,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 5_000,
    application_name: 'freshly-api',
  });

  const logger = new Logger('DatabasePool');

  // pg emits 'error' on idle clients when the server hangs up — a pooler
  // recycling connections, a failover, a network blip. With no listener Node
  // treats it as unhandled and kills the process, so a transient ECONNRESET
  // from Supabase took the whole API down rather than costing one connection.
  // The pool replaces the client on its own; this only has to not be fatal.
  pool.on('error', (err) => {
    logger.warn(`idle client error, connection will be replaced: ${err.message}`);
  });

  // Not fatal: the API should still boot and report unhealthy if the database
  // is briefly unreachable, rather than crash-looping before it can say why.
  await registerEnumArrayParsers(pool, logger).catch((err) =>
    logger.error(`could not register enum array parsers: ${err.message}`),
  );

  return pool;
}
