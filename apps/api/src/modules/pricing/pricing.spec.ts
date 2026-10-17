import { PricingService } from './pricing.service';
import { MarketConfig } from '../markets/markets.service';

const ZA: MarketConfig = {
  code: 'ZA', name: 'South Africa', defaultCurrency: 'ZAR', supportedCurrencies: ['ZAR'],
  dialPrefix: '+27', phoneNationalLength: 9, timezone: 'Africa/Johannesburg',
  commissionBps: 1250, serviceFeeMinor: 1000, travelFeePerKmMinor: 700, travelFeeFreeKm: 3,
  vatBps: 1500, vatLabel: 'VAT', taxAuthority: 'SARS', paymentProvider: 'stitch',
  kycProvider: 'smileid', sosProvider: 'aura', gridStatusProvider: 'eskom_se_push',
  cancellationWindowMinutes: 120, cancellationFeeBps: 5000, noShowGraceMinutes: 10, minPayoutMinor: 5000,
  referralRefereeDiscountMinor: 5000, referralReferrerCreditMinor: 5000, referralCreditTtlDays: 90,
  dispatchOfferSeconds: 60, maxSearchRadiusKm: 25, isLive: true,
};

const ZW: MarketConfig = {
  ...ZA, code: 'ZW', name: 'Zimbabwe', defaultCurrency: 'USD', supportedCurrencies: ['USD', 'ZWG'],
  dialPrefix: '+263', serviceFeeMinor: 50, travelFeePerKmMinor: 40,
  taxAuthority: 'ZIMRA', paymentProvider: 'paynow', sosProvider: 'mock', isLive: false,
};

const service = (priceMinor: number) => ({
  id: 's1', name: 'Skin fade', priceMinor, durationMinutes: 45,
});

describe('PricingService', () => {
  const pricing = new PricingService();

  it('prices a standard mobile booking in South Africa', () => {
    const q = pricing.quote({
      market: ZA, services: [service(18_000)], travelDistanceKm: 4.2, venueMode: 'mobile',
    });

    expect(q.currency).toBe('ZAR');
    expect(q.subtotalMinor).toBe(18_000);
    // 4.2km - 3km free = 1.2km * R7 = R8.40, rounded up to R9.00
    expect(q.travelFeeMinor).toBe(900);
    expect(q.serviceFeeMinor).toBe(1_000);
    expect(q.totalMinor).toBe(19_900);
    expect(q.commissionMinor).toBe(2_250); // 12.5% of R180
    expect(q.providerPayoutMinor).toBe(15_750 + 900); // service share plus travel
  });

  it('never charges travel for an in-shop booking', () => {
    const q = pricing.quote({
      market: ZA, services: [service(18_000)], travelDistanceKm: 12, venueMode: 'in_shop',
    });
    expect(q.travelFeeMinor).toBe(0);
  });

  it('does not charge travel inside the free radius', () => {
    const q = pricing.quote({
      market: ZA, services: [service(18_000)], travelDistanceKm: 2.4, venueMode: 'mobile',
    });
    expect(q.travelFeeMinor).toBe(0);
  });

  it('reconciles the money exactly, across a wide sweep of prices and distances', () => {
    for (let price = 1_000; price <= 200_000; price += 1_337) {
      for (const km of [0, 2.9, 3.1, 7.5, 18.4]) {
        const q = pricing.quote({
          market: ZA, services: [service(price)], travelDistanceKm: km, venueMode: 'mobile',
        });

        // What the client pays must equal what everyone receives.
        const distributed = q.commissionMinor + q.providerPayoutMinor + q.serviceFeeMinor;
        expect(distributed).toBe(q.totalMinor);

        // Nobody is ever paid a negative amount.
        expect(q.commissionMinor).toBeGreaterThanOrEqual(0);
        expect(q.providerPayoutMinor).toBeGreaterThanOrEqual(0);

        // Everything stays in integer minor units.
        expect(Number.isInteger(q.totalMinor)).toBe(true);
        expect(Number.isInteger(q.providerPayoutMinor)).toBe(true);
      }
    }
  });

  it('leaves the whole travel fee with the provider', () => {
    const q = pricing.quote({
      market: ZA, services: [service(10_000)], travelDistanceKm: 10, venueMode: 'mobile',
    });
    const serviceShare = q.providerPayoutMinor - q.travelFeeMinor;
    expect(serviceShare + q.commissionMinor).toBe(10_000);
  });

  it('prices the same booking in Zimbabwe using USD tariffs', () => {
    const q = pricing.quote({
      market: ZW, services: [service(1_500)], travelDistanceKm: 5, venueMode: 'mobile',
    });
    expect(q.currency).toBe('USD');
    expect(q.serviceFeeMinor).toBe(50);          // $0.50
    expect(q.travelFeeMinor).toBe(100);          // 2km * $0.40 = $0.80 -> $1.00
    expect(q.totalMinor).toBe(1_650);
    expect(q.commissionMinor + q.providerPayoutMinor + q.serviceFeeMinor).toBe(q.totalMinor);
  });

  it('applies surge to service value only, never to the platform fee', () => {
    const flat = pricing.quote({
      market: ZA, services: [service(20_000)], travelDistanceKm: 0, venueMode: 'mobile',
    });
    const surged = pricing.quote({
      market: ZA, services: [service(20_000)], travelDistanceKm: 0, venueMode: 'mobile', surgeBps: 2000,
    });
    expect(surged.totalMinor - flat.totalMinor).toBe(4_000);
    expect(surged.serviceFeeMinor).toBe(flat.serviceFeeMinor);
  });

  it('refuses to let a discount eat the platform fee', () => {
    const q = pricing.quote({
      market: ZA, services: [service(5_000)], travelDistanceKm: 0, venueMode: 'mobile',
      discountMinor: 99_999,
    });
    expect(q.totalMinor).toBe(q.serviceFeeMinor);
    expect(q.commissionMinor + q.providerPayoutMinor + q.serviceFeeMinor).toBe(q.totalMinor);
  });

  it('extracts VAT from platform revenue rather than adding it on top', () => {
    const q = pricing.quote({
      market: ZA, services: [service(20_000)], travelDistanceKm: 0, venueMode: 'mobile',
    });
    const platformRevenue = q.commissionMinor + q.serviceFeeMinor;
    expect(q.vatOnFeesMinor).toBe(Math.round((platformRevenue * 1500) / 11500));
    expect(q.vatOnFeesMinor).toBeLessThan(platformRevenue);
  });

  describe('cancellation', () => {
    const quote = { totalMinor: 19_900, serviceFeeMinor: 1_000 };

    it('is free outside the window when nobody has travelled', () => {
      const r = pricing.cancellationFee(ZA, quote, {
        minutesUntilStart: 600, providerEnRoute: false, cancelledBy: 'client',
      });
      expect(r.feeMinor).toBe(0);
      expect(r.refundMinor).toBe(19_900);
    });

    it('charges half inside the two-hour window', () => {
      const r = pricing.cancellationFee(ZA, quote, {
        minutesUntilStart: 45, providerEnRoute: false, cancelledBy: 'client',
      });
      expect(r.feeMinor).toBe(9_450);
      expect(r.feeMinor + r.refundMinor).toBe(19_900);
    });

    it('charges once the provider is already travelling, whatever the clock says', () => {
      const r = pricing.cancellationFee(ZA, quote, {
        minutesUntilStart: null, providerEnRoute: true, cancelledBy: 'client',
      });
      expect(r.feeMinor).toBeGreaterThan(0);
      expect(r.reason).toBe('provider_en_route');
    });

    it('never charges the client when the provider cancels', () => {
      const r = pricing.cancellationFee(ZA, quote, {
        minutesUntilStart: 10, providerEnRoute: true, cancelledBy: 'provider',
      });
      expect(r.feeMinor).toBe(0);
      expect(r.refundMinor).toBe(19_900);
    });
  });
});
