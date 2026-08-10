import { SetMetadata, createParamDecorator, ExecutionContext } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
/** Opt an endpoint out of JWT authentication. Auth is on by default. */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

export const ROLES_KEY = 'roles';
export type AccountRole = 'client' | 'provider' | 'staff' | 'admin' | 'support';
export const Roles = (...roles: AccountRole[]) => SetMetadata(ROLES_KEY, roles);

export interface AuthenticatedUser {
  userId: string;
  phone: string;
  roles: AccountRole[];
  countryCode: 'ZA' | 'ZW';
  providerId?: string;
}

export const CurrentUser = createParamDecorator(
  (field: keyof AuthenticatedUser | undefined, ctx: ExecutionContext) => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as AuthenticatedUser;
    return field ? user?.[field] : user;
  },
);

export const IDEMPOTENT_KEY = 'idempotent';
/** Marks a mutating endpoint as requiring an Idempotency-Key header. */
export const Idempotent = () => SetMetadata(IDEMPOTENT_KEY, true);
