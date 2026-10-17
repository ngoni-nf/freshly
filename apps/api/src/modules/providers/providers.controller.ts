import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional, IsString,
  Length, Matches, Max, Min, ValidateNested,
} from 'class-validator';
import { SERVICE_CATEGORIES } from '../auth/dto/auth.dto';

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

class ClientNotesDto {
  /// A plain `{ notes: string }` type here validated nothing — ValidationPipe
  /// works off the class, so the field was unbounded and not even checked to
  /// be a string. Capped because this is free-text a provider types once and
  /// the platform then stores forever.
  @IsString() @Length(0, 4000) notes!: string;
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

class UpdateBusinessDto {
  @IsOptional() @IsString() @Length(2, 120) displayName?: string;
  @IsOptional() @IsString() @Length(0, 600) bio?: string;
  @IsOptional() @IsArray() @ArrayMinSize(1) @ArrayMaxSize(6)
  @IsIn(SERVICE_CATEGORIES, { each: true })
  categories?: string[];
  @IsOptional() @IsIn(['mobile', 'in_shop', 'both']) venueMode?: 'mobile' | 'in_shop' | 'both';
  @IsOptional() @IsArray() @ArrayMaxSize(5)
  @IsIn(['generator', 'inverter', 'battery_clippers', 'portable_lights', 'solar'], { each: true })
  powerBackup?: string[];
  @IsOptional() @IsString() @Length(0, 300) shopAddress?: string;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(1) @Max(50) travelRadiusKm?: number;
  @IsOptional() @IsBoolean() acceptsInstant?: boolean;
  @IsOptional() @IsBoolean() acceptsScheduled?: boolean;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng?: number;
}

class AvailabilityRuleDto {
  @Type(() => Number) @IsInt() @Min(0) @Max(6) weekday!: number;
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) startsAt!: string;
  @Matches(/^([01]\d|2[0-3]):[0-5]\d$/) endsAt!: string;
}

class AvailabilityRulesDto {
  @IsArray() @ArrayMaxSize(21) @ValidateNested({ each: true }) @Type(() => AvailabilityRuleDto)
  rules!: AvailabilityRuleDto[];
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
  @ApiOperation({ summary: 'The roster: everyone, with live and upcoming work' })
  adminSearch(@Query('q') q?: string, @Query('limit') limit?: string) {
    return this.providers.adminSearch(q, Math.min(Number(limit) || 100, 200));
  }

  @Roles('admin', 'support')
  @Get('schedule/upcoming')
  @ApiOperation({ summary: 'Everything booked ahead, for the ops diary' })
  adminSchedule(@Query('days') days?: string) {
    return this.providers.adminSchedule(Math.min(Number(days) || 14, 90));
  }

  @Roles('admin', 'support')
  @Get('schedule/completed')
  @ApiOperation({ summary: 'Jobs done, who did them, and what the client said' })
  adminCompleted(@Query('days') days?: string, @Query('limit') limit?: string) {
    return this.providers.adminCompleted(
      Math.min(Number(days) || 30, 365),
      Math.min(Number(limit) || 100, 200),
    );
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

  @Roles('provider')
  @Get('me')
  @ApiOperation({ summary: 'Your own business details' })
  myBusiness(@CurrentUser('providerId') providerId: string) {
    return this.providers.myBusiness(providerId);
  }

  @Roles('provider')
  @Patch('me')
  @ApiOperation({ summary: 'Edit your business details' })
  updateBusiness(@CurrentUser('providerId') providerId: string, @Body() dto: UpdateBusinessDto) {
    return this.providers.updateBusiness(providerId, dto);
  }

  @Roles('provider')
  @Get('me/availability/rules')
  @ApiOperation({ summary: 'Your working hours, per weekday' })
  availabilityRules(@CurrentUser('providerId') providerId: string) {
    return this.providers.availabilityRules(providerId);
  }

  @Roles('provider')
  @Put('me/availability/rules')
  @ApiOperation({ summary: 'Replace your working hours' })
  replaceAvailabilityRules(
    @CurrentUser('providerId') providerId: string,
    @Body() dto: AvailabilityRulesDto,
  ) {
    return this.providers.replaceAvailabilityRules(providerId, dto.rules);
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
  @Get('me/reviews')
  @ApiOperation({ summary: 'Reviews written by clients for this provider' })
  myReviews(@CurrentUser('providerId') providerId: string) {
    return this.providers.listMyReviews(providerId);
  }

  @Roles('provider')
  @Post('me/clients/:id/notes')
  @ApiOperation({ summary: 'Add or update private provider-only notes for a client' })
  updateClientNotes(
    @CurrentUser('providerId') providerId: string,
    @Param('id', ParseUUIDPipe) clientId: string,
    @Body() dto: ClientNotesDto,
  ) {
    return this.providers.updateClientNotes(providerId, clientId, dto.notes);
  }

  // Declared last: Nest matches routes in order, and a ':id' above would
  // swallow 'me' and answer 400 for a path that is not a UUID.
  @Public()
  @Get(':id')
  @ApiOperation({ summary: 'Public provider profile with services and portfolio' })
  profile(@Param('id', ParseUUIDPipe) id: string) {
    return this.providers.profile(id);
  }
}
