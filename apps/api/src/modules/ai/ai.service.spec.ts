import { ConfigService } from '@nestjs/config';
import { AiService } from './ai.service';

/**
 * The deterministic parser is not a stopgap — it is what runs whenever the
 * model is unavailable, unaffordable or slow, which on a bad day is most of
 * the time. It gets the same test scrutiny as anything else on the hot path.
 */
describe('AiService fallback parsing', () => {
  const config = { get: () => undefined } as unknown as ConfigService;
  const ai = new AiService(config);

  const parse = (text: string) => ai.parseBookingIntent(text);

  it.each([
    ['need a fade right now', 'barber'],
    ['chiskop please', 'barber'],
    ['knotless braids on Saturday', 'braiding'],
    ['cornrows for my daughter', 'braiding'],
    ['gel nails and a pedicure', 'nails'],
    ['bridal makeup trial', 'makeup'],
    ['lash extensions', 'brows_lashes'],
    ['deep tissue massage', 'massage'],
  ])('classifies %j as %s', async (text, expected) => {
    const result = await parse(text);
    expect(result.serviceCategory).toBe(expected);
  });

  it('sends locs work to locs, not braiding', async () => {
    // "retwist" contains "twist"; a substring match sent this to braiding.
    for (const text of ['retwist my dreads', 'starter locs', 'loc maintenance', 'dreadlock retwist']) {
      expect((await parse(text)).serviceCategory).toBe('locs');
    }
  });

  it('does not match a category inside an unrelated word', async () => {
    // "blocks" contains "loc"; "cutlery" contains "cut".
    expect((await parse('two blocks from the mall')).serviceCategory).toBeNull();
  });

  it('detects load shedding in South African phrasing', async () => {
    for (const text of ['fade during stage 6 load shedding', 'eskom is off', 'no power at my place']) {
      expect((await parse(text)).powerBackupRequired).toBe(true);
    }
  });

  it('detects power loss in Zimbabwean phrasing', async () => {
    for (const text of ['retwist, ZESA is off in Borrowdale', 'braids but no lights today']) {
      expect((await parse(text)).powerBackupRequired).toBe(true);
    }
  });

  it('separates instant from scheduled intent', async () => {
    expect((await parse('need a fade right now')).bookingType).toBe('instant');
    expect((await parse('gel nails on Saturday morning')).bookingType).toBe('scheduled');
    expect((await parse('braids tomorrow at 4pm')).bookingType).toBe('scheduled');
  });

  it('returns low confidence when nothing is recognised', async () => {
    const result = await parse('something completely unrelated');
    expect(result.serviceCategory).toBeNull();
    expect(result.confidence).toBeLessThan(0.5);
  });
});
