import { loadConfiguration } from './configuration';

/**
 * The bare minimum a config needs to parse at all, so each test can vary one
 * thing without every unrelated "Required" firing.
 */
const base = {
  DATABASE_URL: 'postgres://localhost/freshly',
  REDIS_URL: 'redis://localhost:6379',
  JWT_SECRET: 'x'.repeat(32),
  PII_ENCRYPTION_KEY: 'y'.repeat(32),
};

describe('loadConfiguration boolean handling', () => {
  const load = (extra: Record<string, unknown>) => {
    // loadConfiguration merges process.env over its argument, so a stray
    // OTP_DEV_BYPASS in the real environment would poison the test. Scrub it.
    const saved = process.env.OTP_DEV_BYPASS;
    delete process.env.OTP_DEV_BYPASS;
    try {
      return loadConfiguration({ ...base, ...extra });
    } finally {
      if (saved !== undefined) process.env.OTP_DEV_BYPASS = saved;
    }
  };

  it('reads the string "false" as false — the bug that kept the OTP bypass on', () => {
    expect(load({ OTP_DEV_BYPASS: 'false' }).OTP_DEV_BYPASS).toBe(false);
  });

  it('reads "true"/"1"/"on" as true and "0"/"no"/"off" as false', () => {
    expect(load({ OTP_DEV_BYPASS: 'true' }).OTP_DEV_BYPASS).toBe(true);
    expect(load({ OTP_DEV_BYPASS: '1' }).OTP_DEV_BYPASS).toBe(true);
    expect(load({ OTP_DEV_BYPASS: 'on' }).OTP_DEV_BYPASS).toBe(true);
    expect(load({ OTP_DEV_BYPASS: '0' }).OTP_DEV_BYPASS).toBe(false);
    expect(load({ OTP_DEV_BYPASS: 'no' }).OTP_DEV_BYPASS).toBe(false);
    expect(load({ OTP_DEV_BYPASS: 'off' }).OTP_DEV_BYPASS).toBe(false);
  });

  it('falls back to the default when unset or empty', () => {
    expect(load({}).OTP_DEV_BYPASS).toBe(false);
    expect(load({ OTP_DEV_BYPASS: '' }).OTP_DEV_BYPASS).toBe(false);
  });
});
