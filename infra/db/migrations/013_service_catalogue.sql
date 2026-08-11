-- ---------------------------------------------------------------------------
-- A canonical service catalogue.
--
-- Until now a provider typed their own service names. One barber has "Skin
-- fade", the next "Skin Fade", the third "Fade". Three consequences, all bad:
--
--   1. A client cannot browse a service. Searching for knotless braids across
--      providers is impossible when the string differs every time.
--   2. There is no menu to choose from — only whatever one provider happened
--      to type, so a new provider builds their offering from a blank box.
--   3. services.requires_credential had nothing to derive from. Migration 009
--      says it must be set by the catalogue and never from provider input;
--      this is the catalogue it was waiting for.
--
-- Templates are reference data, not user content. A provider picks one and
-- sets their own price and duration; the name, the category and whether the
-- procedure is invasive are ours.
-- ---------------------------------------------------------------------------

CREATE TABLE service_templates (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category      service_category_enum NOT NULL,
  slug          VARCHAR(80) NOT NULL UNIQUE,
  name          VARCHAR(120) NOT NULL,
  description   TEXT,
  -- A starting point for the provider, who may adjust it. Realistic values
  -- matter: braids at 45 minutes would wreck a diary.
  typical_duration_minutes INT NOT NULL CHECK (typical_duration_minutes > 0),
  -- Clippers, lasers, LED, autoclaves. Drives the load-shedding filter.
  requires_power BOOLEAN NOT NULL DEFAULT false,
  -- Breaks skin or fires a regulated device. The credential gate reads this
  -- rather than guessing from the name.
  is_invasive   BOOLEAN NOT NULL DEFAULT false,
  sort_order    INT NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_templates_category ON service_templates (category) WHERE is_active;

-- A provider's own service may point at the template it came from. Nullable,
-- because the services seeded before this migration existed have no template
-- and there is no honest way to invent one for them.
ALTER TABLE services
  ADD COLUMN template_id UUID REFERENCES service_templates(id) ON DELETE SET NULL;

CREATE INDEX idx_services_template ON services (template_id);

-- ---------------------------------------------------------------------------
-- The guard now prefers the template's answer.
--
-- Name matching stays as the safety net for anything listed off-catalogue, but
-- a service built from a template inherits `is_invasive` directly, which is
-- both deterministic and the thing migration 009 asked for.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_service_credential_guard() RETURNS TRIGGER AS $$
DECLARE
  v_country  country_code_enum;
  v_gate     RECORD;
  v_template service_templates%ROWTYPE;
BEGIN
  SELECT country_code INTO v_country FROM providers WHERE id = NEW.provider_id;

  IF NEW.template_id IS NOT NULL THEN
    SELECT * INTO v_template FROM service_templates WHERE id = NEW.template_id;
    IF v_template.is_invasive THEN
      NEW.requires_credential := true;
    END IF;
  END IF;

  SELECT * INTO v_gate
    FROM fn_service_gate(v_country, NEW.category, NEW.name, NEW.requires_credential);

  IF NOT v_gate.gated THEN
    RETURN NEW;
  END IF;

  NEW.requires_credential := true;

  IF v_gate.in_shop_only AND NEW.venue_mode <> 'in_shop' THEN
    RAISE EXCEPTION
      '% requires premises and cannot be offered as a mobile service',
      NEW.name USING ERRCODE = 'check_violation';
  END IF;

  IF NOT fn_provider_has_credential(NEW.provider_id, NEW.category) THEN
    RAISE EXCEPTION
      'provider % has no verified % credential for %',
      NEW.provider_id, COALESCE(v_gate.credential_kind, 'practitioner'), NEW.category
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_service_credential_guard ON services;
CREATE TRIGGER trg_service_credential_guard
  BEFORE INSERT OR UPDATE OF category, venue_mode, requires_credential, name, provider_id, template_id
  ON services
  FOR EACH ROW EXECUTE FUNCTION fn_service_credential_guard();
