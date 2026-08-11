-- ============================================================================
-- Seed: demo supply for Johannesburg North.
--
-- Development only. Enough density and variety that the client app has a real
-- feed to render: online and offline pros, with and without backup power, a
-- salon with staff, and a price spread wide enough to exercise the filters.
-- ============================================================================

DO $$
DECLARE
  jhb_id UUID;
  u_client UUID; u_sipho UUID; u_kabelo UUID; u_lerato UUID; u_nomsa UUID; u_admin UUID;
  p_sipho UUID; p_kabelo UUID; p_lerato UUID; p_salon UUID;
BEGIN
  SELECT id INTO jhb_id FROM service_areas WHERE slug = 'jhb-north';

  -- ── People ───────────────────────────────────────────────────────────────
  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version)
  VALUES ('+27821112222', 'ZA', 'Thandi Mokoena', 'thandi@example.co.za',
          ARRAY['client']::account_role_enum[], now(), now(), now(), 'v1')
  RETURNING id INTO u_client;

  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version, rating, rating_count)
  VALUES ('+27823334444', 'ZA', 'Sipho Mahlangu', 'sipho@example.co.za',
          ARRAY['client','provider']::account_role_enum[], now(), now(), now(), 'v1', 4.90, 127)
  RETURNING id INTO u_sipho;

  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version, rating, rating_count)
  VALUES ('+27825556666', 'ZA', 'Kabelo Tshabalala', 'kabelo@example.co.za',
          ARRAY['client','provider']::account_role_enum[], now(), now(), now(), 'v1', 4.70, 88)
  RETURNING id INTO u_kabelo;

  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version, rating, rating_count)
  VALUES ('+27827778888', 'ZA', 'Lerato Ndlovu', 'lerato@example.co.za',
          ARRAY['client','provider']::account_role_enum[], now(), now(), now(), 'v1', 4.80, 203)
  RETURNING id INTO u_lerato;

  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version)
  VALUES ('+27829990000', 'ZA', 'Nomsa Dlamini', 'nomsa@example.co.za',
          ARRAY['client','provider','staff']::account_role_enum[], now(), now(), now(), 'v1')
  RETURNING id INTO u_nomsa;

  INSERT INTO users (phone_e164, country_code, full_name, email, roles, phone_verified_at,
                     consent_privacy_at, consent_terms_at, consent_version)
  VALUES ('+27820000001', 'ZA', 'Freshly Ops', 'ops@freshly.africa',
          ARRAY['admin','support']::account_role_enum[], now(), now(), now(), 'v1')
  RETURNING id INTO u_admin;

  -- ── Providers ────────────────────────────────────────────────────────────
  -- Sipho: online, inverter + battery clippers. The reference "available now
  -- during load shedding" case the whole power filter exists to surface.
  INSERT INTO providers (user_id, country_code, service_area_id, business_mode, display_name, slug,
                         bio, categories, venue_mode, power_backup, base_location, last_location,
                         last_location_at, travel_radius_km, is_online, kyc_status, kyc_verified_at,
                         payout_currency, rating, rating_count, completed_jobs)
  VALUES (u_sipho, 'ZA', jhb_id, 'solo', 'Sipho M.', 'sipho-m',
          'Fades, line-ups and beard work. Ten years in Alex and Sandton. I carry an inverter, so load shedding is not your problem.',
          ARRAY['barber']::service_category_enum[], 'mobile',
          ARRAY['inverter','battery_clippers']::power_backup_enum[],
          ST_GeogFromText('POINT(28.0473 -26.1076)'), ST_GeogFromText('POINT(28.0473 -26.1076)'),
          now(), 15, true, 'verified', now(), 'ZAR', 4.90, 127, 341)
  RETURNING id INTO p_sipho;

  -- Kabelo: online, no backup power. Disappears from the feed at stage 4+.
  INSERT INTO providers (user_id, country_code, service_area_id, business_mode, display_name, slug,
                         bio, categories, venue_mode, power_backup, base_location, last_location,
                         last_location_at, travel_radius_km, is_online, kyc_status, kyc_verified_at,
                         payout_currency, rating, rating_count, completed_jobs)
  VALUES (u_kabelo, 'ZA', jhb_id, 'solo', 'Kabelo T.', 'kabelo-t',
          'Clean cuts, on time. Randburg and surrounds.',
          ARRAY['barber']::service_category_enum[], 'both', '{}'::power_backup_enum[],
          ST_GeogFromText('POINT(28.0100 -26.0940)'), ST_GeogFromText('POINT(28.0100 -26.0940)'),
          now(), 10, true, 'verified', now(), 'ZAR', 4.70, 88, 156)
  RETURNING id INTO p_kabelo;

  -- Lerato: offline right now, generator. Bookable in advance, not instantly.
  INSERT INTO providers (user_id, country_code, service_area_id, business_mode, display_name, slug,
                         bio, categories, venue_mode, power_backup, base_location, travel_radius_km,
                         is_online, accepts_instant, kyc_status, kyc_verified_at, payout_currency,
                         rating, rating_count, completed_jobs)
  VALUES (u_lerato, 'ZA', jhb_id, 'solo', 'Lerato N.', 'lerato-n',
          'Braiding and locs specialist. Knotless, box braids, starter locs and retwists.',
          ARRAY['braiding','locs']::service_category_enum[], 'mobile',
          ARRAY['generator','portable_lights']::power_backup_enum[],
          ST_GeogFromText('POINT(28.0650 -26.1400)'), 20,
          false, true, 'verified', now(), 'ZAR', 4.80, 203, 512)
  RETURNING id INTO p_lerato;

  -- A salon with a chair, exercising the multi-seat path.
  INSERT INTO providers (user_id, country_code, service_area_id, business_mode, display_name, slug,
                         bio, categories, venue_mode, power_backup, base_location, shop_address,
                         travel_radius_km, is_online, kyc_status, kyc_verified_at, payout_currency,
                         rating, rating_count, completed_jobs)
  VALUES (u_nomsa, 'ZA', jhb_id, 'salon', 'Glow Bar Rosebank', 'glow-bar-rosebank',
          'Nails, brows and lashes in the heart of Rosebank.',
          ARRAY['nails','brows']::service_category_enum[], 'in_shop',
          ARRAY['inverter']::power_backup_enum[],
          ST_GeogFromText('POINT(28.0436 -26.1460)'), 'Shop 12, Rosebank Mall, Johannesburg',
          5, true, 'verified', now(), 'ZAR', 4.60, 74, 209)
  RETURNING id INTO p_salon;

  -- ── Service menus ────────────────────────────────────────────────────────
  INSERT INTO services (provider_id, name, description, category, venue_mode, price_minor,
                        currency, duration_minutes, requires_power, sort_order) VALUES
    (p_sipho, 'Skin fade', 'Full fade, shaped up, hot towel finish.', 'barber', 'both', 18000, 'ZAR', 45, true, 1),
    (p_sipho, 'Beard line-up', 'Shape, trim and line.', 'barber', 'both', 7000, 'ZAR', 20, true, 2),
    (p_sipho, 'Kids cut', 'Under 12s.', 'barber', 'both', 12000, 'ZAR', 30, true, 3),
    (p_kabelo, 'Classic cut', 'Scissor or clipper cut.', 'barber', 'both', 15000, 'ZAR', 40, true, 1),
    (p_kabelo, 'Head shave', 'Full shave, oiled.', 'barber', 'both', 10000, 'ZAR', 25, true, 2),
    (p_lerato, 'Knotless braids (medium)', 'Hair not included.', 'braiding', 'mobile', 55000, 'ZAR', 240, false, 1),
    (p_lerato, 'Cornrows', 'Straight back, 6-8 lines.', 'braiding', 'mobile', 22000, 'ZAR', 90, false, 2),
    (p_lerato, 'Loc retwist', 'Retwist and style.', 'locs', 'mobile', 32000, 'ZAR', 120, false, 3),
    (p_salon, 'Gel overlay', 'Natural nail gel overlay.', 'nails', 'in_shop', 25000, 'ZAR', 60, true, 1),
    (p_salon, 'Acrylic full set', 'Sculpted, any length.', 'nails', 'in_shop', 45000, 'ZAR', 105, true, 2),
    (p_salon, 'Brow shape and tint', 'Wax, shape and tint.', 'brows', 'in_shop', 18000, 'ZAR', 40, false, 3);

  INSERT INTO service_addons (provider_id, name, price_minor, currency, duration_minutes) VALUES
    (p_sipho, 'Beard oil treatment', 4000, 'ZAR', 10),
    (p_sipho, 'Eyebrow trim', 3000, 'ZAR', 5),
    (p_lerato, 'Hair extensions (per pack)', 12000, 'ZAR', 0),
    (p_salon, 'Nail art (per nail)', 3000, 'ZAR', 10);

  -- ── Availability: weekdays 08:00-18:00, Saturdays 08:00-14:00 ────────────
  INSERT INTO availability_rules (provider_id, weekday, starts_at, ends_at)
  SELECT p.id, d.weekday, '08:00'::TIME, CASE WHEN d.weekday = 6 THEN '14:00'::TIME ELSE '18:00'::TIME END
    FROM (VALUES (p_sipho), (p_kabelo), (p_lerato), (p_salon)) AS p(id)
    CROSS JOIN (VALUES (1),(2),(3),(4),(5),(6)) AS d(weekday);

  -- account_number_enc is a placeholder, because seeds are plain SQL and the
  -- AES key lives only in the API process — there is no way to write a real
  -- ciphertext here. So these are is_verified = false, deliberately: a payout
  -- would decrypt this and fail, and an account whose details cannot be read
  -- is exactly what "not verified" means. Add a real one through
  -- POST /payouts/accounts to exercise a cash-out.
  INSERT INTO payout_accounts (provider_id, country_code, currency, method, institution_name,
                               account_name, account_number_enc, account_last4, is_verified)
  VALUES
    (p_sipho, 'ZA', 'ZAR', 'bank_transfer', 'Capitec', 'S Mahlangu', '\x00'::BYTEA, '4821', false),
    (p_kabelo, 'ZA', 'ZAR', 'bank_transfer', 'FNB', 'K Tshabalala', '\x00'::BYTEA, '9014', false),
    (p_lerato, 'ZA', 'ZAR', 'bank_transfer', 'TymeBank', 'L Ndlovu', '\x00'::BYTEA, '3372', false),
    (p_salon, 'ZA', 'ZAR', 'bank_transfer', 'Standard Bank', 'Glow Bar Pty Ltd', '\x00'::BYTEA, '6650', false);

  INSERT INTO provider_wallets (provider_id, currency, available_minor, pending_minor, lifetime_earned_minor)
  VALUES (p_sipho, 'ZAR', 84250, 0, 1204500),
         (p_kabelo, 'ZAR', 31200, 0, 448900),
         (p_lerato, 'ZAR', 156000, 0, 2871000),
         (p_salon, 'ZAR', 62800, 0, 934200);

  INSERT INTO salon_staff (salon_id, provider_id, job_title, commission_split_bps, can_manage, accepted_at)
  VALUES (p_salon, p_salon, 'Owner', 10000, true, now());

  INSERT INTO subscriptions (provider_id, tier, status, price_minor, currency, seats, current_period_end)
  VALUES (p_salon, 'salon', 'active', 39900, 'ZAR', 3, now() + INTERVAL '30 days');

  -- Grid: stage 0 by default so the demo feed is not filtered on first run.
  INSERT INTO grid_status (country_code, stage, source, effective_from)
  VALUES ('ZA', 0, 'manual', now());

  INSERT INTO promo_codes (code, country_code, discount_bps, max_discount_minor, min_spend_minor,
                           first_booking_only, max_redemptions)
  VALUES ('FRESH20', 'ZA', 2000, 5000, 10000, true, 1000);

  RAISE NOTICE 'Demo data: 4 providers, 11 services, 1 salon, promo FRESH20';
END $$;
