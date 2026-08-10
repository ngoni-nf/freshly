-- ============================================================================
-- 001  Extensions, domains and enumerated types
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ---------------------------------------------------------------------------
-- Money is stored as BIGINT MINOR UNITS (cents / ngwee), never as float or
-- decimal. Rationale: the platform runs multi-currency (ZAR, USD, ZWG) and
-- every commission split is an integer division with a defined remainder
-- owner. Decimal money in a marketplace ledger eventually loses a cent.
-- ---------------------------------------------------------------------------
CREATE DOMAIN money_minor AS BIGINT;

CREATE TYPE country_code_enum      AS ENUM ('ZA', 'ZW');
CREATE TYPE currency_code_enum     AS ENUM ('ZAR', 'USD', 'ZWG');

CREATE TYPE account_role_enum      AS ENUM ('client', 'provider', 'staff', 'admin', 'support');
CREATE TYPE account_status_enum    AS ENUM ('active', 'suspended', 'deleted');

CREATE TYPE business_mode_enum     AS ENUM ('solo', 'salon', 'salon_staff');
CREATE TYPE kyc_status_enum        AS ENUM ('unstarted', 'pending', 'in_review', 'verified', 'rejected', 'expired');
CREATE TYPE power_backup_enum      AS ENUM ('generator', 'inverter', 'battery_clippers', 'portable_lights', 'solar');
CREATE TYPE service_venue_enum     AS ENUM ('mobile', 'in_shop', 'both');

CREATE TYPE service_category_enum  AS ENUM ('barber', 'hair', 'nails', 'makeup', 'aesthetics', 'braiding', 'locs', 'massage', 'brows_lashes');

CREATE TYPE booking_type_enum      AS ENUM ('instant', 'scheduled');
CREATE TYPE booking_status_enum    AS ENUM (
  'draft',            -- cart assembled, no payment attempted
  'pending_auth',     -- checkout started, awaiting gateway authorization
  'authorized',       -- funds held in escrow, awaiting provider acceptance
  'accepted',         -- provider accepted, not yet moving
  'en_route',         -- provider travelling to client
  'arrived',          -- provider on site
  'in_progress',      -- PIN verified, service underway
  'completed',        -- service finished, escrow captured
  'cancelled',        -- cancelled by either party
  'expired',          -- no provider accepted in time
  'disputed'          -- under mediation, funds frozen
);

CREATE TYPE escrow_status_enum     AS ENUM ('unauthorized', 'authorizing', 'authorized', 'captured', 'partially_captured', 'released', 'refunded', 'partially_refunded', 'frozen', 'failed');
CREATE TYPE cancelled_by_enum      AS ENUM ('client', 'provider', 'system', 'admin');

CREATE TYPE payment_method_enum    AS ENUM ('card', 'capitec_pay', 'instant_eft', 'ecocash', 'onemoney', 'innbucks', 'wallet', 'cash');

CREATE TYPE ledger_direction_enum  AS ENUM ('debit', 'credit');
CREATE TYPE ledger_account_enum    AS ENUM (
  'client_source',        -- the client's funding instrument
  'escrow',               -- funds held pending service completion
  'provider_payable',     -- provider earnings, not yet paid out
  'platform_commission',  -- marketplace take rate
  'platform_service_fee', -- flat per-checkout fee
  'payment_processing',   -- gateway costs
  'tax_payable',          -- VAT collected on platform fees
  'promotions',           -- discounts funded by the platform
  'bank_settlement'       -- money that has physically left for a bank
);

CREATE TYPE payout_status_enum     AS ENUM ('requested', 'queued', 'processing', 'paid', 'failed', 'reversed');
CREATE TYPE subscription_tier_enum AS ENUM ('free', 'pro', 'salon');
CREATE TYPE subscription_status_enum AS ENUM ('trialing', 'active', 'past_due', 'cancelled');

CREATE TYPE sos_status_enum        AS ENUM ('armed', 'aborted', 'dispatched', 'acknowledged', 'resolved', 'false_alarm');
CREATE TYPE sos_actor_enum         AS ENUM ('client', 'provider');

CREATE TYPE dispute_status_enum    AS ENUM ('open', 'awaiting_evidence', 'under_review', 'resolved_client', 'resolved_provider', 'resolved_split', 'withdrawn');

CREATE TYPE review_direction_enum  AS ENUM ('client_to_provider', 'provider_to_client');
CREATE TYPE grid_stage_source_enum AS ENUM ('eskom_se_push', 'zesa', 'manual');
