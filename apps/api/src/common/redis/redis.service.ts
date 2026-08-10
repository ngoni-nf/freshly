import { Inject, Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

export const REDIS_CLIENT = Symbol('REDIS_CLIENT');

/**
 * Redis carries three kinds of state, none of them durable by design:
 *   1. Provider GPS breadcrumbs (5-second cadence, TTL-bounded).
 *   2. Dispatch offer locks, so two providers cannot accept the same job.
 *   3. Rate limit and OTP throttle counters.
 *
 * Location data deliberately never reaches Postgres. POPIA s14 and the
 * Zimbabwe Data Protection Act both require that personal information is kept
 * no longer than necessary; a trip breadcrumb has no purpose once the job is
 * done, so it expires rather than being retained and later justified.
 */
@Injectable()
export class RedisService implements OnModuleDestroy {
  constructor(@Inject(REDIS_CLIENT) public readonly client: Redis) {}

  private locationKey(providerId: string): string {
    return `loc:${providerId}`;
  }

  async recordLocation(
    providerId: string,
    point: { lat: number; lng: number; heading?: number; speedKph?: number },
    ttlSeconds: number,
  ): Promise<void> {
    await this.client.set(
      this.locationKey(providerId),
      JSON.stringify({ ...point, at: new Date().toISOString() }),
      'EX',
      ttlSeconds,
    );
  }

  async getLocation(
    providerId: string,
  ): Promise<{ lat: number; lng: number; heading?: number; speedKph?: number; at: string } | null> {
    const raw = await this.client.get(this.locationKey(providerId));
    return raw ? JSON.parse(raw) : null;
  }

  async purgeLocation(providerId: string): Promise<void> {
    await this.client.del(this.locationKey(providerId));
  }

  /**
   * Single-winner lock. The first provider to acquire a booking's dispatch
   * lock is the one who gets the job; everyone else's accept is rejected
   * cleanly rather than racing at the database.
   */
  async acquireLock(key: string, holder: string, ttlSeconds: number): Promise<boolean> {
    const result = await this.client.set(`lock:${key}`, holder, 'EX', ttlSeconds, 'NX');
    return result === 'OK';
  }

  async releaseLock(key: string, holder: string): Promise<void> {
    const script = `
      if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
      else
        return 0
      end`;
    await this.client.eval(script, 1, `lock:${key}`, holder);
  }

  /** Fixed-window counter, used for OTP and search throttling. */
  async incrementWindow(key: string, windowSeconds: number): Promise<number> {
    const count = await this.client.incr(`ctr:${key}`);
    if (count === 1) await this.client.expire(`ctr:${key}`, windowSeconds);
    return count;
  }

  async healthy(): Promise<boolean> {
    try {
      return (await this.client.ping()) === 'PONG';
    } catch {
      return false;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.quit();
  }
}
