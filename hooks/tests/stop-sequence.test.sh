#!/data/data/com.termux/files/usr/bin/bash
# stop-gate.sh: opening steps O1-O6 named and enforced; wrap-up W1 (PENDING in repo OR vault), W5 (RESUME rewritten
# AND dated today), W6 (vault uncommitted -> vault-ship); #skip-enforce inside a subagent hand-back is ignored;
# operator-only items yield on stop_hook_active.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export HOME=$T
st=$T/.claude/state; V=$T/storage/shared/Documents/NovAExorpus; mkdir -p "$st" "$V"
repo=$T/repo; git init -q -b main "$repo"; git -C "$repo" config user.email t@x; git -C "$repo" config user.name t
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
tp=$T/t.jsonl; : > "$tp"
umsg(){ jq -nc --arg c "$1" '{type:"user",message:{role:"user",content:$c}}' >> "$tp"; }
G(){ jq -n --arg c "$repo" --arg t "$tp" --argjson a "${1:-false}" '{session_id:"S",cwd:$c,transcript_path:$t,stop_hook_active:$a}' | bash "$S/stop-gate.sh" | jq -r '.reason // ""'; }
has(){ grep -c -- "$2" <<<"$1"; }
# repo files
printf '# RESUME\n\nLast updated: 2026-10-01\n\n## START HERE\n1. Fix the widget\n2. Write the doc\n' > "$repo/RESUME.md"
printf '# AGENTS\n' > "$repo/AGENTS.md"; printf '# PENDING\n' > "$repo/PENDING.md"; printf '# MEMORY\n' > "$repo/MEMORY.md"
git -C "$repo" add . && git -C "$repo" commit -qm init; echo old > "$V/RESUME.md"; echo "# P" > "$V/PENDING.md"

out=$(G); ok "$(has "$out" 'Opening O1')" 1 "O1: RESUME not read"
sha256sum "$repo/RESUME.md" | cut -d' ' -f1 > "$st/resume-S.ok"; cp "$repo/RESUME.md" "$st/resume-S.snap.md"
out=$(G); ok "$(has "$out" 'Opening O2')" 1 "O2: AGENTS.md not read"; ok "$(has "$out" 'Opening O3')" 1 "O3: PENDING.md not read"; ok "$(has "$out" 'Opening O4')" 1 "O4: plan not posted"
printf 'read:AGENTS.md\t%s\t00:00\nread:PENDING.md\t%s\t00:00\n' "$repo/AGENTS.md" "$repo/PENDING.md" > "$st/opening-S.tsv"
out=$(G); ok "$(has "$out" 'Opening O2')" 0 "O2 satisfied by the opening ledger"; ok "$(has "$out" 'Opening O4')" 1 "O4 still missing"
touch "$st/plan-S.txt"; out=$(G); ok "$(has "$out" 'Opening O6')" 1 "O6: waiting for check-in"
ok "$(G true | wc -c | tr -d ' ')" 0 "only operator items left -> yields on stop_hook_active"
# bypass: #skip-enforce inside a subagent hand-back does not count; typed by the operator it does
umsg "<agent-message from=\"x\">all done #skip-enforce</agent-message>"
out=$(G); ok "$(has "$out" 'Opening O6')" 1 "#skip-enforce from a subagent is ignored"
umsg "fine, #skip-enforce"; ok "$(G | wc -c | tr -d ' ')" 0 "#skip-enforce typed by the operator skips"
umsg "/ok 1,2"; touch "$st/checkin-S"; printf '1\taccepted\t00:00\n2\taccepted\t00:00\n' > "$st/confirm-S.tsv"
ok "$(G | wc -c | tr -d ' ')" 0 "checked in, nothing else open -> stop allowed"

# ---- wrap-up ----
touch "$st/wrapup-S"
printf '1\tconfirmed-done\t00:01\n2\tdeferred\t00:01\n' >> "$st/confirm-S.tsv"
out=$(G)
ok "$(has "$out" 'item 2 was deferred by the operator')" 1 "W1: deferred item must be in PENDING"
ok "$(has "$out" 'Wrap-up W5: rewrite')" 1 "W5: RESUME not rewritten"
echo "- Write the doc" >> "$repo/PENDING.md"
out=$(G); ok "$(has "$out" 'item 2 was deferred by the operator')" 0 "W1: deferred item accepted in the REPO PENDING.md"
printf '# RESUME\n\nLast updated: 2026-10-01\n\n## START HERE\n1. x\n' > "$repo/RESUME.md"
out=$(G); ok "$(has "$out" "don't carry today's date")" 1 "W5: rewritten but not dated today"
printf '# RESUME\n\nLast updated: %s\n\n## START HERE\n1. x\n' "$(date +%F)" > "$repo/RESUME.md"
out=$(G); ok "$(has "$out" 'Wrap-up W5: /')" 0 "W5: repo RESUME rewritten and dated passes"
ok "$(has "$out" 'vault RESUME.md')" 1 "W5: vault RESUME still has to be rewritten"
printf 'Last session: %s\n' "$(date +%F)" > "$V/RESUME.md"
out=$(G); ok "$(has "$out" 'vault RESUME.md')" 0 "W5: dated vault RESUME passes"
ok "$(has "$out" 'uncommitted session work in')" 1 "W6: repo changes uncommitted"
git -C "$repo" add . && git -C "$repo" commit -qm wrap
# vault with uncommitted changes -> vault-ship, not the old GitSync exemption
git init -q "$V" 2>/dev/null; git -C "$V" config user.email t@x; git -C "$V" config user.name t; git -C "$V" add . && git -C "$V" commit -qm v >/dev/null
echo "# P\n- new" > "$V/PENDING.md"
mkdir -p "$V/_recaps"; printf '# Session S\n\n## Repos touched\n- %s\n\n## Files written\n- %s/PENDING.md\n' "$V" "$V" > "$V/_recaps/$(date +%F)-S.md"
out=$(G); ok "$(has "$out" 'vault has uncommitted changes')" 1 "W6: vault uncommitted -> vault-ship"
git -C "$V" add . && git -C "$V" commit -qm p >/dev/null
out=$(G); ok "$(has "$out" 'vault has uncommitted changes')" 0 "W6: vault committed passes"
ok "$(has "$out" 'Wrap-up W3')" 1 "W3: MEMORY.md unchanged is reported"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
