-- ---------------------------------------------------------------------------
-- 015: extend 011's lockdown to `places`.
--
-- 011 enumerated the tables that existed when it ran, which means every table
-- added afterwards arrives unprotected and fails the same lint 011 was written
-- to answer. Same reasoning as there: deny-all RLS with no policies, not
-- FORCED, because the API connects as the owner and forcing it would lock the
-- API out of its own database.
--
-- Anything that adds a table in `public` from here needs the same three lines.
-- ---------------------------------------------------------------------------

ALTER TABLE places ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  role_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    -- Absent on a local Postgres or in CI; the migration must still apply.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('REVOKE ALL ON TABLE places FROM %I', role_name);
    END IF;
  END LOOP;
END $$;
