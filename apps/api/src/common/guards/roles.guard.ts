import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AccountRole, AuthenticatedUser, ROLES_KEY } from '../decorators';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<AccountRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required?.length) return true;

    const user = context.switchToHttp().getRequest().user as AuthenticatedUser | undefined;
    if (!user) throw new ForbiddenException({ code: 'forbidden', message: 'Not permitted' });

    const granted = required.some((role) => user.roles.includes(role));
    if (!granted) {
      throw new ForbiddenException({
        code: 'insufficient_role',
        message: 'Your account does not have access to this action',
      });
    }
    return true;
  }
}
