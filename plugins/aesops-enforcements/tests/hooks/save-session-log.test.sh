#!/usr/bin/env bash
# Rule 7 (operator numbering): the session log is two parts in one place, NvAEx-Recaps session-logs/<date>-<sid8>/.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); export HOME=$T STATE_DIR=$T/st RECAPS_DIR=$T/st/recaps
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
git init -q --bare -b main "$T/rr.git"; git clone -q "$T/rr.git" "$T/rr" 2>/dev/null
( cd "$T/rr" && git switch -q -c main 2>/dev/null; echo r > README.md; git add . && git commit -q -m init && git push -q -u origin main && git remote set-head origin main ) >/dev/null 2>&1
SID=abcdef1234567890; mkdir -p "$T/tmp/claude-1/p/$SID/scratchpad" "$RECAPS_DIR"
echo "did the thing" > "$T/tmp/claude-1/p/$SID/scratchpad/session-notes.md"
printf '# Session\n\n## Repos touched\n- /r/x\n\n## Files written\n- /r/x/a.sh\n' > "$RECAPS_DIR/2026-11-10-${SID:0:8}.md"
{ jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:"task-observer"}}]}}'
  jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:"ls"}}]}}'
  jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:"pwd"}}]}}'; } > "$T/tr.jsonl"
jq -cn --arg s "$SID" --arg t "$T/tr.jsonl" '{session_id:$s,transcript_path:$t,hook_event_name:"SessionEnd"}' \
  | RECAPS_REPO=$T/rr SCRATCH_ROOT=$T/tmp bash "$S/save-session-log.sh"
br="session-log/$(date +%F)-${SID:0:8}"; d="session-logs/$(date +%F)-${SID:0:8}"
ok "$(git -C "$T/rr" rev-parse -q --verify "refs/heads/$br" >/dev/null && echo yes)" yes "branch $br committed"
show(){ git -C "$T/rr" show "$br:$d/$1" 2>/dev/null; }
ok "$(show scratchpad/session-notes.md)" "did the thing" "part 1: the scratchpad"
ok "$(show task-log.md | grep -c '/r/x/a.sh')" 1 "part 2: the task log has the files written"
ok "$(show task-log.md | grep -c 'task-observer (1)')" 1 "task log lists skills used"
ok "$(show task-log.md | grep -c 'Bash (2)')" 1 "task log lists tools used"
ok "$(git -C "$T/rr" ls-tree -r --name-only "$br" | grep -vc "^$d/\|^README.md$")" 0 "nothing outside session-logs/<date>-<sid8>/"
ok "$([ -d "$T/.claude/scratchpad-archive" ] && echo yes || echo no)" no "no device copy"
ok "$(git -C "$T/rr" worktree list | wc -l | tr -d ' ')" 1 "worktree cleaned up"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
