import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { IS_PUBLIC_KEY, AuthenticatedUser } from '../decorators';

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest();
    const header: string | undefined = request.headers?.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedException({ code: 'missing_token', message: 'Authentication required' });
    }

    try {
      const payload = await this.jwt.verifyAsync(header.slice(7), {
        secret: this.config.getOrThrow<string>('JWT_SECRET'),
      });
      const user: AuthenticatedUser = {
        userId: payload.sub,
        phone: payload.phone,
        roles: payload.roles ?? ['client'],
        countryCode: payload.country ?? 'ZA',
        providerId: payload.providerId,
      };
      request.user = user;
      return true;
    } catch {
      throw new UnauthorizedException({ code: 'invalid_token', message: 'Session expired, please sign in again' });
    }
  }
}
