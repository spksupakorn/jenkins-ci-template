#!/bin/sh

# The official image executes this script only while initializing an empty volume.
set -eu

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 \
  --set=migrator_password="$MIGRATOR_DB_PASSWORD" \
  --set=dev_password="$DEV_DB_PASSWORD" \
  --set=app_password="$APP_DB_PASSWORD" \
  --set=platform_password="$PLATFORM_DB_PASSWORD" <<'SQL'

CREATE ROLE dev_altpro
    LOGIN
    PASSWORD :'dev_password'
    NOSUPERUSER
    CREATEDB
    NOCREATEROLE
    NOBYPASSRLS;

CREATE DATABASE mattersolv_dev
    OWNER dev_altpro;

-- PostgreSQL forbids removing SUPERUSER from the bootstrap role, so the migrator is
-- created here as an ordinary role instead. It owns the schema and may create the
-- pytest database, but stays subject to RLS.
CREATE ROLE migrator
    LOGIN
    NOSUPERUSER
    CREATEDB
    NOCREATEROLE
    NOINHERIT
    NOBYPASSRLS
    PASSWORD :'migrator_password';

CREATE ROLE general_altpro
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    NOBYPASSRLS
    PASSWORD :'app_password';

-- This credential is used exclusively by DATABASES["platform"] for the small,
-- reviewed cross-tenant platform surface. It is never the default API connection.
CREATE ROLE platform
    LOGIN
    NOSUPERUSER
    NOCREATEDB
    NOCREATEROLE
    NOINHERIT
    BYPASSRLS
    PASSWORD :'platform_password';

ALTER DATABASE mattersolv_general OWNER TO migrator;
ALTER SCHEMA public OWNER TO migrator;

REVOKE ALL ON DATABASE mattersolv_general FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT CONNECT ON DATABASE mattersolv_general TO general_altpro;
GRANT USAGE ON SCHEMA public TO general_altpro;
GRANT CONNECT ON DATABASE mattersolv_general TO platform;
GRANT USAGE ON SCHEMA public TO platform;

ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO general_altpro;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO general_altpro;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO platform;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO platform;

-- Fail loudly here rather than let the suite run without RLS enforcement.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'migrator' AND (rolsuper OR rolbypassrls)
    ) THEN
        RAISE EXCEPTION 'migrator must be NOSUPERUSER and NOBYPASSRLS';
    END IF;
END
$$;
SQL
