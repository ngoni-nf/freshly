import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import { ServerOptions } from 'socket.io';

/**
 * socket.io across more than one API machine.
 *
 * Every emit in this API targets a room (`user:`, `provider:`, `booking:`), and
 * socket.io's default adapter only knows the sockets connected to its own
 * process. With two machines, an emit from machine A reached nobody connected
 * to machine B: the outbox relay hands each event to exactly one machine
 * (`FOR UPDATE SKIP LOCKED`), and a dispatch offer is emitted by whichever
 * machine took the checkout. Roughly half of all offers, status updates and
 * chat messages vanished without an error anywhere.
 *
 * The Redis adapter publishes each room emit on a channel every machine
 * subscribes to, so the machine holding the socket delivers it. Pub/sub needs
 * connections of its own: a subscribed ioredis connection cannot run ordinary
 * commands, so these are separate from the shared client in RedisModule.
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly logger = new Logger(RedisIoAdapter.name);
  private adapterConstructor?: ReturnType<typeof createAdapter>;
  private connections: Redis[] = [];

  constructor(app: INestApplicationContext) {
    super(app);
  }

  async connectToRedis(url: string): Promise<void> {
    const pub = new Redis(url, { maxRetriesPerRequest: null, lazyConnect: true });
    const sub = pub.duplicate();
    // Same reasoning as RedisModule: an unhandled 'error' event would take
    // the process down on every reconnect attempt during a Redis blip.
    for (const conn of [pub, sub]) {
      conn.on('error', (err) =>
        this.logger.warn(`realtime redis error: ${err.message}`),
      );
    }
    await Promise.all([pub.connect(), sub.connect()]);
    this.connections = [pub, sub];
    this.adapterConstructor = createAdapter(pub, sub, { key: 'freshly:io' });
    this.logger.log('realtime fan-out across machines via Redis');
  }

  override createIOServer(port: number, options?: ServerOptions): unknown {
    const server = super.createIOServer(port, options);
    if (this.adapterConstructor) server.adapter(this.adapterConstructor);
    return server;
  }

  override async close(server: unknown): Promise<void> {
    await super.close(server as never);
    await Promise.all(this.connections.map((c) => c.quit().catch(() => undefined)));
  }
}
