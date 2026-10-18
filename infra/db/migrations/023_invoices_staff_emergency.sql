-- ---------------------------------------------------------------------------
-- 023: invoices, salon staff, and the number to dial in an emergency.
--
-- Emergency number. Both apps dialled 10111 — the South African police — from
-- the SOS screen whichever market the person was standing in. In Harare that
-- is a wrong number at the worst possible moment. It belongs on the country
-- row with everything else that differs by market.
--
-- Invoices. SARS and ZIMRA both expect a completed job to leave two documents
-- behind: the provider's invoice to the client for the work, and ours to the
-- provider for the commission and service fee we took out of it. Written
-- inside the completion transaction, from the booking's own frozen figures,
-- so an invoice can never say something the ledger did not do. Numbers are
-- sequential per country and year because a tax authority asks for exactly
-- that, and a gap in a sequence is a question we would rather not be asked.
-- `invoice_sequences` is the counter; it is bumped with an upsert inside the
-- same transaction as the invoice row, so two completions racing each other
-- serialise on the row and cannot both take the same number.
--
-- Only what a tax document needs is stored. A city and the last four digits
-- of a phone identify a party well enough for a reviewer; a full number or an
-- ID number on a row that will be rendered to a PDF and shared is a leak
-- waiting for a forwarded email.
--
-- Salon staff. A salon is a provider whose business_mode is 'salon'; its
-- staff are provider rows of mode 'salon_staff' pointing back at it, a shape
-- 002 already allowed for. They are invited by phone number so someone who
-- has never installed Freshly can be asked to join. A booking stays owned by
-- the salon (`provider_id`, and so the wallet the money lands in) and gains
-- `assigned_staff_id` for the person who actually does it. The `salon_staff`
-- seat table from 002 is left alone: it modelled commission splits and
-- management rights that are not built, and a second place to record who
-- works where would only be a place for the two to disagree.
-- ---------------------------------------------------------------------------

ALTER TABLE countries
  ADD COLUMN IF NOT EXISTS emergency_number VARCHAR(12) NOT NULL DEFAULT '112';

UPDATE countries SET emergency_number = '10111' WHERE code = 'ZA';
UPDATE countries SET emergency_number = '999'   WHERE code = 'ZW';

-- ---------------------------------------------------------------------------
-- Invoices
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invoice_kind_enum') THEN
    CREATE TYPE invoice_kind_enum AS ENUM ('provider_to_client', 'platform_to_provider');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS invoice_sequences (
  country_code country_code_enum NOT NULL REFERENCES countries(code),
  year         INT NOT NULL,
  last         INT NOT NULL DEFAULT 0,
  PRIMARY KEY (country_code, year)
);

-- 004 declared an invoices table that nothing ever wrote to: no code, no
-- rows, in any environment. It is reshaped here rather than replaced so the
-- hosted database's history stays one straight line. `tax_*` becomes `vat_*`
-- to match the booking columns it is copied from; `issuer_tax_id` and
-- `pdf_key` go because neither is stored (the PDF is rendered on request,
-- and a tax number is the kind of identifier these rows must not carry).
-- `lines` is the itemisation the document is rendered from, in display
-- order: [{ "label": "Skin fade", "amountMinor": 1000 }, ...].
ALTER TABLE invoices
  ALTER COLUMN kind TYPE invoice_kind_enum USING kind::invoice_kind_enum,
  ALTER COLUMN number TYPE TEXT,
  ADD COLUMN IF NOT EXISTS lines            JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS issuer_detail    VARCHAR(200),
  ADD COLUMN IF NOT EXISTS recipient_detail VARCHAR(200);

-- The default only existed to add a NOT NULL column; every row is written
-- with its lines, and a silent empty itemisation would be an invoice for
-- nothing.
ALTER TABLE invoices ALTER COLUMN lines DROP DEFAULT;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_name = 'invoices' AND column_name = 'tax_minor') THEN
    ALTER TABLE invoices RENAME COLUMN tax_minor TO vat_minor;
  END IF;
END $$;

ALTER TABLE invoices
  DROP COLUMN IF EXISTS tax_label,
  DROP COLUMN IF EXISTS issuer_tax_id,
  DROP COLUMN IF EXISTS pdf_key;

CREATE INDEX IF NOT EXISTS idx_invoices_booking ON invoices (booking_id);

-- ---------------------------------------------------------------------------
-- Salon staff
-- ---------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'staff_invite_enum') THEN
    CREATE TYPE staff_invite_enum AS ENUM ('pending', 'accepted', 'cancelled');
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS staff_invites (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  salon_provider_id    UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  phone_e164           VARCHAR(16) NOT NULL,
  status               staff_invite_enum NOT NULL DEFAULT 'pending',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  accepted_at          TIMESTAMPTZ,
  accepted_provider_id UUID REFERENCES providers(id) ON DELETE SET NULL
);

-- One open invitation per number per salon. A cancelled or accepted one may
-- be followed by another, which is why this is partial rather than UNIQUE.
CREATE UNIQUE INDEX IF NOT EXISTS uq_staff_invites_pending
  ON staff_invites (salon_provider_id, phone_e164) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_staff_invites_phone
  ON staff_invites (phone_e164) WHERE status = 'pending';

ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS assigned_staff_id UUID REFERENCES providers(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bookings_assigned_staff
  ON bookings (assigned_staff_id) WHERE assigned_staff_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 011's lockdown, extended to the new tables, as 015 and 020 did for theirs.
-- Not FORCED, for 011's reason: the API connects as the owner.
-- ---------------------------------------------------------------------------

ALTER TABLE invoices          ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_invites     ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  role_name TEXT;
  tbl       TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    -- Absent on a local Postgres or in CI; the migration must still apply.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      FOREACH tbl IN ARRAY ARRAY['invoices', 'invoice_sequences', 'staff_invites'] LOOP
        EXECUTE format('REVOKE ALL ON TABLE %I FROM %I', tbl, role_name);
      END LOOP;
    END IF;
  END LOOP;
END $$;
