#!/usr/bin/env bash
# Observation 0090, end to end: a fresh session's opening runs through BOTH gates and finishes with no okay.
# The job is closed (nothing typed that opens it). The stop-gate names the opening; every step it names must
# pass the direction-gate; after doing them, the stop-gate has no opening item left.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T VAULT=$T/v AESOP_VAULT=$T/v STATE_DIR=$T/.claude/state REPOS_DIR=$T/repos
pass=0; fail=0; ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
repo=$T/repos/NovAExopia; mkdir -p "$repo" "$STATE_DIR" "$VAULT/skill-observations/observation-log" "$T/.claude/skills/task-observer/scripts"
git init -q "$repo"; for f in AGENTS MEMORY RESUME PENDING; do echo "# $f" > "$repo/$f.md"; done
: > "$VAULT/skill-observations/checkpoints.log"; touch -d '2000-01-01' "$VAULT/skill-observations/checkpoints.log"
printf '#!/usr/bin/env bash\necho "$(date "+%%F %%R") [t] session-start scan: files=0" >> "$1/skill-observations/checkpoints.log"\n' > "$T/.claude/skills/task-observer/scripts/session-start-scan.sh"
tp=$T/t.jsonl; jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:"task-observer"}}]}}' > "$tp"
U(){ jq -n --arg p "$1" --arg c "$repo" '{session_id:"S",hook_event_name:"UserPromptSubmit",cwd:$c,prompt:$p}' | bash "$S/direction-gate.sh" >/dev/null 2>&1; }
D(){ jq -n --arg t "$1" --arg f "${2:-}" --arg c "$repo" --arg x "${3:-}" '{session_id:"S",hook_event_name:"PreToolUse",cwd:$c,tool_name:$t,tool_input:{file_path:$f,command:$x,skill:$x}}' | bash "$S/direction-gate.sh" >/dev/null 2>&1; echo $?; }
St(){ jq -n --arg c "$repo" --arg t "$tp" '{session_id:"S",hook_event_name:"Stop",cwd:$c,transcript_path:$t,stop_hook_active:false}' | bash "$S/stop-gate.sh" 2>/dev/null | jq -r '.reason // ""'; }
U "[-]"; sleep 1                     # first prompt opens nothing: the job stays closed through the opening
echo 'Handoff: NvAEx-Recaps `handoff/h/handoff.md`.' >> "$repo/RESUME.md"; mkdir -p "$REPOS_DIR/NvAEx-Recaps/handoff/h"; echo "# handoff" > "$REPOS_DIR/NvAEx-Recaps/handoff/h/handoff.md"
r=$(St); grep -q 'Opening, in this order' <<<"$r"; ok $? 0 "stop-gate names the opening"
for f in AGENTS MEMORY RESUME PENDING; do grep -qF "$repo/$f.md" <<<"$r"; ok $? 0 "stop-gate lists $f.md as not read"; done
grep -qF "handoff/h/handoff.md" <<<"$r"; ok $? 0 "stop-gate lists the handoff RESUME.md points to"
for f in AGENTS MEMORY RESUME PENDING; do ok "$(D Read "$repo/$f.md")" 0 "closed job: opening read $f.md passes"; done
ok "$(D Skill "" task-observer)" 0 "closed job: task-observer skill loads"
ok "$(D Read "$REPOS_DIR/NvAEx-Recaps/handoff/h/handoff.md")" 0 "closed job: the handoff read passes"
r=$(St); grep -q 'read these with Read' <<<"$r"; ok $? 1 "after the reads: the stop-gate asks only for the scan"
cmd=$(grep -oE 'session-start scan: bash [^(]*' <<<"$r" | sed -E 's/^session-start scan: //; s/[[:space:]]+$//')
[ -n "$cmd" ]; ok $? 0 "stop-gate gives the exact scan command"
ok "$(D Bash "" "$cmd")" 0 "the command the stop-gate gives passes the direction-gate"
ok "$(D Bash "" "bash \"$T/.claude/skills/task-observer/scripts/session-start-scan.sh\" \"$VAULT\"")" 0 "the scan quoted as in field test 8f020c32 passes"
ok "$(D Bash "" "$cmd | tail -20")" 2 "the scan piped through tail is refused (output read whole)"
ok "$(D Bash "" "$cmd 2>&1 | grep -v x")" 2 "the scan piped through grep is refused"
eval "$cmd"
r=$(St); grep -q 'Opening' <<<"$r"; ok $? 1 "after the opening: no opening item left (no okay given)"
ok "$(D Edit "$repo/x")" 2 "the job itself still waits for the operator"
U "test"; ok "$(D Edit "$repo/x")" 2 "a plain message ('test') does not open the job"
U "#fix it"; ok "$(D Edit "$repo/x")" 0 "a # message opens the job"
echo "opening-e2e.test.sh passed=$pass failed=$fail"; [ "$fail" = 0 ]
