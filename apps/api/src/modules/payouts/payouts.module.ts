import { Module } from '@nestjs/common';
import { PayoutsService } from './payouts.service';
import { PayoutsController } from './payouts.controller';
import { PayoutPolicy } from './payout.policy';
import { PaymentsModule } from '../payments/payments.module';

@Module({
  imports: [PaymentsModule],
  providers: [PayoutsService, PayoutPolicy],
  controllers: [PayoutsController],
  exports: [PayoutsService],
})
export class PayoutsModule {}
