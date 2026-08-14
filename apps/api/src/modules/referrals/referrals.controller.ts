import { Body, Controller, Get, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import { CurrentUser } from '../../common/decorators';
import { ReferralsService } from './referrals.service';

class ClaimCodeDto {
  @IsString() @Length(4, 12) code!: string;
}

@ApiTags('referrals')
@Controller('referrals')
export class ReferralsController {
  constructor(private readonly referrals: ReferralsService) {}

  @Get('me')
  @ApiOperation({ summary: 'Your invite code, and how it is doing' })
  async me(@CurrentUser('userId') userId: string) {
    const [code, summary] = await Promise.all([
      this.referrals.myCode(userId),
      this.referrals.summary(userId),
    ]);
    return { ...code, ...summary };
  }

  @Post('claim')
  @ApiOperation({ summary: "Use somebody's invite code before your first booking" })
  claim(@CurrentUser('userId') userId: string, @Body() dto: ClaimCodeDto) {
    return this.referrals.claim(userId, dto.code);
  }
}
