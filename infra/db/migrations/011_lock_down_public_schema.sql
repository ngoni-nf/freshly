-- ---------------------------------------------------------------------------
-- Make the closed door explicit.
--
-- Supabase's linter flags every table in `public` without row level security,
-- because in a normal Supabase project PostgREST exposes that schema to the
-- `anon` and `authenticated` roles, and RLS is the only thing standing between
-- an API key and the table.
--
-- This project is not that shape. Nothing talks to PostgREST: the API connects
-- directly as `postgres` over the session pooler and enforces every rule in
-- application and trigger code. And today those roles cannot reach `public` at
-- all — they hold no USAGE on the schema, because `db:reset` drops and
-- recreates it, which discards the grants Supabase installs.
--
-- That is protection by accident. A table created through the dashboard, a
-- restored backup, or Supabase reapplying its defaults would silently undo it,
-- and nobody would notice until data was already readable. So state it:
--
--   1. Revoke explicitly, including for objects that do not exist yet.
--   2. Enable RLS with no policies, which denies everyone except the table
--      owner. The API connects as the owner, so this costs it nothing, and a
--      future accidental GRANT is no longer sufficient to read a row.
--
-- Deliberately NOT forced. FORCE ROW LEVEL SECURITY would apply the (empty)
-- policy set to the owner too and lock the API out of its own database.
--
-- `public.spatial_ref_sys` will keep failing the lint and that is correct. It
-- belongs to the PostGIS extension and is owned by `supabase_admin`, so we are
-- not permitted to alter it; it holds the public EPSG projection registry, so
-- there is nothing in it to protect. Silence that finding in the dashboard
-- rather than granting ourselves rights over an extension's own tables.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  role_name TEXT;
BEGIN
  FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    -- The roles only exist on a hosted Supabase project; a local Postgres or
    -- a CI database has neither, and the migration must still apply there.
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = role_name) THEN
      EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', role_name);
      EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', role_name);
      EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM %I', role_name);
      EXECUTE format('REVOKE ALL ON SCHEMA public FROM %I', role_name);
      -- Covers tables added by later migrations, which is the case that would
      -- otherwise reintroduce the hole one deploy at a time.
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM %I', role_name);
      EXECUTE format(
        'ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', role_name);
    END IF;
  END LOOP;
END $$;

-- Deny-all RLS on everything we own. Skips spatial_ref_sys and anything else
-- belonging to an extension, which we neither own nor need to protect.
DO $$
DECLARE
  target RECORD;
BEGIN
  FOR target IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relkind = 'r'
       AND NOT c.relrowsecurity
       AND pg_get_userbyid(c.relowner) = current_user
       -- Tables owned by an extension are its business, not ours.
       AND NOT EXISTS (
             SELECT 1 FROM pg_depend d
              WHERE d.objid = c.oid AND d.deptype = 'e'
           )
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', target.relname);
  END LOOP;
END $$;
