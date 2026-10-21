#!/bin/bash
# Auto-bootstrap aesop-xi's own orchestration stack on every fresh session
# opened here, cloud or local. aesop-xi owns this logic directly (scripts/
# bootstrap-stack.sh) — it does not reach into any harness's own bootstrap
# script. Which agent harness(es) get installed is decided purely by which
# harness repo(s) (ECC-aesop, NvAEx-prime-agent) are attached as siblings this
# session — no separate variable to set.
#
# Previously gated on CLAUDE_CODE_REMOTE=true (cloud-only). Dropped 2026-09-06
# at the operator's explicit direction: local/Termux sessions should get the
# identical bootstrap, not a lesser one, just because they're on the phone.
set -uo pipefail

echo '{"async": true, "asyncTimeout": 590000}'

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT="$PROJECT_DIR/scripts/bootstrap-stack.sh"
LOG="$PROJECT_DIR/.session-start-bootstrap.log"

if [ -x "$SCRIPT" ]; then
  bash "$SCRIPT" >> "$LOG" 2>&1
else
  echo "[bootstrap] skip: $SCRIPT not found" >> "$LOG" 2>&1
fi

# Commit + push the log so proof this ran survives this (disposable) session's
# container — the raw log, not a fixed-schema summary, since which harnesses/
# assets are present varies session to session and a schema would need to
# keep changing to match. Best-effort: never fail the session over this.
(
  cd "$PROJECT_DIR" \
    && git add -f "$(basename "$LOG")" \
    && git commit -q -m "chore: session-start bootstrap log $(date -u +%Y-%m-%dT%H:%M:%SZ)" -- "$(basename "$LOG")" \
    && git push -q origin main
) >> "$LOG" 2>&1 || echo "[bootstrap] log commit/push failed — see above" >> "$LOG" 2>&1
