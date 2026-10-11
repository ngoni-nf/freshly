-- ---------------------------------------------------------------------------
-- 021: pin search_path on every fn_* function.
--
-- These functions are the database's last line of defence: the booking state
-- machine, the ledger's nets-to-zero assertion, the credential gate. Each
-- resolved unqualified names (`bookings`, `ST_DWithin`) through whatever
-- search_path the CALLER had. A session that put its own schema first could
-- shadow `ledger_entries` or `fn_provider_has_credential` with an object of
-- its own, and the guard would check the impostor. Supabase's advisor flags
-- all eleven as "role mutable search_path".
--
-- `public, pg_temp` is not a behaviour change: everything these functions
-- touch lives in `public`, PostGIS included. pg_temp goes last explicitly,
-- because when it is left out Postgres searches it FIRST, which is the shadowing
-- hole this migration exists to close.
--
-- A loop rather than eleven ALTERs, so it cannot miss one whose signature a
-- later migration changes.
-- ---------------------------------------------------------------------------

DO $$
DECLARE
  target RECORD;
BEGIN
  FOR target IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname LIKE 'fn\_%'
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp',
                   target.signature);
  END LOOP;
END $$;
