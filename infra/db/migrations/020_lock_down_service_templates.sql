-- ---------------------------------------------------------------------------
-- 020: extend 011's lockdown to `service_templates`.
--
-- 013 added the table after 011 had already enumerated the ones it protected,
-- so it arrived without row level security and Supabase's advisor flags it as
-- fully exposed. Today it is not: 011's revokes, including the default
-- privileges for future tables, leave `anon` and `authenticated` with no
-- USAGE on the schema and no grant on the table. That is the same "closed by
-- accident" state 011 was written to end — one re-applied Supabase default
-- would open it — so close it on purpose, exactly as 015 did for `places`.
--
-- Not FORCED, for 011's reason: the API connects as the owner, and forcing an
-- empty policy set on the owner would lock it out of its own catalogue.
-- ---------------------------------------------------------------------------

ALTER TABLE service_templates ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  role_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    -- Absent on a local Postgres or in CI; the migration must still apply.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('REVOKE ALL ON TABLE service_templates FROM %I', role_name);
    END IF;
  END LOOP;
END $$;
