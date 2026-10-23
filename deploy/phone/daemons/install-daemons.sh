#!/data/data/com.termux/files/usr/bin/bash
# Install AESOP daemons as termux-services (runit) services.
#
# Creates two supervised services:
#   llamad — llama-server · Gemma 4 12B IT QAT GGUF · port 8081 (GGML plane)
#   aesopd — WebSocket bridge · port 8765 (control/event plane)
#
# Why runit over tmux: sv restarts a crashed daemon automatically, survives
# `pkill`, and gives you `sv status llamad` at a glance. tmux stays useful
# for interactive sessions (OpenWiki), but the load-bearing processes get
# real supervision.
#
# Port map (device-wide loopback — never collide these):
#   8080  ort_engine   (app context, NPU/HTP)     ← DO NOT BIND FROM TERMUX
#   8081  llamad       (Termux, GGML/llama.cpp)
#   8091  media daemon (app context, STT/TTS)     ← DO NOT BIND FROM TERMUX
#   8765  aesopd       (Termux, WS bridge)
set -euo pipefail

if ! command -v sv &>/dev/null; then
  echo "termux-services not installed. Run: pkg install termux-services"
  echo "Then RESTART Termux (the service supervisor starts with the session)."
  exit 1
fi

SVDIR="$PREFIX/var/service"
AESOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# ── llamad ──────────────────────────────────────────────────────────
mkdir -p "$SVDIR/llamad/log"
cat > "$SVDIR/llamad/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
exec /data/data/com.termux/files/usr/bin/bash "$AESOP/deploy/phone/daemons/llamad-run"
EOF
cat > "$SVDIR/llamad/log/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
mkdir -p "$HOME/.aesop/log/llamad"
exec svlogd -tt "$HOME/.aesop/log/llamad"
EOF
chmod +x "$SVDIR/llamad/run" "$SVDIR/llamad/log/run"

# ── aesopd ──────────────────────────────────────────────────────────
mkdir -p "$SVDIR/aesopd/log"
cat > "$SVDIR/aesopd/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec 2>&1
export AESOP_DIR="$AESOP"
exec /data/data/com.termux/files/usr/bin/python3 "$AESOP/deploy/phone/bridge/aesopd.py"
EOF
cat > "$SVDIR/aesopd/log/run" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
mkdir -p "$HOME/.aesop/log/aesopd"
exec svlogd -tt "$HOME/.aesop/log/aesopd"
EOF
chmod +x "$SVDIR/aesopd/run" "$SVDIR/aesopd/log/run"

# ── enable ──────────────────────────────────────────────────────────
sv-enable llamad || true
sv-enable aesopd || true

echo ""
echo "=== AESOP daemons installed ==="
echo ""
echo "  sv status llamad    # Gemma 12B llama-server (8081)"
echo "  sv status aesopd    # WebSocket bridge (8765)"
echo "  sv restart llamad   # bounce after changing AESOP_MODEL"
echo "  sv-disable llamad   # stop + disable"
echo ""
echo "Logs: ~/.aesop/log/llamad/current, ~/.aesop/log/aesopd/current"
echo "Note: services start when the Termux session (supervisor) is up."
echo "      Keep termux-wake-lock held — device reboots daily."
