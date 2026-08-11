import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean, IsIn, IsNumber, IsOptional, IsString, Length, Max, Min,
} from 'class-validator';
import { CurrentUser, Public, Roles } from '../../common/decorators';
import { ProvidersService } from './providers.service';

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
}
