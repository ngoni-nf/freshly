-- ============================================================================
-- 006  Functions, triggers and the booking state machine
-- ============================================================================

-- --------------------------------------------------------------------------
-- updated_at maintenance
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['countries','users','providers','services','bookings','payment_intents']
  LOOP
    EXECUTE format(
      'CREATE TRIGGER trg_%1$s_touch BEFORE UPDATE ON %1$s
       FOR EACH ROW EXECUTE FUNCTION fn_touch_updated_at()', t);
  END LOOP;
END $$;

-- --------------------------------------------------------------------------
-- Human-readable booking reference: FRS-XXXXXX (Crockford-ish, no 0/O/1/I)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generate_booking_reference() RETURNS TRIGGER AS $$
DECLARE
  alphabet CONSTANT TEXT := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  candidate TEXT;
  i INT;
BEGIN
  IF NEW.reference IS NOT NULL AND NEW.reference <> '' THEN
    RETURN NEW;
  END IF;
  LOOP
    candidate := 'FRS-';
    FOR i IN 1..6 LOOP
      candidate := candidate || substr(alphabet, 1 + floor(random() * length(alphabet))::INT, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM bookings WHERE reference = candidate);
  END LOOP;
  NEW.reference := candidate;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bookings_reference
  BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_generate_booking_reference();

-- --------------------------------------------------------------------------
-- Booking state machine, enforced in the database.
--
-- The application also guards these transitions, but putting the truth table
-- here means no background job, admin script or future service can corrupt a
-- booking's lifecycle. Illegal transitions raise, they do not silently pass.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_booking_status_guard() RETURNS TRIGGER AS $$
DECLARE
  allowed booking_status_enum[];
BEGIN
  IF NEW.status = OLD.status THEN
    RETURN NEW;
  END IF;

  allowed := CASE OLD.status
    WHEN 'draft'        THEN ARRAY['pending_auth','cancelled','expired']
    WHEN 'pending_auth' THEN ARRAY['authorized','cancelled','expired']
    WHEN 'authorized'   THEN ARRAY['accepted','cancelled','expired']
    WHEN 'accepted'     THEN ARRAY['en_route','in_progress','cancelled']
    WHEN 'en_route'     THEN ARRAY['arrived','cancelled']
    WHEN 'arrived'      THEN ARRAY['in_progress','cancelled']
    WHEN 'in_progress'  THEN ARRAY['completed','disputed']
    WHEN 'completed'    THEN ARRAY['disputed']
    WHEN 'disputed'     THEN ARRAY['completed','cancelled']
    ELSE ARRAY[]::booking_status_enum[]
  END::booking_status_enum[];

  IF NOT (NEW.status = ANY(allowed)) THEN
    RAISE EXCEPTION
      'illegal booking transition % -> % for booking %',
      OLD.status, NEW.status, OLD.id
      USING ERRCODE = 'check_violation';
  END IF;

  -- Stamp the lifecycle column that corresponds to the new state.
  NEW.authorized_at := COALESCE(NEW.authorized_at, CASE WHEN NEW.status = 'authorized'  THEN now() END);
  NEW.accepted_at   := COALESCE(NEW.accepted_at,   CASE WHEN NEW.status = 'accepted'    THEN now() END);
  NEW.en_route_at   := COALESCE(NEW.en_route_at,   CASE WHEN NEW.status = 'en_route'    THEN now() END);
  NEW.arrived_at    := COALESCE(NEW.arrived_at,    CASE WHEN NEW.status = 'arrived'     THEN now() END);
  NEW.started_at    := COALESCE(NEW.started_at,    CASE WHEN NEW.status = 'in_progress' THEN now() END);
  NEW.completed_at  := COALESCE(NEW.completed_at,  CASE WHEN NEW.status = 'completed'   THEN now() END);
  NEW.cancelled_at  := COALESCE(NEW.cancelled_at,  CASE WHEN NEW.status = 'cancelled'   THEN now() END);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bookings_status_guard
  BEFORE UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_booking_status_guard();

-- Every transition is journalled automatically.
CREATE OR REPLACE FUNCTION fn_booking_status_journal() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO booking_events (booking_id, from_status, to_status, actor_kind, metadata)
    VALUES (
      NEW.id,
      CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END,
      NEW.status,
      'system',
      jsonb_build_object('provider_id', NEW.provider_id, 'total_minor', NEW.total_minor)
    );
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bookings_journal
  AFTER INSERT OR UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION fn_booking_status_journal();

-- --------------------------------------------------------------------------
-- Ledger integrity: a transaction group must net to zero, per currency.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_assert_ledger_balanced(p_group UUID) RETURNS VOID AS $$
DECLARE
  imbalance RECORD;
BEGIN
  FOR imbalance IN
    SELECT currency, SUM(signed_minor) AS net
    FROM ledger_entries WHERE group_key = p_group
    GROUP BY currency HAVING SUM(signed_minor) <> 0
  LOOP
    RAISE EXCEPTION 'unbalanced ledger group % : % net %',
      p_group, imbalance.currency, imbalance.net
      USING ERRCODE = 'check_violation';
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- --------------------------------------------------------------------------
-- Rating rollups. Cheaper than recomputing an average on every profile view.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_apply_review_rollup() RETURNS TRIGGER AS $$
BEGIN
  IF NEW.is_published AND (TG_OP = 'INSERT' OR NOT OLD.is_published) THEN
    IF NEW.direction = 'client_to_provider' THEN
      UPDATE providers p
      SET rating = ((p.rating * p.rating_count) + NEW.rating) / (p.rating_count + 1),
          rating_count = p.rating_count + 1
      WHERE p.user_id = NEW.subject_user_id;
    END IF;
    UPDATE users u
    SET rating = ((u.rating * u.rating_count) + NEW.rating) / (u.rating_count + 1),
        rating_count = u.rating_count + 1
    WHERE u.id = NEW.subject_user_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reviews_rollup
  AFTER INSERT OR UPDATE OF is_published ON reviews
  FOR EACH ROW EXECUTE FUNCTION fn_apply_review_rollup();

-- --------------------------------------------------------------------------
-- Discovery. One spatial query does distance, filtering, availability and
-- load-shedding resilience so the API never fans out into N+1 lookups.
--
-- p_require_power reflects the client's "power backup only" filter chip; when
-- the grid stage is 4 or higher the API passes true regardless, because a
-- clipper with no inverter is a wasted trip.
-- --------------------------------------------------------------------------
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
  GROUP BY p.id
  ORDER BY
    -- Online providers first for instant intent, then proximity, then quality.
    (p.is_online AND p.accepts_instant) DESC,
    ST_Distance(COALESCE(p.last_location, p.base_location), origin) ASC,
    p.rating DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- --------------------------------------------------------------------------
-- Availability check used before confirming a scheduled booking.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_provider_is_available(
  p_provider_id UUID,
  p_start       TIMESTAMPTZ,
  p_end         TIMESTAMPTZ
) RETURNS BOOLEAN AS $$
DECLARE
  has_rule BOOLEAN;
  is_blocked BOOLEAN;
  has_clash BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM availability_rules r
    WHERE r.provider_id = p_provider_id
      AND r.weekday = EXTRACT(DOW FROM p_start)::INT
      AND r.starts_at <= p_start::TIME
      AND r.ends_at   >= p_end::TIME
  ) INTO has_rule;

  SELECT EXISTS (
    SELECT 1 FROM availability_blocks b
    WHERE b.provider_id = p_provider_id
      AND b.period && tstzrange(p_start, p_end, '[)')
  ) INTO is_blocked;

  SELECT EXISTS (
    SELECT 1 FROM bookings bk
    WHERE bk.provider_id = p_provider_id
      AND bk.status IN ('authorized','accepted','en_route','arrived','in_progress')
      AND tstzrange(bk.scheduled_start, bk.scheduled_end, '[)') && tstzrange(p_start, p_end, '[)')
  ) INTO has_clash;

  RETURN has_rule AND NOT is_blocked AND NOT has_clash;
END;
$$ LANGUAGE plpgsql STABLE;

-- --------------------------------------------------------------------------
-- Live operational snapshot for the admin Live Pulse screen.
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_platform_pulse AS
SELECT
  (SELECT COUNT(*) FROM bookings
     WHERE status IN ('authorized','accepted','en_route','arrived','in_progress')) AS active_jobs,
  (SELECT COALESCE(SUM(authorized_minor - captured_minor), 0) FROM payment_intents
     WHERE escrow_status = 'authorized')                                            AS escrow_locked_minor,
  (SELECT COALESCE(SUM(total_minor), 0) FROM bookings
     WHERE status = 'completed' AND completed_at >= date_trunc('day', now()))        AS gmv_today_minor,
  (SELECT COUNT(*) FROM providers WHERE is_online AND kyc_status = 'verified')       AS providers_online,
  (SELECT COUNT(*) FROM kyc_submissions WHERE status IN ('pending','in_review'))     AS kyc_queue_depth,
  (SELECT COUNT(*) FROM sos_events
     WHERE status IN ('armed','dispatched','acknowledged'))                          AS open_emergencies,
  (SELECT COUNT(*) FROM disputes
     WHERE status NOT IN ('resolved_client','resolved_provider','resolved_split','withdrawn')) AS open_disputes;
