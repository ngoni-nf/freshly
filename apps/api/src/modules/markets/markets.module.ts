import { Global, Module } from '@nestjs/common';
import { AddressSearchService } from './address-search.service';
import { MarketsService } from './markets.service';
import { MarketsController } from './markets.controller';

@Global()
@Module({
  providers: [MarketsService, AddressSearchService],
  controllers: [MarketsController],
  exports: [MarketsService, AddressSearchService],
})
export class MarketsModule {}
