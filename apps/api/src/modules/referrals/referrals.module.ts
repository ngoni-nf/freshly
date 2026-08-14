import { Module } from '@nestjs/common';
import { ReferralsController } from './referrals.controller';
import { ReferralsService } from './referrals.service';

@Module({
  controllers: [ReferralsController],
  providers: [ReferralsService],
  // BookingsService qualifies a referral when a booking completes, and applies
  // credit when it quotes.
  exports: [ReferralsService],
})
export class ReferralsModule {}
