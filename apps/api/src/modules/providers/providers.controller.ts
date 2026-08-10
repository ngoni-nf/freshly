import { Body, Controller, Get, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsIn, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
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

class BlockDto {
  @IsString() start!: string;
  @IsString() end!: string;
  @IsOptional() @IsIn(['manual', 'load_shedding', 'leave']) reason?: string;
}

@ApiTags('providers')
@Controller('providers')
export class ProvidersController {
  constructor(private readonly providers: ProvidersService) {}

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
