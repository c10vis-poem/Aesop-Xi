#!/bin/sh
# Create /opt/dumbass/mem0.env once. LLM + embedding calls go through OmniRoute; its key is filled in after OmniRoute setup.
set -eu
f=/opt/dumbass/mem0.env
[ -f "$f" ] && { echo "exists: $f (kept)"; exit 0; }
. /opt/dumbass/.env
umask 077
cat > "$f" <<EOT
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=mem0
POSTGRES_USER=mem0
POSTGRES_PASSWORD=${MEM0_DB_PASSWORD}
POSTGRES_COLLECTION_NAME=memories
APP_DB_NAME=mem0_app
JWT_SECRET=$(openssl rand -hex 32)
ADMIN_API_KEY=$(openssl rand -hex 24)
AUTH_DISABLED=false
MEM0_TELEMETRY=false
DASHBOARD_URL=http://127.0.0.1:3000
OPENAI_BASE_URL=http://omniroute:20128/v1
OPENAI_API_KEY=set-after-omniroute-setup
EOT
echo "created: $f"
