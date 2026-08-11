import { Global, Module } from '@nestjs/common';
import { PushService } from './push.service';

/**
 * Global because almost anything that changes state for a user is worth
 * telling them about, and threading an import through every module that might
 * one day send a notification is noise.
 */
@Global()
@Module({
  providers: [PushService],
  exports: [PushService],
})
export class NotificationsModule {}
