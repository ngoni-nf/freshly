import { Module } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { ReviewRevealJob } from './review-reveal.job';
import { BookingsController } from './bookings.controller';
import { PaymentsModule } from '../payments/payments.module';
import { DispatchModule } from '../dispatch/dispatch.module';
import { ReferralsModule } from '../referrals/referrals.module';
import { InvoicesModule } from '../invoices/invoices.module';

@Module({
  imports: [PaymentsModule, DispatchModule, ReferralsModule, InvoicesModule],
  providers: [BookingsService, ReviewRevealJob],
  controllers: [BookingsController],
})
export class BookingsModule {}
