import { Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsIn, IsInt, IsNumber, IsOptional,
  IsString, IsUUID, Length, Matches, Max, Min, ValidateNested,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class ChatMessageDto {
  /// Was a plain `{ body: string }` type, which ValidationPipe cannot see, so
  /// the field was neither length-limited nor checked to be a string at all.
  /// Long enough for a real message about a gate code, short enough that
  /// nobody pastes a novel into a push notification.
  @ApiProperty({ example: "I'm at the gate, buzzer 4B" })
  @IsString() @Length(1, 2000) body!: string;
}

export class AddonRequestDto {
  @ApiProperty({ description: 'One of your own active services' })
  @IsUUID() serviceId!: string;
}

export class AddonResponseDto {
  @ApiProperty({ description: 'The client accepting or refusing the extra work' })
  @IsBoolean() approve!: boolean;
}

export class DestinationDto {
  @ApiProperty() @IsNumber() @Min(-90) @Max(90) lat!: number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) lng!: number;
}

export class ChangeDestinationDto {
  @ApiProperty() @ValidateNested() @Type(() => DestinationDto) destination!: DestinationDto;

  @ApiProperty({ example: '12 Sandton Drive, Parkmore, Sandton' })
  @IsString() @Length(4, 500) destinationAddress!: string;

  @ApiPropertyOptional({ description: 'Gate code, unit, which door' })
  @IsOptional() @IsString() @Length(0, 500) destinationNotes?: string;
}

export class QuoteBookingDto {
  @ApiProperty() @IsUUID() providerId!: string;

  @ApiProperty({ type: [String] })
  @IsArray() @ArrayMinSize(1) @ArrayMaxSize(10) @IsUUID('4', { each: true })
  serviceIds!: string[];

  @ApiProperty() @ValidateNested() @Type(() => DestinationDto) destination!: DestinationDto;

  @ApiPropertyOptional() @IsOptional() @IsString() @Length(3, 30) promoCode?: string;

  @ApiPropertyOptional({ enum: ['mobile', 'in_shop'] })
  @IsOptional() @IsIn(['mobile', 'in_shop']) venueMode?: 'mobile' | 'in_shop';
}

export class CreateBookingDto extends QuoteBookingDto {
  @ApiProperty({ enum: ['instant', 'scheduled'] })
  @IsIn(['instant', 'scheduled']) bookingType!: 'instant' | 'scheduled';

  @ApiProperty() @IsString() @Length(3, 500) destinationAddress!: string;

  @ApiPropertyOptional() @IsOptional() @IsString() @Length(0, 500) destinationNotes?: string;

  @ApiPropertyOptional({ description: 'ISO 8601, required when bookingType is scheduled' })
  @IsOptional() @IsString() scheduledStart?: string;
}

export class CheckoutDto {
  @ApiProperty({ enum: ['card', 'capitec_pay', 'instant_eft', 'ecocash', 'onemoney', 'innbucks'] })
  @IsIn(['card', 'capitec_pay', 'instant_eft', 'ecocash', 'onemoney', 'innbucks'])
  method!: string;
}

export class AdvanceStatusDto {
  @ApiProperty({ enum: ['en_route', 'arrived', 'in_progress'] })
  @IsIn(['en_route', 'arrived', 'in_progress'])
  status!: 'en_route' | 'arrived' | 'in_progress';
}

export class VerifyPinDto {
  @ApiProperty({ example: '7391' })
  @Matches(/^\d{4}$/, { message: 'The completion code is 4 digits' })
  pin!: string;
}

export class CancelBookingDto {
  @ApiProperty() @IsString() @Length(3, 300) reason!: string;
}

export class AddAddonDto {
  @ApiProperty() @IsUUID() addonId!: string;
}

export class RespondAddonDto {
  @ApiProperty() approve!: boolean;
}

export class ReviewDto {
  @ApiProperty({ minimum: 1, maximum: 5 })
  @Type(() => Number) @IsInt() @Min(1) @Max(5) rating!: number;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional() @IsArray() @IsString({ each: true }) @ArrayMaxSize(6) tags?: string[];

  @ApiPropertyOptional()
  @IsOptional() @IsString() @Length(0, 1000) comment?: string;
}
