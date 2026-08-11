import { Controller, Get, Query } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
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
  @Get('places')
  @ApiQuery({ name: 'q', required: false, description: 'What the user has typed so far' })
  @ApiOperation({ summary: 'Suburb autocomplete, restricted to areas we serve' })
  places(@Query('q') q?: string, @Query('limit') limit?: string) {
    return this.markets.searchPlaces(q, limit ? Number(limit) : undefined);
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
      cancellationWindowMinutes: m.cancellationWindowMinutes,
      cancellationFeeBps: m.cancellationFeeBps,
      noShowGraceMinutes: m.noShowGraceMinutes,
    }));
  }
}
