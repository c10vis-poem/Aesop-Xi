#!/data/data/com.termux/files/usr/bin/bash
# Tests observe-event.sh, the stop-gate observer checks and observe-dismiss in a fake HOME.
S=$(cd "$(dirname "$0")/.." && pwd); D="$S/../deploy/phone/bin/observe-dismiss"
T=$(mktemp -d); export HOME=$T; st=$T/.claude/state; so=$T/storage/shared/Documents/NovAExorpus/skill-observations
mkdir -p "$st" "$so/observation-log" "$T/bin"; export PATH="$T/bin:$PATH"; unset CLAUDE_CODE_SESSION_ID
echo "2026-10-01 10:00 [home] session-start scan: files=1 parsed=1 principles=0" > "$so/checkpoints.log"
tp=$T/t.jsonl; skill(){ jq -nc --arg t "$1" '{type:"assistant",timestamp:$t,message:{content:[{type:"tool_use",name:"Skill",input:{skill:"task-observer"}}]}}' >> "$tp"; }
skill 2026-01-01T00:00:00.000Z
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
E(){ jq -nc --arg e "$1" '{session_id:"S1",hook_event_name:$e}' | jq -c ". + $2" | bash "$S/observe-event.sh"; }
SG(){ jq -n --arg tp "$tp" --arg c "$T" --argjson a "${1:-false}" '{session_id:"S1",transcript_path:$tp,cwd:$c,stop_hook_active:$a}' | bash "$S/stop-gate.sh" | jq -r .reason; }
q=$st/observe-queue-S1.tsv; ev(){ cat "$q" 2>/dev/null | grep -c "	$1	"; }   # 0, not empty, before the queue exists

ok "$(SG | wc -c | tr -d ' ')" 0 "nothing queued -> stop allowed"
# compaction re-arms
echo "skill: task-observer" > "$st/satisfied-S1.tsv"
E SessionStart '{source:"resume"}' >/dev/null; ok "$([ -f "$st/compact-S1" ] && echo y || echo n)" n "resume start -> no compaction state"
out=$(E SessionStart '{source:"compact"}'); ok "$(grep -c compacted <<<"$out")" 1 "compact -> context line"
ok "$([ -f "$st/satisfied-S1.tsv" ] && echo y || echo n)" n "compact clears satisfied-<sid>.tsv"
out=$(SG); ok "$(grep -c 'load the task-observer skill again' <<<"$out")" 1 "after compact: old Skill call doesn't count"
ok "$(grep -c 'session-start scan again' <<<"$out")" 1 "after compact: old scan line doesn't count"
skill 2099-01-01T00:00:00.000Z; echo "2099-01-01 00:00 [home] session-start scan: files=1 parsed=1 principles=0" >> "$so/checkpoints.log"
ok "$(SG | wc -c | tr -d ' ')" 0 "skill + new scan after compact -> stop allowed"
# friction events
E PostToolUseFailure '{tool_name:"Bash",tool_input:{},tool_use_id:"t",error:"Exit code 1\nboom"}' >/dev/null; ok "$(ev tool-fail)" 0 "Bash non-zero exit not queued"
E PostToolUseFailure '{tool_name:"Bash",tool_input:{},tool_use_id:"t",error:"timed out",is_timeout:true}' >/dev/null; ok "$(ev tool-fail)" 1 "Bash timeout queued"
E PostToolUseFailure '{tool_name:"Edit",tool_input:{},tool_use_id:"t",error:"old_string not found"}' >/dev/null; ok "$(ev tool-fail)" 2 "Edit failure queued"; sed -i "/old_string not found/d" "$q"   # keep later counts at 5 events
E PostToolUseFailure '{tool_name:"Read",tool_input:{},tool_use_id:"t",error:"x",is_interrupt:true}' >/dev/null; ok "$(ev tool-fail)" 1 "interrupt not queued"
E PermissionDenied '{tool_name:"Bash",tool_input:{},tool_use_id:"t",reason:"classifier said no"}' >/dev/null; ok "$(ev denied)" 1 "PermissionDenied queued"
out=$(E UserPromptSubmit '{prompt:"That was wrong, put it back"}'); ok "$(ev correction)" 1 "correction prompt queued"
ok "$(grep -c 'observe-dismiss e' <<<"$out")" 1 "correction prompt -> pointer line"
E UserPromptSubmit '{prompt:"write a poem about knowledge"}' >/dev/null; ok "$(ev correction)" 1 "ordinary prompt -> not queued"
E UserPromptSubmit '{prompt:"Another Claude session sent a message:\n<agent-message from=\"x\">the old copy was wrong</agent-message>"}' >/dev/null; ok "$(ev correction)" 1 "subagent hand-back -> not queued"
E UserPromptSubmit '{prompt:"no, the other file"}' >/dev/null; ok "$(ev correction)" 2 "^no matches"
printf '%s BLOCK git-gate: git push\n%s STOP-BLOCK 2 item(s)\n' "$(date +%T)" "$(date +%T)" >> "$st/enforce-S1.log"
out=$(SG); ok "$(ev block)" 1 "gate BLOCK line imported (STOP-BLOCK not)"
ok "$(grep -c '^- Friction event e' <<<"$out")" 5 "stop blocked: one line per open event"
SG >/dev/null; ok "$(ev block)" 1 "BLOCK line imported once"
ok "$(SG true | wc -c | tr -d ' ')" 0 "stop_hook_active + no event resolved -> yields (no loop)"
id=$(grep "	denied	" "$q" | cut -f1)
bash "$D" "$id" >/dev/null 2>&1; ok "$?" 1 "dismiss without reason refused"
bash "$D" e0 "x" >/dev/null 2>&1; ok "$?" 1 "dismiss of unknown id refused"
bash "$D" "$id" "classifier was right" >/dev/null; ok "$(SG | grep -c '^- Friction event')" 4 "dismissed event no longer blocks"
bash "$D" "$(grep "	block	" "$q" | cut -f1)" "expected git-gate block" >/dev/null
ok "$(SG true | grep -c '^- Friction event')" 3 "stop_hook_active after progress -> still blocks"
ok "$(bash "$D" list | grep -c dismissed)" 2 "list shows the dismissals"
touch -d '+5 sec' "$so/observation-log/0001-x.md"
ok "$(SG | wc -c | tr -d ' ')" 0 "observation written after the events -> stop allowed"
# wrap-up: review age + parked branches
touch "$st/wrapup-S1"; o=$so/observation-log
printf -- '---\nid: 2\nstatus: open\n---\n' > "$o/0002-a.md"
printf -- '---\nid: 3\nstatus: parked\nparked_until: "fork branch fix/x merged into aesop-task-observer main"\n---\n' > "$o/0003-b.md"
printf '#!/data/data/com.termux/files/usr/bin/bash\necho "$*" >> %s/gh.log; echo "${GH_MERGED:-0}"\n' "$T" > "$T/bin/gh"; chmod +x "$T/bin/gh"
echo never > "$so/last-review-date.txt"; out=$(SG); ok "$(grep -c 'weekly review is due' <<<"$out")" 1 "wrap-up: review never + open obs -> blocked"
ok "$(grep -c 'pr list -R c10vis-poem/aesop-task-observer --state merged --head fix/x' "$T/gh.log")" 1 "parked branch checked with gh against the named repo"
ok "$(grep -c 'parked observation' <<<"$out")" 0 "parked branch not merged -> not flagged"
date -d '3 days ago' +%F > "$so/last-review-date.txt"; ok "$(SG | grep -c 'weekly review')" 0 "recent review -> not blocked"
date -d '9 days ago' +%F > "$so/last-review-date.txt"; ok "$(SG | grep -c 'weekly review')" 1 "9-day-old review -> blocked"
sed -i 's/status: open/status: actioned/' "$o/0002-a.md"; ok "$(SG | grep -c 'weekly review')" 0 "old review, no open obs -> not blocked"
out=$(GH_MERGED=1 SG); ok "$(grep -c 'parked observation 0003-b.md waits for branch fix/x merged into aesop-task-observer' <<<"$out")" 1 "merged parked branch flagged"
ok "$(grep -c 'status: parked' "$o/0003-b.md")" 1 "parked observation not edited"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
