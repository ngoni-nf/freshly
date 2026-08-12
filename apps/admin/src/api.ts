/**
 * The only place this console talks to the API.
 *
 * Same rule as the mobile apps: one client, so auth, error shape and the base
 * URL are decided once. Screens call these functions, never fetch directly.
 */

const BASE = import.meta.env.VITE_API_BASE_URL ?? '/api';

/**
 * Session storage, not local storage.
 *
 * This console can read identity documents and suspend providers. A token that
 * survives closing the tab is a token left behind on a shared operations
 * machine, so it dies with the tab and the operator signs in again.
 */
const TOKEN_KEY = 'freshly.ops.token';

export const token = {
  get: () => sessionStorage.getItem(TOKEN_KEY),
  set: (value: string) => sessionStorage.setItem(TOKEN_KEY, value),
  clear: () => sessionStorage.removeItem(TOKEN_KEY),
};

export class ApiError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const auth = token.get();
  const response = await fetch(`${BASE}${path}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(auth ? { Authorization: `Bearer ${auth}` } : {}),
      ...init.headers,
    },
  });

  if (response.status === 204) return undefined as T;

  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new ApiError(
      body.code ?? 'unknown_error',
      body.message ?? 'Something went wrong',
      response.status,
    );
  }
  return body as T;
}

// ─── Types ────────────────────────────────────────────────────────────────

export interface Me {
  id: string;
  fullName: string;
  phone: string;
  roles: string[];
}

export interface KycSubmission {
  id: string;
  providerId: string;
  providerName: string;
  legalName: string;
  countryCode: string;
  status: string;
  documentType: string;
  idNumberLast4: string | null;
  livenessScore: number | null;
  faceMatchScore: number | null;
  hasDocuments: boolean;
  submittedAt: string;
}

export interface Credential {
  id: string;
  providerName: string;
  countryCode: string;
  category: string;
  credentialKind: string;
  issuer: string | null;
  referenceLast4: string | null;
  expiresOn: string | null;
  submittedAt: string;
}

export interface Provider {
  id: string;
  displayName: string;
  phone: string;
  countryCode: string;
  kycStatus: string;
  isSuspended: boolean;
  isOnline: boolean;
  rating: number;
  completedJobs: number;
  categories: string[];
  venueMode: string;
  joinedAt: string | null;
  /** Null unless they are working right now. Online and busy are not the same. */
  activeJob: { reference: string; status: string } | null;
  upcomingCount: number;
}

export interface ScheduledBooking {
  id: string;
  reference: string;
  status: string;
  bookingType: string;
  scheduledStart: string | null;
  createdAt: string;
  total: { minor: number; currency: string };
  /** Null when nobody has accepted it yet — the row ops most needs to see. */
  providerName: string | null;
  providerId: string | null;
  clientName: string;
  services: string[];
  destinationAddress: string;
}

export interface CompletedJob {
  id: string;
  reference: string;
  completedAt: string | null;
  total: { minor: number; currency: string };
  clientName: string;
  providerId: string | null;
  providerName: string | null;
  /** The provider's running average, for context around a single bad job. */
  providerRating: number | null;
  providerRatingCount: number;
  services: string[];
  destinationAddress: string;
  /** Null when the client left no review. Silence is worth seeing too. */
  review: {
    rating: number;
    tags: string[];
    comment: string | null;
    reviewedAt: string;
  } | null;
}

export interface TicketMessage {
  id: string;
  isStaff: boolean;
  body: string;
  createdAt: string;
}

export interface Ticket {
  id: string;
  subject: string;
  body: string;
  status: string;
  createdAt: string;
  closedAt: string | null;
  lastStaffReplyAt: string | null;
  messages: TicketMessage[];
  raisedByName: string;
  raisedByPhone: string;
  bookingReference: string | null;
}

export interface SosAlert {
  id: string;
  status: string;
  actor: string;
  createdAt: string;
  acknowledgedAt: string | null;
  location: { lat: number; lng: number };
  accuracyM: number | null;
  batteryPct: number | null;
  vehicleDescription: string | null;
  personName: string;
  personPhone: string;
  counterpartyName: string | null;
  bookingReference: string | null;
  destinationAddress: string | null;
  resolutionNotes?: string | null;
  resolvedAt?: string | null;
}

export type DocumentLinks = Record<string, { url: string; expiresIn: number }>;

// ─── Calls ────────────────────────────────────────────────────────────────

export const api = {
  requestOtp: (phone: string, countryCode: string) =>
    request<void>('/auth/otp/request', {
      method: 'POST',
      body: JSON.stringify({ phone, countryCode }),
    }),

  verifyOtp: (phone: string, countryCode: string, code: string) =>
    request<{ accessToken: string; user: Me }>('/auth/otp/verify', {
      method: 'POST',
      body: JSON.stringify({ phone, countryCode, code }),
    }),

  me: () => request<Me>('/auth/me'),

  kycPending: () => request<KycSubmission[]>('/kyc/pending'),

  kycDocuments: (id: string) =>
    request<DocumentLinks>(`/kyc/submissions/${id}/documents`),

  reviewKyc: (id: string, decision: 'verified' | 'rejected', reason?: string) =>
    request<{ status: string }>(`/kyc/submissions/${id}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision, reason }),
    }),

  credentialsPending: () => request<Credential[]>('/credentials/pending'),

  reviewCredential: (id: string, decision: 'verified' | 'rejected', reason?: string) =>
    request<{ status: string }>(`/credentials/${id}/review`, {
      method: 'POST',
      body: JSON.stringify({ decision, reason }),
    }),

  /** An empty query is deliberate and returns the whole roster. */
  searchProviders: (q: string) =>
    request<Provider[]>(q ? `/providers?q=${encodeURIComponent(q)}` : '/providers'),

  upcoming: (days = 14) =>
    request<ScheduledBooking[]>(`/providers/schedule/upcoming?days=${days}`),

  completed: (days = 30) =>
    request<CompletedJob[]>(`/providers/schedule/completed?days=${days}`),

  tickets: (side: 'clients' | 'providers', status = 'open') =>
    request<Ticket[]>(`/support/queue/${side}?status=${status}`),

  replyToTicket: (id: string, body: string) =>
    request<{ ok: true }>(`/support/tickets/${id}/reply`, {
      method: 'POST',
      body: JSON.stringify({ body }),
    }),

  closeTicket: (id: string, resolution: string) =>
    request<{ ok: true }>(`/support/tickets/${id}/close`, {
      method: 'POST',
      body: JSON.stringify({ resolution }),
    }),

  sosActive: () => request<SosAlert[]>('/safety/sos/active'),
  sosHistory: () => request<SosAlert[]>('/safety/sos/history'),

  sosAcknowledge: (id: string) =>
    request<{ ok: true }>(`/safety/sos/${id}/acknowledge`, { method: 'POST' }),

  sosResolve: (id: string, notes: string) =>
    request<{ ok: true }>(`/safety/sos/${id}/resolve`, {
      method: 'POST',
      body: JSON.stringify({ notes }),
    }),

  setSuspension: (id: string, suspended: boolean, reason: string) =>
    request<{ isSuspended: boolean }>(`/providers/${id}/suspension`, {
      method: 'POST',
      body: JSON.stringify({ suspended, reason }),
    }),
};
