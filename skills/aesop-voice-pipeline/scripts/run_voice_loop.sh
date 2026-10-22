#!/data/data/com.termux/files/usr/bin/bash
# Fixed launcher for the aesop real-time voice engine (mic -> VAD -> STT -> TTS -> speaker).
# Replaces ~/repos/Aesop-Xi/voice-engine/scripts/run_live.sh, whose own PulseAudio socket
# discovery (`find ... -name "pulse-*"`) never matches a plainly-started daemon, which
# uses the fixed path .../tmp/pulse/native (no random suffix). Confirmed working
# end-to-end 2026-08-28 on a Moto Razr Ultra 2025 (Snapdragon, proot-distro debian).
#
# Usage:
#   run_voice_loop.sh              # live mic loop
#   run_voice_loop.sh --demo       # TTS -> speaker -> STT self-test, no mic
#
# Requires (installs itself if missing, on first run):
#   - sounddevice in /root/venv  (pip)
#   - /etc/asound.conf and /etc/pulse/client.conf in the debian proot

set -euo pipefail

AESOP_SCRIPT="/root/repos/Aesop-Xi/voice-engine/scripts/live_voice_loop.py"

log() { echo "[run_voice_loop] $*"; }

# --- 1. Make sure PulseAudio is actually running in Termux -------------------
# Do NOT try to kill and restart an existing daemon: on this device `pulseaudio -k`
# fails silently and something respawns a default-path instance anyway, so killing
# just wastes time. Work with whatever is already there.
if ! pactl info >/dev/null 2>&1; then
    log "PulseAudio not running, starting it..."
    pulseaudio --start -nF ~/pulse-noauth.pa --exit-idle-time=-1 --disable-shm >/dev/null 2>&1 || true
    sleep 2
fi

if ! pactl info >/dev/null 2>&1; then
    echo "ERROR: PulseAudio still not reachable. Check 'pactl info' manually." >&2
    exit 1
fi

# --- 2. Find the real socket dir, whatever it's actually named ---------------
# Covers both the plain default path (.../tmp/pulse) and a custom -nF instance
# (.../tmp/pulse-<random>). run_live.sh only ever checked the second form.
PULSE_SOCKET_DIR=""
for candidate in \
    /data/data/com.termux/files/usr/tmp/pulse \
    $(find /data/data/com.termux/files/usr/tmp -maxdepth 1 -iname "pulse-*" 2>/dev/null)
do
    if [ -S "$candidate/native" ]; then
        PULSE_SOCKET_DIR="$candidate"
        break
    fi
done

if [ -z "$PULSE_SOCKET_DIR" ]; then
    echo "ERROR: no live PulseAudio socket found under .../tmp/pulse*" >&2
    exit 1
fi
log "Using PulseAudio socket: $PULSE_SOCKET_DIR/native"

# --- 3. Idempotently ensure the two proot-side audio config fixes exist ------
# Bug A: Debian's portaudio19 has no native Pulse hostapi (confirmed via
#   sounddevice.query_hostapis() -> only ALSA/OSS, both with zero devices).
#   Fix: route ALSA's default device through the pulse ALSA plugin.
# Bug B: connecting via pactl/sounddevice from inside the proot over the bind-mount
#   fails with "Protocol error" unless SHM is disabled on the CLIENT side too --
#   the server's --disable-shm flag alone was not enough once a persistent
#   default-path daemon was already running.
proot-distro login debian -- bash -c '
    if [ ! -f /etc/asound.conf ]; then
        cat > /etc/asound.conf << "EOF"
pcm.!default { type pulse }
ctl.!default { type pulse }
EOF
    fi
    mkdir -p /etc/pulse
    if ! grep -q "enable-shm = no" /etc/pulse/client.conf 2>/dev/null; then
        echo "enable-shm = no" >> /etc/pulse/client.conf
    fi
'

# --- 4. Run it ----------------------------------------------------------------
exec proot-distro login debian \
    --bind "$PULSE_SOCKET_DIR":/tmp/pulse-termux \
    -- env \
        PULSE_SERVER=unix:/tmp/pulse-termux/native \
        AESOP_MODELS_DIR=/root/models \
        python3 "$AESOP_SCRIPT" "$@"
