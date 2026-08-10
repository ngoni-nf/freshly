import { Module } from '@nestjs/common';
import { EscrowService } from './escrow.service';
import { LedgerService } from './ledger.service';

@Module({
  providers: [EscrowService, LedgerService],
  exports: [EscrowService, LedgerService],
})
export class PaymentsModule {}
