#!/bin/bash
# Runs once, on first start of an empty Postgres volume: one role + database per service.
set -euo pipefail
psql -v ON_ERROR_STOP=1 -U postgres <<EOSQL
CREATE ROLE brain_app LOGIN PASSWORD '${TB_DB_PASSWORD}';
CREATE DATABASE terrestrial_brain OWNER brain_app;
CREATE ROLE mem0 LOGIN PASSWORD '${MEM0_DB_PASSWORD}';
CREATE DATABASE mem0 OWNER mem0;
CREATE DATABASE mem0_app OWNER mem0;
EOSQL
for db in terrestrial_brain mem0; do
  psql -v ON_ERROR_STOP=1 -U postgres -d "$db" -c "CREATE EXTENSION IF NOT EXISTS vector;"
done
