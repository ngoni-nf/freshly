import { Body, Controller, Delete, Get, HttpCode, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsString, Length } from 'class-validator';
import { CurrentUser, Roles } from '../../common/decorators';
import { StaffService } from './staff.service';

class StaffInviteDto {
  /** Local or E.164; normalised to the salon's market. */
  @IsString() @Length(6, 20) phone!: string;
}

/**
 * The salon's side of team management. Declared as its own controller so
 * these routes register before ProvidersController's public `:id`, which
 * would otherwise try to parse "me" as a UUID.
 */
@ApiTags('providers')
@Controller('providers/me/staff')
export class StaffController {
  constructor(private readonly staff: StaffService) {}

  @Roles('provider')
  @Get()
  @ApiOperation({ summary: 'Salon only: the team, active members and open invitations together' })
  list(@CurrentUser('providerId') providerId: string) {
    return this.staff.list(providerId);
  }

  @Roles('provider')
  @Post('invites')
  @ApiOperation({ summary: 'Salon only: invite a phone number to join the team' })
  invite(@CurrentUser('providerId') providerId: string, @Body() dto: StaffInviteDto) {
    return this.staff.invite(providerId, dto.phone);
  }

  @Roles('provider')
  @Delete(':id')
  @HttpCode(200)
  @ApiOperation({ summary: 'Salon only: cancel an invitation or remove a team member' })
  remove(@CurrentUser('providerId') providerId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.staff.remove(providerId, id);
  }
}

/**
 * The invitee's side lives under /auth because accepting is a sign-up step:
 * it ends with a new session, the same as become-provider.
 */
@ApiTags('auth')
@Controller('auth/staff-invites')
export class StaffInvitesController {
  constructor(private readonly staff: StaffService) {}

  @Get()
  @ApiOperation({ summary: 'Salons that have invited the signed-in number' })
  pending(@CurrentUser('userId') userId: string) {
    return this.staff.pendingFor(userId);
  }

  @Post(':id/accept')
  @ApiOperation({ summary: 'Join the salon; returns a session carrying the provider role' })
  accept(@CurrentUser('userId') userId: string, @Param('id', ParseUUIDPipe) id: string) {
    return this.staff.accept(userId, id);
  }
}
