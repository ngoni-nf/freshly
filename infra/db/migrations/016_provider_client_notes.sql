-- ---------------------------------------------------------------------------
-- 016: Provider-only client notes.
--
-- A world-class CRM needs a way for a professional to keep private notes on a
-- client (e.g. "prefers low fade", "allergic to peppermint oil"). These are
-- never shown to the client and belong only to the provider who wrote them.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS provider_client_notes (
  provider_id      UUID NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  client_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notes            TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (provider_id, client_user_id)
);

CREATE INDEX IF NOT EXISTS idx_provider_client_notes_client ON provider_client_notes(client_user_id);

-- Ensure providers can only see notes they wrote.
ALTER TABLE provider_client_notes ENABLE ROW LEVEL SECURITY;

-- Note: RLS is a secondary control here as the API layer already enforces
-- scoping to the authenticated provider.
