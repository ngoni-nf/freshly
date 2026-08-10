import {
  PayoutAccountRequiredError,
  PayoutBelowMinimumError,
  PayoutCurrencyMismatchError,
  PayoutPolicy,
  PayoutRequestContext,
} from './payout.policy';
import { InsufficientFundsError, KycRequiredError } from '../../common/errors/domain.errors';

const base: PayoutRequestContext = {
  availableMinor: 100_000,
  requestedMinor: 50_000,
  walletCurrency: 'ZAR',
  accountCurrency: 'ZAR',
  accountVerified: true,
  hasAccount: true,
  kycStatus: 'verified',
  isSuspended: false,
  minimumMinor: 5_000,
  instantFeeBps: 150,
  instant: false,
};

const ctx = (overrides: Partial<PayoutRequestContext> = {}): PayoutRequestContext => ({
  ...base,
  ...overrides,
});

describe('PayoutPolicy', () => {
  const policy = new PayoutPolicy();

  it('takes no fee on the free daily batch', () => {
    const result = policy.assess(ctx());
    expect(result.feeMinor).toBe(0);
    expect(result.netMinor).toBe(50_000);
    expect(result.grossMinor).toBe(50_000);
  });

  it('charges the instant fee only when instant is chosen', () => {
    const result = policy.assess(ctx({ instant: true }));
    expect(result.feeMinor).toBe(750); // 1.5% of R500
    expect(result.netMinor).toBe(49_250);
  });

  it('never charges a fee the provider did not opt into', () => {
    // `instant` omitted upstream must mean the free batch, not the paid rail.
    expect(policy.assess(ctx({ instant: false })).feeMinor).toBe(0);
  });

  it('refuses a provider who is not verified', () => {
    expect(() => policy.assess(ctx({ kycStatus: 'in_review' }))).toThrow(KycRequiredError);
    expect(() => policy.assess(ctx({ kycStatus: 'rejected' }))).toThrow(KycRequiredError);
    expect(() => policy.assess(ctx({ isSuspended: true }))).toThrow(KycRequiredError);
  });

  it('refuses without a verified destination account', () => {
    expect(() => policy.assess(ctx({ hasAccount: false }))).toThrow(PayoutAccountRequiredError);
    expect(() => policy.assess(ctx({ accountVerified: false }))).toThrow(PayoutAccountRequiredError);
  });

  it('refuses to pay a ZAR balance into a USD account', () => {
    expect(() => policy.assess(ctx({ accountCurrency: 'USD' }))).toThrow(PayoutCurrencyMismatchError);
  });

  it('enforces the minimum and the available balance', () => {
    expect(() => policy.assess(ctx({ requestedMinor: 4_999 }))).toThrow(PayoutBelowMinimumError);
    expect(() => policy.assess(ctx({ requestedMinor: 100_001 }))).toThrow(InsufficientFundsError);
  });

  it('allows withdrawing the entire balance', () => {
    const result = policy.assess(ctx({ requestedMinor: 100_000 }));
    expect(result.netMinor).toBe(100_000);
  });

  it('rejects fractional and non-positive amounts', () => {
    expect(() => policy.assess(ctx({ requestedMinor: 5_000.5 }))).toThrow(/whole amount/);
    expect(() => policy.assess(ctx({ requestedMinor: 0 }))).toThrow(/whole amount/);
    expect(() => policy.assess(ctx({ requestedMinor: -5_000 }))).toThrow(/whole amount/);
  });

  /**
   * The property the ledger depends on. If gross ever stops equalling fee plus
   * net, fn_assert_ledger_balanced fires on every cash-out and nobody gets
   * paid — so it is swept rather than spot-checked.
   */
  it('always splits gross into exactly fee plus net, across the range', () => {
    for (let amount = 5_000; amount <= 5_000_000; amount += 7_331) {
      // 10000 bps is excluded on purpose: a 100% fee leaves nothing to send
      // and is rejected, which the next test covers.
      for (const bps of [0, 1, 150, 250, 999, 5_000]) {
        const result = policy.assess(
          ctx({ requestedMinor: amount, availableMinor: 5_000_000, instant: true, instantFeeBps: bps }),
        );
        expect(result.feeMinor + result.netMinor).toBe(result.grossMinor);
        expect(result.grossMinor).toBe(amount);
        expect(Number.isInteger(result.feeMinor)).toBe(true);
        expect(Number.isInteger(result.netMinor)).toBe(true);
        expect(result.feeMinor).toBeGreaterThanOrEqual(0);
        expect(result.netMinor).toBeGreaterThan(0);
      }
    }
  });

  it('refuses a fee that would consume the whole payout', () => {
    // 100% fee leaves nothing to send; failing is better than a zero-value
    // instruction to a bank.
    expect(() =>
      policy.assess(ctx({ instant: true, instantFeeBps: 10_000, requestedMinor: 5_000 })),
    ).toThrow(PayoutBelowMinimumError);
  });
});
