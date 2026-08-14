-- ---------------------------------------------------------------------------
-- 018: referrals.
--
-- Word of mouth is how this category actually spreads — somebody sees a cut
-- and asks who did it — and the app had no way to carry that. This is the
-- cheapest acquisition channel available and the only one that compounds.
--
-- Three decisions worth stating, because each one is a fraud control:
--
-- 1. The reward is earned on the referee's first COMPLETED booking, never on
--    signup. Signup is free to fake; a completed booking requires a real
--    provider to have shown up, a real card to have been authorised and
--    captured, and the client's PIN. Paying on signup is how referral
--    programmes get farmed.
--
-- 2. Rewards are credits spent as a discount on a future booking, not cash
--    and not wallet balance. A discount is already a first-class part of the
--    quote and moves no money on its own, so nothing here can unbalance the
--    ledger. Cash rewards would be a payable and a withdrawal path, which is
--    a different and much larger thing to get right.
--
-- 3. One referral per referee, ever, enforced by a primary key on the referee
--    rather than by application logic. A person can be referred once; after
--    that they are a customer.
-- ---------------------------------------------------------------------------

-- A stable, shareable code per user. Generated on demand rather than for
-- everybody at signup, because most users never share one and a code nobody
-- has seen is a row nobody needs.
CREATE TABLE IF NOT EXISTS referral_codes (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  code        VARCHAR(12) NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_codes_code ON referral_codes(upper(code));

CREATE TYPE referral_status_enum AS ENUM ('pending', 'qualified', 'expired');

CREATE TABLE IF NOT EXISTS referrals (
  -- The referee is the key: one person can only ever be referred once.
  referee_user_id   UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  referrer_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status            referral_status_enum NOT NULL DEFAULT 'pending',
  -- The booking that earned it, kept so a dispute can be traced to the job.
  qualifying_booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  qualified_at      TIMESTAMPTZ,
  -- Nobody may refer themselves. Cheap to attempt, so it is refused by the
  -- database rather than only by the code that happens to call it today.
  CONSTRAINT chk_no_self_referral CHECK (referrer_user_id <> referee_user_id)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_user_id, status);

-- ---------------------------------------------------------------------------
-- Credits.
--
-- Spendable against a future booking and nothing else. Deliberately not a
-- wallet: `provider_wallets` holds money that can be withdrawn to a bank and
-- is backed by captured funds, and conflating the two would let promotional
-- credit be cashed out.
--
-- Consumption is recorded by booking id, so a credit cannot be spent twice and
-- a discount on any booking can be traced back to what granted it.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_credits (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_minor       money_minor NOT NULL CHECK (amount_minor > 0),
  currency           currency_code_enum NOT NULL,
  reason             VARCHAR(40) NOT NULL,
  -- Credit that never expires is a liability that never ages off the books.
  expires_at         TIMESTAMPTZ,
  consumed_booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  consumed_at        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_credits_user ON user_credits(user_id);

-- The lookup every quote makes: what is spendable, oldest first so the credit
-- closest to expiring is used before one that has longer to run.
CREATE INDEX IF NOT EXISTS idx_user_credits_spendable
  ON user_credits(user_id, created_at)
  WHERE consumed_at IS NULL;

-- ---------------------------------------------------------------------------
-- Reward amounts are market data, like commission and travel tariffs. Turning
-- the programme up in Zimbabwe must not be a deploy.
-- ---------------------------------------------------------------------------
ALTER TABLE countries ADD COLUMN IF NOT EXISTS referral_referee_discount_minor money_minor NOT NULL DEFAULT 0;
ALTER TABLE countries ADD COLUMN IF NOT EXISTS referral_referrer_credit_minor  money_minor NOT NULL DEFAULT 0;
ALTER TABLE countries ADD COLUMN IF NOT EXISTS referral_credit_ttl_days INT NOT NULL DEFAULT 90;

-- R50 each way in South Africa. Deliberately modest: the point is to make
-- sharing feel worth a message, not to buy growth at a loss on every job.
UPDATE countries SET
  referral_referee_discount_minor = 5000,
  referral_referrer_credit_minor  = 5000
WHERE code = 'ZA';

-- Zimbabwe stays at zero until the market opens and the economics are known.
-- A default of zero means the feature is inert there rather than wrong.

-- Same lockdown as everything else we own in public.
ALTER TABLE referral_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_credits ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  role_name TEXT;
  tbl TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      FOREACH tbl IN ARRAY ARRAY['referral_codes', 'referrals', 'user_credits'] LOOP
        EXECUTE format('REVOKE ALL ON TABLE %I FROM %I', tbl, role_name);
      END LOOP;
    END IF;
  END LOOP;
END $$;
