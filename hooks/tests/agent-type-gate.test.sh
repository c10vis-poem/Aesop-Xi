#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d)
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
A(){ jq -cn --arg t "$1" --arg p "$2" '{tool_name:"Agent",tool_input:({description:"d",prompt:$p} + (if $t=="" then {} else {subagent_type:$t} end))}' | bash "$S/agent-type-gate.sh" 2>"$T/err"; echo $?; }
PF="FIRST create progress file ~/.claude/session-work/2026-10-23/agent-x.md"
ok "$(A Explore "$PF")" 2 "Explore + agent-*.md -> block"
ok "$(command grep -c 'general-purpose' "$T/err")" 1 "reason names a writer type"
ok "$(A Plan "Keep a live Progress File as you go")" 2 "Plan + 'progress file' -> block"
ok "$(A general-purpose "$PF")" 0 "general-purpose + progress file -> pass"
ok "$(A "" "$PF")" 0 "no subagent_type (default) -> pass"
ok "$(A Explore "find where the parser lives")" 0 "Explore without progress file -> pass"
ok "$(echo 'not json{' | bash "$S/agent-type-gate.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
