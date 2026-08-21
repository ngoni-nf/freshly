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
  /** Optional pooler endpoint for the running API; migrations always use DATABASE_URL. */
  DATABASE_POOL_URL: z.string().optional(),

  REDIS_URL: z.string().min(1),

  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  JWT_REFRESH_TTL: z.string().default('30d'),
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().positive().default(5),
  OTP_DEV_BYPASS: z.coerce.boolean().default(false),

  PII_ENCRYPTION_KEY: z.string().min(1),

  PAYMENTS_ZA_PROVIDER: z.enum(['stitch', 'peach', 'paystack', 'mock']).default('mock'),
  PAYMENTS_ZW_PROVIDER: z.enum(['paynow', 'mock']).default('mock'),
  STITCH_CLIENT_ID: z.string().optional(),
  STITCH_CLIENT_SECRET: z.string().optional(),
  STITCH_WEBHOOK_SECRET: z.string().optional(),
  PEACH_ENTITY_ID: z.string().optional(),
  PEACH_ACCESS_TOKEN: z.string().optional(),
  PAYSTACK_SECRET_KEY: z.string().optional(),
  PAYSTACK_PUBLIC_KEY: z.string().optional(),
  PAYSTACK_BASE_URL: z.string().url().default('https://api.paystack.co'),
  PAYNOW_INTEGRATION_ID: z.string().optional(),
  PAYNOW_INTEGRATION_KEY: z.string().optional(),
  STITCH_BASE_URL: z.string().url().default('https://secure.stitch.money'),

  // Money out is a separate vendor decision from money in: the acquirer that
  // authorises a card is rarely the rail that pushes a bank EFT.
  // Paystack is deliberately absent here: payouts go through a separate
  // PayoutProvider abstraction, and Paystack Transfers need business
  // verification we do not have yet. Adding it before the provider exists would
  // silently fall back to mock — a payout that reports success and moves
  // nothing. Payments can be Paystack while payouts stay mock.
  PAYOUTS_ZA_PROVIDER: z.enum(['stitch', 'mock']).default('mock'),
  PAYOUTS_ZW_PROVIDER: z.enum(['paynow', 'mock']).default('mock'),

  KYC_PROVIDER: z.enum(['smileid', 'sumsub', 'mock']).default('mock'),
  SMILE_ID_PARTNER_ID: z.string().optional(),
  SMILE_ID_API_KEY: z.string().optional(),
  SMILE_ID_CALLBACK_URL: z.string().optional(),
  SMILE_ID_BASE_URL: z.string().url().default('https://api.smileidentity.com'),
  SUMSUB_APP_TOKEN: z.string().optional(),
  SUMSUB_SECRET_KEY: z.string().optional(),
  SUMSUB_WEBHOOK_SECRET: z.string().optional(),
  SUMSUB_LEVEL_NAME: z.string().default('basic-kyc-level'),
  SUMSUB_BASE_URL: z.string().url().default('https://api.sumsub.com'),

  SOS_PROVIDER: z.enum(['aura', 'mock']).default('mock'),
  AURA_API_KEY: z.string().optional(),
  AURA_BASE_URL: z.string().default('https://api.aura.services'),

  COMMS_PROVIDER: z.enum(['gupshup', 'twilio', 'mock']).default('mock'),
  GUPSHUP_API_KEY: z.string().optional(),
  GUPSHUP_SOURCE_NUMBER: z.string().optional(),
  TWILIO_ACCOUNT_SID: z.string().optional(),
  TWILIO_AUTH_TOKEN: z.string().optional(),
  // Was absent, which the schema silently strips — the adapter then sent every
  // SMS with an undefined From and Twilio rejected all of them. Declared so it
  // survives validation, and enforced below when the provider is twilio.
  TWILIO_FROM_NUMBER: z.string().optional(),

  FIREBASE_ENABLED: z.coerce.boolean().default(false),
  FIREBASE_PROJECT_ID: z.string().optional(),
  GOOGLE_APPLICATION_CREDENTIALS: z.string().optional(),
  FIREBASE_SERVICE_ACCOUNT_JSON: z.string().optional(),
  PUSH_ENABLED: z.coerce.boolean().default(false),

  GOOGLE_API_KEY: z.string().optional(),
  AI_MODEL: z.string().default('gemini-2.5-flash'),
  AI_ENABLED: z.coerce.boolean().default(false),

  ESKOMSEPUSH_API_KEY: z.string().optional(),
  ZESA_STATUS_FEED_URL: z.string().optional(),

  // Supabase Storage. The service role key is the most dangerous secret in
  // this file — it bypasses RLS entirely — so it lives only in the API
  // process and is never handed to an app.
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().optional(),

  S3_ENDPOINT: z.string().default('http://localhost:9000'),
  S3_BUCKET: z.string().default('freshly-media'),
  S3_ACCESS_KEY: z.string().optional(),
  S3_SECRET_KEY: z.string().optional(),
  S3_REGION: z.string().default('af-south-1'),
});

export type AppConfig = z.infer<typeof schema>;

/**
 * @param source Variables parsed from the env file by ConfigModule.
 *
 * ConfigModule calls `validate` with the file contents *before* it assigns
 * anything to process.env, so reading process.env alone here saw nothing and
 * every variable came back "Required" even when correctly set. The real
 * environment is layered on top, so an explicitly exported variable still
 * beats the file — which is what CI and one-off overrides depend on.
 */
export function loadConfiguration(source: Record<string, unknown> = {}): AppConfig {
  const parsed = schema.safeParse({ ...source, ...process.env });
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
    // A mock payout adapter in production reports success and moves no money,
    // which is the one failure mode a provider would notice before we do.
    if (cfg.PAYOUTS_ZA_PROVIDER === 'mock') violations.push('PAYOUTS_ZA_PROVIDER must not be mock');
    if (cfg.KYC_PROVIDER === 'mock') violations.push('KYC_PROVIDER must not be mock');
    if (cfg.PII_ENCRYPTION_KEY.startsWith('REPLACE')) violations.push('PII_ENCRYPTION_KEY is a placeholder');
    if (cfg.FIREBASE_ENABLED && !cfg.FIREBASE_PROJECT_ID) {
      violations.push('FIREBASE_ENABLED is set but FIREBASE_PROJECT_ID is missing');
    }
    if (cfg.PUSH_ENABLED && !cfg.FIREBASE_PROJECT_ID) {
      violations.push('PUSH_ENABLED is set but FIREBASE_PROJECT_ID is missing');
    }
    // Without push, a dispatch offer only reaches a provider who happens to be
    // looking at the app. In production that is not a degraded experience, it
    // is a marketplace that silently fails to fill most of its bookings.
    if (!cfg.PUSH_ENABLED) violations.push('PUSH_ENABLED must be true');
    // A hosted database over the public internet without TLS would put every
    // booking, phone number and payment reference on the wire in clear.
    if (!cfg.DATABASE_SSL && !/localhost|127\.0\.0\.1/.test(cfg.DATABASE_URL)) {
      violations.push('DATABASE_SSL must be true for a non-local database');
    }
    if (violations.length) {
      throw new Error(`Refusing to boot in production:\n  ${violations.join('\n  ')}`);
    }
  }

  // Selecting a real comms provider without its credentials is worse than the
  // mock: the mock says out loud that it sends nothing, whereas a half-wired
  // Twilio drops every OTP with an authentication error and looks like a bug in
  // sign-in. This holds in every environment, not just production, because the
  // whole point of switching to twilio is that codes actually go out.
  if (cfg.COMMS_PROVIDER === 'twilio') {
    const missing = (
      ['TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_FROM_NUMBER'] as const
    ).filter((k) => !cfg[k]);
    if (missing.length) {
      throw new Error(`COMMS_PROVIDER=twilio requires: ${missing.join(', ')}`);
    }
  }
  if (cfg.COMMS_PROVIDER === 'gupshup') {
    const missing = (['GUPSHUP_API_KEY', 'GUPSHUP_SOURCE_NUMBER'] as const).filter((k) => !cfg[k]);
    if (missing.length) {
      throw new Error(`COMMS_PROVIDER=gupshup requires: ${missing.join(', ')}`);
    }
  }
  // Same reasoning as comms: a KYC provider selected without its keys fails
  // every verification with an auth error that reads like a product bug, and
  // an unverified provider reaching a customer's door is the failure that
  // matters. The webhook secret is required too — without it every callback is
  // rejected and applicants sit in `pending` forever.
  if (cfg.KYC_PROVIDER === 'sumsub') {
    const missing = (
      ['SUMSUB_APP_TOKEN', 'SUMSUB_SECRET_KEY', 'SUMSUB_WEBHOOK_SECRET'] as const
    ).filter((k) => !cfg[k]);
    if (missing.length) {
      throw new Error(`KYC_PROVIDER=sumsub requires: ${missing.join(', ')}`);
    }
  }

  return cfg;
}
