import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsEmail, IsIn, IsNumber, IsOptional, IsString,
  IsUUID, Length, Matches, Max, Min,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class SetServiceAreaDto {
  @ApiPropertyOptional({ description: 'An id from GET /markets/areas' })
  @IsOptional()
  @IsUUID()
  serviceAreaId?: string;

  /** Preferred over serviceAreaId: it names a suburb the user recognises. */
  @ApiPropertyOptional({ description: 'An id from GET /markets/places' })
  @IsOptional()
  @IsUUID()
  placeId?: string;
}

export class RequestOtpDto {
  @ApiProperty({ example: '0821234567', description: 'Local or E.164 mobile number' })
  @IsString()
  @Length(9, 20)
  phone!: string;

  @ApiProperty({ enum: ['ZA', 'ZW'], example: 'ZA' })
  @IsIn(['ZA', 'ZW'])
  countryCode!: 'ZA' | 'ZW';
}

export class VerifyOtpDto {
  @ApiProperty({ example: '0821234567' })
  @IsString()
  phone!: string;

  @ApiProperty({ enum: ['ZA', 'ZW'] })
  @IsIn(['ZA', 'ZW'])
  countryCode!: 'ZA' | 'ZW';

  @ApiProperty({ example: '481920' })
  @Matches(/^\d{6}$/, { message: 'The code must be exactly 6 digits' })
  code!: string;

  @ApiPropertyOptional({ enum: ['ios', 'android', 'web'] })
  @IsOptional()
  @IsIn(['ios', 'android', 'web'])
  platform?: 'ios' | 'android' | 'web';

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  pushToken?: string;
}

export class CompleteProfileDto {
  @ApiProperty({ example: 'Thandi Mokoena' })
  @IsString()
  @Length(2, 120)
  fullName!: string;

  @ApiPropertyOptional({ example: 'thandi@example.co.za', description: 'Required for invoicing' })
  @IsOptional()
  @IsEmail()
  email?: string;

  @ApiProperty({ description: 'POPIA / Zimbabwe DPA consent to the privacy notice' })
  @IsBoolean()
  acceptPrivacy!: boolean;

  @ApiProperty()
  @IsBoolean()
  acceptTerms!: boolean;

  @ApiPropertyOptional()
  @IsOptional()
  @IsBoolean()
  acceptMarketing?: boolean;
}

export class RegisterPushTokenDto {
  @ApiProperty({ description: 'FCM registration token, refreshed by the app when it rotates' })
  @IsString()
  @Length(20, 4096)
  pushToken!: string;

  @ApiPropertyOptional({ enum: ['ios', 'android', 'web'] })
  @IsOptional()
  @IsIn(['ios', 'android', 'web'])
  platform?: 'ios' | 'android' | 'web';
}

export class RefreshDto {
  @ApiProperty()
  @IsString()
  refreshToken!: string;
}

export class FirebaseSignInDto {
  @ApiProperty({ description: 'Firebase ID token from phone sign-in' })
  @IsString()
  @Length(20, 4096)
  idToken!: string;

  @ApiProperty({ enum: ['ZA', 'ZW'] })
  @IsIn(['ZA', 'ZW'])
  countryCode!: 'ZA' | 'ZW';

  @ApiPropertyOptional({ enum: ['ios', 'android', 'web'] })
  @IsOptional()
  @IsIn(['ios', 'android', 'web'])
  platform?: 'ios' | 'android' | 'web';

  @ApiPropertyOptional({ description: 'FCM registration token for dispatch alerts' })
  @IsOptional()
  @IsString()
  pushToken?: string;
}

export class LinkPhoneDto {
  @ApiProperty({ description: 'Firebase ID token from phone verification' })
  @IsString()
  @Length(20, 4096)
  idToken!: string;

  @ApiProperty({ enum: ['ZA', 'ZW'] })
  @IsIn(['ZA', 'ZW'])
  countryCode!: 'ZA' | 'ZW';
}

/** Mirrors service_category_enum. The database refuses anything else, but a
 *  validation error names the field; a cast error does not. */
export const SERVICE_CATEGORIES = [
  'barber', 'hair', 'nails', 'makeup', 'aesthetics', 'braiding', 'locs', 'massage',
  'brows', 'lashes', 'beard', 'scalp', 'extensions', 'color', 'body_grooming',
];

export class BecomeProviderDto {
  @ApiProperty({ example: 'Tendai Moyo' })
  @IsString()
  @Length(2, 120)
  displayName!: string;

  @ApiProperty({ enum: ['solo', 'salon'] })
  @IsIn(['solo', 'salon'])
  businessMode!: 'solo' | 'salon';

  @ApiProperty({ example: ['barber', 'beard'] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(6)
  @IsIn(SERVICE_CATEGORIES, { each: true })
  categories!: string[];

  @ApiProperty({ enum: ['mobile', 'in_shop', 'both'] })
  @IsIn(['mobile', 'in_shop', 'both'])
  venueMode!: 'mobile' | 'in_shop' | 'both';

  /** Where they work from: the shop, or home for a mobile pro. Dispatch and
   *  discovery measure from here until the first live location arrives. */
  @ApiProperty({ example: -17.7932 })
  @Type(() => Number) @IsNumber() @Min(-90) @Max(90)
  lat!: number;

  @ApiProperty({ example: 31.0361 })
  @Type(() => Number) @IsNumber() @Min(-180) @Max(180)
  lng!: number;

  @ApiPropertyOptional({ example: 'Avondale Shopping Centre, Shop 12' })
  @IsOptional() @IsString() @Length(3, 300)
  shopAddress?: string;

  @ApiPropertyOptional({ example: 10, description: 'How far a mobile pro will travel' })
  @IsOptional() @Type(() => Number) @IsNumber() @Min(1) @Max(50)
  travelRadiusKm?: number;

  @ApiPropertyOptional({ example: ['battery_clippers'] })
  @IsOptional() @IsArray() @ArrayMaxSize(5)
  @IsIn(['generator', 'inverter', 'battery_clippers', 'portable_lights', 'solar'], { each: true })
  powerBackup?: string[];

  @ApiPropertyOptional({ example: 'Fades and line-ups, ten years in Avondale.' })
  @IsOptional() @IsString() @Length(0, 600)
  bio?: string;
}
