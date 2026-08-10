import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { AuthService } from './auth.service';
import { FirebaseAuthService } from './firebase-auth.service';
import { AuthController } from './auth.controller';

@Module({
  // Registered globally because JwtAuthGuard is bound as an APP_GUARD and is
  // therefore instantiated in the root injector, where a module-scoped
  // JwtService would not be visible.
  imports: [JwtModule.register({ global: true })],
  providers: [AuthService, FirebaseAuthService],
  controllers: [AuthController],
  exports: [AuthService, FirebaseAuthService],
})
export class AuthModule {}
