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
# 4/5 (operator 2026-11-10: "You should have to be forced to prove it"): a status list matches its source; read counts need reads
RT(){ jq -cn --arg c "$1" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t",content:$c}]}}'; }
rep=$'## unsupported (2)\n- `Assets/a.zip`: no converter for .zip\n- `More/jev_db.py`: no converter for .py'
quar=$'/x/Argon/the remedy.txt\tnull\n/x/Assets/a.zip\tnull'
{ U "ingest"; A Bash '{"command":"python3 convert.py"}'; RT "$rep"; A Bash '{"command":"jq . q.jsonl"}'; RT "$quar"; } > "$T/tr.jsonl"
ok "$(G $'Convert: 2 unsupported. By name:\n- `Assets/a.zip`\n- `Argon/the remedy.txt`')" 2 "a name under 'unsupported' that only another output showed -> block"
ok "$(command grep -c 'the remedy.txt' "$T/err")" 1 "reason names the unproven file"
ok "$(G $'Convert: 2 unsupported:\n- `Assets/a.zip`\n- `More/jev_db.py`')" 0 "names copied from the report -> pass"
ok "$(G $'Two files are unsupported: `Assets/a.zip` and `More/jev_db.py`.')" 0 "inline list matching the report -> pass"
ok "$(G $'Unsupported:\n- `Assets/a.zip`\n\nNext: `Argon/the remedy.txt`.')" 0 "a later paragraph is not part of the list -> pass"
ok "$(G 'All flags now come back as "released": nothing stops them. Your list is `~/.local/state/released.txt`.')" 0 "a path in the next sentence is not listed under the status -> pass"
{ U "ingest"; A Read '{"file_path":"/x/a.md"}'; R; A Read '{"file_path":"/x/b.md"}'; R; } > "$T/tr.jsonl"
ok "$(G "I read 240 files and analyzed them.")" 2 "read-count claim above the Reads this session -> block"
ok "$(G "I read 2 files.")" 0 "read-count claim matching the Reads -> pass"
ok "$(G "Ingested 3 documents.")" 2 "ingested count above Reads -> block"
# 6/7 Rule 13, no lying
{ U "check"; A Read '{"file_path":"/x/AGENTS.md"}'; R; A Bash '{"command":"bash t.sh"}'; RT "t.sh passed=12 failed=0"; } > "$T/tr.jsonl"
ok "$(G 'I read `AGENTS.md` and `RULES.md`.')" 2 "says a file was read that no tool touched -> block"
ok "$(G 'I read `AGENTS.md`.')" 0 "read claim backed by a Read -> pass"
ok "$(G "It passes 12 of 12.")" 0 "test numbers shown by a tool this turn -> pass"
ok "$(G "Selftest: 787 of 787 passed.")" 2 "test numbers no tool showed this turn -> block"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
