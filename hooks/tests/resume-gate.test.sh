#!/data/data/com.termux/files/usr/bin/bash
# resume-gate.sh: blocks until RESUME is Read; records opening reads; re-checks the hash (obs 0044); dates RESUME.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export HOME=$T
st=$T/.claude/state; mkdir -p "$st"; repo=$T/repo; git init -q "$repo"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
G(){ jq -n --arg t "$1" --arg f "$2" --arg c "$repo" '{session_id:"S",cwd:$c,tool_name:$t,tool_input:{file_path:$f}}' | bash "$S/resume-gate.sh" >"$T/out" 2>"$T/err"; echo $?; }
printf '# RESUME\n\n**Last updated: 2026-01-01**\n\n## START HERE\n1. a\n' > "$repo/RESUME.md"; printf '# rules\n' > "$repo/AGENTS.md"
ok "$(G Bash "")" 2 "blocked before RESUME is read"
ok "$(G Read "$repo/AGENTS.md")" 2 "reading another file first is still blocked"
ok "$(G Read "$repo/RESUME.md")" 0 "Read RESUME -> allowed"
ok "$([ -f "$st/resume-S.ok" ] && [ -f "$st/resume-S.snap.md" ] && echo y)" y "hash + snapshot written"
ok "$(cat "$st/resume-date-S")" 2026-01-01 "RESUME date recorded"
ok "$(grep -c 'days ago' "$T/out")" 1 "stale RESUME reported as context"
ok "$(G Read "$repo/AGENTS.md")" 0 "after RESUME: tools run"
ok "$(grep -c '^read:AGENTS.md' "$st/opening-S.tsv")" 1 "opening ledger records AGENTS.md"
# external change -> block once until re-read; re-read refreshes
echo "- 2. b" >> "$repo/RESUME.md"
ok "$(G Bash "")" 2 "RESUME changed on disk -> blocked"
ok "$(grep -c 'changed since this session read it' "$T/err")" 1 "reason explains the drift"
ok "$(G Read "$repo/RESUME.md")" 0 "re-read allowed"
ok "$([ -f "$st/resume-S.snap.prev.md" ] && echo y)" y "old snapshot kept"
ok "$(G Bash "")" 0 "after re-read: allowed"
# this session wrote it (change log) -> no drift block
printf '%s\tEDIT\trepo:repo\t%s\n' "$(date '+%F %T')" "$repo/RESUME.md" >> "$st/changes-S.log"; echo "- 3. c" >> "$repo/RESUME.md"
ok "$(G Bash "")" 0 "own write recorded in change log -> no block"
# wrap-up mode -> no drift block
rm "$st/changes-S.log"; echo "- 4. d" >> "$repo/RESUME.md"; touch "$st/wrapup-S"
ok "$(G Bash "")" 0 "wrap-up mode -> no drift block"
# undated RESUME is reported
rm -f "$st"/resume-S* "$st"/advised-* "$st/wrapup-S"; printf '# RESUME\n## START HERE\n1. a\n' > "$repo/RESUME.md"
G Read "$repo/RESUME.md" >/dev/null; ok "$(grep -c 'carries no date' "$T/out")" 1 "undated RESUME reported"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
