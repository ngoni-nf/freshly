/**
 * The two invoices a completed booking produces, drafted from the booking's
 * own frozen figures.
 *
 * Pure, so the arithmetic can be proven in a unit test against the same sweep
 * the pricing engine is proven against. The property that matters: the two
 * totals are exactly what the ledger moved at capture. The provider's invoice
 * to the client is the escrow release less our service fee, which is the sum
 * of the provider_payable and platform_commission credits; ours to the
 * provider is the commission and service fee credits. Nothing here rounds —
 * every figure was rounded once already, at quote time, by the pricing
 * engine — so there is nothing for an invoice to drift from.
 */

export type InvoiceKind = 'provider_to_client' | 'platform_to_provider';

export interface InvoiceLine {
  label: string;
  amountMinor: number;
}

export interface InvoiceDraft {
  kind: InvoiceKind;
  lines: InvoiceLine[];
  subtotalMinor: number;
  /** Informational on both: the provider accounts for their own VAT, and the
   *  platform's fees are quoted inclusive, so the total never adds it on. */
  vatMinor: number;
  totalMinor: number;
}

export interface InvoiceSource {
  subtotalMinor: number;
  addonsMinor: number;
  travelFeeMinor: number;
  serviceFeeMinor: number;
  discountMinor: number;
  totalMinor: number;
  commissionBps: number;
  commissionMinor: number;
  vatOnFeesMinor: number;
  travelDistanceKm: number;
  /** Booked services and client-approved extras, in menu order. */
  items: Array<{ label: string; amountMinor: number; isAddon: boolean }>;
  vatLabel: string;
  vatBps: number;
}

export function draftInvoices(src: InvoiceSource): {
  providerToClient: InvoiceDraft;
  platformToProvider: InvoiceDraft;
} {
  const lines: InvoiceLine[] = src.items.map((item) => ({
    label: item.isAddon ? `${item.label} (extra)` : item.label,
    amountMinor: item.amountMinor,
  }));
  const itemsMinor = lines.reduce((acc, l) => acc + l.amountMinor, 0);

  // What the client paid for the provider's work: everything but our fee.
  const clientFacingMinor = src.totalMinor - src.serviceFeeMinor;

  // Surge is not stored as an amount, only as the rate it was quoted at, so
  // it is recovered as whatever the itemised lines, travel and discount do
  // not account for. Deriving it this way also means the lines always add up
  // to the total even if an item snapshot and the subtotal ever disagree.
  const surgeMinor = clientFacingMinor + src.discountMinor - src.travelFeeMinor - itemsMinor;
  if (surgeMinor > 0) lines.push({ label: 'Busy period', amountMinor: surgeMinor });
  if (surgeMinor < 0) lines.push({ label: 'Adjustment', amountMinor: surgeMinor });
  if (src.travelFeeMinor > 0) {
    lines.push({ label: `Travel (${src.travelDistanceKm.toFixed(1)} km)`, amountMinor: src.travelFeeMinor });
  }
  if (src.discountMinor > 0) lines.push({ label: 'Promo discount', amountMinor: -src.discountMinor });

  const providerToClient: InvoiceDraft = {
    kind: 'provider_to_client',
    lines,
    subtotalMinor: clientFacingMinor,
    vatMinor: 0,
    totalMinor: clientFacingMinor,
  };

  const feesMinor = src.commissionMinor + src.serviceFeeMinor;
  const platformToProvider: InvoiceDraft = {
    kind: 'platform_to_provider',
    lines: [
      { label: `Marketplace commission (${formatBps(src.commissionBps)})`, amountMinor: src.commissionMinor },
      { label: 'Platform service fee', amountMinor: src.serviceFeeMinor },
    ],
    subtotalMinor: feesMinor,
    vatMinor: src.vatOnFeesMinor,
    totalMinor: feesMinor,
  };

  return { providerToClient, platformToProvider };
}

/** 1250 -> "12.5%", 1500 -> "15%". */
export function formatBps(bps: number): string {
  const pct = bps / 100;
  return `${Number.isInteger(pct) ? pct : pct.toFixed(2).replace(/0+$/, '')}%`;
}

/** FR-ZW-2026-000001 */
export function invoiceNumber(countryCode: string, year: number, sequence: number): string {
  return `FR-${countryCode}-${year}-${String(sequence).padStart(6, '0')}`;
}
