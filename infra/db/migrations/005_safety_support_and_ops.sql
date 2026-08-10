-- ============================================================================
-- 005  Safety, messaging, reviews, disputes, promotions, ops plumbing
-- ============================================================================

-- ---------------------------------------------------------------------------
-- SOS. Retained beyond the usual purge window because these records are
-- evidence; the ephemeral GPS breadcrumbs are NOT stored here, only the
-- snapshot at trigger time.
-- ---------------------------------------------------------------------------
CREATE TABLE sos_events (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id          UUID REFERENCES bookings(id) ON DELETE SET NULL,
  triggered_by_user_id UUID NOT NULL REFERENCES users(id),
  actor               sos_actor_enum NOT NULL,
  status              sos_status_enum NOT NULL DEFAULT 'armed',
  trigger_location    GEOGRAPHY(Point, 4326) NOT NULL,
  counterparty_location GEOGRAPHY(Point, 4326),
  accuracy_m          NUMERIC(6,2),
  battery_pct         INT,
  vehicle_description TEXT,
  external_provider   VARCHAR(40),
  external_reference  VARCHAR(120),
  dispatched_at       TIMESTAMPTZ,
  acknowledged_at     TIMESTAMPTZ,
  resolved_at         TIMESTAMPTZ,
  resolution_notes    TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_sos_open ON sos_events(created_at DESC)
  WHERE status IN ('armed','dispatched','acknowledged');

CREATE TABLE emergency_contacts (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        VARCHAR(120) NOT NULL,
  phone_e164  VARCHAR(20) NOT NULL,
  relationship VARCHAR(40),
  notify_on_trip BOOLEAN NOT NULL DEFAULT false,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Masked messaging. Message bodies are encrypted at rest; the leak_flags
-- column records why the moderator redacted something.
-- ---------------------------------------------------------------------------
CREATE TABLE conversations (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id   UUID NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  client_proxy_number  VARCHAR(20),
  provider_proxy_number VARCHAR(20),
  closes_at    TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE messages (
  id              BIGSERIAL PRIMARY KEY,
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  sender_id       UUID NOT NULL REFERENCES users(id),
  body_enc        BYTEA NOT NULL,
  redacted        BOOLEAN NOT NULL DEFAULT false,
  leak_flags      TEXT[] NOT NULL DEFAULT '{}',   -- phone | email | offplatform_payment
  read_at         TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at);

CREATE TABLE call_sessions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  initiated_by    UUID NOT NULL REFERENCES users(id),
  duration_seconds INT,
  external_reference VARCHAR(120),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Double-sided reviews. Neither side is visible until both have submitted or
-- the reveal window lapses — this is what stops retaliatory rating.
-- ---------------------------------------------------------------------------
CREATE TABLE reviews (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id    UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  direction     review_direction_enum NOT NULL,
  author_id     UUID NOT NULL REFERENCES users(id),
  subject_user_id UUID NOT NULL REFERENCES users(id),
  rating        INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  tags          TEXT[] NOT NULL DEFAULT '{}',
  comment       TEXT,
  photo_keys    TEXT[] NOT NULL DEFAULT '{}',
  is_published  BOOLEAN NOT NULL DEFAULT false,
  published_at  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (booking_id, direction)
);
CREATE INDEX idx_reviews_subject ON reviews(subject_user_id) WHERE is_published;

CREATE TABLE disputes (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  booking_id    UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  raised_by     UUID NOT NULL REFERENCES users(id),
  reason_code   VARCHAR(40) NOT NULL,
  narrative     TEXT,
  evidence_keys TEXT[] NOT NULL DEFAULT '{}',
  status        dispute_status_enum NOT NULL DEFAULT 'open',
  refund_minor  money_minor NOT NULL DEFAULT 0,
  assigned_to   UUID REFERENCES users(id),
  resolved_at   TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_disputes_open ON disputes(created_at DESC)
  WHERE status NOT IN ('resolved_client','resolved_provider','resolved_split','withdrawn');

-- ---------------------------------------------------------------------------
-- Promotions
-- ---------------------------------------------------------------------------
CREATE TABLE promo_codes (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code            VARCHAR(30) NOT NULL UNIQUE,
  country_code    country_code_enum REFERENCES countries(code),
  discount_bps    INT CHECK (discount_bps BETWEEN 0 AND 10000),
  discount_minor  money_minor,
  currency        currency_code_enum,
  max_discount_minor money_minor,
  min_spend_minor money_minor NOT NULL DEFAULT 0,
  first_booking_only BOOLEAN NOT NULL DEFAULT false,
  max_redemptions INT,
  redemption_count INT NOT NULL DEFAULT 0,
  valid_from      TIMESTAMPTZ NOT NULL DEFAULT now(),
  valid_to        TIMESTAMPTZ,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT chk_promo_has_value CHECK (discount_bps IS NOT NULL OR discount_minor IS NOT NULL)
);

CREATE TABLE promo_redemptions (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  promo_id   UUID NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  amount_minor money_minor NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (promo_id, booking_id)
);

-- ---------------------------------------------------------------------------
-- Ops plumbing
-- ---------------------------------------------------------------------------

-- Transactional outbox: domain events are written in the same transaction as
-- the state change, then relayed. No lost notifications, no dual writes.
CREATE TABLE outbox_events (
  id             BIGSERIAL PRIMARY KEY,
  aggregate_type VARCHAR(40) NOT NULL,
  aggregate_id   UUID NOT NULL,
  event_type     VARCHAR(60) NOT NULL,
  payload        JSONB NOT NULL,
  available_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  attempts       INT NOT NULL DEFAULT 0,
  published_at   TIMESTAMPTZ,
  last_error     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_outbox_unpublished ON outbox_events(available_at)
  WHERE published_at IS NULL;

CREATE TABLE audit_log (
  id           BIGSERIAL PRIMARY KEY,
  actor_id     UUID REFERENCES users(id),
  actor_role   account_role_enum,
  action       VARCHAR(80) NOT NULL,
  entity_type  VARCHAR(60) NOT NULL,
  entity_id    UUID,
  before       JSONB,
  after        JSONB,
  ip_address   INET,
  user_agent   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id, created_at DESC);

CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel     VARCHAR(20) NOT NULL,   -- push | sms | whatsapp | email | inapp
  template    VARCHAR(60) NOT NULL,
  payload     JSONB NOT NULL DEFAULT '{}',
  sent_at     TIMESTAMPTZ,
  read_at     TIMESTAMPTZ,
  failure     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(user_id, created_at DESC);

-- Runtime-tunable platform settings, edited from the admin portal.
CREATE TABLE platform_settings (
  key          VARCHAR(80) PRIMARY KEY,
  value        JSONB NOT NULL,
  description  TEXT,
  updated_by   UUID REFERENCES users(id),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Support conversations from the in-app help desk.
CREATE TABLE support_tickets (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  booking_id    UUID REFERENCES bookings(id) ON DELETE SET NULL,
  subject       VARCHAR(160) NOT NULL,
  body          TEXT NOT NULL,
  ai_category   VARCHAR(40),
  ai_priority   VARCHAR(20),
  ai_summary    TEXT,
  status        VARCHAR(20) NOT NULL DEFAULT 'open',
  assigned_to   UUID REFERENCES users(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  closed_at     TIMESTAMPTZ
);
