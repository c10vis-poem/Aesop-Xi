#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
U(){ jq -cn --arg c "$1" '{type:"user",message:{role:"user",content:$c}}'; }
A(){ jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:"t",name:$n,input:$i}]}}'; }
R(){ jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t",content:"x"}]}}'; }
G(){ jq -n --arg t "$T/tr.jsonl" --arg m "$1" --argjson a "${2:-false}" '{session_id:"S1",transcript_path:$t,last_assistant_message:$m,stop_hook_active:$a}' \
  | bash "$S/absence-gate.sh" 2>"$T/err"; echo $?; }
CLAIM="JEV is undefined in the notes."
{ U "what is JEV?"; A Read '{"file_path":"/x"}'; R; } > "$T/tr.jsonl"
ok "$(G "$CLAIM")" 2 "claim + no search -> block"; ok "$(command grep -c 'undefined in the notes' "$T/err")" 1 "reason quotes the claim"
{ U "old"; A Bash '{"command":"grep -r JEV ~/repos"}'; R; U "what is JEV?"; A Read '{"file_path":"/x"}'; R; } > "$T/tr.jsonl"
ok "$(G "$CLAIM")" 2 "search before the last user prompt doesn't count"
{ U "what is JEV?"; A Bash '{"command":"command grep -ri jev ~/repos"}'; R; } > "$T/tr.jsonl"
ok "$(G "That repo doesn't exist.")" 0 "claim + grep -> pass"
{ U "what is JEV?"; A Bash '{"command":"gh search repos jev"}'; R; } > "$T/tr.jsonl"
ok "$(G "$CLAIM")" 0 "claim + gh search -> pass"
{ U "q"; A mcp__claude_ai_Hugging_Face__hf_fs '{}'; R; } > "$T/tr.jsonl"
ok "$(G "No such model.")" 0 "claim + hf_fs -> pass"
{ U "what is JEV?"; A Read '{"file_path":"/x"}'; R; } > "$T/tr.jsonl"
ok "$(G "JEV: not found by grep ~/repos, vault, gh search repos.")" 0 "claim naming probes -> pass"
ok "$(G "All tests pass.")" 0 "no claim -> pass"
ok "$(G "$CLAIM" true)" 0 "stop_hook_active -> pass"
ok "$(echo 'not json{' | bash "$S/absence-gate.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass"
ok "$(command grep -c fail-open "$T/.claude/state/absence-gate.log")" 1 "fail-open logged"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
