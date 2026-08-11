-- ---------------------------------------------------------------------------
-- The area a client chose when they joined.
--
-- Discovery previously depended entirely on a live GPS fix. When one did not
-- arrive — permission declined, cold GPS, indoors, an emulator — the feed
-- resolved the device's actual coordinates against the geofence and told the
-- customer "Freshly is not live in this area yet" about a place they had never
-- chosen and could not see. That reads as "this app does not work here", which
-- for someone standing in Rosebank is simply false.
--
-- Asking once, at sign-up, gives every later screen a sane origin to fall back
-- to, and makes the location permission a genuine choice rather than a wall.
-- ---------------------------------------------------------------------------
ALTER TABLE users
  ADD COLUMN preferred_service_area_id UUID REFERENCES service_areas(id) ON DELETE SET NULL;

COMMENT ON COLUMN users.preferred_service_area_id IS
  'Where the client says they want service. A fallback origin for discovery, not a restriction: a live GPS fix inside any live area still wins.';

CREATE INDEX idx_users_preferred_area ON users (preferred_service_area_id)
  WHERE preferred_service_area_id IS NOT NULL;
