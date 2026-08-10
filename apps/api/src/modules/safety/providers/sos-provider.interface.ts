import { Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';

export interface SosDispatchRequest {
  sosId: string;
  countryCode: 'ZA' | 'ZW';
  lat: number;
  lng: number;
  accuracyM?: number;
  personName: string;
  personPhone: string;
  /** Free text the responder reads first: booking reference, who the other party is. */
  context: string;
}

export interface SosDispatchResult {
  externalReference: string;
  accepted: boolean;
  /** What to tell the user to dial if we could not reach a response service. */
  fallbackNumber?: string;
}

export interface SosProvider {
  readonly name: string;
  dispatch(request: SosDispatchRequest): Promise<SosDispatchResult>;
}

/**
 * No armed-response integration.
 *
 * This deliberately reports `accepted: false` rather than pretending. The
 * user-facing consequence is that the app tells them to call the emergency
 * number themselves, which is true and useful — whereas a mock that claims a
 * response unit is coming would be the single most dangerous lie this codebase
 * could tell.
 */
export class MockSosProvider implements SosProvider {
  readonly name = 'mock';
  private readonly logger = new Logger('MockSosProvider');

  async dispatch(request: SosDispatchRequest): Promise<SosDispatchResult> {
    this.logger.error(
      `SOS ${request.sosId} at ${request.lat},${request.lng} — no response provider configured`,
    );
    return { externalReference: `mocksos_${randomUUID()}`, accepted: false };
  }
}

/**
 * Private armed response. Contracted per market, and the contract is the hard
 * part — a control room has to accept our alerts, which is a commercial
 * agreement with an SLA, not an API key.
 */
export class AuraSosProvider implements SosProvider {
  readonly name = 'aura';

  constructor(
    private readonly apiKey: string,
    private readonly baseUrl: string,
  ) {}

  async dispatch(request: SosDispatchRequest): Promise<SosDispatchResult> {
    const response = await fetch(`${this.baseUrl}/v1/incidents`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        reference: request.sosId,
        location: { latitude: request.lat, longitude: request.lng, accuracy: request.accuracyM },
        contact: { name: request.personName, phone: request.personPhone },
        notes: request.context,
      }),
    });

    if (!response.ok) {
      // Never throw out of an SOS path. A failed dispatch must still return,
      // so the caller can fall back to telling the user which number to dial.
      return { externalReference: '', accepted: false };
    }

    const body = (await response.json()) as { id?: string };
    return { externalReference: String(body.id ?? ''), accepted: true };
  }
}
