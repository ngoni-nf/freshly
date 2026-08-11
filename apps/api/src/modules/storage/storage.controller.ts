import { Body, Controller, ForbiddenException, Get, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsString, Length } from 'class-validator';
import { CurrentUser } from '../../common/decorators';
import { StorageService, UploadPurpose } from './storage.service';

const PURPOSES: UploadPurpose[] = [
  'kyc_document',
  'kyc_selfie',
  'credential_document',
  'portfolio',
  'avatar',
];

class SignUploadDto {
  @IsIn(PURPOSES) purpose!: UploadPurpose;
  @IsString() @Length(3, 100) contentType!: string;
  @IsOptional() @IsString() @Length(1, 200) fileName?: string;
}

@ApiTags('storage')
@Controller('storage')
export class StorageController {
  constructor(private readonly storage: StorageService) {}

  @Post('uploads')
  @ApiOperation({ summary: 'Get a short-lived URL to upload one file' })
  signUpload(@CurrentUser('userId') userId: string, @Body() dto: SignUploadDto) {
    return this.storage.signUpload(userId, dto.purpose, dto.contentType, dto.fileName);
  }

  /**
   * Reading back is scoped to the owner. Support and admin review goes through
   * the KYC endpoints, which check the reviewer's role — this one exists so a
   * provider can see the document they just uploaded, and nothing more.
   */
  @Get('downloads')
  async signDownload(
    @CurrentUser('userId') userId: string,
    @Query('bucket') bucket: string,
    @Query('key') key: string,
  ) {
    if (!StorageService.isOwnedBy(key, userId)) {
      throw new ForbiddenException({
        code: 'not_your_file',
        message: 'That file does not belong to you',
      });
    }
    return this.storage.signDownload(bucket, key);
  }
}
