import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService, PG_POOL, createPool } from './database.service';

@Global()
@Module({
  providers: [
    { provide: PG_POOL, inject: [ConfigService], useFactory: createPool },
    DatabaseService,
  ],
  exports: [DatabaseService],
})
export class DatabaseModule {}
