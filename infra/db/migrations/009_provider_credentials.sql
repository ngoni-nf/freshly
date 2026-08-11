-- ---------------------------------------------------------------------------
-- Credential gating for invasive services.
--
-- kyc_status proves who a provider is. It does not prove they are competent to
-- put a needle into someone's dermis. Scalp micropigmentation, microblading,
-- ombre powder brows, lip blush, microneedling, dermaplaning with a scalpel,
-- chemical peels and laser hair removal all break the skin or fire a regulated
-- device, and in both markets they attract scope-of-practice, device and
-- skin-penetration rules that ordinary grooming does not.
--
-- The gate is per SERVICE, not per category, and that is deliberate. No
-- category in the taxonomy is wholly invasive: 'brows' covers threading and
-- microblading, 'aesthetics' covers a cleansing facial and microneedling,
-- 'scalp' covers a dandruff massage and SMP, 'body_grooming' covers waxing and
-- laser. Gating whole categories would block the ordinary, high-volume,
-- perfectly lawful work that pays these providers' rent.
--
-- Three layers, because relying on a provider to tick a box is not a control:
--   1. services.requires_credential  — the explicit marker.
--   2. service_category_rules        — a per-market default for a category.
--   3. regulated_procedures          — a name-matching safety net, so listing
--      "Microblading" under 'brows' without the flag is still caught.
-- Any one of them gates the service. The trigger is the enforcement point, so
-- a seed, an admin script or a future endpoint cannot route around it.
-- ---------------------------------------------------------------------------

CREATE TYPE credential_status_enum AS ENUM ('pending', 'verified', 'rejected', 'expired');

-- Which categories need a licence, in which market, and who issues it.
-- Market rules are data: turning a category on or off is an UPDATE.
CREATE TABLE service_category_rules (
  country_code        country_code_enum NOT NULL REFERENCES countries(code) ON DELETE CASCADE,
  category            service_category_enum NOT NULL,
  -- Default for the whole category. False for every mixed category; see the
  -- header. Set true only where every procedure in the category is invasive.
  requires_credential BOOLEAN NOT NULL DEFAULT false,
  -- What to ask the provider for. Populated even when the category default is
  -- false, because individual services inside it are still gated.
  credential_kind     VARCHAR(60),
  regulator           VARCHAR(120),
  -- Invasive work needs premises, sharps disposal and an autoclave. It is not
  -- something to perform on a customer's kitchen chair.
  in_shop_only        BOOLEAN NOT NULL DEFAULT false,
  rationale           TEXT,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (country_code, category),
  CONSTRAINT chk_credential_kind_present
    CHECK (NOT requires_credential OR credential_kind IS NOT NULL)
);

-- The safety net. Matched case-insensitively against the service name.
CREATE TABLE regulated_procedures (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  country_code    country_code_enum NOT NULL REFERENCES countries(code) ON DELETE CASCADE,
  -- ILIKE pattern, e.g. '%microblading%'.
  name_pattern    VARCHAR(120) NOT NULL,
  category        service_category_enum,
  credential_kind VARCHAR(60) NOT NULL,
  regulator       VARCHAR(120),
  in_shop_only    BOOLEAN NOT NULL DEFAULT true,
  rationale       TEXT,
  UNIQUE (country_code, name_pattern)
);

CREATE TABLE provider_credentials (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider_id      UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  category         service_category_enum NOT NULL,
  credential_kind  VARCHAR(60) NOT NULL,
  issuer           VARCHAR(120),
  -- A practitioner registration number identifies a person and is personal
  -- information under POPIA, so it is encrypted like every other identifier.
  reference_enc    BYTEA,
  reference_last4  VARCHAR(4),
  document_key     TEXT,
  status           credential_status_enum NOT NULL DEFAULT 'pending',
  -- Licences lapse. A gate that only checks at listing time would let an
  -- expired practitioner keep working indefinitely.
  expires_on       DATE,
  reviewed_by      UUID REFERENCES users(id),
  reviewed_at      TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (provider_id, category, credential_kind)
);

CREATE INDEX idx_provider_credentials_active
  ON provider_credentials (provider_id, category)
  WHERE status = 'verified';

ALTER TABLE services
  ADD COLUMN requires_credential BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN services.requires_credential IS
  'Set by the catalogue, never from provider input. A future service-creation endpoint must derive this from a service template.';

-- ---------------------------------------------------------------------------
-- Is this provider currently allowed to perform this category?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_provider_has_credential(
  p_provider UUID,
  p_category service_category_enum
) RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1
      FROM provider_credentials c
     WHERE c.provider_id = p_provider
       AND c.category    = p_category
       AND c.status      = 'verified'
       AND (c.expires_on IS NULL OR c.expires_on >= CURRENT_DATE)
  );
$$ LANGUAGE sql STABLE;

-- ---------------------------------------------------------------------------
-- Does this service need a credential, and must it be performed in shop?
-- Returns the strictest answer across all three layers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_service_gate(
  p_country  country_code_enum,
  p_category service_category_enum,
  p_name     TEXT,
  p_flagged  BOOLEAN
) RETURNS TABLE (gated BOOLEAN, in_shop_only BOOLEAN, credential_kind VARCHAR) AS $$
DECLARE
  v_rule      service_category_rules%ROWTYPE;
  v_procedure regulated_procedures%ROWTYPE;
BEGIN
  SELECT * INTO v_rule
    FROM service_category_rules r
   WHERE r.country_code = p_country AND r.category = p_category;

  SELECT * INTO v_procedure
    FROM regulated_procedures rp
   WHERE rp.country_code = p_country
     AND (rp.category IS NULL OR rp.category = p_category)
     AND p_name ILIKE rp.name_pattern
   LIMIT 1;

  gated := COALESCE(p_flagged, false)
        OR COALESCE(v_rule.requires_credential, false)
        OR v_procedure.id IS NOT NULL;

  -- Only meaningful when gated; an ungated service is not forced in-shop.
  in_shop_only := gated AND (
                    COALESCE(v_rule.in_shop_only, false)
                    OR COALESCE(v_procedure.in_shop_only, false)
                  );

  credential_kind := COALESCE(v_procedure.credential_kind, v_rule.credential_kind);
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql STABLE;

-- ---------------------------------------------------------------------------
-- Enforcement. In the database for the same reason the booking state machine
-- is: this must hold against a seed, a migration, an admin script and any
-- future service that has not been written yet.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_service_credential_guard() RETURNS TRIGGER AS $$
DECLARE
  v_country country_code_enum;
  v_gate    RECORD;
BEGIN
  SELECT country_code INTO v_country FROM providers WHERE id = NEW.provider_id;

  SELECT * INTO v_gate
    FROM fn_service_gate(v_country, NEW.category, NEW.name, NEW.requires_credential);

  IF NOT v_gate.gated THEN
    RETURN NEW;
  END IF;

  -- Keep the row honest, so discovery and the apps can read one column
  -- instead of re-deriving the rules.
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

CREATE TRIGGER trg_service_credential_guard
  BEFORE INSERT OR UPDATE OF category, venue_mode, requires_credential, name, provider_id
  ON services
  FOR EACH ROW EXECUTE FUNCTION fn_service_credential_guard();

-- ---------------------------------------------------------------------------
-- Discovery re-checks at read time, because the trigger only fires on write
-- and a licence can lapse the day after a service was listed.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_search_providers(
  p_lat            DOUBLE PRECISION,
  p_lng            DOUBLE PRECISION,
  p_radius_km      NUMERIC,
  p_category       service_category_enum DEFAULT NULL,
  p_venue          service_venue_enum    DEFAULT NULL,
  p_max_price_minor money_minor          DEFAULT NULL,
  p_min_rating     NUMERIC               DEFAULT 0,
  p_require_power  BOOLEAN               DEFAULT false,
  p_instant_only   BOOLEAN               DEFAULT false,
  p_limit          INT                   DEFAULT 20,
  p_offset         INT                   DEFAULT 0
)
RETURNS TABLE (
  provider_id     UUID,
  display_name    VARCHAR,
  distance_km     NUMERIC,
  rating          NUMERIC,
  rating_count    INT,
  completed_jobs  INT,
  has_power_backup BOOLEAN,
  is_online       BOOLEAN,
  from_price_minor money_minor,
  currency        currency_code_enum,
  categories      service_category_enum[]
) AS $$
DECLARE
  origin GEOGRAPHY := ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::GEOGRAPHY;
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.display_name,
    ROUND((ST_Distance(COALESCE(p.last_location, p.base_location), origin) / 1000)::NUMERIC, 2),
    p.rating,
    p.rating_count,
    p.completed_jobs,
    p.has_power_backup,
    p.is_online,
    MIN(s.price_minor)::money_minor,
    MIN(s.currency),
    p.categories
  FROM providers p
  JOIN services s ON s.provider_id = p.id AND s.is_active
  WHERE p.kyc_status = 'verified'
    AND NOT p.is_suspended
    AND p.business_mode <> 'salon_staff'
    AND COALESCE(p.last_location, p.base_location) IS NOT NULL
    -- Respect BOTH the search radius and how far the provider will travel.
    AND ST_DWithin(COALESCE(p.last_location, p.base_location), origin, LEAST(p_radius_km, p.travel_radius_km) * 1000)
    AND (p_category IS NULL OR s.category = p_category)
    AND (p_venue    IS NULL OR p.venue_mode = p_venue OR p.venue_mode = 'both')
    AND (p_max_price_minor IS NULL OR s.price_minor <= p_max_price_minor)
    AND p.rating >= p_min_rating
    AND (NOT p_require_power OR p.has_power_backup)
    AND (NOT p_instant_only  OR (p.is_online AND p.accepts_instant))
    -- A gated service disappears from search the moment its licence lapses.
    AND (NOT s.requires_credential OR fn_provider_has_credential(p.id, s.category))
  GROUP BY p.id
  ORDER BY
    -- Online providers first for instant intent, then proximity, then quality.
    (p.is_online AND p.accepts_instant) DESC,
    ST_Distance(COALESCE(p.last_location, p.base_location), origin) ASC,
    p.rating DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;
