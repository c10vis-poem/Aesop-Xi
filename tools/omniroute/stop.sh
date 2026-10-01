#!/usr/bin/env bash
# Stop local OmniRoute
if [ -f /tmp/omniroute.pid ]; then
  kill "$(cat /tmp/omniroute.pid)" 2>/dev/null && echo "[omniroute/stop] Stopped" || echo "[omniroute/stop] Already dead"
  rm -f /tmp/omniroute.pid
else
  echo "[omniroute/stop] No pid file"
fi
