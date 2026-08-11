import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize, IsArray, IsBoolean, IsIn, IsNumber, IsOptional, IsString, Length, Max, Min,
} from 'class-validator';

import { CurrentUser, Public, Roles } from '../../common/decorators';
import { ProvidersService } from './providers.service';

class PortfolioItemDto {
  /// The key returned by POST /storage/uploads. Checked server-side against
  /// the caller's own namespace — it is not enough that it is well-formed.
  @IsString() @Length(8, 400) mediaKey!: string;

  @IsOptional() @IsArray() @ArrayMaxSize(10) @IsString({ each: true })
  @Length(1, 40, { each: true })
  tags?: string[];
}

class PresenceDto {
  @IsBoolean() isOnline!: boolean;
}

class LocationDto {
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat!: number;
  @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng!: number;
  @IsOptional() @Type(() => Number) @IsNumber() heading?: number;
  @IsOptional() @Type(() => Number) @IsNumber() speedKph?: number;
}

class SuspensionDto {
  @IsBoolean() suspended!: boolean;
  /// Required in both directions: a reinstatement with no stated reason is as
  /// unauditable as a suspension with none.
  @IsString() @Length(3, 500) reason!: string;
}

class BlockDto {
  @IsString() start!: string;
  @IsString() end!: string;
  @IsOptional() @IsIn(['manual', 'load_shedding', 'leave']) reason?: string;
}

@ApiTags('providers')
@Controller('providers')
export class ProvidersController {
  constructor(private readonly providers: ProvidersService) {}

  @Roles('admin', 'support')
  @Get()
  @ApiOperation({ summary: 'Operator search, including suspended and unverified' })
  adminSearch(@Query('q') q?: string, @Query('limit') limit?: string) {
    return this.providers.adminSearch(q, Math.min(Number(limit) || 25, 100));
  }

  @Roles('admin')
  @Post(':id/suspension')
  @ApiOperation({ summary: 'Suspend or reinstate a provider' })
  setSuspension(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('userId') actorUserId: string,
    @Body() dto: SuspensionDto,
  ) {
    return this.providers.setSuspension(id, dto.suspended, dto.reason, actorUserId);
  }

  @Public()
  @Get(':id')
  @ApiOperation({ summary: 'Public provider profile with services and portfolio' })
  profile(@Param('id', ParseUUIDPipe) id: string) {
    return this.providers.profile(id);
  }

  @Roles('provider')
  @Get('me/portfolio')
  @ApiOperation({ summary: "The provider's own work, including items in review" })
  myPortfolio(@CurrentUser('providerId') providerId: string) {
    return this.providers.myPortfolio(providerId);
  }

  @Roles('provider')
  @Post('me/portfolio')
  @ApiOperation({ summary: 'Register a photo already uploaded via /storage/uploads' })
  addPortfolioItem(
    @CurrentUser('providerId') providerId: string,
    @CurrentUser('userId') userId: string,
    @Body() dto: PortfolioItemDto,
  ) {
    return this.providers.addPortfolioItem(providerId, userId, dto.mediaKey, dto.tags ?? []);
  }

  @Roles('provider')
  @Delete('me/portfolio/:id')
  @ApiOperation({ summary: 'Remove one of your own photos' })
  removePortfolioItem(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.providers.removePortfolioItem(providerId, id);
  }

  @Roles('provider')
  @Post('me/presence')
  @ApiOperation({ summary: 'Go online or offline' })
  presence(@CurrentUser('providerId') providerId: string, @Body() dto: PresenceDto) {
    return this.providers.setPresence(providerId, dto.isOnline);
  }

  @Roles('provider')
  @Post('me/location')
  location(@CurrentUser('providerId') providerId: string, @Body() dto: LocationDto) {
    return this.providers.updateLocation(providerId, dto.lat, dto.lng, dto.heading, dto.speedKph);
  }

  @Roles('provider')
  @Get('me/schedule')
  schedule(@CurrentUser('providerId') providerId: string) {
    return this.providers.todaySchedule(providerId);
  }

  @Roles('provider')
  @Post('me/availability/blocks')
  @ApiOperation({ summary: 'Block time, including one-tap load-shedding windows' })
  block(@CurrentUser('providerId') providerId: string, @Body() dto: BlockDto) {
    return this.providers.addAvailabilityBlock(
      providerId, new Date(dto.start), new Date(dto.end), dto.reason ?? 'manual',
    );
  }

  @Roles('provider')
  @Get('me/clients')
  @ApiOperation({ summary: 'Clients who have previously booked this provider' })
  listClients(@CurrentUser('providerId') providerId: string) {
    return this.providers.listMyClients(providerId);
  }

  @Roles('provider')
  @Get('me/clients/:id')
  @ApiOperation({ summary: 'Client detail: contact, history and private notes' })
  clientDetail(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) clientId: string,
  ) {
    return this.providers.clientDetail(providerId, clientId);
  }

  @Roles('provider')
  @Post('me/clients/:id/notes')
  @ApiOperation({ summary: 'Add or update private provider-only notes for a client' })
  updateClientNotes(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) clientId: string,
    @Body() dto: { notes: string },
  ) {
    return this.providers.updateClientNotes(providerId, clientId, dto.notes);
  }
}
