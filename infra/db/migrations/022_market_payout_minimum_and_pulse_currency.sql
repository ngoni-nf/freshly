-- ---------------------------------------------------------------------------
-- 022: the minimum cash-out belongs to the market, and the pulse to a currency.
--
-- `payout.min_amount_minor` was one global setting: 5000 minor units. That is
-- R50 in Johannesburg and US$50 in Harare, where a skin fade is US$10. Five
-- jobs before a barber can be paid is not a minimum, it is a reason to leave.
-- The number now lives on the country row, next to the commission and the
-- service fee that already do.
--
-- The pulse view summed `total_minor` across every booking regardless of
-- currency, so one Harare fade added 1150 to a rand total. Money is only
-- additive inside a currency; the view now reports per currency.
-- ---------------------------------------------------------------------------

ALTER TABLE countries
  ADD COLUMN IF NOT EXISTS min_payout_minor money_minor NOT NULL DEFAULT 5000;

UPDATE countries SET min_payout_minor = 5000 WHERE code = 'ZA';
UPDATE countries SET min_payout_minor = 2000 WHERE code = 'ZW';

DROP VIEW IF EXISTS vw_platform_pulse;
CREATE VIEW vw_platform_pulse AS
SELECT
  (SELECT COUNT(*) FROM bookings
     WHERE status IN ('authorized','accepted','en_route','arrived','in_progress')) AS active_jobs,
  (SELECT COALESCE(jsonb_object_agg(currency, locked), '{}'::jsonb)
     FROM (SELECT currency, SUM(authorized_minor - captured_minor) AS locked
             FROM payment_intents WHERE escrow_status = 'authorized'
            GROUP BY currency) e)                                                   AS escrow_locked_by_currency,
  (SELECT COALESCE(jsonb_object_agg(currency, gmv), '{}'::jsonb)
     FROM (SELECT currency, SUM(total_minor) AS gmv
             FROM bookings
            WHERE status = 'completed' AND completed_at >= date_trunc('day', now())
            GROUP BY currency) g)                                                   AS gmv_today_by_currency,
  (SELECT COUNT(*) FROM providers WHERE is_online AND kyc_status = 'verified')       AS providers_online,
  (SELECT COUNT(*) FROM kyc_submissions WHERE status IN ('pending','in_review'))     AS kyc_queue_depth,
  (SELECT COUNT(*) FROM sos_events
     WHERE status IN ('armed','dispatched','acknowledged'))                          AS open_emergencies,
  (SELECT COUNT(*) FROM disputes
     WHERE status NOT IN ('resolved_client','resolved_provider','resolved_split','withdrawn')) AS open_disputes;

-- Reviews are held back until both sides have written one, so neither can
-- retaliate. `review.reveal_window_hours` was seeded for the other half of
-- that rule and never read: a client whose provider never rates them would
-- wait forever. This publishes what has waited long enough; the API calls it
-- on a schedule.
CREATE OR REPLACE FUNCTION fn_publish_overdue_reviews(p_window_hours INT)
RETURNS INT AS $$
DECLARE
  n INT;
BEGIN
  WITH due AS (
    UPDATE reviews
       SET is_published = true, published_at = now()
     WHERE NOT is_published
       AND created_at < now() - make_interval(hours => p_window_hours)
    RETURNING 1
  )
  SELECT COUNT(*) INTO n FROM due;
  RETURN n;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;

-- A provider's base location must sit inside a live area of their own
-- country. Resolved here so the sign-up endpoint and any future import agree
-- on what "inside" means.
CREATE OR REPLACE FUNCTION fn_service_area_for_point(
  p_country country_code_enum,
  p_lat     DOUBLE PRECISION,
  p_lng     DOUBLE PRECISION
) RETURNS UUID AS $$
  SELECT id FROM service_areas
   WHERE country_code = p_country
     AND is_live
     AND ST_Covers(boundary, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography)
   ORDER BY ST_Distance(centroid, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography)
   LIMIT 1;
$$ LANGUAGE sql STABLE SET search_path = public, pg_temp;
