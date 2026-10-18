#!/bin/bash
# Rebuild the terrestrial_brain schema from the repo's migrations (mirrors local-mcp/setup.sh), against dockerized Postgres.
# DESTRUCTIVE to the terrestrial_brain database only. Reports every migration that errors.
set -uo pipefail
cd /opt/dumbass
P="docker compose exec -T postgres"
. /opt/dumbass/.env
$P psql -q -U postgres -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS terrestrial_brain;
CREATE DATABASE terrestrial_brain OWNER brain_app;
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END \$\$;
GRANT service_role TO brain_app;
SQL
$P psql -q -U postgres -d terrestrial_brain -v ON_ERROR_STOP=1 <<SQL
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS \$f\$ SELECT 'service_role'::text; \$f\$;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS \$f\$ SELECT NULL::uuid; \$f\$;
GRANT ALL ON SCHEMA extensions TO brain_app;
GRANT ALL ON SCHEMA public TO brain_app;
GRANT USAGE ON SCHEMA auth TO brain_app;
GRANT EXECUTE ON FUNCTION auth.role() TO brain_app;
GRANT EXECUTE ON FUNCTION auth.uid() TO brain_app;
ALTER DATABASE terrestrial_brain SET search_path TO public, extensions;
SQL
ok=0; bad=0
for f in ~/repos/NvAEx-terrestrial-brain/supabase/migrations/*.sql; do
  out=$(docker compose exec -T -e PGPASSWORD="$TB_DB_PASSWORD" postgres psql -h 127.0.0.1 -U brain_app -d terrestrial_brain -v ON_ERROR_STOP=1 -q < "$f" 2>&1)
  if [ $? -eq 0 ]; then ok=$((ok+1)); else bad=$((bad+1)); echo "FAIL $(basename $f): $(echo "$out" | grep -m1 -i error | cut -c1-150)"; fi
done
echo "migrations: $ok ok, $bad failed"
docker compose exec -T -e PGPASSWORD="$TB_DB_PASSWORD" postgres psql -h 127.0.0.1 -U brain_app -d terrestrial_brain -q -c "revoke execute on all functions in schema public from public, anon, authenticated; grant execute on all functions in schema public to service_role;" 2>&1 | grep -i error
docker compose exec -T postgres psql -U postgres -d terrestrial_brain -At -c "select count(*) from information_schema.tables where table_schema='public'" | sed 's/^/public tables: /'
