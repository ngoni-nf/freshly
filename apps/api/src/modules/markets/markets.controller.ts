import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiQuery, ApiTags } from '@nestjs/swagger';
import { Public } from '../../common/decorators';
import { AddressSearchService } from './address-search.service';
import { MarketsService } from './markets.service';

@ApiTags('markets')
@Controller('markets')
export class MarketsController {
  constructor(
    private readonly markets: MarketsService,
    private readonly addresses: AddressSearchService,
  ) {}

  @Public()
  @Get('areas')
  @ApiOperation({ summary: 'Service areas a client can choose from at sign-up' })
  areas() {
    return this.markets.liveServiceAreas();
  }

  @Public()
  @Get('places')
  @ApiQuery({ name: 'q', required: false, description: 'What the user has typed so far' })
  @ApiQuery({ name: 'countryCode', required: false, enum: ['ZA', 'ZW'] })
  @ApiOperation({ summary: 'Suburb autocomplete, restricted to areas we serve' })
  places(
    @Query('q') q?: string,
    @Query('limit') limit?: string,
    @Query('countryCode') countryCode?: string,
  ) {
    // Anything other than a market code is ignored rather than rejected: this
    // is autocomplete, and an error here would just leave the field empty.
    const market = countryCode === 'ZA' || countryCode === 'ZW' ? countryCode : undefined;
    return this.markets.searchPlaces(q, limit ? Number(limit) : undefined, market);
  }

  /**
   * Street-address autocomplete. Authenticated, unlike the suburb list: every
   * keystroke here costs money, and an open endpoint is somebody else's free
   * geocoder billed to us.
   */
  @Get('address-search')
  @ApiQuery({ name: 'q', description: 'What the user has typed' })
  @ApiQuery({ name: 'session', description: 'One token per address being entered' })
  @ApiOperation({ summary: 'Search street addresses in a market we serve' })
  addressSearch(
    @Query('q') q: string,
    @Query('session') session: string,
    @Query('countryCode') countryCode?: 'ZA' | 'ZW',
    @Query('lat') lat?: string,
    @Query('lng') lng?: string,
  ) {
    const near = lat && lng ? { lat: Number(lat), lng: Number(lng) } : undefined;
    return this.addresses.suggest(q ?? '', countryCode ?? 'ZA', session, near);
  }

  @Get('address-search/:placeId')
  @ApiOperation({ summary: 'Turn a chosen suggestion into coordinates' })
  resolveAddress(
    @Param('placeId') placeId: string,
    @Query('session') session: string,
  ) {
    return this.addresses.resolve(placeId, session);
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
