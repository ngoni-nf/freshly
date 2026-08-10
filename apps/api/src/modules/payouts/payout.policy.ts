import { Injectable } from '@nestjs/common';
import { applyBps } from '../../common/money/money';
import { DomainError, InsufficientFundsError, KycRequiredError } from '../../common/errors/domain.errors';
import { HttpStatus } from '@nestjs/common';

export class PayoutBelowMinimumError extends DomainError {
  constructor(minimumMinor: number) {
    super(
      'payout_below_minimum',
      'This amount is below the minimum cash-out',
      HttpStatus.UNPROCESSABLE_ENTITY,
      { minimumMinor },
    );
  }
}

export class PayoutAccountRequiredError extends DomainError {
  constructor(reason: 'missing' | 'unverified') {
    super(
      reason === 'missing' ? 'payout_account_missing' : 'payout_account_unverified',
      reason === 'missing'
        ? 'Add a bank or mobile money account before cashing out'
        : 'Your payout account is still being verified',
      HttpStatus.CONFLICT,
    );
  }
}

export class PayoutCurrencyMismatchError extends DomainError {
  constructor(walletCurrency: string, accountCurrency: string) {
    super(
      'payout_currency_mismatch',
      'Your payout account cannot receive this currency',
      HttpStatus.CONFLICT,
      { walletCurrency, accountCurrency },
    );
  }
}

export interface PayoutRequestContext {
  availableMinor: number;
  requestedMinor: number;
  walletCurrency: string;
  accountCurrency: string | null;
  accountVerified: boolean;
  hasAccount: boolean;
  kycStatus: string;
  isSuspended: boolean;
  minimumMinor: number;
  instantFeeBps: number;
  instant: boolean;
}

export interface PayoutBreakdown {
  /** Deducted from the wallet. */
  grossMinor: number;
  feeMinor: number;
  /** What actually lands in the provider's account. */
  netMinor: number;
  instant: boolean;
}

/**
 * Who may cash out, how much, and what it costs.
 *
 * Separated from the database work for the same reason PricingService is: this
 * is the arithmetic that must never drift, and it is worth being able to sweep
 * it across a range of amounts in a unit test rather than only exercising it
 * through a live wallet.
 *
 * Two rules here are not negotiable. Gross always equals fee plus net, so the
 * ledger group balances by construction rather than by luck. And a provider
 * who is not KYC-verified cannot withdraw at all — money leaving the platform
 * to an unverified identity is the exact shape of the transaction every
 * financial-crime rule in both markets exists to prevent.
 */
@Injectable()
export class PayoutPolicy {
  assess(context: PayoutRequestContext): PayoutBreakdown {
    if (context.kycStatus !== 'verified' || context.isSuspended) {
      throw new KycRequiredError();
    }
    if (!context.hasAccount) {
      throw new PayoutAccountRequiredError('missing');
    }
    if (!context.accountVerified) {
      throw new PayoutAccountRequiredError('unverified');
    }
    if (context.accountCurrency && context.accountCurrency !== context.walletCurrency) {
      throw new PayoutCurrencyMismatchError(context.walletCurrency, context.accountCurrency);
    }

    const grossMinor = context.requestedMinor;
    if (!Number.isInteger(grossMinor) || grossMinor <= 0) {
      throw new DomainError(
        'invalid_amount',
        'Enter a whole amount greater than zero',
        HttpStatus.BAD_REQUEST,
      );
    }
    if (grossMinor < context.minimumMinor) {
      throw new PayoutBelowMinimumError(context.minimumMinor);
    }
    if (grossMinor > context.availableMinor) {
      throw new InsufficientFundsError(context.availableMinor, grossMinor);
    }

    // The daily batch is free. Only an instant cash-out carries a fee, because
    // only an instant cash-out costs the platform anything extra — and a fee
    // the provider did not choose is the fastest way to lose their trust.
    const feeMinor = context.instant ? applyBps(grossMinor, context.instantFeeBps) : 0;
    const netMinor = grossMinor - feeMinor;

    if (netMinor <= 0) {
      throw new PayoutBelowMinimumError(context.minimumMinor);
    }

    return { grossMinor, feeMinor, netMinor, instant: context.instant };
  }
}
