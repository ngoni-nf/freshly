import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface ParsedBookingIntent {
  serviceCategory: string | null;
  rawSearchQuery: string;
  bookingType: 'instant' | 'scheduled';
  targetDate?: string;
  targetTime?: string;
  locationContext?: string;
  powerBackupRequired: boolean;
  confidence: number;
}

const CATEGORIES = [
  'barber', 'hair', 'nails', 'makeup', 'aesthetics', 'braiding', 'locs', 'massage', 'brows_lashes',
];

/**
 * The concierge.
 *
 * Free text in, structured booking intent out, so "fade at my place tomorrow
 * at 4, load shedding" becomes a filtered search instead of four taps.
 *
 * Two design choices matter. The model is asked for JSON against a fixed
 * schema rather than prose, so a hallucinated category cannot reach the
 * database. And there is a deterministic fallback: if the API key is absent,
 * the call fails, or the response does not parse, we degrade to keyword
 * matching rather than showing an error. A search box that breaks when a
 * third party has an outage is not a search box.
 */
@Injectable()
export class AiService {
  private readonly logger = new Logger(AiService.name);
  private readonly enabled: boolean;
  private readonly model: string;
  private readonly apiKey?: string;

  constructor(private readonly config: ConfigService) {
    this.apiKey = this.config.get<string>('GOOGLE_API_KEY');
    this.enabled = Boolean(this.config.get<boolean>('AI_ENABLED') && this.apiKey);
    this.model = this.config.get<string>('AI_MODEL') ?? 'gemini-2.5-flash';
    if (!this.enabled) {
      this.logger.log('AI concierge disabled; using deterministic keyword parsing');
    }
  }

  async parseBookingIntent(text: string): Promise<ParsedBookingIntent> {
    if (!this.enabled) return this.fallbackParse(text);

    try {
      const { GoogleGenAI, Type } = await import('@google/genai');
      const ai = new GoogleGenAI({ apiKey: this.apiKey! });

      const response = await ai.models.generateContent({
        model: this.model,
        contents: `Today is ${new Date().toISOString().split('T')[0]}. User request: "${text}"`,
        config: {
          systemInstruction:
            'You route requests for an on-demand beauty and grooming marketplace in South Africa and Zimbabwe. ' +
            'Extract structured parameters. South African and Zimbabwean usage matters: "fade", "chiskop", ' +
            '"line-up" and "cut" mean barber; "gel", "tips", "acrylics" mean nails; "cornrows", "knotless", ' +
            '"box braids" mean braiding; "dreads", "retwist" mean locs. Any mention of load shedding, ' +
            'a power cut, ZESA, or "no lights" means backup power is required. Output JSON only.',
          responseMimeType: 'application/json',
          responseSchema: {
            type: Type.OBJECT,
            properties: {
              serviceCategory: { type: Type.STRING, enum: CATEGORIES },
              rawSearchQuery: { type: Type.STRING },
              bookingType: { type: Type.STRING, enum: ['instant', 'scheduled'] },
              targetDate: { type: Type.STRING },
              targetTime: { type: Type.STRING },
              locationContext: { type: Type.STRING },
              powerBackupRequired: { type: Type.BOOLEAN },
            },
            required: ['serviceCategory', 'rawSearchQuery', 'bookingType', 'powerBackupRequired'],
          },
        },
      });

      const parsed = JSON.parse(response.text ?? '{}');

      // Never trust the model's category blindly — it reaches a SQL enum.
      if (parsed.serviceCategory && !CATEGORIES.includes(parsed.serviceCategory)) {
        parsed.serviceCategory = null;
      }

      return { ...parsed, confidence: 0.9 } as ParsedBookingIntent;
    } catch (err) {
      this.logger.warn(`concierge parse failed, falling back: ${(err as Error).message}`);
      return this.fallbackParse(text);
    }
  }

  /** Keyword parsing that works offline and costs nothing. */
  private fallbackParse(text: string): ParsedBookingIntent {
    const lower = text.toLowerCase();

    // Order is significant: the most specific category is tested first.
    // "retwist my dreads" must resolve to locs, and a naive substring pass
    // would have matched "twist" under braiding and sent the customer to the
    // wrong professional entirely.
    const keywords: Array<[string, string[]]> = [
      ['locs', ['loc', 'locs', 'dread', 'dreads', 'dreadlock', 'retwist', 'starter locs']],
      ['braiding', ['braid', 'braids', 'cornrow', 'cornrows', 'knotless', 'box braids', 'twists', 'faux locs']],
      ['brows_lashes', ['brow', 'brows', 'lash', 'lashes', 'eyebrow', 'threading', 'microblading']],
      ['nails', ['nail', 'nails', 'gel', 'acrylic', 'acrylics', 'tips', 'manicure', 'pedicure', 'polish']],
      ['barber', ['fade', 'chiskop', 'line-up', 'lineup', 'barber', 'haircut', 'cut', 'shave', 'trim', 'taper']],
      ['makeup', ['makeup', 'make-up', 'beat', 'bridal', 'foundation']],
      ['massage', ['massage', 'deep tissue', 'swedish']],
      ['aesthetics', ['facial', 'wax', 'waxing', 'peel', 'aesthetic', 'microneedling']],
      ['hair', ['hair', 'blow-dry', 'blowdry', 'weave', 'relaxer', 'silk press', 'colour', 'color', 'wig']],
    ];

    // Whole-word matching, so "retwist" cannot satisfy "twist" and "locs"
    // cannot be triggered by "blocks".
    const matches = (word: string): boolean => {
      const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      return new RegExp(`(^|[^a-z])${escaped}([^a-z]|$)`).test(lower);
    };

    const serviceCategory =
      keywords.find(([, words]) => words.some(matches))?.[0] ?? null;

    const powerBackupRequired = [
      'load shedding', 'loadshedding', 'load-shedding', 'power cut', 'no power',
      'no lights', 'zesa', 'eskom', 'stage 4', 'stage 6', 'generator', 'inverter',
    ].some((w) => lower.includes(w));

    const scheduled = ['tomorrow', 'next week', 'monday', 'tuesday', 'wednesday', 'thursday',
      'friday', 'saturday', 'sunday', 'later', 'at ', 'pm', 'am'].some((w) => lower.includes(w));

    return {
      serviceCategory,
      rawSearchQuery: text.trim(),
      bookingType: scheduled ? 'scheduled' : 'instant',
      powerBackupRequired,
      confidence: serviceCategory ? 0.5 : 0.2,
    };
  }
}
