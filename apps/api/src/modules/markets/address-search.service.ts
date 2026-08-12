import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DomainError } from '../../common/errors/domain.errors';

export interface AddressSuggestion {
  placeId: string;
  primary: string;
  secondary: string;
}

/**
 * Street addresses, via Google Places.
 *
 * Proxied rather than called from the app, for the same reason storage is: the
 * key never leaves the process. A Places key shipped in an APK is extractable
 * in about a minute and is billed to us until somebody notices, and Android
 * app-signature restrictions do not apply to the web service endpoints.
 *
 * Two calls, deliberately. Autocomplete returns names and opaque place ids and
 * no coordinates; Details turns one chosen id into a point. Billing follows
 * the same shape — a session token ties the keystrokes and the final lookup
 * into one charged session instead of one per keystroke, which is roughly the
 * difference between $2.83 and $80 per thousand addresses.
 *
 * Results are restricted to the countries we operate in. Suggesting an address
 * in Lagos to somebody in Rosebank wastes a tap and a call.
 */
@Injectable()
export class AddressSearchService {
  private readonly logger = new Logger(AddressSearchService.name);
  private readonly key: string | undefined;

  constructor(private readonly config: ConfigService) {
    this.key = this.config.get<string>('GOOGLE_API_KEY') || undefined;
    if (!this.key) {
      this.logger.warn(
        'GOOGLE_API_KEY is not set; address search will refuse rather than guess',
      );
    }
  }

  get enabled(): boolean {
    return Boolean(this.key);
  }

  private assertEnabled(): void {
    if (!this.key) {
      // Refuses rather than degrading to something that looks like it worked.
      // A silent fallback to suburb-only search would let somebody book a job
      // to the middle of a suburb centroid and find out on the day.
      throw new DomainError(
        'address_search_unavailable',
        'Address search is not set up yet. Choose a saved address or your suburb.',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
  }

  async suggest(
    query: string,
    countryCode: 'ZA' | 'ZW',
    sessionToken: string,
    near?: { lat: number; lng: number },
  ): Promise<AddressSuggestion[]> {
    this.assertEnabled();
    if (query.trim().length < 3) return [];

    const params = new URLSearchParams({
      input: query,
      key: this.key!,
      sessiontoken: sessionToken,
      components: `country:${countryCode.toLowerCase()}`,
      // Street addresses and premises, not restaurants. Somebody booking a
      // haircut at home does not want a list of nearby businesses.
      types: 'address',
      language: countryCode === 'ZA' ? 'en-ZA' : 'en',
    });
    // Bias, not restriction: a 30km circle around where they are, so local
    // streets sort first without hiding anything further out.
    if (near) params.set('locationbias', `circle:30000@${near.lat},${near.lng}`);

    try {
      const res = await fetch(
        `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params}`,
      );
      const body = (await res.json()) as {
        status: string;
        predictions?: Array<{
          place_id: string;
          structured_formatting?: { main_text: string; secondary_text: string };
          description: string;
        }>;
        error_message?: string;
      };

      if (body.status === 'ZERO_RESULTS') return [];
      if (body.status !== 'OK') {
        // REQUEST_DENIED almost always means billing is off or the Places API
        // is not enabled on the key, so say that rather than "try again".
        this.logger.error(`Places autocomplete ${body.status}: ${body.error_message ?? ''}`);
        throw new DomainError(
          'address_search_failed',
          body.status === 'REQUEST_DENIED'
            ? 'Address search is not enabled on this key'
            : 'We could not search addresses just now',
          HttpStatus.BAD_GATEWAY,
        );
      }

      return (body.predictions ?? []).map((p) => ({
        placeId: p.place_id,
        primary: p.structured_formatting?.main_text ?? p.description,
        secondary: p.structured_formatting?.secondary_text ?? '',
      }));
    } catch (err) {
      if (err instanceof DomainError) throw err;
      this.logger.error(`Places autocomplete failed: ${(err as Error).message}`);
      throw new DomainError(
        'address_search_failed',
        'We could not search addresses just now',
        HttpStatus.BAD_GATEWAY,
      );
    }
  }

  /** Turn a chosen suggestion into something bookable. */
  async resolve(
    placeId: string,
    sessionToken: string,
  ): Promise<{ formatted: string; lat: number; lng: number }> {
    this.assertEnabled();

    const params = new URLSearchParams({
      place_id: placeId,
      key: this.key!,
      sessiontoken: sessionToken,
      // Only what is needed. Places bills per field group, and asking for the
      // whole record costs several times a geometry lookup.
      fields: 'formatted_address,geometry/location',
    });

    try {
      const res = await fetch(
        `https://maps.googleapis.com/maps/api/place/details/json?${params}`,
      );
      const body = (await res.json()) as {
        status: string;
        result?: {
          formatted_address: string;
          geometry: { location: { lat: number; lng: number } };
        };
      };

      if (body.status !== 'OK' || !body.result) {
        throw new DomainError(
          'address_not_found',
          'We could not find that address',
          HttpStatus.NOT_FOUND,
        );
      }

      return {
        formatted: body.result.formatted_address,
        lat: body.result.geometry.location.lat,
        lng: body.result.geometry.location.lng,
      };
    } catch (err) {
      if (err instanceof DomainError) throw err;
      this.logger.error(`Places details failed: ${(err as Error).message}`);
      throw new DomainError(
        'address_search_failed',
        'We could not look that address up just now',
        HttpStatus.BAD_GATEWAY,
      );
    }
  }
}
