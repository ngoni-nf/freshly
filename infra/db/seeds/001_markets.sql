-- ============================================================================
-- Seed: markets. South Africa launches first; Zimbabwe is pre-configured but
-- is_live = false until supply is onboarded.
-- ============================================================================

INSERT INTO countries (
  code, name, default_currency, supported_currencies, dial_prefix, phone_national_length,
  timezone, commission_bps, service_fee_minor, travel_fee_per_km_minor, travel_fee_free_km,
  vat_bps, vat_label, tax_authority, payment_provider, kyc_provider, sos_provider,
  grid_status_provider, cancellation_window_minutes, cancellation_fee_bps,
  no_show_grace_minutes, dispatch_offer_seconds, max_search_radius_km, is_live,
  min_payout_minor, emergency_number
) VALUES
-- South Africa: 12.5% commission, R10 service fee, R7/km beyond 3km, 15% VAT.
('ZA', 'South Africa', 'ZAR', ARRAY['ZAR']::currency_code_enum[], '+27', 9,
 'Africa/Johannesburg', 1250, 1000, 700, 3.00,
 1500, 'VAT', 'SARS', 'stitch', 'smileid', 'aura',
 'eskom_se_push', 120, 5000, 10, 60, 25.00, true,
 5000, '10111'),

-- Zimbabwe: USD-first (the functional retail currency), 12.5% commission,
-- $0.50 service fee, $0.40/km. 15.5% VAT administered by ZIMRA, from
-- 1 January 2026 (Finance Act No. 7 of 2025; ZIMRA Public Notice 7 of 2026).
-- No national armed-response API equivalent to AURA, so SOS falls back to
-- emergency-contact broadcast plus local control-room numbers.
('ZW', 'Zimbabwe', 'USD', ARRAY['USD','ZWG']::currency_code_enum[], '+263', 9,
 'Africa/Harare', 1250, 50, 40, 3.00,
 1550, 'VAT', 'ZIMRA', 'paynow', 'smileid', 'mock',
 'zesa', 120, 5000, 10, 75, 20.00, true,
 -- US$20: two fades, not five. The ZA figure is R50 for the same reason.
 2000, '999');

-- --------------------------------------------------------------------------
-- Launch service areas. Boundaries here are deliberately coarse bounding
-- boxes for the geofenced pilot; replace with real municipal polygons before
-- opening a metro publicly.
-- --------------------------------------------------------------------------
INSERT INTO service_areas (country_code, name, slug, boundary, centroid, is_live) VALUES
('ZA', 'Johannesburg North', 'jhb-north',
  ST_GeogFromText('POLYGON((27.9 -26.20, 28.20 -26.20, 28.20 -25.95, 27.9 -25.95, 27.9 -26.20))'),
  ST_GeogFromText('POINT(28.0473 -26.1076)'), true),
('ZA', 'Cape Town Metro', 'cpt-metro',
  ST_GeogFromText('POLYGON((18.35 -34.05, 18.70 -34.05, 18.70 -33.85, 18.35 -33.85, 18.35 -34.05))'),
  ST_GeogFromText('POINT(18.4241 -33.9249)'), false),
('ZA', 'eThekwini', 'dbn-metro',
  ST_GeogFromText('POLYGON((30.85 -29.95, 31.10 -29.95, 31.10 -29.75, 30.85 -29.75, 30.85 -29.95))'),
  ST_GeogFromText('POINT(31.0218 -29.8587)'), false),
-- Harare launches first. Widened from the original 30.95-31.20 box, which cut
-- off Budiriro, Glen View, Kuwadzana and Dzivarasekwa: the high-density west,
-- where a large share of the city lives. Still a box; it now covers every
-- suburb in the Harare places list below.
('ZW', 'Harare Metro', 'hre-metro',
  ST_GeogFromText('POLYGON((30.90 -17.98, 31.26 -17.98, 31.26 -17.68, 30.90 -17.68, 30.90 -17.98))'),
  ST_GeogFromText('POINT(31.0530 -17.8252)'), true),
('ZW', 'Bulawayo', 'byo-metro',
  ST_GeogFromText('POLYGON((28.50 -20.25, 28.68 -20.25, 28.68 -20.05, 28.50 -20.05, 28.50 -20.25))'),
  ST_GeogFromText('POINT(28.5836 -20.1325)'), false);

-- --------------------------------------------------------------------------
-- Runtime-tunable settings surfaced in the admin portal.
-- --------------------------------------------------------------------------
INSERT INTO platform_settings (key, value, description) VALUES
('dispatch.wave_radii_km',        '[3, 6, 10, 15]',  'Expanding search radii per dispatch wave'),
('dispatch.max_waves',            '4',               'Give up and expire the booking after this many waves'),
('dispatch.offer_seconds',        '60',              'Seconds a provider has to accept before the offer lapses'),
('escrow.auth_hold_hours',        '168',             'Gateway authorisation validity; re-auth scheduled jobs beyond this'),
('escrow.capture_delay_minutes',  '0',               'Delay between completion and capture, for a dispute cooling-off window'),
('payout.instant_fee_bps',        '150',             'Fee charged for instant cash-out versus the free daily batch'),
('review.reveal_window_hours',    '336',             'Both-sided reviews stay hidden until this lapses'),
('safety.sos_abort_seconds',      '3',               'Countdown before an SOS is transmitted'),
('loadshedding.auto_filter_stage','4',               'At or above this stage, force the power-backup filter on'),
('media.max_upload_bytes',        '512000',          'Hard cap on uploaded image size after client-side compression'),
('tracking.ping_interval_seconds','5',               'Provider GPS ping cadence while en route'),
('tracking.retention_minutes',    '60',              'Redis TTL for location breadcrumbs; nothing persists to Postgres');

-- ---------------------------------------------------------------------------
-- Which categories can require a licence, and who issues it.
--
-- Every one of these is `requires_credential = false` on purpose. No category
-- is wholly invasive — 'brows' is mostly threading, 'aesthetics' is mostly
-- facials — so the category default would block ordinary work. What these rows
-- carry is the metadata: when a service inside the category IS gated, this is
-- what we ask the provider for and who we expect issued it.
--
-- The named regulators below are a starting point for legal review, not a
-- legal opinion. Confirm the scope-of-practice and premises position in each
-- market before opening these categories to real providers.
-- ---------------------------------------------------------------------------
INSERT INTO service_category_rules
  (country_code, category, requires_credential, credential_kind, regulator, in_shop_only, rationale)
VALUES
  ('ZA', 'scalp',         false, 'skin_penetration_permit', 'Municipal health by-laws; HPCSA scope',      true,
   'Scalp micropigmentation implants pigment into the dermis. Scalp detox and dandruff work in the same category do not.'),
  ('ZA', 'brows',         false, 'skin_penetration_permit', 'Municipal health by-laws; HPCSA scope',      true,
   'Microblading, powder brows and lip blush are needle work. Threading, waxing and tinting are not.'),
  ('ZA', 'aesthetics',    false, 'aesthetics_practitioner', 'HPCSA; SAHPRA for devices',                  true,
   'Microneedling, dermaplaning and peels break or abrade the skin. Cleansing facials do not.'),
  ('ZA', 'body_grooming', false, 'laser_operator',          'SAHPRA; municipal health by-laws',           true,
   'Laser hair removal is a regulated device. Waxing, sugaring and threading are not.'),
  ('ZW', 'scalp',         false, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe',   true,
   'Mirrors ZA. Confirm the local position before Zimbabwe opens.'),
  ('ZW', 'brows',         false, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe',   true,
   'Mirrors ZA. Confirm the local position before Zimbabwe opens.'),
  ('ZW', 'aesthetics',    false, 'aesthetics_practitioner', 'Health Professions Authority of Zimbabwe',   true,
   'Mirrors ZA. Confirm the local position before Zimbabwe opens.'),
  ('ZW', 'body_grooming', false, 'laser_operator',          'Medicines Control Authority of Zimbabwe',    true,
   'Mirrors ZA. Confirm the local position before Zimbabwe opens.')
ON CONFLICT (country_code, category) DO NOTHING;

-- ---------------------------------------------------------------------------
-- The safety net: procedures that are gated whatever category they are filed
-- under and whatever flag the catalogue did or did not set. `category` is left
-- NULL deliberately so a provider cannot escape the check by listing
-- microblading under 'makeup'.
-- ---------------------------------------------------------------------------
INSERT INTO regulated_procedures
  (country_code, name_pattern, category, credential_kind, regulator, in_shop_only, rationale)
VALUES
  ('ZA', '%micropigmentation%', NULL, 'skin_penetration_permit', 'Municipal health by-laws', true, 'Needle; implants pigment into the dermis'),
  ('ZA', '%microbladin%',       NULL, 'skin_penetration_permit', 'Municipal health by-laws', true, 'Blade; opens the skin'),
  ('ZA', '%powder brow%',       NULL, 'skin_penetration_permit', 'Municipal health by-laws', true, 'PMU machine work'),
  ('ZA', '%lip blush%',         NULL, 'skin_penetration_permit', 'Municipal health by-laws', true, 'PMU machine work'),
  ('ZA', '%hair tattoo%',       NULL, 'skin_penetration_permit', 'Municipal health by-laws', true, 'SMP under another name'),
  ('ZA', '%microneedl%',        NULL, 'aesthetics_practitioner', 'HPCSA; SAHPRA',            true, 'Punctures the dermis'),
  ('ZA', '%dermaplan%',         NULL, 'aesthetics_practitioner', 'HPCSA',                    true, 'Medical scalpel against skin'),
  ('ZA', '%chemical peel%',     NULL, 'aesthetics_practitioner', 'HPCSA',                    true, 'Controlled chemical burn requiring neutralisation'),
  ('ZA', '%laser%',             NULL, 'laser_operator',          'SAHPRA',                   true, 'Regulated device; eye and burn risk'),
  ('ZW', '%micropigmentation%', NULL, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe', true, 'Needle; implants pigment into the dermis'),
  ('ZW', '%microbladin%',       NULL, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe', true, 'Blade; opens the skin'),
  ('ZW', '%powder brow%',       NULL, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe', true, 'PMU machine work'),
  ('ZW', '%lip blush%',         NULL, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe', true, 'PMU machine work'),
  ('ZW', '%hair tattoo%',       NULL, 'skin_penetration_permit', 'Health Professions Authority of Zimbabwe', true, 'SMP under another name'),
  ('ZW', '%microneedl%',        NULL, 'aesthetics_practitioner', 'Health Professions Authority of Zimbabwe', true, 'Punctures the dermis'),
  ('ZW', '%dermaplan%',         NULL, 'aesthetics_practitioner', 'Health Professions Authority of Zimbabwe', true, 'Medical scalpel against skin'),
  ('ZW', '%chemical peel%',     NULL, 'aesthetics_practitioner', 'Health Professions Authority of Zimbabwe', true, 'Controlled chemical burn requiring neutralisation'),
  ('ZW', '%laser%',             NULL, 'laser_operator',          'Medicines Control Authority of Zimbabwe',  true, 'Regulated device; eye and burn risk')
ON CONFLICT (country_code, name_pattern) DO NOTHING;
