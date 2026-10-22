#!/data/data/com.termux/files/usr/bin/bash
# H3 session-ledger.sh: sections, dedupe, git-action filter/truncation, marker, never blocks.
source "$(dirname "$0")/lib.sh"
SID=11111111-aaaa-bbbb-cccc-000000000000
mkrepo r1
F="$T/work/r1/a.txt"

ledger "$(write_ev "$F")"; rc=$?
ledger "$(write_ev "$F")"
ledger "$(bash_ev 'git commit -m "x"' "$T/work/r1")"
ledger "$(bash_ev "git push origin $(printf 'z%.0s' {1..300})" "$T/work/r1")"
ledger "$(bash_ev 'ls -la' "$T/work/r1")"
ledger "$(bash_ev 'gh pr create --fill' /)"
L=$(ls "$VAULT"/_recaps/*-11111111.md 2>/dev/null)
cat "$L"

check "exit 0" '[ $rc -eq 0 ]'
check "ledger named <date>-<sid8>.md" '[ "$(basename "$L")" = "$(date +%F)-11111111.md" ]'
check "start marker written" '[ -e "$STATE_DIR/session-$SID.start" ]'
check "sections present in order" '[ "$(grep "^## " "$L" | tr "\n" "|")" = "## Repos touched|## Files written|## Git actions|" ]'
check "repo recorded once" '[ "$(grep -cFx -- "- $T/work/r1" "$L")" = 1 ]'
check "file recorded once" '[ "$(grep -cFx -- "- $F" "$L")" = 1 ]'
check "file under Files written" 'awk "/^## Files written/{f=1;next}/^## /{f=0}f" "$L" | grep -qFx -- "- $F"'
check "git commit recorded" 'grep -qF "\`git commit -m \"x\"\`" "$L"'
check "gh pr create recorded" 'grep -qF "\`gh pr create --fill\`" "$L"'
check "non-git bash not recorded" '! grep -q "ls -la" "$L"'
check "git cmd truncated to 200" '[ "$(grep "git push" "$L" | wc -c)" -le 206 ]'
bash "$HOOKS/session-ledger.sh" <<<"not json"; rc=$?
check "garbage stdin exits 0" '[ $rc -eq 0 ]'
finish
