#!/usr/bin/env bash
# Rule 4, PreToolUse (Bash, Edit, Write): the agent cannot change settings, enforcement state or the switches,
# unless the operator directs it: a # direction this prompt that names settings, hooks, gates or the
# switches (direction-gate writes $ST/direct4-<session>; state-guard keeps the agent from writing it).
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
. "$(dirname "$(realpath "$0")")/lib/env.sh"
sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null)
if [ -n "$sid" ] && [ -f "$ST/direct4-$sid" ]; then hook_log "Rule 4: allowed by operator direction ($tool, $sid)"; exit 0; fi
run_parts settings-guard state-guard
