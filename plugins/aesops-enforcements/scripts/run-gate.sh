#!/usr/bin/env bash
# The one launcher. hooks/hooks.json calls `run-gate.sh --event <Event>`; rows of gates.tsv run in order.
# `run-gate.sh <hook> [args]` runs one hook the same way.
#   1. kill switches first: ~/.nvaex-hooks-off, off/aesops-enforcements (killswitch.sh), then per hook off/<hook>,
#      off/aesops-enforcements.<hook>; #hooks-off typed by the operator sets state/hooks-off until #hooks-on.
#   2. a script that is MISSING is logged, recorded in state/gate-missing, told to the agent and reported
#      by `gate status`; it cannot pass silently. A crash or timeout is allowed and logged (fail-open).
#   3. exit 2 counts as a block only with "BLOCKED (" on stderr: bash and jq also exit 2 on their own
#      errors, and a broken hook must not lock the session.
#   4. a block is dropped by the hook's verb in the operator's latest prompt, or by an override phrase
#      that prompt matched (override-phrases.txt, this turn). Subagent hand-backs never count.
#   5. loop breaker (PR #84): the same call blocked more than AESOP_MAX_BLOCKS times (2), or more than
#      AESOP_MAX_TURN_BLOCKS blocks (6) from one agent in a turn, and the gate yields and logs
#      LOOP-BREAKER. A turn starts at each operator prompt.
#   6. every block that stands names the override and the revoke.
# Hard guards (secret-guard, guard) skip 4's phrases and 5: each stops one named
# action, so it cannot deadlock a session, and yielding on retry would hand the agent the operator's
# settings or secrets. The operator still has `! <command>` and `gate off <hook>`.
here=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd); root=${here%/*}; pkg=aesops-enforcements
sh "$here/killswitch.sh" "$pkg" 2>/dev/null && exit 0
st=${STATE_DIR:-$HOME/.claude/state}; off=$HOME/.claude/state/off; mkdir -p "$st" "$off" 2>/dev/null
table=$here/gates.tsv; hard=" secret-guard guard direction-gate "
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$st/hooks.log" 2>/dev/null; }

event=; if [ "$1" = --event ]; then event=$2; shift 2; else one=${1%.sh}; shift; fi
in=$(cat)
if ! command -v jq >/dev/null 2>&1; then
  log "DEGRADE no jq on this device: every hook needs it, ${event:-$one} did NOT run (allowed)"; exit 0
fi
IFS=$'\x1f' read -r sid aid tool tp < <(jq -r '[.session_id // "x", .agent_id // "main", .tool_name // "", .transcript_path // ""] | join("\u001f")' <<<"$in" 2>/dev/null)
sid=${sid:-x}; aid=${aid:-main}; aid=${aid//[^A-Za-z0-9_-]/_}; tp=${tp/#\~/$HOME}

is_handback() { grep -qE '<agent-message|<task-notification>|^Another Claude session sent a message' <<<"$1"; }
if [ "$event" = UserPromptSubmit ]; then
  p=$(jq -r '.prompt // ""' <<<"$in")
  if ! is_handback "$p"; then
    rm -f "${st:?}/blocks-$sid-"* "${st:?}/override-$sid" 2>/dev/null          # a new turn starts
    printf '%s\n' "$p" > "$st/prompt-$sid.txt"
    if grep -q '#hooks-on' <<<"$p"; then rm -f "${st:?}/hooks-off"; log "MASTER hooks ON (operator)"
    elif grep -q '#hooks-off' <<<"$p"; then : > "$st/hooks-off"; log "MASTER hooks OFF (operator)"; fi
    grep -q '#no-ship' <<<"$p" && : > "$st/noship-$sid"
    if grep -qiEf <(grep -vE '^[[:space:]]*(#[^a-z]|$)' "$here/override-phrases.txt" 2>/dev/null) <<<"$p"; then
      : > "$st/override-$sid"; log "OVERRIDE this turn (operator) sid=$sid"
    fi
  fi
fi
if [ -e "$st/hooks-off" ]; then
  [ "$event" = SessionStart ] && jq -n '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:"NOTE: every aesops-enforcements hook is OFF (operator master switch). The operator types #hooks-on to turn them back on."}}'
  exit 0
fi

typed() {   # the operator's latest prompt
  if [ -f "$st/prompt-$sid.txt" ]; then cat "$st/prompt-$sid.txt"
  elif [ -f "$tp" ]; then
    jq -r 'select(.type=="user" and (.isMeta|not) and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null \
      | grep -vE '<agent-message|<task-notification>|^Another Claude session sent a message' | tail -1
  fi
}
verb_of() { awk -F'\t' -v n="$1" '$3==n{print $5; exit}' "$table" 2>/dev/null; }
overridden() {   # hook verb -> true when the operator's latest prompt lifts this block
  local p h
  case $2 in
    ''|-|'!') return 1 ;;
    '#show-secret')   # one call: the named path must be in this call, and each naming works once
      while read -r p; do
        [ -n "$p" ] || continue
        grep -qF -- "$p" <<<"$in" || grep -qF -- "${p/#\~/$HOME}" <<<"$in" || continue
        h="$st/shown-$sid-$(typed | sha256sum | cut -c1-12)-$(sha256sum <<<"$p" | cut -c1-12)"
        [ -e "$h" ] && continue
        : > "$h"; return 0
      done < <(typed | grep -oE '#show-secret[[:space:]]+[^[:space:]]+' | awk '{print $2}')
      return 1 ;;
    *) typed | grep -qF -- "$2" ;;
  esac
}
footer() {   # hook verb
  local rev="REVOKE this rule: the operator runs gate off $1 (gate on $1 restores; $root/bin/gate)."
  case $2 in
    '!') echo "OVERRIDE: none for the agent; the operator does it with a ! line. $rev" ;;
    '#show-secret') echo "OVERRIDE this call: the operator types #show-secret <path>; a skipped git hook needs the operator's own ! line. $rev" ;;
    ''|-) echo "OVERRIDE this turn: the operator says \"override\". $rev" ;;
    *) echo "OVERRIDE this call: the operator types $2 (or \"override\", \"go ahead\" for the whole turn). $rev" ;;
  esac
  case $hard in *" $1 "*) ;; *) echo "This gate yields after ${AESOP_MAX_BLOCKS:-2} identical blocks. Do not hand the operator either/or choices to clear a gate: do what they said, or state the one thing that is missing." ;; esac
}

o=$(mktemp); e=$(mktemp); trap 'rm -f "$o" "$e"' EXIT
ctx=; blocks=
note_missing() {
  log "MISSING $1: $here/$1.sh is not there, hook did NOT run (call allowed)"
  grep -qxF "$1" "$st/gate-missing" 2>/dev/null || echo "$1" >> "$st/gate-missing"
  ctx+="HOOK MISSING: $here/$1.sh is not on this device, so the rule did not run. Tell the operator (gate status)."$'\n'
}
run_one() {   # hook timeout verb args...
  local name=$1 tmo=${AESOP_HOOK_TIMEOUT:-${2:-8}} verb=$3 rc k n t msg blocked=0; shift 3
  [ -e "$off/$name" ] || [ -e "$off/$pkg.$name" ] && return 0
  [ -f "$here/$name.sh" ] || { note_missing "$name"; return 0; }
  [ -n "${NVAEX_GATE_TRACE:-}" ] && log "FIRED ${event:-direct} $name"
  if command -v timeout >/dev/null 2>&1; then timeout -k 2 "$tmo" bash "$here/$name.sh" "$@" <<<"$in" >"$o" 2>"$e"; rc=$?
  else bash "$here/$name.sh" "$@" <<<"$in" >"$o" 2>"$e"; rc=$?; fi
  case $rc in
    0) grep -qE '"decision"[[:space:]]*:[[:space:]]*"block"|"permissionDecision"[[:space:]]*:[[:space:]]*"deny"|"continue"[[:space:]]*:[[:space:]]*false' "$o" && blocked=1 ;;
    2) if grep -q 'BLOCKED (' "$e"; then blocked=1; else log "$name CRASH exit 2 without a block message (allowed): $(head -c 300 "$e")"; return 0; fi ;;
    124|137) log "$name TIMEOUT ${tmo}s (allowed)"; return 0 ;;
    *) log "$name ERROR exit $rc (allowed): $(head -c 300 "$e")"; return 0 ;;
  esac
  if [ "$blocked" = 0 ]; then
    cat "$e" >&2
    [ -s "$o" ] || return 0
    if jq -e 'type=="object"' "$o" >/dev/null 2>&1; then ctx+=$(jq -r '.hookSpecificOutput.additionalContext // .additionalContext // .systemMessage // empty' "$o")$'\n'
    else ctx+=$(cat "$o")$'\n'; fi
    return 0
  fi
  if [ "$rc" = 2 ]; then msg=$(cat "$e")
  else msg=$(jq -r '.reason // .hookSpecificOutput.permissionDecisionReason // .stopReason // "blocked"' "$o" 2>/dev/null); fi
  if overridden "$name" "$verb"; then log "$name block LIFTED by operator $verb"; return 0; fi
  k=$( { [ "$event" = PreToolUse ] && jq -c '[.tool_name,.tool_input]' <<<"$in" || grep -v '^- NOTE' <<<"$msg"; } | sha256sum | cut -c1-16)
  case $hard in
    *" $name "*) log "$name held a hard block (no loop breaker on guards) agent=$aid" ;;
    *)
      [ -e "$st/override-$sid" ] && { log "$name block LET THROUGH (operator override this turn)"; return 0; }
      n=$(( $(cat "$st/blocks-$sid-$aid-$name-$k" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$st/blocks-$sid-$aid-$name-$k"
      t=$(( $(cat "$st/blocks-$sid-$aid-_turn" 2>/dev/null || echo 0) + 1 )); echo "$t" > "$st/blocks-$sid-$aid-_turn"
      if [ "$n" -gt "${AESOP_MAX_BLOCKS:-2}" ] || [ "$t" -gt "${AESOP_MAX_TURN_BLOCKS:-6}" ]; then
        log "$name LOOP-BREAKER yielded (same call $n, turn total $t) agent=$aid: $(head -c 200 <<<"$msg")"; return 0
      fi ;;
  esac
  blocks+="$msg"$'\n'"$(footer "$name" "$verb")"$'\n'
}
finish() {
  if [ -n "$blocks" ]; then printf '%s' "$blocks" >&2; exit 2; fi
  [ -n "${ctx//[[:space:]]/}" ] || exit 0
  case $event in
    SessionStart|UserPromptSubmit|PreToolUse|PostToolUse)
      jq -n --arg e "$event" --arg c "${ctx%$'\n'}" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' ;;
    *) printf '%s' "$ctx" ;;
  esac
  exit 0
}

if [ -z "$event" ]; then   # one hook, by name
  run_one "$one" "$(awk -F'\t' -v n="$one" '$3==n{print $4; exit}' "$table" 2>/dev/null)" "$(verb_of "$one")" "$@"
  finish
fi
[ -f "$table" ] || { log "MISSING $table: no hook ran for $event (call allowed)"; echo gates.tsv >> "$st/gate-missing"; exit 0; }
if [ "$event" = SessionStart ]; then   # say so now, not only when the missing hook's event comes round
  while read -r name; do [ -f "$here/$name.sh" ] || note_missing "$name"; done < <(awk -F'\t' '!/^#/{print $3}' "$table" | sort -u)
fi
while IFS=$'\t' read -r ev m name tmo verb pre; do
  [ "$ev" = "$event" ] || continue
  [ "$m" = '*' ] || [[ $tool =~ ^($m)$ ]] || continue
  [ -z "$pre" ] || [ "$tool" != Bash ] || [[ $in =~ $pre ]] || continue
  run_one "$name" "$tmo" "$verb"
  # a blocked tool call never runs, so later gates have nothing to judge; every Stop hook still gets its say
  [ "$event" = PreToolUse ] && [ -n "$blocks" ] && break
done < "$table"
finish
