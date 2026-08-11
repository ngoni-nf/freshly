import {
  Body, Controller, Get, Headers, HttpCode, Param, ParseUUIDPipe, Post, Query, Req,
} from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsISO8601, IsOptional, IsString, Length, Matches } from 'class-validator';
import type { Request } from 'express';
import { CurrentUser, Public, Roles } from '../../common/decorators';
import { KycService } from './kyc.service';

class SubmitKycDto {
  @IsIn(['national_id', 'passport', 'drivers_licence']) documentType!: string;
  @Matches(/^[A-Za-z0-9\s-]{5,30}$/, { message: 'Enter the number exactly as it appears on the document' })
  idNumber!: string;
  @IsString() @Length(2, 120) fullName!: string;
  @IsOptional() @IsISO8601() dateOfBirth?: string;
  @IsOptional() @IsString() documentFrontKey?: string;
  @IsOptional() @IsString() documentBackKey?: string;
  @IsOptional() @IsString() selfieKey?: string;
}

class ReviewKycDto {
  @IsIn(['verified', 'rejected']) decision!: 'verified' | 'rejected';
  @IsOptional() @IsString() @Length(3, 500) reason?: string;
}

@ApiTags('kyc')
@Controller('kyc')
export class KycController {
  constructor(private readonly kyc: KycService) {}

  @Roles('provider')
  @Get('status')
  @ApiOperation({ summary: 'Verification state and what is blocking it' })
  status(@CurrentUser('providerId') providerId: string) {
    return this.kyc.status(providerId);
  }

  @Roles('provider')
  @Post('submissions')
  @ApiOperation({ summary: 'Submit identity documents for verification' })
  submit(@CurrentUser('providerId') providerId: string, @Body() dto: SubmitKycDto) {
    return this.kyc.submit(providerId, dto);
  }

  @Roles('admin', 'support')
  @Get('pending')
  @ApiOperation({ summary: 'Submissions waiting on a human decision' })
  pending(@Query('limit') limit?: string) {
    return this.kyc.pending(Math.min(Number(limit) || 50, 200));
  }

  @Roles('admin', 'support')
  @Get('submissions/:id/documents')
  @ApiOperation({ summary: 'Short-lived links to a submission’s documents' })
  documents(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('userId') reviewerUserId: string,
  ) {
    return this.kyc.documents(id, reviewerUserId);
  }

  @Roles('admin', 'support')
  @Post('submissions/:id/review')
  @ApiOperation({ summary: 'Manual decision on a submission that needs a human' })
  review(
    @Param('id', ParseUUIDPipe) id: string,
    @CurrentUser('userId') reviewerUserId: string,
    @Body() dto: ReviewKycDto,
  ) {
    return this.kyc.review(id, reviewerUserId, dto.decision, dto.reason);
  }

  /** Signed vendor callback; authenticated by the signature, not a token. */
  @Public()
  @HttpCode(200)
  @Post('callbacks/:provider')
  callback(
    @Param('provider') provider: string,
    @Headers('x-signature') signature: string,
    @Req() request: Request & { rawBody?: Buffer },
  ) {
    const raw = request.rawBody?.toString('utf8') ?? JSON.stringify(request.body ?? {});
    return this.kyc.handleCallback(provider, signature, raw);
  }
}
