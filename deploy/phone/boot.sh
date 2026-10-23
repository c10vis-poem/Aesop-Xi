#!/data/data/com.termux/files/usr/bin/bash
# AESOP boot script — starts LLM server + voice pipeline in tmux
# Survives screen-off. Run: bash ~/aesop/deploy/phone/boot.sh
#
# To auto-run on Termux launch, add to ~/.bashrc:
#   [ -z "$TMUX" ] && bash ~/aesop/deploy/phone/boot.sh
set -euo pipefail

# PORT 8081, not 8080: the Horizons app's ort_engine (NPU daemon) owns
# 8080 on this device, and the media daemon owns 8091. Loopback is shared
# across all Android apps — binding 8080 here collides with the NPU plane.
# Full port map: aesop/protocol/bridge-protocol.md
# Q4_0 quant specifically — llama.cpp repacks Q4_0 to the ARM-optimized
# layout on Snapdragon; faster than Q4_K_* here. Keep the q4_0 file.
MODEL="${AESOP_MODEL:-$HOME/models/gemma-4-12b-it-qat-q4_0.gguf}"
PORT="${AESOP_PORT:-8081}"
CTX="${AESOP_CTX:-4096}"

# ── Prefer supervised daemons when installed ────────────────────────
# install-daemons.sh sets up runit services (llamad + aesopd) with
# auto-restart. If they exist, use them and skip the tmux path for the LLM.
if [ -d "$PREFIX/var/service/llamad" ] && command -v sv &>/dev/null; then
  echo "Supervised daemons detected — starting via termux-services..."
  termux-wake-lock 2>/dev/null || true
  sv up llamad 2>/dev/null || true
  sv up aesopd 2>/dev/null || true
  echo "  sv status llamad aesopd:"
  sv status llamad aesopd 2>/dev/null || true
  echo ""
  echo "  GGML API:  http://localhost:8081/v1  (Gemma 12B · llama.cpp)"
  echo "  Bridge:    ws://localhost:8765       (aesopd)"
  echo "  NPU API:   http://localhost:8080     (app ort_engine, if running)"
  exit 0
fi

# ── Sanity checks ───────────────────────────────────────────────────
if [ ! -f "$MODEL" ]; then
  echo "Model not found: $MODEL"
  echo "Set AESOP_MODEL to your .gguf path, or download one to ~/models/"
  echo ""
  echo "Available .gguf files:"
  find ~/models /sdcard/Download -name '*.gguf' 2>/dev/null | head -10 || echo "  (none found)"
  exit 1
fi

if ! command -v tmux &>/dev/null; then
  echo "tmux not installed. Run: pkg install tmux"
  exit 1
fi

# ── Wake lock ────────────────────────────────────────────────────────
echo "Acquiring wake lock..."
termux-wake-lock 2>/dev/null || true

# ── Kill existing sessions if re-running ─────────────────────────────
tmux kill-session -t llm 2>/dev/null || true
tmux kill-session -t openwiki 2>/dev/null || true

# ── Start LLM server ────────────────────────────────────────────────
echo "Starting llama-server (model: $(basename "$MODEL"), ctx: $CTX, port: $PORT)..."
LLAMA_LOG="${PREFIX:-/data/data/com.termux/files/usr}/tmp/llama-server.log"
tmux new-session -d -s llm "llama-server -m '$MODEL' -c $CTX --host 127.0.0.1 --port $PORT 2>&1 | tee '$LLAMA_LOG'"

# Wait for server to come up
echo -n "Waiting for server..."
for i in $(seq 1 60); do
  if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
    echo " ready! (${i}s)"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo " timed out after 60s."
    echo "Check logs: tmux attach -t llm"
    echo "Or:         cat $LLAMA_LOG"
    exit 1
  fi
  sleep 1
  echo -n "."
done

# ── Start OpenWiki (optional) ────────────────────────────────────────
if command -v ow &>/dev/null || command -v openwiki &>/dev/null; then
  OW_CMD=$(command -v ow 2>/dev/null || command -v openwiki)
  echo "Starting OpenWiki CLI in tmux..."
  tmux new-session -d -s openwiki "export LANGCHAIN_TRACING_V2=false LANGSMITH_TRACING=false; cd ~/vault 2>/dev/null || cd ~; $OW_CMD"
fi

# ── Status ───────────────────────────────────────────────────────────
echo ""
echo "=== AESOP Edge Online ==="
echo ""
echo "  LLM API:    http://localhost:$PORT/v1"
echo "  Model:      $(basename "$MODEL")"
echo "  Context:    $CTX tokens"
echo "  Wake lock:  active"
echo ""
echo "tmux sessions:"
tmux ls 2>/dev/null
echo ""
echo "Commands:"
echo "  tmux attach -t llm       # watch LLM server"
echo "  tmux attach -t openwiki  # interact with OpenWiki"
echo "  termux-wake-unlock       # release wake lock when done"
echo ""
echo "Voice pipeline ready — use OpenWiki Ctrl+R or run:"
echo '  proot-distro login debian --bind ~:~ -- python3 ~/aesop/deploy/phone/stt_process.py <audio>'
