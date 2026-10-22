#!/usr/bin/env bash
# Start OmniRoute. Works on any platform where Node 22+ is installed.
# If OMNIROUTE_URL is already set (remote VM), skip — the gateway is remote.
set -euo pipefail

PORT="${OMNIROUTE_PORT:-20128}"

# If a remote OmniRoute is configured, don't start a local one
if [ -n "${OMNIROUTE_URL:-}" ]; then
  echo "[omniroute/start] Remote OmniRoute configured at $OMNIROUTE_URL — skipping local start"
  exit 0
fi

# Already running?
if nc -z localhost "$PORT" 2>/dev/null; then
  echo "[omniroute/start] Already running on port $PORT"
  exit 0
fi

# Find OmniRoute repo
OMNIROUTE_DIR="${OMNIROUTE_DIR:-}"
for candidate in \
  "$HOME/repos/OmniRoute" \
  "/opt/novaxorpus/OmniRoute" \
  "$(dirname "$(dirname "$(readlink -f "$0")")")/../OmniRoute"; do
  if [ -z "$OMNIROUTE_DIR" ] && [ -f "$candidate/bin/omniroute.mjs" ]; then
    OMNIROUTE_DIR="$candidate"
  fi
done

if [ -z "$OMNIROUTE_DIR" ] || [ ! -f "$OMNIROUTE_DIR/bin/omniroute.mjs" ]; then
  echo "[omniroute/start] ERROR: OmniRoute repo not found. Set OMNIROUTE_DIR or clone to ~/repos/OmniRoute" >&2
  exit 1
fi

cd "$OMNIROUTE_DIR"

# Install deps if needed
if [ ! -d node_modules ]; then
  echo "[omniroute/start] Installing dependencies..."
  if command -v pnpm &>/dev/null; then
    pnpm install --frozen-lockfile 2>/dev/null || pnpm install
  else
    npm install
  fi
fi

# Start in background
echo "[omniroute/start] Starting on port $PORT (pid file: /tmp/omniroute.pid)"
nohup node bin/omniroute.mjs --port "$PORT" > /tmp/omniroute.log 2>&1 &
echo $! > /tmp/omniroute.pid

# Wait for port
for i in $(seq 1 10); do
  if nc -z localhost "$PORT" 2>/dev/null; then
    echo "[omniroute/start] Running (pid $(cat /tmp/omniroute.pid))"
    exit 0
  fi
  sleep 1
done

echo "[omniroute/start] WARN: started but port $PORT not responding after 10s — check /tmp/omniroute.log" >&2
