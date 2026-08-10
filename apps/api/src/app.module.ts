import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { ScheduleModule } from '@nestjs/schedule';
import { resolve } from 'node:path';

import { loadConfiguration } from './common/config/configuration';
import { DatabaseModule } from './common/database/database.module';
import { RedisModule } from './common/redis/redis.module';
import { CryptoModule } from './common/crypto/crypto.module';
import { AllExceptionsFilter } from './common/filters/http-exception.filter';
import { JwtAuthGuard } from './common/guards/jwt-auth.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { IdempotencyInterceptor } from './common/interceptors/idempotency.interceptor';

import { MarketsModule } from './modules/markets/markets.module';
import { CommsModule } from './modules/comms/comms.module';
import { AuthModule } from './modules/auth/auth.module';
import { HealthModule } from './modules/health/health.module';
import { PricingModule } from './modules/pricing/pricing.module';
import { GridModule } from './modules/grid/grid.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { DiscoveryModule } from './modules/discovery/discovery.module';
import { ProvidersModule } from './modules/providers/providers.module';
import { BookingsModule } from './modules/bookings/bookings.module';
import { AiModule } from './modules/ai/ai.module';
import { PayoutsModule } from './modules/payouts/payouts.module';
import { KycModule } from './modules/kyc/kyc.module';
import { SafetyModule } from './modules/safety/safety.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      // .env lives at the repository root, but npm workspaces run this with
      // cwd = apps/api, so the default lookup missed it entirely and every
      // variable came back "Required" despite being set. Both candidates are
      // listed, nearest first, so it works whichever directory it starts in.
      envFilePath: [
        resolve(process.cwd(), '.env'),
        resolve(process.cwd(), '..', '..', '.env'),
      ],
      // Validation happens once, at boot, against a Zod schema. A missing
      // payment secret fails the deploy rather than the first payout.
      validate: (config) => loadConfiguration(config),
    }),
    ThrottlerModule.forRoot([
      { name: 'short', ttl: 1000, limit: 10 },
      { name: 'medium', ttl: 60_000, limit: 120 },
    ]),
    ScheduleModule.forRoot(),
    DatabaseModule,
    RedisModule,
    CryptoModule,
    MarketsModule,
    CommsModule,
    AuthModule,
    HealthModule,
    PricingModule,
    GridModule,
    RealtimeModule,
    DiscoveryModule,
    ProvidersModule,
    BookingsModule,
    AiModule,
    PayoutsModule,
    KycModule,
    SafetyModule,
  ],
  providers: [
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    // Order matters: authenticate, then authorise, then rate limit.
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_INTERCEPTOR, useClass: IdempotencyInterceptor },
  ],
})
export class AppModule {}
