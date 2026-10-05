#!/data/data/com.termux/files/usr/bin/bash
# aesop-xi/tools/bootstrap.sh
#
# Canonical bootstrap for the NovÆxorpus stack. Every other base repo's
# tools/bootstrap.sh is a thin wrapper that calls this first, then does
# repo-specific post-boot. Idempotent, fast on hot start, loud on failure.
#
# Triggers: AGENTS.md instruction on session start, git post-checkout hook,
# or manual `bash tools/bootstrap.sh`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AESOP_XI_ROOT="${AESOP_XI_ROOT:-$HOME/repos/aesop-xi}"

log() { echo "[bootstrap $(basename "$REPO_ROOT")] $*"; }
warn() { echo "[bootstrap $(basename "$REPO_ROOT")] WARN: $*" >&2; }
fail() { echo "[bootstrap $(basename "$REPO_ROOT")] ERROR: $*" >&2; exit 1; }

# ---------- 1. Git sync with origin/main (git-sink) ----------
cd "$REPO_ROOT"
if git rev-parse --git-dir >/dev/null 2>&1; then
  git fetch origin --quiet
  branch=$(git branch --show-current)
  if [ "$branch" != "main" ]; then
    log "on branch $branch, not main — leaving alone (bootstrap doesn't switch branches)"
  else
    git pull --ff-only origin main --quiet || warn "ff-pull failed (divergent local main?)"
  fi
fi

# ---------- 2. Load secrets from home-scoped .env files (never committed) ----------
for envfile in "$HOME/.mem0/.env" "$HOME/.openwiki/.env" "$HOME/.omniroute/.env"; do
  if [ -f "$envfile" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$envfile"
    set +a
    log "loaded $envfile"
  fi
done
# terrestrial-brain's own env
if [ -f "$HOME/repos/NovA-terrestrial-brain/local-mcp/.env.local" ]; then
  set -a
  . "$HOME/repos/NovA-terrestrial-brain/local-mcp/.env.local"
  set +a
fi

# ---------- 3. Bring up runtime deps (idempotent) ----------

# 3a. Postgres for terrestrial-brain
if ! nc -z localhost 5432 2>/dev/null; then
  if [ -d "$HOME/pgdata" ]; then
    log "starting Postgres from $HOME/pgdata"
    pg_ctl -D "$HOME/pgdata" -l "$HOME/pgdata.log" start >/dev/null || warn "pg_ctl start failed"
  else
    warn "no ~/pgdata — run 'initdb -D ~/pgdata -E UTF8 --auth-local=trust --auth-host=trust' first"
  fi
fi

# 3b. pgvector extension (checked, not created here — schema init is terrestrial-brain's job)
psql -h localhost -d postgres -tAc "SELECT default_version FROM pg_available_extensions WHERE name='vector';" 2>/dev/null | grep -q '^[0-9]' \
  || warn "pgvector extension not available on this Postgres — build from source with SHLIB_LINK='-lm'"

# 3c. terrestrial-brain MCP on 8000
if ! nc -z localhost 8000 2>/dev/null; then
  TB_MCP_DIR="$HOME/repos/NovA-terrestrial-brain/supabase/functions/terrestrial-brain-mcp"
  if [ ! -d "$TB_MCP_DIR" ]; then
    TB_MCP_DIR="/opt/novaxorpus/NovA-terrestrial-brain/supabase/functions/terrestrial-brain-mcp"
  fi
  if [ -d "$TB_MCP_DIR" ] && [ -f "$TB_MCP_DIR/index.ts" ]; then
    log "starting terrestrial-brain MCP"
    TB_ENV="$HOME/repos/NovA-terrestrial-brain/local-mcp/.env.local"
    [ -f "$TB_ENV" ] || TB_ENV="/opt/novaxorpus/NovA-terrestrial-brain/local-mcp/.env.local"
    if [ -f "$TB_ENV" ]; then
      _MCP_KEY=$(grep MCP_ACCESS_KEY "$TB_ENV" | cut -d= -f2)
      cd "$TB_MCP_DIR"
      LOCAL_PG_URL="postgres://brain_app:brain_local_dev@127.0.0.1:5432/terrestrial_brain" \
        MCP_ACCESS_KEY="$_MCP_KEY" \
        OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}" \
        nohup deno run --allow-net --allow-env --allow-read --allow-write index.ts > /tmp/terrestrial-brain.log 2>&1 &
      echo $! > /tmp/terrestrial-brain.pid
      sleep 2
      if nc -z localhost 8000 2>/dev/null; then
        log "terrestrial-brain MCP running (pid $(cat /tmp/terrestrial-brain.pid))"
      else
        warn "terrestrial-brain started but port 8000 not responding — check /tmp/terrestrial-brain.log"
      fi
      cd "$REPO_ROOT"
    else
      warn "terrestrial-brain .env.local not found — skipping"
    fi
  else
    warn "terrestrial-brain repo not found — skipping"
  fi
fi

# 3d. OmniRoute gateway on 20128
if ! nc -z localhost 20128 2>/dev/null; then
  if [ -x "$AESOP_XI_ROOT/tools/omniroute/start.sh" ]; then
    log "starting OmniRoute"
    bash "$AESOP_XI_ROOT/tools/omniroute/start.sh"
  else
    warn "OmniRoute start script missing at $AESOP_XI_ROOT/tools/omniroute/start.sh — skipping"
  fi
fi

# 3e. mem0 backend — hosted MCP; verify key is present
if [ -z "${MEM0_API_KEY:-}" ]; then
  warn "MEM0_API_KEY not set — mem0 layer will be inert. Fix: paste key into ~/.mem0/.env"
fi

# ---------- 4. Sanity-check installed Claude Code skills ----------
for skill in task-observer honey-ccr graphify obsidian-vault corpus-batch-processing memory-triage; do
  [ -d "$HOME/.claude/skills/$skill" ] || warn "skill $skill missing from ~/.claude/skills/"
done

# ---------- 5. Verify round-trip: OmniRoute /health ----------
if nc -z localhost 20128 2>/dev/null; then
  if curl -sf "http://localhost:20128/health" >/dev/null 2>&1; then
    log "OmniRoute /health OK"
  else
    warn "OmniRoute bound but /health not responding"
  fi
fi

# ---------- 6. Ready ----------
rev=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git")
log "ready. repo=$(basename "$REPO_ROOT") branch=$(git branch --show-current 2>/dev/null || echo unknown) rev=$rev"
