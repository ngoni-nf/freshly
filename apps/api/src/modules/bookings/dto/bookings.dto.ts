import { Type } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsIn, IsInt, IsNumber, IsOptional,
  IsString, IsUUID, Length, Matches, Max, Min, ValidateNested,
} from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class DestinationDto {
  @ApiProperty() @IsNumber() @Min(-90) @Max(90) lat!: number;
  @ApiProperty() @IsNumber() @Min(-180) @Max(180) lng!: number;
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
