-- ============================================================================
-- 002  Countries, accounts, providers, KYC
-- ============================================================================

-- ---------------------------------------------------------------------------
-- countries: every market-specific rule lives here, not in application code.
-- Adding Zimbabwe is a row insert plus a payment adapter, not a refactor.
-- ---------------------------------------------------------------------------
CREATE TABLE countries (
  code                     country_code_enum PRIMARY KEY,
  name                     VARCHAR(80)  NOT NULL,
  default_currency         currency_code_enum NOT NULL,
  supported_currencies     currency_code_enum[] NOT NULL,
  dial_prefix              VARCHAR(5)   NOT NULL,
  phone_national_length    INT          NOT NULL,
  timezone                 VARCHAR(64)  NOT NULL,
  -- Monetisation defaults (overridable per provider contract)
  commission_bps           INT          NOT NULL CHECK (commission_bps BETWEEN 0 AND 5000),
  service_fee_minor        money_minor  NOT NULL CHECK (service_fee_minor >= 0),
  travel_fee_per_km_minor  money_minor  NOT NULL CHECK (travel_fee_per_km_minor >= 0),
  travel_fee_free_km       NUMERIC(5,2) NOT NULL DEFAULT 0,
  -- Tax
  vat_bps                  INT          NOT NULL DEFAULT 0 CHECK (vat_bps BETWEEN 0 AND 5000),
  vat_label                VARCHAR(20)  NOT NULL DEFAULT 'VAT',
  tax_authority            VARCHAR(40),
  -- Integrations selected per market
  payment_provider         VARCHAR(40)  NOT NULL,
  kyc_provider             VARCHAR(40)  NOT NULL,
  sos_provider             VARCHAR(40),
  grid_status_provider     VARCHAR(40),
  -- Ops
  cancellation_window_minutes INT       NOT NULL DEFAULT 120,
  cancellation_fee_bps     INT          NOT NULL DEFAULT 5000,
  no_show_grace_minutes    INT          NOT NULL DEFAULT 10,
  dispatch_offer_seconds   INT          NOT NULL DEFAULT 60,
  max_search_radius_km     NUMERIC(5,2) NOT NULL DEFAULT 25,
  is_live                  BOOLEAN      NOT NULL DEFAULT false,
  launched_at              TIMESTAMPTZ,
  created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Service areas gate where the app actually functions (geofenced metro launch).
CREATE TABLE service_areas (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code  country_code_enum NOT NULL REFERENCES countries(code),
  name          VARCHAR(80) NOT NULL,
  slug          VARCHAR(80) NOT NULL UNIQUE,
  boundary      GEOGRAPHY(Polygon, 4326) NOT NULL,
  centroid      GEOGRAPHY(Point, 4326)   NOT NULL,
  is_live       BOOLEAN NOT NULL DEFAULT false,
  surge_bps     INT NOT NULL DEFAULT 0 CHECK (surge_bps BETWEEN 0 AND 10000),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- users: one identity, many roles. A salon owner is also a client.
-- PII columns marked (enc) are AES-256-GCM ciphertext written by the app layer;
-- the database never sees plaintext ID numbers or bank details.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code       country_code_enum NOT NULL REFERENCES countries(code),
  phone_e164         VARCHAR(20)  NOT NULL UNIQUE,
  phone_verified_at  TIMESTAMPTZ,
  email              CITEXT,
  email_verified_at  TIMESTAMPTZ,
  full_name          VARCHAR(120) NOT NULL,
  avatar_url         TEXT,
  roles              account_role_enum[] NOT NULL DEFAULT ARRAY['client']::account_role_enum[],
  status             account_status_enum NOT NULL DEFAULT 'active',
  locale             VARCHAR(10)  NOT NULL DEFAULT 'en-ZA',
  rating             NUMERIC(3,2) NOT NULL DEFAULT 5.00 CHECK (rating BETWEEN 0 AND 5),
  rating_count       INT          NOT NULL DEFAULT 0,
  -- Consent ledger (POPIA s11 / Zimbabwe Data Protection Act s14)
  consent_terms_at      TIMESTAMPTZ,
  consent_privacy_at    TIMESTAMPTZ,
  consent_marketing_at  TIMESTAMPTZ,
  consent_version       VARCHAR(20),
  -- Right to erasure: soft-delete then scrub via scheduled job
  deletion_requested_at TIMESTAMPTZ,
  anonymised_at         TIMESTAMPTZ,
  last_seen_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE saved_addresses (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label        VARCHAR(40) NOT NULL,
  formatted    TEXT NOT NULL,
  unit_notes   TEXT,
  access_notes TEXT,
  location     GEOGRAPHY(Point, 4326) NOT NULL,
  is_default   BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform      VARCHAR(10) NOT NULL CHECK (platform IN ('ios','android','web')),
  push_token    TEXT,
  app_version   VARCHAR(20),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, push_token)
);

-- OTP challenges. Codes are stored as a salted hash, never plaintext.
CREATE TABLE auth_challenges (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone_e164    VARCHAR(20) NOT NULL,
  code_hash     TEXT NOT NULL,
  attempts      INT NOT NULL DEFAULT 0,
  max_attempts  INT NOT NULL DEFAULT 5,
  consumed_at   TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ NOT NULL,
  ip_address    INET,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_auth_challenges_phone ON auth_challenges(phone_e164, created_at DESC);

CREATE TABLE refresh_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,
  device_id   UUID REFERENCES devices(id) ON DELETE SET NULL,
  revoked_at  TIMESTAMPTZ,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- providers
-- ---------------------------------------------------------------------------
CREATE TABLE providers (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  country_code          country_code_enum NOT NULL REFERENCES countries(code),
  service_area_id       UUID REFERENCES service_areas(id),
  business_mode         business_mode_enum NOT NULL DEFAULT 'solo',
  salon_parent_id       UUID REFERENCES providers(id) ON DELETE SET NULL,
  display_name          VARCHAR(120) NOT NULL,
  bio                   TEXT,
  slug                  VARCHAR(140) UNIQUE,
  categories            service_category_enum[] NOT NULL DEFAULT '{}',
  venue_mode            service_venue_enum NOT NULL DEFAULT 'mobile',
  -- Load-shedding resilience
  power_backup          power_backup_enum[] NOT NULL DEFAULT '{}',
  has_power_backup      BOOLEAN GENERATED ALWAYS AS (cardinality(power_backup) > 0) STORED,
  -- Geography
  base_location         GEOGRAPHY(Point, 4326),
  shop_address          TEXT,
  travel_radius_km      NUMERIC(5,2) NOT NULL DEFAULT 10 CHECK (travel_radius_km > 0),
  -- Live dispatch state
  is_online             BOOLEAN NOT NULL DEFAULT false,
  last_location         GEOGRAPHY(Point, 4326),
  last_location_at      TIMESTAMPTZ,
  accepts_instant       BOOLEAN NOT NULL DEFAULT true,
  accepts_scheduled     BOOLEAN NOT NULL DEFAULT true,
  -- Compliance & commercial terms
  kyc_status            kyc_status_enum NOT NULL DEFAULT 'unstarted',
  kyc_verified_at       TIMESTAMPTZ,
  commission_bps_override INT CHECK (commission_bps_override BETWEEN 0 AND 5000),
  payout_currency       currency_code_enum NOT NULL,
  -- Reputation
  rating                NUMERIC(3,2) NOT NULL DEFAULT 5.00 CHECK (rating BETWEEN 0 AND 5),
  rating_count          INT NOT NULL DEFAULT 0,
  completed_jobs        INT NOT NULL DEFAULT 0,
  cancellation_rate_bps INT NOT NULL DEFAULT 0,
  acceptance_rate_bps   INT NOT NULL DEFAULT 10000,
  is_suspended          BOOLEAN NOT NULL DEFAULT false,
  suspended_reason      TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_salon_staff_has_parent
    CHECK (business_mode <> 'salon_staff' OR salon_parent_id IS NOT NULL)
);

-- Salon seats: a staff member is a provider row bound to a parent salon.
CREATE TABLE salon_staff (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  salon_id       UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  provider_id    UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  job_title      VARCHAR(80),
  commission_split_bps INT NOT NULL DEFAULT 0 CHECK (commission_split_bps BETWEEN 0 AND 10000),
  can_manage     BOOLEAN NOT NULL DEFAULT false,
  invited_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at    TIMESTAMPTZ,
  removed_at     TIMESTAMPTZ,
  UNIQUE (salon_id, provider_id)
);

-- KYC / FICA submissions. Document images live in object storage; only the
-- key and the encrypted identity number are persisted here.
CREATE TABLE kyc_submissions (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id          UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  document_type        VARCHAR(30) NOT NULL,
  id_number_enc        BYTEA,
  id_number_last4      VARCHAR(4),
  document_front_key   TEXT,
  document_back_key    TEXT,
  selfie_key           TEXT,
  liveness_score       NUMERIC(5,4),
  face_match_score     NUMERIC(5,4),
  external_provider    VARCHAR(40),
  external_reference   VARCHAR(120),
  external_payload     JSONB,
  status               kyc_status_enum NOT NULL DEFAULT 'pending',
  reviewed_by          UUID REFERENCES users(id),
  reviewed_at          TIMESTAMPTZ,
  rejection_reason     TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Bank / mobile-money settlement destinations.
CREATE TABLE payout_accounts (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id        UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  country_code       country_code_enum NOT NULL REFERENCES countries(code),
  currency           currency_code_enum NOT NULL,
  method             VARCHAR(30) NOT NULL,           -- bank_transfer | ecocash | onemoney
  institution_code   VARCHAR(20),                    -- bank branch / MNO code
  institution_name   VARCHAR(80),
  account_name       VARCHAR(120) NOT NULL,
  account_number_enc BYTEA NOT NULL,
  account_last4      VARCHAR(4) NOT NULL,
  is_verified        BOOLEAN NOT NULL DEFAULT false,
  is_default         BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE subscriptions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id     UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  tier            subscription_tier_enum NOT NULL DEFAULT 'free',
  status          subscription_status_enum NOT NULL DEFAULT 'trialing',
  price_minor     money_minor NOT NULL DEFAULT 0,
  currency        currency_code_enum NOT NULL,
  seats           INT NOT NULL DEFAULT 1 CHECK (seats > 0),
  current_period_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  current_period_end   TIMESTAMPTZ NOT NULL,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
