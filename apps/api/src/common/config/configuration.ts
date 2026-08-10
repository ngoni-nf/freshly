import { z } from 'zod';

/**
 * Fail fast on boot rather than at 2am when a payout job discovers the
 * gateway secret was never set. Every environment variable the process
 * depends on is declared, typed and defaulted here or nowhere.
 */
const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  API_BASE_URL: z.string().url().default('http://localhost:3000'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),

  DATABASE_URL: z.string().min(1),
  DATABASE_SSL: z.coerce.boolean().default(false),
  DATABASE_POOL_MAX: z.coerce.number().int().positive().default(20),

  REDIS_URL: z.string().min(1),

  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),
  OTP_DEV_BYPASS: z.coerce.boolean().default(false),

  PII_ENCRYPTION_KEY: z.string().min(1),

  PAYMENTS_ZA_PROVIDER: z.enum(['stitch', 'peach', 'mock']).default('mock'),
  PAYMENTS_ZW_PROVIDER: z.enum(['paynow', 'mock']).default('mock'),
  STITCH_CLIENT_ID: z.string().optional(),
  STITCH_CLIENT_SECRET: z.string().optional(),
  STITCH_WEBHOOK_SECRET: z.string().optional(),
  PEACH_ENTITY_ID: z.string().optional(),
  PEACH_ACCESS_TOKEN: z.string().optional(),
  PAYNOW_INTEGRATION_ID: z.string().optional(),
  PAYNOW_INTEGRATION_KEY: z.string().optional(),

  KYC_PROVIDER: z.enum(['smileid', 'mock']).default('mock'),
  SMILE_ID_PARTNER_ID: z.string().optional(),
  SMILE_ID_API_KEY: z.string().optional(),
  SMILE_ID_CALLBACK_URL: z.string().optional(),

  SOS_PROVIDER: z.enum(['aura', 'mock']).default('mock'),
  AURA_API_KEY: z.string().optional(),
  AURA_BASE_URL: z.string().default('https://api.aura.services'),

  COMMS_PROVIDER: z.enum(['gupshup', 'twilio', 'mock']).default('mock'),
  GUPSHUP_API_KEY: z.string().optional(),
  GUPSHUP_SOURCE_NUMBER: z.string().optional(),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),

  GOOGLE_API_KEY: z.string().optional(),
  AI_MODEL: z.string().default('gemini-2.5-flash'),
  AI_ENABLED: z.coerce.boolean().default(false),

  ESKOMSEPUSH_API_KEY: z.string().optional(),
  ZESA_STATUS_FEED_URL: z.string().optional(),

  S3_ENDPOINT: z.string().default('http://localhost:9000'),
  S3_BUCKET: z.string().default('freshly-media'),
  S3_ACCESS_KEY: z.string().optional(),
  S3_SECRET_KEY: z.string().optional(),
  S3_REGION: z.string().default('af-south-1'),
});

export type AppConfig = z.infer<typeof schema>;

export function loadConfiguration(): AppConfig {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    const detail = parsed.error.issues
      .map((i) => `  ${i.path.join('.')}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment configuration:\n${detail}`);
  }

  const cfg = parsed.data;

  // Production must never run on mock adapters or a bypassed OTP.
  if (cfg.NODE_ENV === 'production') {
    const violations: string[] = [];
    if (cfg.OTP_DEV_BYPASS) violations.push('OTP_DEV_BYPASS must be false');
    if (cfg.PAYMENTS_ZA_PROVIDER === 'mock') violations.push('PAYMENTS_ZA_PROVIDER must not be mock');
    if (cfg.KYC_PROVIDER === 'mock') violations.push('KYC_PROVIDER must not be mock');
    if (cfg.PII_ENCRYPTION_KEY.startsWith('REPLACE')) violations.push('PII_ENCRYPTION_KEY is a placeholder');
    if (violations.length) {
      throw new Error(`Refusing to boot in production:\n  ${violations.join('\n  ')}`);
    }
  }

  return cfg;
}
