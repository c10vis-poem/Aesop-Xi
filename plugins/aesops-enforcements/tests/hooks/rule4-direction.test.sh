#!/usr/bin/env bash
# Rule 4, "unless the operator directs it": a # direction naming settings/hooks/gates lets guard through for that prompt.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); export HOME=$T STATE_DIR=$T/st
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
P(){ jq -cn --arg p "$1" '{session_id:"S1",hook_event_name:"UserPromptSubmit",prompt:$p,cwd:"/"}' | bash "$S/direction-gate.sh" >/dev/null 2>&1; }
E(){ jq -cn --arg f "$T/.claude/settings.json" '{session_id:"S1",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$f}}' \
  | bash "$S/guard.sh" 2>/dev/null; echo $?; }
P "fix the docs"
ok "$(E)" 2 "plain prompt: settings edit -> block"
P "#fix the docs"
ok "$(E)" 2 "direction not naming settings -> block"
P "#update the settings to add the plugin"
ok "$(E)" 0 "direction naming settings -> pass"
P "thanks"
ok "$(E)" 2 "next prompt re-decides -> block again"
P "#turn the stop gate back on"
ok "$(E)" 0 "direction naming a gate -> pass"
X(){ jq -cn --arg f "$1" '{session_id:"S1",hook_event_name:"PreToolUse",tool_name:"Write",tool_input:{file_path:$f}}' \
  | bash "$S/state-guard.sh" 2>/dev/null; echo $?; }
ok "$(X "$T/.claude/state/direct4-S1")" 2 "agent cannot write the direction marker itself"
ok "$(X "$T/.claude/state/job-S1")" 2 "agent cannot write the job marker itself"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
