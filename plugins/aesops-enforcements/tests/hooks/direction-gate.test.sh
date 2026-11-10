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
# Opening reads named the way the docs write them (crane test 2026-11-10): "<repo> `inside/path`", and files named in
# the always-loaded instructions (~/.agents/AGENTS.md) or in the session agent's definition.
export REPOS_DIR=$T/repos; R2=$REPOS_DIR
mkdir -p "$R2/Aesop-Xi/plugins/x" "$R2/NvAEx-Recaps/handoff/h" "$R2/NvAEx-Recaps/memory/active" "$T/.agents" "$R2/Other"
: > "$R2/Aesop-Xi/plugins/x/RULES.md"; : > "$R2/NvAEx-Recaps/memory/general.md"; : > "$R2/NvAEx-Recaps/memory/active/e.md"; : > "$R2/Other/RULES.md"
printf 'Details: Aesop-Xi `plugins/x/RULES.md` and `memory/general.md`.\n' > "$R2/NvAEx-Recaps/handoff/h/handoff.md"
printf 'Shared memory: NvAEx-Recaps `memory/active/e.md`.\n' > "$T/.agents/AGENTS.md"
U "stop"   # close the job opened above: only the opening reads pass
ok "$(G Read "$R2/Aesop-Xi/plugins/x/RULES.md")" 2 "before the handoff is read: blocked"
ok "$(G Read "$R2/NvAEx-Recaps/handoff/h/handoff.md")" 0 "handoff readable (opening document)"
ok "$(G Read "$R2/Aesop-Xi/plugins/x/RULES.md")" 0 "'Aesop-Xi \`plugins/x/RULES.md\`' in the handoff -> readable"
ok "$(G Read "$R2/NvAEx-Recaps/memory/general.md")" 0 "path inside the handoff's own repo -> readable"
ok "$(G Read "$R2/Other/RULES.md")" 2 "same inside path in another repo the docs never name -> blocked"
ok "$(G Read "$R2/NvAEx-Recaps/memory/active/e.md")" 0 "named in ~/.agents/AGENTS.md (loaded every session) -> readable"
ok "$(G Write "$T/v/skill-observations/observation-log/0090-x.md")" 0 "closed: writing an observation passes (no loop with the friction line)"
ok "$(G Bash "" "bash /x/scripts/new-observation.sh slug /v")" 0 "closed: the observation helper passes"
ok "$(G Write "$T/v/skill-observations/other.md")" 2 "closed: other writes in the vault still blocked"
mkdir -p "$T/v/skill-observations" "$T/.claude/skills/task-observer/scripts"
ok "$(G Bash "" "ls $T/v/skill-observations")" 0 "closed: task-observer protocol: probe of the workspace passes"
ok "$(G Bash "" "cat $T/v/skill-observations/last-review-date.txt")" 0 "closed: protocol read of last-review-date passes"
ok "$(G Bash "" "bash $T/.claude/skills/task-observer/scripts/session-start-scan.sh $T/v")" 0 "closed: the scan itself passes"
ok "$(G Bash "" "cat $T/v/skill-observations/x $T/secret.txt")" 2 "closed: a path outside the workspace in the same command -> blocked"
ok "$(G Read "$T/v/skill-observations/checkpoints.log")" 0 "closed: protocol Read in the workspace passes"
mkdir -p "$T/v/plugins/greedy-crane/agents" "$T/v/plugins/greedy-crane/docs" "$R2/Dup/plugins/nvaex-wiki-admin/agents"
echo "direction-gate.test.sh passed=$pass failed=$fail"; [ "$fail" = 0 ]
