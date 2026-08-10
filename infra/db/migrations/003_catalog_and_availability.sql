-- ============================================================================
-- 003  Service catalogue, portfolio, availability and load-shedding
-- ============================================================================

CREATE TABLE services (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id       UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  name              VARCHAR(150) NOT NULL,
  description       TEXT,
  category          service_category_enum NOT NULL,
  venue_mode        service_venue_enum NOT NULL DEFAULT 'both',
  price_minor       money_minor NOT NULL CHECK (price_minor > 0),
  currency          currency_code_enum NOT NULL,
  duration_minutes  INT NOT NULL CHECK (duration_minutes BETWEEN 5 AND 600),
  buffer_minutes    INT NOT NULL DEFAULT 0 CHECK (buffer_minutes >= 0),
  requires_power    BOOLEAN NOT NULL DEFAULT false,  -- drives load-shedding filtering
  is_active         BOOLEAN NOT NULL DEFAULT true,
  sort_order        INT NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_services_provider ON services(provider_id) WHERE is_active;
CREATE INDEX idx_services_category ON services(category) WHERE is_active;
CREATE INDEX idx_services_name_trgm ON services USING gin (name gin_trgm_ops);

-- Optional add-ons a provider can attach mid-service (Screen B.11).
CREATE TABLE service_addons (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id      UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  name             VARCHAR(120) NOT NULL,
  price_minor      money_minor NOT NULL CHECK (price_minor > 0),
  currency         currency_code_enum NOT NULL,
  duration_minutes INT NOT NULL DEFAULT 0,
  is_active        BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE portfolio_items (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id   UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  media_key     TEXT NOT NULL,
  thumb_key     TEXT,
  width         INT,
  height        INT,
  bytes         INT,
  category      service_category_enum,
  ai_tags       TEXT[] NOT NULL DEFAULT '{}',
  moderation_status VARCHAR(20) NOT NULL DEFAULT 'pending',
  sort_order    INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Recurring weekly availability.
CREATE TABLE availability_rules (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id  UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  weekday      INT NOT NULL CHECK (weekday BETWEEN 0 AND 6),  -- 0 = Sunday
  starts_at    TIME NOT NULL,
  ends_at      TIME NOT NULL,
  CHECK (ends_at > starts_at),
  UNIQUE (provider_id, weekday, starts_at)
);

-- Concrete blocks of unavailable time: holidays, personal, and — the reason
-- this table exists at all — load-shedding blackout windows.
CREATE TABLE availability_blocks (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id  UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  reason       VARCHAR(40) NOT NULL DEFAULT 'manual',  -- manual | load_shedding | leave | booked
  period       TSTZRANGE NOT NULL,
  source_ref   VARCHAR(80),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  EXCLUDE USING gist (provider_id WITH =, period WITH &&)
);
CREATE INDEX idx_availability_blocks_period ON availability_blocks USING gist (period);

-- ---------------------------------------------------------------------------
-- Grid status. Eskom load-shedding stages for ZA, ZESA outage windows for ZW.
-- Cached here so the app degrades gracefully when the upstream feed is down.
-- ---------------------------------------------------------------------------
CREATE TABLE grid_status (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code   country_code_enum NOT NULL REFERENCES countries(code),
  service_area_id UUID REFERENCES service_areas(id) ON DELETE CASCADE,
  stage          INT NOT NULL DEFAULT 0 CHECK (stage BETWEEN 0 AND 8),
  source         grid_stage_source_enum NOT NULL,
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to   TIMESTAMPTZ,
  raw_payload    JSONB,
  fetched_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_grid_status_lookup ON grid_status(country_code, effective_from DESC);

-- Per-suburb outage schedule, used to pre-warn clients and auto-suggest blocks.
CREATE TABLE grid_outage_windows (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_area_id UUID NOT NULL REFERENCES service_areas(id) ON DELETE CASCADE,
  zone_label     VARCHAR(40) NOT NULL,
  stage          INT NOT NULL,
  period         TSTZRANGE NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_outage_windows_period ON grid_outage_windows USING gist (period);
