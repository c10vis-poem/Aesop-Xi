#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
E(){ jq -cn --arg e "$1" --arg c "${2:-}" --arg a "${3:-}" '{hook_event_name:$e,session_id:"S1",cwd:"/",tool_name:"Bash",tool_input:{command:$c}} + (if $a=="" then {} else {agent_id:$a} end)' | bash "$S/delegation-tripwire.sh"; }
warned(){ E PreToolUse ls | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null | command grep -c 'subagent'; }
E UserPromptSubmit
for r in A B C D A B C; do E PostToolUse "git -C ~/repos/$r status"; done
ok "$(warned)" 1 "7 calls over 4 repos -> warning on next Bash"
ok "$(warned)" 0 "warned once per turn"
ok "$(E PreToolUse ls >/dev/null; echo $?)" 0 "warning is non-blocking (exit 0)"
E UserPromptSubmit; ok "$(warned)" 0 "new prompt resets"
for r in A B C A B C A B; do E PostToolUse "ls \$HOME/repos/$r"; done
ok "$(warned)" 0 "8 calls over 3 repos -> no warning"
E PostToolUse "ls ~/storage/shared/Documents/NovAExorpus/skill-observations"
ok "$(warned)" 1 "vault folder counts as a 4th target"
E UserPromptSubmit
for r in A B C D A B; do E PostToolUse "ls ~/repos/$r"; done
ok "$(warned)" 0 "6 calls -> no warning"
for r in E F G H; do E PostToolUse "ls ~/repos/$r" agent-1; done
ok "$(warned)" 0 "subagent calls not counted"
E PostToolUse "echo hi"; ok "$(warned)" 0 "calls touching no repo not counted"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
