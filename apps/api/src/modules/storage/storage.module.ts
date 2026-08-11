import { Global, Module } from '@nestjs/common';
import { StorageService } from './storage.service';
import { StorageController } from './storage.controller';

/// Global because KYC, credentials and portfolio moderation all need to turn
/// a stored key back into a viewable link.
@Global()
@Module({
  providers: [StorageService],
  controllers: [StorageController],
  exports: [StorageService],
})
export class StorageModule {}
