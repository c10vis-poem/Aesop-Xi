#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Agent), obs 0023: a read-only subagent (Explore, Plan) cannot write the progress file
# the standing order requires, so refuse those spawns when the prompt names one.
in=$(cat)
t=$(jq -r '.tool_input.subagent_type // ""' <<<"$in" 2>/dev/null) || exit 0
case $t in Explore|Plan) ;; *) exit 0 ;; esac
jq -r '.tool_input.prompt // ""' <<<"$in" | command grep -qiE 'agent-[^[:space:]]*\.md|progress file' || exit 0
echo "BLOCKED (agent-type-gate): $t is read-only and cannot write the progress file this prompt asks for. Spawn general-purpose or builder instead (obs 0023)." >&2
exit 2
