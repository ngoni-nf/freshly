-- ============================================================================
-- Seed: markets. South Africa launches first; Zimbabwe is pre-configured but
-- is_live = false until supply is onboarded.
-- ============================================================================

INSERT INTO countries (
  code, name, default_currency, supported_currencies, dial_prefix, phone_national_length,
  timezone, commission_bps, service_fee_minor, travel_fee_per_km_minor, travel_fee_free_km,
  vat_bps, vat_label, tax_authority, payment_provider, kyc_provider, sos_provider,
  grid_status_provider, cancellation_window_minutes, cancellation_fee_bps,
  no_show_grace_minutes, dispatch_offer_seconds, max_search_radius_km, is_live
) VALUES
-- South Africa: 12.5% commission, R10 service fee, R7/km beyond 3km, 15% VAT.
('ZA', 'South Africa', 'ZAR', ARRAY['ZAR']::currency_code_enum[], '+27', 9,
 'Africa/Johannesburg', 1250, 1000, 700, 3.00,
 1500, 'VAT', 'SARS', 'stitch', 'smileid', 'aura',
 'eskom_se_push', 120, 5000, 10, 60, 25.00, true),

-- Zimbabwe: USD-first (the functional retail currency), 12.5% commission,
-- $0.50 service fee, $0.40/km. 15% VAT administered by ZIMRA.
-- No national armed-response API equivalent to AURA, so SOS falls back to
-- emergency-contact broadcast plus local control-room numbers.
('ZW', 'Zimbabwe', 'USD', ARRAY['USD','ZWG']::currency_code_enum[], '+263', 9,
 'Africa/Harare', 1250, 50, 40, 3.00,
 1500, 'VAT', 'ZIMRA', 'paynow', 'smileid', 'mock',
 'zesa', 120, 5000, 10, 75, 20.00, false);

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
('ZW', 'Harare Metro', 'hre-metro',
  ST_GeogFromText('POLYGON((30.95 -17.95, 31.20 -17.95, 31.20 -17.72, 30.95 -17.72, 30.95 -17.95))'),
  ST_GeogFromText('POINT(31.0530 -17.8252)'), false),
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
('payout.min_amount_minor',       '5000',            'Minimum balance that can be withdrawn'),
('review.reveal_window_hours',    '336',             'Both-sided reviews stay hidden until this lapses'),
('safety.sos_abort_seconds',      '3',               'Countdown before an SOS is transmitted'),
('loadshedding.auto_filter_stage','4',               'At or above this stage, force the power-backup filter on'),
('media.max_upload_bytes',        '512000',          'Hard cap on uploaded image size after client-side compression'),
('tracking.ping_interval_seconds','5',               'Provider GPS ping cadence while en route'),
('tracking.retention_minutes',    '60',              'Redis TTL for location breadcrumbs; nothing persists to Postgres');
