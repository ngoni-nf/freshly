import { MarketConfig } from '../markets/markets.service';
import { PricingService } from '../pricing/pricing.service';
import { draftInvoices, formatBps, invoiceNumber } from './invoice-lines';

const ZA: MarketConfig = {
  code: 'ZA', name: 'South Africa', defaultCurrency: 'ZAR', supportedCurrencies: ['ZAR'],
  dialPrefix: '+27', phoneNationalLength: 9, timezone: 'Africa/Johannesburg',
  commissionBps: 1250, serviceFeeMinor: 1000, travelFeePerKmMinor: 700, travelFeeFreeKm: 3,
  vatBps: 1500, vatLabel: 'VAT', taxAuthority: 'SARS', paymentProvider: 'stitch',
  kycProvider: 'smileid', sosProvider: 'aura', gridStatusProvider: 'eskom_se_push',
  cancellationWindowMinutes: 120, cancellationFeeBps: 5000, noShowGraceMinutes: 10, minPayoutMinor: 5000,
  emergencyNumber: '10111',
  referralRefereeDiscountMinor: 5000, referralReferrerCreditMinor: 5000, referralCreditTtlDays: 90,
  dispatchOfferSeconds: 60, maxSearchRadiusKm: 25, isLive: true,
};

const sum = (lines: Array<{ amountMinor: number }>) => lines.reduce((a, l) => a + l.amountMinor, 0);

describe('draftInvoices', () => {
  const pricing = new PricingService();

  it('splits a quoted booking into what the client paid the provider and what the provider paid us', () => {
    const q = pricing.quote({
      market: ZA,
      services: [{ id: 's1', name: 'Skin fade', priceMinor: 18_000, durationMinutes: 45 }],
      travelDistanceKm: 4.2, venueMode: 'mobile',
    });
    const { providerToClient, platformToProvider } = draftInvoices({
      subtotalMinor: q.subtotalMinor, addonsMinor: 0, travelFeeMinor: q.travelFeeMinor,
      serviceFeeMinor: q.serviceFeeMinor, discountMinor: q.discountMinor, totalMinor: q.totalMinor,
      commissionBps: q.commissionBps, commissionMinor: q.commissionMinor, vatOnFeesMinor: q.vatOnFeesMinor,
      travelDistanceKm: 4.2,
      items: [{ label: 'Skin fade', amountMinor: 18_000, isAddon: false }],
      vatLabel: 'VAT', vatBps: 1500,
    });

    // R180 + R9 travel; the R10 service fee is ours, not the provider's.
    expect(providerToClient.totalMinor).toBe(18_900);
    expect(providerToClient.lines.map((l) => l.label)).toEqual(['Skin fade', 'Travel (4.2 km)']);
    expect(sum(providerToClient.lines)).toBe(providerToClient.totalMinor);

    expect(platformToProvider.totalMinor).toBe(q.commissionMinor + q.serviceFeeMinor);
    expect(platformToProvider.vatMinor).toBe(q.vatOnFeesMinor);
    expect(platformToProvider.lines[0].label).toBe('Marketplace commission (12.5%)');
    expect(sum(platformToProvider.lines)).toBe(platformToProvider.totalMinor);

    // Between them the two documents account for every cent the client paid.
    expect(providerToClient.totalMinor + q.serviceFeeMinor).toBe(q.totalMinor);
  });

  it('itemises approved extras, surge and a promo, and the lines still add up', () => {
    const surgeMinor = 1_500;
    const discountMinor = 2_000;
    const src = {
      subtotalMinor: 18_000, addonsMinor: 5_000, travelFeeMinor: 900, serviceFeeMinor: 1_000,
      discountMinor, totalMinor: 18_000 + 5_000 + 900 + 1_000 + surgeMinor - discountMinor,
      commissionBps: 1250, commissionMinor: 2_875, vatOnFeesMinor: 505, travelDistanceKm: 4.2,
      items: [
        { label: 'Skin fade', amountMinor: 18_000, isAddon: false },
        { label: 'Beard trim', amountMinor: 5_000, isAddon: true },
      ],
      vatLabel: 'VAT', vatBps: 1500,
    };
    const { providerToClient } = draftInvoices(src);
    expect(providerToClient.lines.map((l) => l.label)).toEqual([
      'Skin fade', 'Beard trim (extra)', 'Busy period', 'Travel (4.2 km)', 'Promo discount',
    ]);
    expect(providerToClient.lines.find((l) => l.label === 'Busy period')!.amountMinor).toBe(surgeMinor);
    expect(providerToClient.lines.find((l) => l.label === 'Promo discount')!.amountMinor).toBe(-discountMinor);
    expect(sum(providerToClient.lines)).toBe(providerToClient.totalMinor);
    expect(providerToClient.totalMinor).toBe(src.totalMinor - src.serviceFeeMinor);
  });

  it('reconciles across the same sweep the pricing engine is proven against', () => {
    for (let price = 1_000; price <= 200_000; price += 1_337) {
      for (const km of [0, 2.9, 3.1, 7.5, 18.4]) {
        const q = pricing.quote({
          market: ZA,
          services: [{ id: 's1', name: 'Cut', priceMinor: price, durationMinutes: 30 }],
          travelDistanceKm: km, venueMode: 'mobile',
        });
        const { providerToClient, platformToProvider } = draftInvoices({
          subtotalMinor: q.subtotalMinor, addonsMinor: 0, travelFeeMinor: q.travelFeeMinor,
          serviceFeeMinor: q.serviceFeeMinor, discountMinor: q.discountMinor, totalMinor: q.totalMinor,
          commissionBps: q.commissionBps, commissionMinor: q.commissionMinor, vatOnFeesMinor: q.vatOnFeesMinor,
          travelDistanceKm: km,
          items: [{ label: 'Cut', amountMinor: price, isAddon: false }],
          vatLabel: 'VAT', vatBps: 1500,
        });
        expect(sum(providerToClient.lines)).toBe(providerToClient.totalMinor);
        expect(sum(platformToProvider.lines)).toBe(platformToProvider.totalMinor);
        expect(providerToClient.totalMinor + q.serviceFeeMinor).toBe(q.totalMinor);
        // What the provider keeps is their invoice less ours.
        expect(providerToClient.totalMinor - platformToProvider.totalMinor + q.serviceFeeMinor)
          .toBe(q.providerPayoutMinor);
      }
    }
  });
});

describe('invoice numbering', () => {
  it('is per country and year, zero-padded to six digits', () => {
    expect(invoiceNumber('ZW', 2026, 1)).toBe('FR-ZW-2026-000001');
    expect(invoiceNumber('ZA', 2027, 123456)).toBe('FR-ZA-2027-123456');
  });

  it('prints basis points as a percentage people recognise', () => {
    expect(formatBps(1250)).toBe('12.5%');
    expect(formatBps(1500)).toBe('15%');
    expect(formatBps(1550)).toBe('15.5%');
  });
});
