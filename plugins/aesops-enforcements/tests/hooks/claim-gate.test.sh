#!/usr/bin/env bash
# Rule 9 (operator numbering): a file:line claim needs the file read this session; "done" after edits needs a run.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
U(){ jq -cn --arg c "$1" '{type:"user",message:{role:"user",content:$c}}'; }
A(){ jq -cn --arg n "$1" --argjson i "$2" '{type:"assistant",message:{content:[{type:"tool_use",id:"t",name:$n,input:$i}]}}'; }
R(){ jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t",content:"x"}]}}'; }
G(){ jq -n --arg t "$T/tr.jsonl" --arg m "$1" --argjson a "${2:-false}" '{session_id:"S1",transcript_path:$t,last_assistant_message:$m,stop_hook_active:$a}' \
  | bash "$S/claim-gate.sh" 2>"$T/err"; echo $?; }
{ U "q"; A Read '{"file_path":"/r/RULES.md"}'; R; } > "$T/tr.jsonl"
ok "$(G "See RULES.md:12 and PENDING.md:3.")" 2 "cites an unread file -> block"
ok "$(command grep -c 'PENDING.md' "$T/err")" 1 "reason names the unread file"
ok "$(G "See RULES.md:12.")" 0 "cites a file Read this session -> pass"
{ U "q"; A Bash '{"command":"sed -n 1,20p ~/x/PENDING.md"}'; R; U "next"; A Read '{"file_path":"/r/RULES.md"}'; R; } > "$T/tr.jsonl"
ok "$(G "PENDING.md:3 says so.")" 0 "file read by Bash earlier in the session -> pass"
{ U "fix it"; A Edit '{"file_path":"/r/a.sh"}'; R; } > "$T/tr.jsonl"
ok "$(G "Fixed.")" 2 "done after an edit, nothing run -> block"
{ U "fix it"; A Edit '{"file_path":"/r/a.sh"}'; R; A Bash '{"command":"bash test.sh"}'; R; } > "$T/tr.jsonl"
ok "$(G "Fixed; tests pass.")" 0 "done after edit + run -> pass"
{ U "fix it"; A Bash '{"command":"bash test.sh"}'; R; A Write '{"file_path":"/r/b.sh"}'; R; } > "$T/tr.jsonl"
ok "$(G "Done.")" 2 "run before the last edit doesn't count -> block"
{ U "what is it"; A Read '{"file_path":"/r/x"}'; R; } > "$T/tr.jsonl"
ok "$(G "It works like this.")" 0 "no edits this turn -> pass"
{ U "fix it"; A Edit '{"file_path":"/r/a.sh"}'; R; } > "$T/tr.jsonl"
ok "$(G "Fixed." true)" 0 "stop_hook_active -> pass"
ok "$(echo 'not json{' | bash "$S/claim-gate.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass (fail-open)"
{ U "can it do X?"; A Read '{"file_path":"/r/notes.txt"}'; R; } > "$T/tr.jsonl"
ok "$(G "That flag won't work on Termux.")" 2 "won't-work claim, no docs, no trial -> block"
ok "$(command grep -c 'official documentation' "$T/err")" 1 "reason asks for docs or a trial"
ok "$(G "That feature is not supported.")" 2 "not-supported claim -> block"
{ U "can it do X?"; A WebFetch '{"url":"https://example.invalid/docs"}'; R; } > "$T/tr.jsonl"
ok "$(G "Per the docs, that flag won't work on Termux.")" 0 "docs fetched this turn -> pass"
{ U "can it do X?"; A Read '{"file_path":"/r/fork/README.md"}'; R; } > "$T/tr.jsonl"
ok "$(G "It isn't supported (README).")" 0 "README read this turn -> pass"
{ U "can it do X?"; A Bash '{"command":"tool --flag x"}'; R; } > "$T/tr.jsonl"
ok "$(G "Tried it: that flag won't work.")" 0 "trial run this turn -> pass"
{ U "can it do X?"; A Bash '{"command":"grep flag notes.txt"}'; R; } > "$T/tr.jsonl"
ok "$(G "That flag won't work.")" 2 "a grep is not a trial -> block"
{ U "q"; A Read '{"file_path":"/r/notes.txt"}'; R; } > "$T/tr.jsonl"
ok "$(G 'No. "Modified tests" does not mean these will not work.')" 0 "negated (doesn't mean ... won't work) -> not a claim"
ok "$(G 'You asked whether it "won'"'"'t work on Termux".')" 0 "quoted phrase -> not a claim"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
