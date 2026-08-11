-- ---------------------------------------------------------------------------
-- 014: suburb-level places, so a client can type where they are.
--
-- service_areas stays what it is: the operating metro. It carries the
-- geofence, the surge multiplier and the country whose rules apply, and there
-- are a handful of them. That is the right granularity for the business and
-- entirely the wrong one for a person, who lives in Rosebank and has never
-- once thought of themselves as being in "Johannesburg North".
--
-- So places are a search surface layered over areas, not a replacement for
-- them. Every place resolves to exactly one area, which means autocomplete can
-- only ever suggest somewhere we actually operate — a suggestion we cannot
-- serve is worse than no suggestion, because the customer finds out after
-- choosing rather than before.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS places (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  service_area_id UUID NOT NULL REFERENCES service_areas(id) ON DELETE CASCADE,
  name            VARCHAR(80) NOT NULL,
  -- How people disambiguate two suburbs sharing a name, and South Africa has
  -- several.
  postal_code     VARCHAR(10),
  centroid        GEOGRAPHY(Point, 4326) NOT NULL,
  -- Ranks the obvious answer first: Sandton should beat Sandton Ext 4 for "san".
  popularity      INT NOT NULL DEFAULT 0,
  is_active       BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (service_area_id, name)
);

CREATE INDEX IF NOT EXISTS idx_places_service_area_id ON places(service_area_id);
CREATE INDEX IF NOT EXISTS idx_places_centroid ON places USING GIST(centroid);

-- Prefix matching on a lowered name, which is what autocomplete issues:
-- people type the start of a suburb, not the middle of one.
CREATE INDEX IF NOT EXISTS idx_places_name_prefix ON places(lower(name) text_pattern_ops);

-- ---------------------------------------------------------------------------
-- Remembering where someone said they were.
--
-- The area is what the system needs; the suburb is what the person chose. Both
-- are kept, because showing them "Rosebank" when they next open the app is the
-- difference between a preference and a setting they have to re-derive. It is
-- nullable and ON DELETE SET NULL: retiring a suburb must not take the
-- account's area with it.
-- ---------------------------------------------------------------------------
ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_place_id UUID REFERENCES places(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_users_preferred_place_id ON users(preferred_place_id);

-- ---------------------------------------------------------------------------
-- Shop discovery.
--
-- fn_search_providers already filtered on venue, but returned nothing a client
-- could choose between two salons with: no address, and no way to tell a
-- person who travels from a premises you visit. Added to the existing function
-- rather than a second query, so "at a shop" costs the same single spatial
-- call that "to me" does.
--
-- Everything else below is unchanged from 009 and must stay that way. The
-- credential re-check in particular is what makes a gated service vanish from
-- search the moment a licence lapses; the suspension and salon_staff filters
-- keep people out of results who must not be bookable directly.
--
-- Recreated rather than replaced because the return type gains columns, which
-- CREATE OR REPLACE cannot do.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_search_providers(
  DOUBLE PRECISION, DOUBLE PRECISION, NUMERIC, service_category_enum, service_venue_enum,
  money_minor, NUMERIC, BOOLEAN, BOOLEAN, INTEGER, INTEGER
);

CREATE FUNCTION fn_search_providers(
  p_lat             DOUBLE PRECISION,
  p_lng             DOUBLE PRECISION,
  p_radius_km       NUMERIC,
  p_category        service_category_enum DEFAULT NULL,
  p_venue           service_venue_enum    DEFAULT NULL,
  p_max_price_minor money_minor           DEFAULT NULL,
  p_min_rating      NUMERIC               DEFAULT 0,
  p_require_power   BOOLEAN               DEFAULT false,
  p_instant_only    BOOLEAN               DEFAULT false,
  p_limit           INTEGER               DEFAULT 20,
  p_offset          INTEGER               DEFAULT 0
)
RETURNS TABLE (
  provider_id       UUID,
  display_name      CHARACTER VARYING,
  distance_km       NUMERIC,
  rating            NUMERIC,
  rating_count      INTEGER,
  completed_jobs    INTEGER,
  has_power_backup  BOOLEAN,
  is_online         BOOLEAN,
  from_price_minor  money_minor,
  currency          currency_code_enum,
  categories        service_category_enum[],
  venue_mode        service_venue_enum,
  business_mode     business_mode_enum,
  shop_address      TEXT
)
LANGUAGE plpgsql
STABLE
AS $function$
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
    p.categories,
    p.venue_mode,
    p.business_mode,
    -- A mobile provider's address is nobody's business until they are booked;
    -- a shop's address is the entire point of listing it.
    CASE WHEN p.venue_mode IN ('in_shop', 'both') THEN p.shop_address END
  FROM providers p
  JOIN services s ON s.provider_id = p.id AND s.is_active
  WHERE p.kyc_status = 'verified'
    AND NOT p.is_suspended
    AND p.business_mode <> 'salon_staff'
    AND COALESCE(p.last_location, p.base_location) IS NOT NULL
    -- Respect BOTH the search radius and how far the provider will travel.
    -- A shop does not travel to the client, so its own radius must not hide it
    -- from someone willing to drive there.
    AND ST_DWithin(
          COALESCE(p.last_location, p.base_location),
          origin,
          CASE WHEN p_venue = 'in_shop' THEN p_radius_km
               ELSE LEAST(p_radius_km, p.travel_radius_km) END * 1000)
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
$function$;
