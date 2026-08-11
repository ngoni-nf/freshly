-- ---------------------------------------------------------------------------
-- Index every foreign key.
--
-- Postgres creates an index for a PRIMARY KEY and for UNIQUE, but never for a
-- REFERENCES clause. Forty-nine of ours had none, which costs twice:
--
--   1. Every join and lookup through the key is a sequential scan. The worst
--      are the ones on the hot paths — booking_items.booking_id is read for
--      every booking, and ledger_entries.counterparty_provider_id is how a
--      provider's earnings get reconciled.
--   2. Every DELETE or UPDATE on the *parent* has to scan the whole child
--      table to enforce the constraint. Deleting one user would scan
--      refresh_tokens, saved_addresses, emergency_contacts and the rest end to
--      end. That is invisible on seed data and painful on real volume.
--
-- Low-cardinality columns are indexed too. country_code has two values today,
-- but the index still exists to make the referential check on `countries` a
-- lookup rather than a scan, and Postgres will simply decline to use it for
-- filtering when a scan is cheaper.
--
-- Named idx_<table>_<column> throughout, so the next person can tell at a
-- glance which of these are FK-support indexes and which were designed.
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_audit_log_actor              ON audit_log (actor_id);
CREATE INDEX IF NOT EXISTS idx_booking_events_actor         ON booking_events (actor_id);
CREATE INDEX IF NOT EXISTS idx_booking_items_addon          ON booking_items (addon_id);
CREATE INDEX IF NOT EXISTS idx_booking_items_booking        ON booking_items (booking_id);
CREATE INDEX IF NOT EXISTS idx_booking_items_service        ON booking_items (service_id);
CREATE INDEX IF NOT EXISTS idx_bookings_country             ON bookings (country_code);
CREATE INDEX IF NOT EXISTS idx_bookings_salon               ON bookings (salon_id);
CREATE INDEX IF NOT EXISTS idx_bookings_service_area        ON bookings (service_area_id);
CREATE INDEX IF NOT EXISTS idx_call_sessions_conversation   ON call_sessions (conversation_id);
CREATE INDEX IF NOT EXISTS idx_call_sessions_initiator      ON call_sessions (initiated_by);
CREATE INDEX IF NOT EXISTS idx_disputes_assignee            ON disputes (assigned_to);
CREATE INDEX IF NOT EXISTS idx_disputes_booking             ON disputes (booking_id);
CREATE INDEX IF NOT EXISTS idx_disputes_raiser              ON disputes (raised_by);
CREATE INDEX IF NOT EXISTS idx_emergency_contacts_user      ON emergency_contacts (user_id);
CREATE INDEX IF NOT EXISTS idx_outage_windows_area          ON grid_outage_windows (service_area_id);
CREATE INDEX IF NOT EXISTS idx_grid_status_area             ON grid_status (service_area_id);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_user        ON idempotency_keys (user_id);
CREATE INDEX IF NOT EXISTS idx_kyc_submissions_provider     ON kyc_submissions (provider_id);
CREATE INDEX IF NOT EXISTS idx_kyc_submissions_reviewer     ON kyc_submissions (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_ledger_counterparty_provider ON ledger_entries (counterparty_provider_id);
CREATE INDEX IF NOT EXISTS idx_ledger_counterparty_user     ON ledger_entries (counterparty_user_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender              ON messages (sender_id);
CREATE INDEX IF NOT EXISTS idx_payout_accounts_country      ON payout_accounts (country_code);
CREATE INDEX IF NOT EXISTS idx_payout_accounts_provider     ON payout_accounts (provider_id);
CREATE INDEX IF NOT EXISTS idx_payouts_account              ON payouts (payout_account_id);
CREATE INDEX IF NOT EXISTS idx_platform_settings_updater    ON platform_settings (updated_by);
CREATE INDEX IF NOT EXISTS idx_portfolio_items_provider     ON portfolio_items (provider_id);
CREATE INDEX IF NOT EXISTS idx_promo_codes_country          ON promo_codes (country_code);
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_booking    ON promo_redemptions (booking_id);
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_user       ON promo_redemptions (user_id);
CREATE INDEX IF NOT EXISTS idx_provider_credentials_reviewer ON provider_credentials (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_providers_country            ON providers (country_code);
CREATE INDEX IF NOT EXISTS idx_providers_salon_parent       ON providers (salon_parent_id);
CREATE INDEX IF NOT EXISTS idx_providers_service_area       ON providers (service_area_id);
CREATE INDEX IF NOT EXISTS idx_providers_user               ON providers (user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_device        ON refresh_tokens (device_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user          ON refresh_tokens (user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_author               ON reviews (author_id);
CREATE INDEX IF NOT EXISTS idx_salon_staff_provider         ON salon_staff (provider_id);
CREATE INDEX IF NOT EXISTS idx_saved_addresses_user         ON saved_addresses (user_id);
CREATE INDEX IF NOT EXISTS idx_service_addons_provider      ON service_addons (provider_id);
CREATE INDEX IF NOT EXISTS idx_service_areas_country        ON service_areas (country_code);
CREATE INDEX IF NOT EXISTS idx_sos_events_booking           ON sos_events (booking_id);
CREATE INDEX IF NOT EXISTS idx_sos_events_triggered_by      ON sos_events (triggered_by_user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_provider       ON subscriptions (provider_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assignee     ON support_tickets (assigned_to);
CREATE INDEX IF NOT EXISTS idx_support_tickets_booking      ON support_tickets (booking_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_user         ON support_tickets (user_id);
CREATE INDEX IF NOT EXISTS idx_users_country                ON users (country_code);
