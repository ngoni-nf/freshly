-- ============================================================================
-- 004  Bookings, escrow, double-entry ledger, payouts
-- ============================================================================

CREATE TABLE bookings (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reference             VARCHAR(12) NOT NULL UNIQUE,     -- human-quotable, e.g. GLW-8492
  country_code          country_code_enum NOT NULL REFERENCES countries(code),
  service_area_id       UUID REFERENCES service_areas(id),
  client_id             UUID NOT NULL REFERENCES users(id),
  provider_id           UUID REFERENCES providers(id),   -- NULL until dispatch assigns
  salon_id              UUID REFERENCES providers(id),
  booking_type          booking_type_enum NOT NULL DEFAULT 'instant',
  venue_mode            service_venue_enum NOT NULL DEFAULT 'mobile',
  status                booking_status_enum NOT NULL DEFAULT 'draft',

  -- Scheduling
  scheduled_start       TIMESTAMPTZ,
  scheduled_end         TIMESTAMPTZ,
  duration_minutes      INT NOT NULL,

  -- Geography
  destination           GEOGRAPHY(Point, 4326) NOT NULL,
  destination_address   TEXT NOT NULL,
  destination_notes     TEXT,
  travel_distance_km    NUMERIC(6,2) NOT NULL DEFAULT 0,

  -- Money. Every figure is captured at checkout so a later price change
  -- never rewrites history. currency is denormalised for the same reason.
  currency              currency_code_enum NOT NULL,
  subtotal_minor        money_minor NOT NULL DEFAULT 0,
  addons_minor          money_minor NOT NULL DEFAULT 0,
  travel_fee_minor      money_minor NOT NULL DEFAULT 0,
  service_fee_minor     money_minor NOT NULL DEFAULT 0,
  discount_minor        money_minor NOT NULL DEFAULT 0,
  surge_bps             INT NOT NULL DEFAULT 0,
  total_minor           money_minor NOT NULL DEFAULT 0,
  commission_bps        INT NOT NULL,
  commission_minor      money_minor NOT NULL DEFAULT 0,
  vat_on_fees_minor     money_minor NOT NULL DEFAULT 0,
  provider_payout_minor money_minor NOT NULL DEFAULT 0,
  tip_minor             money_minor NOT NULL DEFAULT 0,

  -- Completion proof
  completion_pin_hash   TEXT,
  pin_verified_at       TIMESTAMPTZ,

  -- Load-shedding context at time of booking
  grid_stage_at_booking INT,
  power_backup_required BOOLEAN NOT NULL DEFAULT false,

  -- Lifecycle timestamps
  authorized_at         TIMESTAMPTZ,
  accepted_at           TIMESTAMPTZ,
  en_route_at           TIMESTAMPTZ,
  arrived_at            TIMESTAMPTZ,
  started_at            TIMESTAMPTZ,
  completed_at          TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  cancelled_by          cancelled_by_enum,
  cancellation_reason   TEXT,
  cancellation_fee_minor money_minor NOT NULL DEFAULT 0,
  expires_at            TIMESTAMPTZ,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT chk_scheduled_has_slot
    CHECK (booking_type <> 'scheduled' OR scheduled_start IS NOT NULL),
  CONSTRAINT chk_totals_non_negative
    CHECK (total_minor >= 0 AND provider_payout_minor >= 0 AND commission_minor >= 0)
);

CREATE INDEX idx_bookings_client        ON bookings(client_id, created_at DESC);
CREATE INDEX idx_bookings_provider      ON bookings(provider_id, created_at DESC);
CREATE INDEX idx_bookings_status_active ON bookings(status)
  WHERE status IN ('authorized','accepted','en_route','arrived','in_progress');
CREATE INDEX idx_bookings_destination   ON bookings USING gist (destination);
CREATE INDEX idx_bookings_scheduled     ON bookings(scheduled_start)
  WHERE booking_type = 'scheduled' AND status NOT IN ('completed','cancelled','expired');

CREATE TABLE booking_items (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id     UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  service_id     UUID REFERENCES services(id),
  addon_id       UUID REFERENCES service_addons(id),
  name_snapshot  VARCHAR(150) NOT NULL,
  price_minor    money_minor NOT NULL,
  duration_minutes INT NOT NULL DEFAULT 0,
  quantity       INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
  is_addon       BOOLEAN NOT NULL DEFAULT false,
  added_mid_service BOOLEAN NOT NULL DEFAULT false,
  client_approved_at TIMESTAMPTZ,
  CONSTRAINT chk_item_target CHECK (service_id IS NOT NULL OR addon_id IS NOT NULL)
);

-- Append-only audit of every state transition. Nothing mutates this table.
CREATE TABLE booking_events (
  id          BIGSERIAL PRIMARY KEY,
  booking_id  UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  from_status booking_status_enum,
  to_status   booking_status_enum NOT NULL,
  actor_id    UUID REFERENCES users(id),
  actor_kind  VARCHAR(20) NOT NULL DEFAULT 'system',
  metadata    JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_booking_events_booking ON booking_events(booking_id, created_at);

-- ---------------------------------------------------------------------------
-- Dispatch: each broadcast to a candidate provider is a row, so acceptance
-- rate, response latency and radius tuning are all measurable after the fact.
-- ---------------------------------------------------------------------------
CREATE TABLE dispatch_offers (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id     UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  provider_id    UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  wave           INT NOT NULL DEFAULT 1,
  distance_km    NUMERIC(6,2),
  eta_minutes    INT,
  payout_minor   money_minor NOT NULL,
  offered_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  responded_at   TIMESTAMPTZ,
  outcome        VARCHAR(20),  -- accepted | declined | expired | superseded
  decline_reason TEXT,
  UNIQUE (booking_id, provider_id, wave)
);
CREATE INDEX idx_dispatch_offers_open ON dispatch_offers(provider_id, expires_at)
  WHERE outcome IS NULL;

-- ---------------------------------------------------------------------------
-- Payments & escrow
-- ---------------------------------------------------------------------------
CREATE TABLE payment_intents (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id           UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  provider_name        VARCHAR(40) NOT NULL,        -- stitch | peach | paynow | mock
  method               payment_method_enum NOT NULL,
  gateway_reference    VARCHAR(120) UNIQUE,
  escrow_status        escrow_status_enum NOT NULL DEFAULT 'unauthorized',
  currency             currency_code_enum NOT NULL,
  authorized_minor     money_minor NOT NULL DEFAULT 0,
  captured_minor       money_minor NOT NULL DEFAULT 0,
  refunded_minor       money_minor NOT NULL DEFAULT 0,
  authorization_expires_at TIMESTAMPTZ,
  idempotency_key      VARCHAR(255) NOT NULL UNIQUE,
  failure_code         VARCHAR(60),
  failure_message      TEXT,
  gateway_payload      JSONB NOT NULL DEFAULT '{}',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_capture_within_auth CHECK (captured_minor <= authorized_minor),
  CONSTRAINT chk_refund_within_capture CHECK (refunded_minor <= captured_minor)
);
CREATE INDEX idx_payment_intents_booking ON payment_intents(booking_id);

CREATE TABLE gateway_webhooks (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_name     VARCHAR(40) NOT NULL,
  event_id          VARCHAR(160) NOT NULL,
  event_type        VARCHAR(80),
  signature_valid   BOOLEAN NOT NULL DEFAULT false,
  payload           JSONB NOT NULL,
  processed_at      TIMESTAMPTZ,
  processing_error  TEXT,
  received_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_name, event_id)
);

-- ---------------------------------------------------------------------------
-- Double-entry ledger. Every cent that moves creates balanced entries.
-- Reconciliation is then a single query: SUM(signed_minor) per booking = 0.
-- ---------------------------------------------------------------------------
CREATE TABLE ledger_entries (
  id             BIGSERIAL PRIMARY KEY,
  booking_id     UUID REFERENCES bookings(id) ON DELETE RESTRICT,
  payout_id      UUID,
  account        ledger_account_enum NOT NULL,
  direction      ledger_direction_enum NOT NULL,
  amount_minor   money_minor NOT NULL CHECK (amount_minor > 0),
  signed_minor   money_minor GENERATED ALWAYS AS
                   (CASE WHEN direction = 'debit' THEN amount_minor ELSE -amount_minor END) STORED,
  currency       currency_code_enum NOT NULL,
  counterparty_provider_id UUID REFERENCES providers(id),
  counterparty_user_id     UUID REFERENCES users(id),
  description    TEXT NOT NULL,
  group_key      UUID NOT NULL,     -- one key per balanced transaction set
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_booking ON ledger_entries(booking_id);
CREATE INDEX idx_ledger_group   ON ledger_entries(group_key);
CREATE INDEX idx_ledger_account ON ledger_entries(account, created_at DESC);

CREATE TABLE provider_wallets (
  provider_id      UUID PRIMARY KEY REFERENCES providers(id) ON DELETE CASCADE,
  currency         currency_code_enum NOT NULL,
  available_minor  money_minor NOT NULL DEFAULT 0 CHECK (available_minor >= 0),
  pending_minor    money_minor NOT NULL DEFAULT 0 CHECK (pending_minor >= 0),
  lifetime_earned_minor money_minor NOT NULL DEFAULT 0,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE payouts (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id      UUID NOT NULL REFERENCES providers(id) ON DELETE RESTRICT,
  payout_account_id UUID NOT NULL REFERENCES payout_accounts(id),
  amount_minor     money_minor NOT NULL CHECK (amount_minor > 0),
  fee_minor        money_minor NOT NULL DEFAULT 0,
  currency         currency_code_enum NOT NULL,
  status           payout_status_enum NOT NULL DEFAULT 'requested',
  external_reference VARCHAR(120),
  failure_reason   TEXT,
  idempotency_key  VARCHAR(255) NOT NULL UNIQUE,
  requested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  settled_at       TIMESTAMPTZ
);
CREATE INDEX idx_payouts_provider ON payouts(provider_id, requested_at DESC);

-- Split invoicing: provider→client and platform→provider, per SARS / ZIMRA.
CREATE TABLE invoices (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id     UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  kind           VARCHAR(30) NOT NULL,   -- provider_to_client | platform_to_provider
  number         VARCHAR(40) NOT NULL UNIQUE,
  currency       currency_code_enum NOT NULL,
  subtotal_minor money_minor NOT NULL,
  tax_minor      money_minor NOT NULL DEFAULT 0,
  total_minor    money_minor NOT NULL,
  tax_label      VARCHAR(20),
  issuer_name    VARCHAR(160) NOT NULL,
  issuer_tax_id  VARCHAR(40),
  recipient_name VARCHAR(160) NOT NULL,
  pdf_key        TEXT,
  issued_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (booking_id, kind)
);

-- Generic idempotency guard for any mutating endpoint.
CREATE TABLE idempotency_keys (
  key            VARCHAR(255) PRIMARY KEY,
  user_id        UUID REFERENCES users(id) ON DELETE CASCADE,
  endpoint       VARCHAR(120) NOT NULL,
  request_hash   TEXT NOT NULL,
  response_body  JSONB,
  status_code    INT,
  locked_at      TIMESTAMPTZ,
  completed_at   TIMESTAMPTZ,
  expires_at     TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
