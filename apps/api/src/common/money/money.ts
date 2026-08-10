/**
 * Money helpers.
 *
 * Every amount in this system is an integer count of minor units. There is no
 * float arithmetic anywhere in the pricing or ledger path — the marketplace
 * splits a single payment three or four ways and a rounding drift of one cent
 * per booking becomes an unreconcilable ledger inside a month.
 */

export type Bps = number; // basis points: 1250 = 12.5%

/** Apply a basis-point rate, rounding half away from zero. */
export function applyBps(amountMinor: number, bps: Bps): number {
  assertInteger(amountMinor, 'amountMinor');
  const scaled = amountMinor * bps;
  const sign = scaled < 0 ? -1 : 1;
  return sign * Math.round(Math.abs(scaled) / 10_000);
}

/**
 * Split an amount into named parts, giving any rounding remainder to the
 * designated bearer. Guarantees the parts always sum back to the original.
 */
export function splitWithRemainder(
  totalMinor: number,
  parts: Array<{ key: string; bps: Bps }>,
  remainderTo: string,
): Record<string, number> {
  assertInteger(totalMinor, 'totalMinor');

  // Validate the remainder bearer up front, not lazily when a remainder
  // happens to appear. A mistyped key would otherwise pass every test that
  // divides evenly and only surface in production on an awkward amount.
  if (!parts.some((p) => p.key === remainderTo)) {
    throw new Error(`remainderTo "${remainderTo}" is not one of the split parts`);
  }

  const totalBps = parts.reduce((acc, p) => acc + p.bps, 0);
  if (totalBps !== 10_000) {
    throw new Error(`split parts must total 10000 bps, received ${totalBps}`);
  }

  const result: Record<string, number> = {};
  let allocated = 0;

  for (const part of parts) {
    const value = applyBps(totalMinor, part.bps);
    result[part.key] = value;
    allocated += value;
  }

  const remainder = totalMinor - allocated;
  if (remainder !== 0) {
    result[remainderTo] += remainder;
  }

  return result;
}

/**
 * Extract tax already included in a gross amount.
 * SA and Zimbabwe both quote VAT-inclusive prices to consumers.
 */
export function taxIncludedIn(grossMinor: number, vatBps: Bps): number {
  assertInteger(grossMinor, 'grossMinor');
  return Math.round((grossMinor * vatBps) / (10_000 + vatBps));
}

/** Round up to the nearest step — used for travel fees so quotes look sane. */
export function roundUpTo(amountMinor: number, stepMinor: number): number {
  if (stepMinor <= 0) return amountMinor;
  return Math.ceil(amountMinor / stepMinor) * stepMinor;
}

export function sum(...amounts: number[]): number {
  return amounts.reduce((acc, n) => {
    assertInteger(n, 'amount');
    return acc + n;
  }, 0);
}

const MINOR_UNIT_DIGITS: Record<string, number> = { ZAR: 2, USD: 2, ZWG: 2 };
const SYMBOLS: Record<string, string> = { ZAR: 'R', USD: 'US$', ZWG: 'ZiG' };

export function formatMoney(minor: number, currency: string): string {
  const digits = MINOR_UNIT_DIGITS[currency] ?? 2;
  const divisor = 10 ** digits;
  const value = (minor / divisor).toFixed(digits);
  const symbol = SYMBOLS[currency] ?? `${currency} `;
  return `${symbol}${value}`;
}

function assertInteger(value: number, label: string): void {
  if (!Number.isInteger(value)) {
    throw new TypeError(`${label} must be an integer number of minor units, received ${value}`);
  }
}
