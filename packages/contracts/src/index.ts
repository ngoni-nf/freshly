/**
 * Shared contracts between the API, the admin portal and (via codegen) the
 * Flutter clients. Single source of truth for anything that crosses a wire.
 */

export type CountryCode = 'ZA' | 'ZW';
export type CurrencyCode = 'ZAR' | 'USD' | 'ZWG';

/** One value per provider specialization. Matches service_category_enum. */
export type ServiceCategory =
  | 'barber' | 'beard' | 'scalp'
  | 'hair' | 'braiding' | 'locs' | 'extensions' | 'color'
  | 'nails'
  | 'makeup' | 'lashes' | 'brows'
  | 'aesthetics' | 'body_grooming' | 'massage';

export type CredentialStatus = 'pending' | 'verified' | 'rejected' | 'expired';

export type BookingType = 'instant' | 'scheduled';
export type VenueMode = 'mobile' | 'in_shop' | 'both';

export type BookingStatus =
  | 'draft' | 'pending_auth' | 'authorized' | 'accepted' | 'en_route'
  | 'arrived' | 'in_progress' | 'completed' | 'cancelled' | 'expired' | 'disputed';

export type EscrowStatus =
  | 'unauthorized' | 'authorizing' | 'authorized' | 'captured'
  | 'partially_captured' | 'released' | 'refunded' | 'partially_refunded'
  | 'frozen' | 'failed';

export type PaymentMethod =
  | 'card' | 'capitec_pay' | 'instant_eft' | 'ecocash' | 'onemoney'
  | 'innbucks' | 'wallet' | 'cash';

export type PowerBackup =
  | 'generator' | 'inverter' | 'battery_clippers' | 'portable_lights' | 'solar';

/** Money always crosses the wire as integer minor units plus its currency. */
export interface Money {
  minor: number;
  currency: CurrencyCode;
}

export interface GeoPoint { lat: number; lng: number; }

export interface PriceQuote {
  currency: CurrencyCode;
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
  breakdown: Array<{ label: string; amountMinor: number; kind: 'charge' | 'discount' | 'info' }>;
}

export interface ProviderSearchResult {
  providerId: string;
  displayName: string;
  avatarUrl: string | null;
  distanceKm: number;
  rating: number;
  ratingCount: number;
  completedJobs: number;
  hasPowerBackup: boolean;
  isOnline: boolean;
  fromPrice: Money;
  categories: ServiceCategory[];
  etaMinutes: number | null;
}

export interface BookingSummary {
  id: string;
  reference: string;
  status: BookingStatus;
  bookingType: BookingType;
  venueMode: VenueMode;
  scheduledStart: string | null;
  destinationAddress: string;
  total: Money;
  providerId: string | null;
  providerName: string | null;
  createdAt: string;
}

/** Payload broadcast on the realtime channel while a job is live. */
export interface TrackingUpdate {
  bookingId: string;
  status: BookingStatus;
  providerLocation: GeoPoint | null;
  headingDegrees: number | null;
  etaMinutes: number | null;
  distanceRemainingKm: number | null;
  updatedAt: string;
}

export interface DispatchOffer {
  offerId: string;
  bookingId: string;
  reference: string;
  serviceNames: string[];
  distanceKm: number;
  etaMinutes: number;
  payout: Money;
  destinationAddress: string;
  scheduledStart: string | null;
  expiresAt: string;
  clientRating: number;
}

export interface GridStatus {
  countryCode: CountryCode;
  stage: number;
  source: string;
  effectiveFrom: string;
  effectiveTo: string | null;
  nextWindow: { start: string; end: string } | null;
}

/** Structured output of the AI concierge search bar. */
export interface ParsedBookingIntent {
  serviceCategory: ServiceCategory | null;
  rawSearchQuery: string;
  bookingType: BookingType;
  targetDate?: string;
  targetTime?: string;
  locationContext?: string;
  powerBackupRequired: boolean;
  confidence: number;
}

export const REALTIME_EVENTS = {
  LOCATION_PING: 'location.ping',
  BOOKING_STATUS: 'booking.status',
  DISPATCH_OFFER: 'dispatch.offer',
  DISPATCH_REVOKED: 'dispatch.revoked',
  ADDON_REQUESTED: 'addon.requested',
  MESSAGE_NEW: 'message.new',
  SOS_TRIGGERED: 'sos.triggered',
} as const;

export type RealtimeEvent = typeof REALTIME_EVENTS[keyof typeof REALTIME_EVENTS];
