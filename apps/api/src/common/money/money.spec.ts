import { applyBps, splitWithRemainder, taxIncludedIn, roundUpTo, formatMoney, sum } from './money';

describe('money', () => {
  describe('applyBps', () => {
    it('applies a commission rate', () => {
      expect(applyBps(20_000, 1250)).toBe(2500); // R200.00 @ 12.5% = R25.00
    });

    it('rounds half away from zero rather than to even', () => {
      expect(applyBps(5, 5000)).toBe(3); // 2.5 -> 3, never 2
    });

    it('refuses non-integer input, which is how cents get lost', () => {
      expect(() => applyBps(10.5, 1250)).toThrow(TypeError);
    });
  });

  describe('splitWithRemainder', () => {
    it('always sums back to the original amount', () => {
      const total = 9_999;
      const parts = splitWithRemainder(
        total,
        [
          { key: 'commission', bps: 1250 },
          { key: 'provider', bps: 8750 },
        ],
        'provider',
      );
      expect(parts.commission + parts.provider).toBe(total);
    });

    it('gives the rounding remainder to the named bearer', () => {
      // 1 cent split three ways cannot divide evenly; the provider absorbs it.
      const parts = splitWithRemainder(
        1,
        [
          { key: 'a', bps: 3333 },
          { key: 'b', bps: 3333 },
          { key: 'provider', bps: 3334 },
        ],
        'provider',
      );
      expect(parts.a + parts.b + parts.provider).toBe(1);
    });

    it('holds over a large sweep of amounts', () => {
      for (let amount = 1; amount <= 5_000; amount += 7) {
        const parts = splitWithRemainder(
          amount,
          [
            { key: 'commission', bps: 1250 },
            { key: 'provider', bps: 8750 },
          ],
          'provider',
        );
        expect(parts.commission + parts.provider).toBe(amount);
        expect(parts.provider).toBeGreaterThanOrEqual(0);
      }
    });

    it('rejects a remainder bearer that is not part of the split, even when nothing is left over', () => {
      expect(() =>
        splitWithRemainder(100, [{ key: 'a', bps: 10_000 }], 'nobody'),
      ).toThrow(/not one of the split parts/);
    });

    it('rejects a split whose rates do not total 100%', () => {
      expect(() =>
        splitWithRemainder(
          100,
          [
            { key: 'commission', bps: 1250 },
            { key: 'provider', bps: 8000 },
          ],
          'provider',
        ),
      ).toThrow(/must total 10000 bps/);
    });
  });

  describe('taxIncludedIn', () => {
    it('extracts 15% VAT from a VAT-inclusive amount', () => {
      // R115.00 inclusive contains R15.00 of VAT.
      expect(taxIncludedIn(11_500, 1500)).toBe(1500);
    });

    it('returns zero when the market has no VAT configured', () => {
      expect(taxIncludedIn(10_000, 0)).toBe(0);
    });
  });

  describe('roundUpTo', () => {
    it('rounds a travel fee up to the nearest rand', () => {
      expect(roundUpTo(1_234, 100)).toBe(1_300);
    });

    it('leaves an exact multiple alone', () => {
      expect(roundUpTo(1_300, 100)).toBe(1_300);
    });
  });

  describe('formatMoney', () => {
    it('formats each supported currency', () => {
      expect(formatMoney(12_500, 'ZAR')).toBe('R125.00');
      expect(formatMoney(12_500, 'USD')).toBe('US$125.00');
      expect(formatMoney(12_500, 'ZWG')).toBe('ZiG125.00');
    });
  });

  describe('sum', () => {
    it('adds integer minor units', () => {
      expect(sum(1_000, 250, 75)).toBe(1_325);
    });

    it('rejects a float sneaking into the total', () => {
      expect(() => sum(1_000, 2.5)).toThrow(TypeError);
    });
  });
});
