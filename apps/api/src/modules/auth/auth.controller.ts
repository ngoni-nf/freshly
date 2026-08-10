import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import {
  CompleteProfileDto, FirebaseSignInDto, RefreshDto, RequestOtpDto, VerifyOtpDto,
} from './dto/auth.dto';
import { CurrentUser, Public } from '../../common/decorators';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Public()
  @Post('otp/request')
  @HttpCode(200)
  @ApiOperation({ summary: 'Send a one-time code by SMS' })
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.auth.requestOtp(dto.phone, dto.countryCode);
  }

  @Public()
  @Post('otp/verify')
  @HttpCode(200)
  @ApiOperation({ summary: 'Exchange a one-time code for a session' })
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.phone, dto.countryCode, dto.code, {
      platform: dto.platform ?? 'android',
      pushToken: dto.pushToken,
    });
  }

  @Public()
  @Post('firebase')
  @HttpCode(200)
  @ApiOperation({ summary: 'Exchange a Firebase ID token for a Freshly session' })
  signInWithFirebase(@Body() dto: FirebaseSignInDto) {
    return this.auth.signInWithFirebase(dto.idToken, dto.countryCode, {
      platform: dto.platform ?? 'android',
      pushToken: dto.pushToken,
    });
  }

  @Get('me')
  @ApiOperation({ summary: 'The signed-in user, for restoring a session at launch' })
  me(@CurrentUser('userId') userId: string) {
    return this.auth.me(userId);
  }

  @Post('profile')
  @ApiOperation({ summary: 'Complete the profile and record consent' })
  completeProfile(@CurrentUser('userId') userId: string, @Body() dto: CompleteProfileDto) {
    return this.auth.completeProfile(userId, dto);
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  @ApiOperation({ summary: 'Rotate a refresh token for a new session' })
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(200)
  logout(@CurrentUser('userId') userId: string) {
    return this.auth.logout(userId);
  }
}
