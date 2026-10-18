import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ProvidersService } from './providers.service';
import { ProvidersController } from './providers.controller';
import { StaffService } from './staff.service';
import { StaffController, StaffInvitesController } from './staff.controller';

@Module({
  // AuthModule for the session a staff member is issued on joining: their
  // JWT carries the provider role and id, so accepting an invite has to end
  // the same way become-provider does.
  imports: [AuthModule],
  providers: [ProvidersService, StaffService],
  // Staff routes first: ProvidersController ends with a public ':id'.
  controllers: [StaffController, StaffInvitesController, ProvidersController],
  exports: [ProvidersService, StaffService],
})
export class ProvidersModule {}
