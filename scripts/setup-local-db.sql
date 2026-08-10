-- Bootstrap a local PostgreSQL for Freshly, without Docker.
--
-- Run as a superuser (usually "postgres"):
--     psql -U postgres -f scripts/setup-local-db.sql
--
-- Creates the role and database the app expects, then installs PostGIS into
-- that database. PostGIS itself must already be present on the server — on
-- Windows that comes from the "Application Stack Builder" bundled with the
-- PostgreSQL installer, under Spatial Extensions.

\set ON_ERROR_STOP on

-- The role is a superuser only because migrations create extensions, which
-- ordinary roles cannot do. Production uses a least-privilege role and has
-- its extensions installed once, out of band.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'freshly') THEN
    CREATE ROLE freshly WITH LOGIN PASSWORD 'freshly' SUPERUSER CREATEDB;
    RAISE NOTICE 'created role freshly';
  ELSE
    ALTER ROLE freshly WITH LOGIN PASSWORD 'freshly' SUPERUSER CREATEDB;
    RAISE NOTICE 'role freshly already existed; password reset';
  END IF;
END $$;

SELECT 'CREATE DATABASE freshly OWNER freshly'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'freshly')\gexec

\connect freshly

CREATE EXTENSION IF NOT EXISTS postgis;

SELECT
  current_database()          AS database,
  current_user                AS connected_as,
  postgis_version()           AS postgis;
