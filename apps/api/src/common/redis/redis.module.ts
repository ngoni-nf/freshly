import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import { REDIS_CLIENT, RedisService } from './redis.service';

const logger = new Logger('RedisModule');

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [ConfigService],
      useFactory: (config: ConfigService) => {
        const client = new Redis(config.getOrThrow<string>('REDIS_URL'), {
          maxRetriesPerRequest: null,
          enableReadyCheck: true,
          lazyConnect: false,
        });
        // ioredis emits 'error' on every failed reconnect attempt. Without a
        // listener Node treats it as unhandled and takes the process down, so
        // a brief Redis blip would become an API outage instead of degraded
        // realtime. Log it and let the readiness probe report the truth.
        client.on('error', (err) =>
          logger.warn(`redis connection error: ${err.message}`),
        );
        return client;
      },
    },
    RedisService,
  ],
  exports: [RedisService, REDIS_CLIENT],
})
export class RedisModule {}
