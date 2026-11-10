#!/usr/bin/env bash
# direction-gate.sh: Rule 1. Tools closed until # or an affirmation; one opening covers the job.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export HOME=$T
mkdir -p "$T/.claude/state"; repo=$T/repo; git init -q "$repo"; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
U(){ jq -n --arg p "$1" --arg c "$repo" '{session_id:"S",hook_event_name:"UserPromptSubmit",cwd:$c,prompt:$p}' | bash "$S/direction-gate.sh" >/dev/null 2>&1; }
G(){ jq -n --arg t "$1" --arg f "${2:-}" --arg c "$repo" --arg x "${3:-}" '{session_id:"S",hook_event_name:"PreToolUse",cwd:$c,tool_name:$t,tool_input:{file_path:$f,command:$x,skill:$x}}' | bash "$S/direction-gate.sh" >/dev/null 2>&1; echo $?; }
printf 'See `other.md` and %s/named.md\n' "$repo" > "$repo/AGENTS.md"; : > "$repo/other.md"; : > "$repo/named.md"; : > "$repo/secret.md"; : > "$repo/RESUME.md"
U "why didn't you do that"
ok "$(G Bash "" "ls")" 2 "question: Bash blocked"
ok "$(G Edit "$repo/x")" 2 "question: Edit blocked"
ok "$(G Read "$repo/secret.md")" 2 "question: unnamed file read blocked"
ok "$(G Grep)" 2 "question: Grep blocked"
ok "$(G WebFetch)" 2 "question: web blocked"
ok "$(G Agent)" 2 "question: agent blocked"
ok "$(G Read "$repo/AGENTS.md")" 0 "AGENTS.md readable"
ok "$(G Read "$repo/named.md")" 0 "absolute path named in AGENTS.md readable"
ok "$(G Read "$repo/other.md")" 0 "relative path named in AGENTS.md readable"
ok "$(G Read "$repo/secret.md")" 2 "still blocked after opening reads"
ok "$(G Skill "" task-observer)" 0 "task-observer allowed"
ok "$(G Skill "" other)" 2 "other skill blocked"
ok "$(G AskUserQuestion)" 0 "can ask"
ok "$(G Bash "" 'bash /x/session-start-scan.sh "/v"')" 0 "observer scan allowed"
ok "$(G Bash "" 'bash /x/session-start-scan.sh /v; rm -rf /')" 2 "scan with a chained command blocked"
for p in "#fix the hook" "  #fix" "hashtag fix it" "okay" "Okay." "yes" "Yeah go ahead" "go" "do it" "override: do this"; do U "$p"; ok "$(G Bash "" ls)" 0 "opens: $p"; U "what is this"; ok "$(G Bash "" ls)" 0 "a comment mid-job keeps it open: $p"; U "stop"; ok "$(G Bash "" ls)" 2 "stop closes after: $p"; done
for p in "amend: also do x" "defer 2" "1. fix this ... #go ahead" "Okay, amend"; do U "stop"; U "$p"; ok "$(G Bash "" ls)" 0 "opens: $p"; done
U "stop"; printf 'hooks\tread: ~/.claude/hooks/README.md\tturn\n' > "$T/.claude/state/required-S.tsv"; mkdir -p "$T/.claude/hooks"; : > "$T/.claude/hooks/README.md"
ok "$(G Read "$T/.claude/hooks/README.md")" 0 "closed: a read ENFORCEMENTS requires is part of the opening protocol"; rm -f "$T/.claude/state/required-S.tsv"
for p in "you need to think about it" "okayish" "goal is x" "yesterday it broke" "why not"; do U "stop"; U "$p"; ok "$(G Edit "$repo/x")" 2 "does not open: $p"; done
U "#one job"; for i in 1 2 3 4 5 6 7 8 9 10; do r=$(G Bash "" ls); [ "$r" = 0 ] || break; done; ok "$r" 0 "one opening covers many steps"
[ -f "$T/.claude/state/resume-S.ok" ]; ok $? 0 "session marker written for other gates"
grep -q '^read:AGENTS.md' "$T/.claude/state/opening-S.tsv"; ok $? 0 "opening ledger recorded"
echo "direction-gate.test.sh passed=$pass failed=$fail"; [ "$fail" = 0 ]
