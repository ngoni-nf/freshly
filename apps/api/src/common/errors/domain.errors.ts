import { HttpException, HttpStatus } from '@nestjs/common';

/**
 * Domain errors carry a stable machine-readable code. Mobile clients switch on
 * the code, never on the message — messages are localised and will change.
 */
export class DomainError extends HttpException {
  constructor(
    public readonly code: string,
    message: string,
    status: HttpStatus = HttpStatus.BAD_REQUEST,
    public readonly details?: Record<string, unknown>,
  ) {
    super({ code, message, details }, status);
  }
}

export class NotFoundError extends DomainError {
  constructor(entity: string, id?: string) {
    super('not_found', `${entity}${id ? ` ${id}` : ''} was not found`, HttpStatus.NOT_FOUND);
  }
}

export class IllegalTransitionError extends DomainError {
  constructor(from: string, to: string) {
    super(
      'illegal_transition',
      `A booking cannot move from ${from} to ${to}`,
      HttpStatus.CONFLICT,
      { from, to },
    );
  }
}

export class PaymentError extends DomainError {
  constructor(message: string, details?: Record<string, unknown>) {
    super('payment_failed', message, HttpStatus.PAYMENT_REQUIRED, details);
  }
}

export class InsufficientFundsError extends DomainError {
  constructor(availableMinor: number, requestedMinor: number) {
    super('insufficient_funds', 'Requested amount exceeds the available balance', HttpStatus.CONFLICT, {
      availableMinor,
      requestedMinor,
    });
  }
}

export class KycRequiredError extends DomainError {
  constructor() {
    super(
      'kyc_required',
      'Identity verification must be completed before you can accept bookings',
      HttpStatus.FORBIDDEN,
    );
  }
}

export class OutsideServiceAreaError extends DomainError {
  constructor() {
    super(
      'outside_service_area',
      'Freshly is not live in this area yet',
      HttpStatus.UNPROCESSABLE_ENTITY,
    );
  }
}

export class DispatchRaceLostError extends DomainError {
  constructor() {
    super('offer_taken', 'Another professional accepted this booking first', HttpStatus.CONFLICT);
  }
}

export class RateLimitedError extends DomainError {
  constructor(retryAfterSeconds: number) {
    super('rate_limited', 'Too many attempts, please wait before trying again', HttpStatus.TOO_MANY_REQUESTS, {
      retryAfterSeconds,
    });
  }
}
