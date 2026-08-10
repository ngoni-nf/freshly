import { Module } from '@nestjs/common';
import { BookingsService } from './bookings.service';
import { BookingsController } from './bookings.controller';
import { PaymentsModule } from '../payments/payments.module';
import { DispatchModule } from '../dispatch/dispatch.module';

@Module({
  imports: [PaymentsModule, DispatchModule],
  providers: [BookingsService],
  controllers: [BookingsController],
})
export class BookingsModule {}
