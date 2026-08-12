import { Body, Controller, Get, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import {
  IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Length, Max, Min,
} from 'class-validator';
import { SkipThrottle } from '@nestjs/throttler';
import { CurrentUser, Roles } from '../../common/decorators';
import { SafetyService } from './safety.service';

class SosDispositionDto {
  /// What was done. An alert closed with no note is one nobody can account for
  /// afterwards, and these are the records that get read back in an inquiry.
  @IsString() @Length(3, 2000) notes!: string;
}

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
   * The live alert board.
   *
   * Deliberately exempt from throttling and polled hard by the console: this
   * is the one screen where being a minute stale is the difference that
   * matters. Returns coordinates, because "where are they" is the only
   * question that counts, and the person's number, because the first action is
   * to ring them.
   */
  @SkipThrottle()
  @Roles('admin', 'support')
  @Get('sos/active')
  @ApiOperation({ summary: 'Open emergency alerts, with location and contacts' })
  activeAlerts() {
    return this.safety.activeAlerts();
  }

  @Roles('admin', 'support')
  @Get('sos/history')
  @ApiOperation({ summary: 'Alerts already dealt with' })
  alertHistory() {
    return this.safety.alertHistory();
  }

  @Roles('admin', 'support')
  @Post('sos/:id/acknowledge')
  @ApiOperation({ summary: 'Take ownership of an alert' })
  acknowledge(
    @CurrentUser('userId') staffUserId: string,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.safety.acknowledge(id, staffUserId);
  }

  @Roles('admin', 'support')
  @Post('sos/:id/resolve')
  @ApiOperation({ summary: 'Close an alert with what was done' })
  resolve(
    @CurrentUser('userId') staffUserId: string,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: SosDispositionDto,
  ) {
    return this.safety.resolve(id, staffUserId, dto.notes);
  }

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
