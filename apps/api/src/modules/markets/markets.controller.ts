import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators';
import { MarketsService } from './markets.service';

@ApiTags('markets')
@Controller('markets')
export class MarketsController {
  constructor(private readonly markets: MarketsService) {}

  @Public()
  @Get('areas')
  @ApiOperation({ summary: 'Service areas a client can choose from at sign-up' })
  areas() {
    return this.markets.liveServiceAreas();
  }

  @Public()
  @Get()
  @ApiOperation({ summary: 'Markets Freshly currently operates in' })
  list() {
    return this.markets.liveMarkets().map((m) => ({
      code: m.code,
      name: m.name,
      currency: m.defaultCurrency,
      dialPrefix: m.dialPrefix,
      phoneLength: m.phoneNationalLength,
      timezone: m.timezone,
      serviceFeeMinor: m.serviceFeeMinor,
      vatLabel: m.vatLabel,
    }));
  }
}
