import { Module } from '@nestjs/common';
import { PaymentsModule } from '../payments/payments.module';
import { AdminService } from './admin.service';
import { AdminController } from './admin.controller';

@Module({
  // AdminService injects EscrowService, which PaymentsModule owns. Without the
  // import the container cannot resolve it and the whole application refuses
  // to boot — a failure tsc cannot see, because the types are all correct and
  // only the wiring is missing.
  imports: [PaymentsModule],
  providers: [AdminService],
  controllers: [AdminController],
  exports: [AdminService],
})
export class AdminModule {}
