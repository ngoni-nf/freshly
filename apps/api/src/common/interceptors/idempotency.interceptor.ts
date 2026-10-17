import {
  BadRequestException,
  CallHandler,
  ConflictException,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Observable, catchError, from, of, switchMap, tap, throwError } from 'rxjs';
import { createHash } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { IDEMPOTENT_KEY } from '../decorators';

/**
 * Idempotency for money-moving endpoints.
 *
 * Mobile clients on unreliable networks retry. Without this, a lost response
 * to POST /bookings/:id/checkout means the client retries and the customer is
 * authorised twice. The key is claimed atomically; a replay with an identical
 * body returns the stored response, a replay with a different body is rejected.
 *
 * A claim is released when the handler throws. Only a success is worth
 * replaying: a refused transition or a gateway error must be retryable with
 * the same key, because the provider app sends one fixed key per booking for
 * "complete" and a key stuck "in flight" meant that job could never be
 * finished or paid. A claim left behind by a crash mid-request expires on its
 * own after STALE_CLAIM_SECONDS, for the same reason.
 */
const STALE_CLAIM_SECONDS = 120;

@Injectable()
export class IdempotencyInterceptor implements NestInterceptor {
  constructor(
    private readonly reflector: Reflector,
    private readonly db: DatabaseService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const required = this.reflector.getAllAndOverride<boolean>(IDEMPOTENT_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required) return next.handle();

    const request = context.switchToHttp().getRequest();
    const key: string | undefined = request.headers['idempotency-key'];

    if (!key || key.length < 8 || key.length > 255) {
      throw new BadRequestException({
        code: 'idempotency_key_required',
        message: 'This request requires an Idempotency-Key header of 8-255 characters',
      });
    }

    const endpoint = `${request.method} ${request.route?.path ?? request.url}`;
    const requestHash = createHash('sha256')
      .update(JSON.stringify(request.body ?? {}))
      .digest('hex');

    return from(this.claim(key, request.user?.userId ?? null, endpoint, requestHash)).pipe(
      switchMap((existing) => {
        if (existing?.completed_at) {
          if (existing.request_hash !== requestHash) {
            throw new ConflictException({
              code: 'idempotency_key_reused',
              message: 'This Idempotency-Key was already used with a different request body',
            });
          }
          return of(existing.response_body);
        }
        if (existing && !existing.completed_at) {
          throw new ConflictException({
            code: 'request_in_flight',
            message: 'An identical request is still being processed',
          });
        }
        return next.handle().pipe(
          tap((body) => {
            void this.complete(key, body);
          }),
          catchError((err) =>
            from(this.release(key)).pipe(switchMap(() => throwError(() => err))),
          ),
        );
      }),
    );
  }

  private async claim(
    key: string,
    userId: string | null,
    endpoint: string,
    requestHash: string,
  ): Promise<{ request_hash: string; response_body: unknown; completed_at: Date | null } | null> {
    const rows = await this.db.query<{
      request_hash: string;
      response_body: unknown;
      completed_at: Date | null;
    }>(
      `INSERT INTO idempotency_keys (key, user_id, endpoint, request_hash, locked_at)
       VALUES ($1, $2, $3, $4, now())
       ON CONFLICT (key) DO UPDATE
         SET user_id = EXCLUDED.user_id, endpoint = EXCLUDED.endpoint,
             request_hash = EXCLUDED.request_hash, locked_at = now()
         WHERE idempotency_keys.completed_at IS NULL
           AND idempotency_keys.locked_at < now() - ($5 || ' seconds')::INTERVAL
       RETURNING request_hash, response_body, completed_at`,
      [key, userId, endpoint, requestHash, String(STALE_CLAIM_SECONDS)],
    );
    if (rows.length) return null; // freshly claimed, proceed

    return this.db.queryOne(
      `SELECT request_hash, response_body, completed_at FROM idempotency_keys WHERE key = $1`,
      [key],
    );
  }

  private async release(key: string): Promise<void> {
    await this.db.query(
      'DELETE FROM idempotency_keys WHERE key = $1 AND completed_at IS NULL',
      [key],
    );
  }

  private async complete(key: string, body: unknown): Promise<void> {
    await this.db.query(
      `UPDATE idempotency_keys
          SET response_body = $2, status_code = 200, completed_at = now()
        WHERE key = $1`,
      [key, JSON.stringify(body ?? null)],
    );
  }
}
