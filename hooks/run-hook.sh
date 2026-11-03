#!/usr/bin/env bash
# Project-level launcher for every hook (registered in Aesop-Xi/.claude/settings.json).
# - If this device already has a REAL global copy (~/.claude/hooks/<name>, wired in user settings),
#   that one runs and this exits 0, so nothing fires twice. An exit-0 stub there (operator order
#   2026-10-28) does not count: the project copy runs instead.
# - Every hook runs on every device, cloud sessions included. Cloud differences are handled inside the
#   hooks through hooks/lib/env.sh.
# - A hook may not crash or hang a session: it runs under a watchdog (AESOP_HOOK_TIMEOUT, default 8 s;
#   SessionEnd ship uses its own detach). A timeout or an internal error (any exit other than 0 or 2)
#   is logged to ~/.claude/state/hooks.log and the call is allowed (fail-open).
#
# SAFETY NET (operator, 2026-11-03). The operator always wins over every hook:
#   1. Master switch: a prompt the operator types containing "#hooks-off" (or "hooks off",
#      "turn the hooks off", "kill the hooks", "disable the hooks") turns EVERY hook off, on this
#      device, across sessions, until a prompt contains "#hooks-on" (or "hooks on", "turn the hooks
#      back on"). Env AESOP_HOOKS_OFF=1 does the same for one launch.
#   2. Operator override: a prompt matching any line of hooks/override-phrases.txt ("override",
#      "I told you", "go ahead", "just do it", "you can read it", "this is what I want", ...)
#      lets every block through for the rest of that turn. The hooks still run and log; nothing blocks.
#   3. Loop breaker: the same hook may block at most AESOP_MAX_BLOCKS times (default 2) in one turn,
#      and all hooks together at most AESOP_MAX_TURN_BLOCKS times (default 6). Past that, it yields
#      and logs LOOP-BREAKER. A turn starts at each operator prompt.
#   Every block carries a footer telling the agent these controls exist and not to hand the operator
#   either/or choices.
name="$1"; shift
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
st="${STATE_DIR:-$HOME/.claude/state}"; mkdir -p "$st" 2>/dev/null
log() { echo "$(date '+%F %T') $*" >> "$st/hooks.log" 2>/dev/null; }

g="$HOME/.claude/hooks/$name"
if [ -x "$g" ] && grep -vE '^[[:space:]]*(#|$)' "$g" | grep -qvE '^[[:space:]]*(exit 0|true|:)[[:space:]]*$'; then
  exit 0
fi
[ -f "$here/$name" ] || exit 0

input=$(cat)
j() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }
sid=$(j .session_id); sid=${sid:-x}; ev=$(j .hook_event_name)

# --- operator controls, read from what the operator typed ---------------------------------------
if [ "$ev" = UserPromptSubmit ]; then
  prompt=$(j .prompt)
  if ! grep -qE '<agent-message|<task-notification>|^Another Claude session sent a message' <<<"$prompt"; then
    rm -f "$st/blocks-$sid-"* "$st/override-$sid" 2>/dev/null          # a new turn starts
    if grep -qiE '#hooks-on|\bhooks (back )?on\b|turn (all )?(the )?hooks (back )?on' <<<"$prompt"; then
      rm -f "$st/hooks-off"; log "MASTER hooks ON (operator)"
    elif grep -qiE '#hooks-off|\bhooks off\b|turn (all )?(the )?hooks off|kill (all )?(the )?hooks|disable (all )?(the )?hooks' <<<"$prompt"; then
      : > "$st/hooks-off"; log "MASTER hooks OFF (operator)"
    fi
    pf="$here/override-phrases.txt"
    if [ -f "$pf" ] && grep -qiEf <(grep -vE '^[[:space:]]*(#[^a-z]|$)' "$pf") <<<"$prompt"; then
      : > "$st/override-$sid"; log "OVERRIDE this turn (operator) sid=$sid"
    fi
  fi
fi

if [ -e "$st/hooks-off" ] || [ "${AESOP_HOOKS_OFF:-}" = 1 ]; then
  if [ "$ev" = SessionStart ] && [ ! -e "$st/hooks-off-noted-$sid" ]; then
    : > "$st/hooks-off-noted-$sid"
    echo "NOTE: every Aesop-Xi hook is OFF (operator master switch). The operator types #hooks-on to turn them back on."
  fi
  exit 0
fi

# --- run the hook -------------------------------------------------------------------------------
tmo=${AESOP_HOOK_TIMEOUT:-8}
case $name in ship-session.sh|archive-scratchpad.sh|sync-on-use.sh) tmo=${AESOP_HOOK_TIMEOUT:-60} ;; esac
out=$(mktemp); err=$(mktemp); trap 'rm -f "$out" "$err"' EXIT
if command -v timeout >/dev/null 2>&1; then
  timeout -k 2 "$tmo" bash "$here/$name" "$@" <<<"$input" >"$out" 2>"$err"; rc=$?
else
  bash "$here/$name" "$@" <<<"$input" >"$out" 2>"$err"; rc=$?
fi
case $rc in
  0|2) ;;
  124|137) log "$name TIMEOUT after ${tmo}s (allowed)"; exit 0 ;;
  *)       log "$name ERROR exit $rc (allowed)"; exit 0 ;;
esac

blocked=0
[ "$rc" = 2 ] && blocked=1
grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"|"permissionDecision"[[:space:]]*:[[:space:]]*"deny"|"continue"[[:space:]]*:[[:space:]]*false' "$out" && blocked=1

if [ "$blocked" = 0 ]; then cat "$out"; cat "$err" >&2; exit "$rc"; fi

# --- a block: override, loop breaker, or pass it through with the footer ------------------------
if [ -e "$st/override-$sid" ]; then
  log "$name block LET THROUGH (operator override this turn)"; exit 0
fi
n=$(( $(cat "$st/blocks-$sid-$name" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/blocks-$sid-$name"
t=$(( $(cat "$st/blocks-$sid-_turn" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$st/blocks-$sid-_turn"
if [ "$n" -gt "${AESOP_MAX_BLOCKS:-2}" ] || [ "$t" -gt "${AESOP_MAX_TURN_BLOCKS:-6}" ]; then
  log "$name LOOP-BREAKER yielded (block $n of this hook, $t this turn)"; exit 0
fi
foot="(Hook safety net: the operator overrides any hook by saying so, e.g. \"override\", \"go ahead\", \"I told you\"; #hooks-off turns every hook off. This gate yields after ${AESOP_MAX_BLOCKS:-2} blocks per turn. Do not hand the operator either/or choices to clear a gate: do what they said, or state the one thing that is missing.)"
if [ "$rc" = 2 ]; then
  cat "$out"; cat "$err" >&2; echo "$foot" >&2; exit 2
fi
if jq -e . "$out" >/dev/null 2>&1; then
  jq --arg f "$foot" 'if has("reason") then .reason += "\n" + $f
    elif (.hookSpecificOutput.permissionDecisionReason? // null) != null then .hookSpecificOutput.permissionDecisionReason += "\n" + $f
    else . end' "$out"
else
  cat "$out"
fi
cat "$err" >&2; exit 0
