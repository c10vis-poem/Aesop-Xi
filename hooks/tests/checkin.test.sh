#!/data/data/com.termux/files/usr/bin/bash
# enforce-prompt check-off: slash forms anywhere, stray dash, and an honest CHECK-IN line.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
mkdir -p "$T/.claude/state"; cp "$S/ENFORCEMENTS.md" "$T/.claude/ENFORCEMENTS.md"
st=$T/.claude/state; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
P(){ jq -n --arg p "$1" '{session_id:"S",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh"; }
has(){ grep -q "$1" <<<"$2" && echo yes || echo no; }
out=$(P "/ok 1"); ok "$(has 'NOT recorded: this session has no RESUME snapshot' "$out")" yes "no snapshot -> says not recorded"
printf '## START HERE\n1. a\n2. b\n' > "$st/resume-S.snap.md"
out=$(P "sounds good /ok -1"); ok "$(has 'CHECK-IN recorded' "$out")" yes "mid-prompt /ok with dash recorded"
ok "$(cut -f1,2 "$st/confirm-S.tsv" | tail -1)" "1	accepted" "item 1 accepted"
out=$(P "/defer 2"); ok "$(cut -f1,2 "$st/confirm-S.tsv" | tail -1)" "2	deferred" "/defer 2 recorded"
rm -f "$st/checkin-S"; out=$(P "/o 0"); ok "$(has 'unrecognised mark' "$out")" yes "typo /o -> told not recorded"
ok "$([ -f "$st/checkin-S" ] && echo y || echo n)" n "typo creates no check-in"
out=$(P "see ~/notes/ok later"); ok "$(has 'CHECK-IN' "$out")" no "path containing /ok is not a mark"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
