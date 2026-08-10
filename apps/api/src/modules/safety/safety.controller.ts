import { Body, Controller, Get, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Length, Max, Min,
} from 'class-validator';
import { SkipThrottle } from '@nestjs/throttler';
import { CurrentUser } from '../../common/decorators';
import { SafetyService } from './safety.service';

class TriggerSosDto {
  @IsOptional() @IsUUID() bookingId?: string;
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90) lat!: number;
  @Type(() => Number) @IsNumber() @Min(-180) @Max(180) lng!: number;
  @IsOptional() @Type(() => Number) @IsNumber() accuracyM?: number;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) @Max(100) batteryPct?: number;
}

class EmergencyContactDto {
  @IsString() @Length(2, 120) name!: string;
  @IsString() @Length(6, 20) phone!: string;
  @IsOptional() @IsString() @Length(2, 40) relationship?: string;
  @IsOptional() @IsBoolean() notifyOnTrip?: boolean;
}

@ApiTags('safety')
@Controller('safety')
export class SafetyController {
  constructor(private readonly safety: SafetyService) {}

  /**
   * Deliberately exempt from rate limiting.
   *
   * Someone in trouble pressing the button repeatedly is the expected
   * behaviour, not abuse, and a 429 on this endpoint is unacceptable in a way
   * a handful of duplicate alerts is not.
   */
  @SkipThrottle()
  @Post('sos')
  @ApiOperation({ summary: 'Raise an emergency alert' })
  trigger(@CurrentUser('userId') userId: string, @Body() dto: TriggerSosDto) {
    return this.safety.trigger(userId, dto);
  }

  @SkipThrottle()
  @Post('sos/:id/abort')
  @ApiOperation({ summary: 'Stand down an alert already sent' })
  abort(@Param('id', ParseUUIDPipe) id: string, @CurrentUser('userId') userId: string) {
    return this.safety.abort(id, userId);
  }

  @Get('contacts')
  contacts(@CurrentUser('userId') userId: string) {
    return this.safety.listEmergencyContacts(userId);
  }

  @Post('contacts')
  addContact(
    @CurrentUser('userId') userId: string,
    @CurrentUser('countryCode') countryCode: 'ZA' | 'ZW',
    @Body() dto: EmergencyContactDto,
  ) {
    return this.safety.addEmergencyContact(userId, countryCode, dto);
  }
}
