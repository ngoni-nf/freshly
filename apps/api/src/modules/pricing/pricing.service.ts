import { Injectable } from '@nestjs/common';
import { applyBps, roundUpTo, splitWithRemainder, sum, taxIncludedIn } from '../../common/money/money';
import { MarketConfig } from '../markets/markets.service';

export interface PricedService {
  id: string;
  name: string;
  priceMinor: number;
  durationMinutes: number;
}

export interface QuoteInput {
  market: MarketConfig;
  services: PricedService[];
  addons?: PricedService[];
  travelDistanceKm: number;
  venueMode: 'mobile' | 'in_shop' | 'both';
  surgeBps?: number;
  discountMinor?: number;
  commissionBpsOverride?: number | null;
}

export interface QuoteLine {
  label: string;
  amountMinor: number;
  kind: 'charge' | 'discount' | 'info';
}

export interface Quote {
  currency: string;
  subtotalMinor: number;
  addonsMinor: number;
  travelFeeMinor: number;
  serviceFeeMinor: number;
  discountMinor: number;
  surgeBps: number;
  totalMinor: number;
  commissionBps: number;
  commissionMinor: number;
  vatOnFeesMinor: number;
  providerPayoutMinor: number;
  travelDistanceKm: number;
  breakdown: QuoteLine[];
}

/**
 * The pricing engine.
 *
 * Three properties are non-negotiable here, and the tests enforce all three:
 *
 *   1. The quote is authoritative. The client renders it and never recomputes,
 *      so what a customer agrees to and what the gateway authorises are the
 *      same number by construction.
 *   2. Every split reconciles. commission + payout + platform fee equals the
 *      total, exactly, for every amount — a stray cent per booking becomes an
 *      unreconcilable ledger inside a month.
 *   3. The provider never absorbs platform costs. The flat service fee is
 *      added to what the client pays; commission is taken from the service
 *      value only, not from the travel fee the provider actually earned by
 *      driving, and not from the fee that covers our own gateway costs.
 */
@Injectable()
export class PricingService {
  quote(input: QuoteInput): Quote {
    const {
      market,
      services,
      addons = [],
      travelDistanceKm,
      venueMode,
      surgeBps = 0,
      discountMinor = 0,
      commissionBpsOverride = null,
    } = input;

    const subtotalMinor = sum(...services.map((s) => s.priceMinor));
    const addonsMinor = addons.length ? sum(...addons.map((a) => a.priceMinor)) : 0;
    const serviceValueMinor = subtotalMinor + addonsMinor;

    // Travel is only charged when the provider actually travels, and only
    // beyond the free radius. Charging from the first metre makes short local
    // jobs look expensive and pushes both sides off-platform.
    const billableKm =
      venueMode === 'in_shop' ? 0 : Math.max(0, travelDistanceKm - market.travelFeeFreeKm);
    const rawTravel = Math.round(billableKm * market.travelFeePerKmMinor);
    const travelFeeMinor = roundUpTo(rawTravel, 100);

    const surgeMinor = surgeBps > 0 ? applyBps(serviceValueMinor, surgeBps) : 0;

    const serviceFeeMinor = market.serviceFeeMinor;

    const grossMinor =
      serviceValueMinor + surgeMinor + travelFeeMinor + serviceFeeMinor;
    const cappedDiscount = Math.min(discountMinor, grossMinor - serviceFeeMinor);
    const totalMinor = grossMinor - cappedDiscount;

    // Commission applies to the service value plus surge — the marketplace's
    // contribution — not to travel reimbursement and not to our own fee.
    const commissionBps = commissionBpsOverride ?? market.commissionBps;
    const commissionableMinor = serviceValueMinor + surgeMinor - cappedDiscount;
    const split = splitWithRemainder(
      Math.max(0, commissionableMinor),
      [
        { key: 'commission', bps: commissionBps },
        { key: 'provider', bps: 10_000 - commissionBps },
      ],
      'provider',
    );

    // VAT is embedded in the platform's own revenue, which is what the tax
    // authority cares about. The provider invoices the client separately for
    // the service and accounts for their own VAT position.
    const platformRevenueMinor = split.commission + serviceFeeMinor;
    const vatOnFeesMinor = taxIncludedIn(platformRevenueMinor, market.vatBps);

    const providerPayoutMinor = split.provider + travelFeeMinor;

    const breakdown: QuoteLine[] = [
      ...services.map<QuoteLine>((s) => ({ label: s.name, amountMinor: s.priceMinor, kind: 'charge' })),
      ...addons.map<QuoteLine>((a) => ({ label: `${a.name} (extra)`, amountMinor: a.priceMinor, kind: 'charge' })),
    ];
    if (surgeMinor > 0) {
      breakdown.push({ label: 'Busy period', amountMinor: surgeMinor, kind: 'charge' });
    }
    if (travelFeeMinor > 0) {
      breakdown.push({
        label: `Travel (${travelDistanceKm.toFixed(1)} km)`,
        amountMinor: travelFeeMinor,
        kind: 'charge',
      });
    }
    breakdown.push({ label: 'Platform fee', amountMinor: serviceFeeMinor, kind: 'charge' });
    if (cappedDiscount > 0) {
      breakdown.push({ label: 'Promo discount', amountMinor: -cappedDiscount, kind: 'discount' });
    }

    return {
      currency: market.defaultCurrency,
      subtotalMinor,
      addonsMinor,
      travelFeeMinor,
      serviceFeeMinor,
      discountMinor: cappedDiscount,
      surgeBps,
      totalMinor,
      commissionBps,
      commissionMinor: split.commission,
      vatOnFeesMinor,
      providerPayoutMinor,
      travelDistanceKm,
      breakdown,
    };
  }

  /**
   * Cancellation fee. Inside the market's window, or once a provider is
   * already travelling, a portion of the hold is captured — the provider has
   * spent fuel and turned down other work, and someone has to carry that.
   */
  cancellationFee(
    market: MarketConfig,
    quote: { totalMinor: number; serviceFeeMinor: number },
    context: {
      minutesUntilStart: number | null;
      providerEnRoute: boolean;
      cancelledBy: 'client' | 'provider';
      reason?: string;
    },
  ): { feeMinor: number; refundMinor: number; reason: string } {
    if (context.cancelledBy === 'provider' && context.reason !== 'no_show') {
      return { feeMinor: 0, refundMinor: quote.totalMinor, reason: 'provider_cancelled' };
    }

    const isNoShow = context.reason === 'no_show';
    const insideWindow =
      context.minutesUntilStart !== null && context.minutesUntilStart <= market.cancellationWindowMinutes;

    if (!insideWindow && !context.providerEnRoute && !isNoShow) {
      return { feeMinor: 0, refundMinor: quote.totalMinor, reason: 'free_cancellation' };
    }

    const chargeableMinor = quote.totalMinor - quote.serviceFeeMinor;
    const feeMinor = applyBps(chargeableMinor, market.cancellationFeeBps);
    return {
      feeMinor,
      refundMinor: quote.totalMinor - feeMinor,
      reason: isNoShow ? 'client_no_show' : (context.providerEnRoute ? 'provider_en_route' : 'late_cancellation'),
    };
  }
}

export interface FrozenBookingFigures {
  /** Booked services and client-approved extras, in display order. */
  items: Array<{ label: string; amountMinor: number; isAddon: boolean }>;
  travelFeeMinor: number;
  serviceFeeMinor: number;
  discountMinor: number;
  totalMinor: number;
  travelDistanceKm: number;
}

/**
 * The breakdown of a booking that already exists, in the same shape as a
 * quote's, so the app renders "what you agreed to" with the widget it used
 * for "what you will pay".
 *
 * Built from the booking row and its item snapshots, never from today's
 * menu prices: the figures were frozen at checkout and have only grown by
 * extras the client approved. Surge is kept as a rate, not an amount, so it
 * is recovered as whatever the itemised lines, travel, fee and discount do
 * not account for; that way the lines always sum to the stored total even
 * if a snapshot and the subtotal ever disagreed.
 */
export function bookingBreakdown(src: FrozenBookingFigures): QuoteLine[] {
  const breakdown: QuoteLine[] = src.items.map<QuoteLine>((i) => ({
    label: i.isAddon ? `${i.label} (extra)` : i.label,
    amountMinor: i.amountMinor,
    kind: 'charge',
  }));
  const itemsMinor = breakdown.reduce((acc, l) => acc + l.amountMinor, 0);
  const surgeMinor = src.totalMinor + src.discountMinor - src.serviceFeeMinor - src.travelFeeMinor - itemsMinor;
  if (surgeMinor > 0) breakdown.push({ label: 'Busy period', amountMinor: surgeMinor, kind: 'charge' });
  if (surgeMinor < 0) breakdown.push({ label: 'Adjustment', amountMinor: surgeMinor, kind: 'discount' });
  if (src.travelFeeMinor > 0) {
    breakdown.push({ label: `Travel (${src.travelDistanceKm.toFixed(1)} km)`, amountMinor: src.travelFeeMinor, kind: 'charge' });
  }
  breakdown.push({ label: 'Platform fee', amountMinor: src.serviceFeeMinor, kind: 'charge' });
  if (src.discountMinor > 0) breakdown.push({ label: 'Promo discount', amountMinor: -src.discountMinor, kind: 'discount' });
  return breakdown;
}
