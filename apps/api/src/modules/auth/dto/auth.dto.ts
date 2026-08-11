import { IsBoolean, IsEmail, IsIn, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

export class SetServiceAreaDto {
  @ApiProperty({ description: 'An id from GET /markets/areas' })
  @IsUUID()
  serviceAreaId!: string;
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
