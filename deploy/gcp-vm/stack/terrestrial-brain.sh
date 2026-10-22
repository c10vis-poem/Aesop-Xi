#!/bin/bash
# Install Terrestrial Brain MCP from the c10vis-poem fork as a systemd service on :8000.
# Needs the dumbass Postgres (compose.yaml) up and /opt/dumbass/.env present. Safe to re-run.
set -euo pipefail
R=~/repos/NvAEx-terrestrial-brain
E=/opt/dumbass/tb.env

if [ -d "$R/.git" ]; then git -C "$R" pull -q --ff-only; else
  mkdir -p ~/repos && git clone -q https://github.com/c10vis-poem/NvAEx-terrestrial-brain.git "$R"; fi
echo "terrestrial-brain @ $(git -C "$R" log -1 --format='%h %cs')"
(cd "$R/local-mcp" && npm install --silent --no-audit --no-fund)

if [ ! -f "$E" ]; then
  . /opt/dumbass/.env
  umask 077
  cat > "$E" <<EOF
LOCAL_PG_URL=postgres://brain_app:${TB_DB_PASSWORD}@127.0.0.1:5432/terrestrial_brain
MCP_ACCESS_KEY=$(openssl rand -hex 24)
OPENROUTER_BASE=http://127.0.0.1:20128/v1
OPENROUTER_API_KEY=set-after-omniroute-setup
VAULT_MEMORIES_DIR=$HOME/vault/memories
EOF
  echo "created $E"
fi

sudo tee /etc/systemd/system/terrestrial-brain.service >/dev/null <<EOF
[Unit]
Description=Terrestrial Brain MCP
After=docker.service network-online.target
Wants=network-online.target

[Service]
User=$USER
WorkingDirectory=$R/supabase/functions/terrestrial-brain-mcp
EnvironmentFile=$E
ExecStart=$R/local-mcp/node_modules/.bin/deno run --allow-net --allow-env --allow-read --allow-write index.ts
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now terrestrial-brain
