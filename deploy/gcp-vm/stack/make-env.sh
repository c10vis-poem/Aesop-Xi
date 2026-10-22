#!/bin/sh
# Create /opt/dumbass/.env with random passwords, once. Never prints the values.
set -eu
f=/opt/dumbass/.env
[ -f "$f" ] && { echo "exists: $f (kept)"; exit 0; }
umask 077
{
  echo "POSTGRES_PASSWORD=$(openssl rand -hex 24)"
  echo "TB_DB_PASSWORD=$(openssl rand -hex 24)"
  echo "MEM0_DB_PASSWORD=$(openssl rand -hex 24)"
  echo "NEO4J_PASSWORD=$(openssl rand -hex 24)"
} > "$f"
echo "created: $f"
