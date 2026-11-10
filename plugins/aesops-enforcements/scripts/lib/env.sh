#!/usr/bin/env bash
# Shared environment for every aesops-enforcements hook. Sourced, never run. Works on the phone (Termux) and in
# cloud sessions (CLAUDE_CODE_REMOTE=true) without changing what the gates require: the same rules
# run everywhere; only the paths and the fail-open behaviour for missing phone-only tools differ.
#
# Exports:
#   AESOP_CLOUD   1 in a cloud session (CLAUDE_CODE_REMOTE=true and not Termux), else 0
#   ST            state dir ($HOME/.claude/state), created
#   VAULT         the NovAExorpus vault checkout, or "" when none is reachable (see vault_find)
#   VAULT_OK      1 when $VAULT is a directory
#   HOOKS_DIR     directory of the hook sources being run (<plugin>/scripts)
#   RECAPS_DIR    session recaps ($ST/recaps): kept out of the vault (CONTRACT rule 8), same on every device
#   PATH          extended with $HOME/bin, $HOME/.local/bin and the plugin's bin/, so
#                 resume-item / observe-dismiss resolve on any device
# Functions:
#   vault_find    prints the vault path (env AESOP_VAULT or VAULT > phone path > $HOME/NovAExorpus >
#                 any checkout under $HOME, $HOME/repos, $CLAUDE_PROJECT_DIR/.. whose origin is NovAExorpus;
#                 result cached in $ST/vault-path for the session host)
#   hook_log MSG  appends a line to $ST/hooks.log (never fails)
#   advise KEY MSG  prints MSG once per session+KEY (for conditions this environment cannot satisfy:
#                 the gate does not block on them, it reports them; on the phone they still block)
#   degrade KEY MSG  appends "DEGRADE MSG" to hooks.log once per session+KEY: a phone-only path or
#                 tool is absent here, so the hook carries on instead of blocking (README, Cloud)
#   ghq ARGS      gh with a 15 s timeout; prints nothing and returns 1 when gh is missing or slow
#   resume_date FILE  prints the newest YYYY-MM-DD in the first 40 lines of FILE, or ""
#   is_operator_prompt TEXT  true when TEXT is an operator-typed prompt, not a subagent hand-back
#                 (<agent-message>, <task-notification>, "Another Claude session sent a message")
[ -n "${AESOP_ENV_LOADED:-}" ] && return 0 2>/dev/null
AESOP_ENV_LOADED=1
HOOKS_DIR=${HOOKS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
ST=${STATE_DIR:-$HOME/.claude/state}; mkdir -p "$ST" 2>/dev/null
case ${PREFIX:-} in *com.termux*) AESOP_CLOUD=0 ;; *) [ "${CLAUDE_CODE_REMOTE:-}" = true ] && AESOP_CLOUD=1 || AESOP_CLOUD=0 ;; esac
RECAPS_DIR=${RECAPS_DIR:-$ST/recaps}
export AESOP_CLOUD ST HOOKS_DIR RECAPS_DIR
for d in "$HOME/bin" "$HOME/.local/bin" "$HOOKS_DIR/../bin"; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$PATH:$d" ;; esac
done
export PATH

hook_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$ST/hooks.log" 2>/dev/null; }

vault_find() {
  local c="$ST/vault-path" p
  for p in "${AESOP_VAULT:-}" "${VAULT:-}"; do [ -n "$p" ] && [ -d "$p" ] && { echo "$p"; return; }; done
  if [ -s "$c" ]; then p=$(cat "$c"); [ -d "$p" ] && { echo "$p"; return; }; fi
  for p in "$HOME/storage/shared/Documents/NovAExorpus" "$HOME/NovAExorpus" "$HOME/novaexorpus" \
           "$HOME/repos/NovAExorpus" "${CLAUDE_PROJECT_DIR:+$(dirname "$CLAUDE_PROJECT_DIR")/novaexorpus}" \
           "${CLAUDE_PROJECT_DIR:+$(dirname "$CLAUDE_PROJECT_DIR")/NovAExorpus}"; do
    [ -n "$p" ] && [ -d "$p" ] && { echo "$p" > "$c" 2>/dev/null; echo "$p"; return; }
  done
  for p in "$HOME"/*/ "$HOME"/repos/*/ "${CLAUDE_PROJECT_DIR:+$(dirname "$CLAUDE_PROJECT_DIR")}"/*/; do
    [ -d "$p/.git" ] || continue
    case $(git -C "$p" remote get-url origin 2>/dev/null) in
      *[Nn]ov[Aa][Ee]xorpus*) p=${p%/}; echo "$p" > "$c" 2>/dev/null; echo "$p"; return ;;
    esac
  done
}
VAULT=$(vault_find); [ -d "${VAULT:-/nonexistent}" ] && VAULT_OK=1 || VAULT_OK=0
export VAULT VAULT_OK

advise() {  # advise KEY MSG -> MSG once per session+key (sid from $sid when set)
  local f="$ST/advised-${sid:-x}-$1"
  [ -e "$f" ] && return 0
  : > "$f" 2>/dev/null; echo "NOTE (hooks, cloud degrade): $2"
}

degrade() {  # degrade KEY MSG -> one DEGRADE line in hooks.log per session+key (sid from $sid when set)
  local f="$ST/degraded-${sid:-x}-$1"
  [ -e "$f" ] && return 0
  : > "$f" 2>/dev/null; hook_log "DEGRADE $2"
}

ghq() { command -v gh >/dev/null 2>&1 || return 1; timeout "${GH_TIMEOUT:-15}" gh "$@" 2>/dev/null; }

resume_date() { head -40 "$1" 2>/dev/null | grep -oE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort | tail -1; }

is_operator_prompt() { ! grep -qE '<agent-message|<task-notification>|^Another Claude session sent a message' <<<"$1"; }
