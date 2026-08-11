import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsISO8601, IsOptional, IsString, Length, Matches } from 'class-validator';
import { CurrentUser, Roles } from '../../common/decorators';
import { CredentialsService } from './credentials.service';
import { SERVICE_CATEGORIES } from '../../common/catalog/service-categories';

class SubmitCredentialDto {
  @IsIn(SERVICE_CATEGORIES) category!: string;
  @IsIn(['skin_penetration_permit', 'aesthetics_practitioner', 'laser_operator'])
  credentialKind!: string;
  @IsOptional() @IsString() @Length(2, 120) issuer?: string;
  @IsOptional() @Matches(/^[A-Za-z0-9\s/-]{3,40}$/, { message: 'Enter the registration number as issued' })
  reference?: string;
  @IsOptional() @IsString() documentKey?: string;
  @IsOptional() @IsISO8601() expiresOn?: string;
}

class ReviewCredentialDto {
  @IsIn(['verified', 'rejected']) decision!: 'verified' | 'rejected';
  @IsOptional() @IsString() @Length(3, 500) reason?: string;
}

@ApiTags('credentials')
@Controller('credentials')
export class CredentialsController {
  constructor(private readonly credentials: CredentialsService) {}

  @Roles('provider')
  @Get('me')
  @ApiOperation({ summary: 'Credentials held, what the market regulates, and any uncovered services' })
  status(@CurrentUser('providerId') providerId: string) {
    return this.credentials.status(providerId);
  }

  @Roles('provider')
  @Post('me')
  @ApiOperation({ summary: 'Submit a practitioner credential for review' })
  submit(@CurrentUser('providerId') providerId: string, @Body() dto: SubmitCredentialDto) {
    return this.credentials.submit(providerId, dto);
  }

  @Roles('admin', 'support')
  @Get('pending')
  pending(@Query('limit') limit?: string) {
    return this.credentials.pending(Math.min(Number(limit) || 50, 200));
  }

  /**
   * Deliberately human-only. Verifying a practitioner registration means
   * checking a regulator's roll, and there is no adapter that can honestly
   * pretend to have done that.
   */
  @Roles('admin', 'support')
  @Post(':id/review')
  review(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('userId') reviewerUserId: string,
    @Body() dto: ReviewCredentialDto,
  ) {
    return this.credentials.review(id, reviewerUserId, dto.decision, dto.reason);
  }
}
