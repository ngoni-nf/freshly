import { Module } from '@nestjs/common';
import { EscrowService } from './escrow.service';
import { CaptureDueJob } from './capture-due.job';
import { LedgerService } from './ledger.service';

@Module({
  providers: [EscrowService, LedgerService, CaptureDueJob],
  exports: [EscrowService, LedgerService],
})
export class PaymentsModule {}
