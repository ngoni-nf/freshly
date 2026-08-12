-- ---------------------------------------------------------------------------
-- 018: make support_tickets a conversation rather than a shout.
--
-- The table has existed since 005 and nothing has ever read or written it. A
-- complaint you can receive but not answer is not a support system, so this
-- adds the reply thread and the few columns an operator needs to work a queue:
-- who it is about, who answered, and when the person was last spoken to.
--
-- Kept as one thread per ticket rather than reusing chat_messages: that table
-- is scoped to a booking and to its two participants, and a complaint is
-- between a user and the platform, often about no booking at all.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS support_ticket_messages (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id    UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  author_id    UUID NOT NULL REFERENCES users(id),
  -- Who is speaking. An operator's reply and the complainant's follow-up look
  -- the same in a body column and must not be confused when read back.
  is_staff     BOOLEAN NOT NULL DEFAULT false,
  body         TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket
  ON support_ticket_messages(ticket_id, created_at);

-- Which side raised it. A provider complaining about a client and a client
-- complaining about a provider are different queues with different handlers,
-- and deriving it from the user's roles later is guesswork — somebody who is
-- both a client and a provider would land in whichever branch was written
-- first.
ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS raised_by VARCHAR(10) NOT NULL DEFAULT 'client'
    CHECK (raised_by IN ('client', 'provider'));

-- Set when an operator answers, so a queue can be sorted by who has been
-- waiting longest without a reply.
ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS last_staff_reply_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_support_tickets_open
  ON support_tickets(status, created_at DESC);

-- Same lockdown as 011 and 015: deny-all RLS, not forced, because the API
-- connects as the owner.
ALTER TABLE support_ticket_messages ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  role_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('REVOKE ALL ON TABLE support_ticket_messages FROM %I', role_name);
    END IF;
  END LOOP;
END $$;
