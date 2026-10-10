#!/data/data/com.termux/files/usr/bin/bash
# ship-session.sh gaps: (1) a session worktree never listed under "Repos touched" is still shipped,
# (2) a repo with no origin is reported "NO REMOTE, NOT SHIPPED" (not silently skipped),
# (3) the recap is copied to <recaps repo>/recaps/<repo>/ for every repo touched.
source "$(dirname "$0")/lib.sh"
SID=55555555-aaaa-bbbb-cccc-000000000000
export REPOS_DIR=$T/repos RECAPS_REPO=$T/work/rr POLL_MAX=2 POLL_SECS=1
mkdir -p "$REPOS_DIR"
for r in rx rn rr; do mkrepo $r; done
W=$T/work
git init -q -b main "$W/rw" && ( cd "$W/rw" && echo w > w.txt && git add . && git commit -q -m init )   # no remote
ledger "$(bash_ev 'git status' "$W/rn")"
touch -d '-1 minute' "$STATE_DIR/session-$SID.start"
# The session works in a worktree of rx that the ledger never sees.
( cd "$W/rx" && git worktree add -q -b pending-fold "$REPOS_DIR/.wt-rx-pending" \
  && cd "$REPOS_DIR/.wt-rx-pending" && echo p > p.txt && git add p.txt && git commit -q -m "feat: pending-fold" ) >/dev/null 2>&1
ledger "$(bash_ev 'ls' "$W/rw")"
L=$(ls "$VAULT"/_recaps/*-55555555.md)
check "ledger lists rn and rw but not rx or its worktree" 'grep -q "/rn$" "$L" && grep -q "/rw$" "$L" && ! grep -q "rx" "$L"'

dry=$(bash "$HOOKS/ship-session.sh" --dry-run "$SID" 2>&1); echo "$dry"
check "dry-run: unlisted worktree branch planned" 'grep -q "would push pending-fold" <<<"$dry"'
check "dry-run: no-remote repo reported" 'grep -q "/rw: NO REMOTE, NOT SHIPPED" <<<"$dry"'
check "dry-run: recap copy planned for rn and rw" 'grep -qE "would copy .* to recaps/\{rn rw\}/" <<<"$dry"'

bash "$HOOKS/ship-session.sh" --worker "$SID" > "$SHIP_LOG" 2>&1; cat "$SHIP_LOG"; echo ----; cat "$L"; echo ----; cat "$T/gh.log"
check "worktree branch pending-fold pushed + PR'd" 'git -C "$T/remotes/rx.git" rev-parse -q --verify refs/heads/pending-fold >/dev/null && grep -q -- "--head pending-fold" "$T/gh.log"'
check "recap lists the pending-fold shipment" 'grep -q "/rx: branch pending-fold, PR " "$L"'
check "no-remote repo: loud line in recap" 'grep -q "/rw: NO REMOTE, NOT SHIPPED" "$L"'
check "no-remote repo: not described as a non-fork skip" '! grep -q "/rw: skipped: origin not" "$L"'
check "recaps branch pushed with a copy per repo" 'b=recaps/$(date +%F)-55555555; git -C "$T/remotes/rr.git" rev-parse -q --verify refs/heads/$b >/dev/null && for n in rn rw; do git -C "$T/remotes/rr.git" cat-file -e $b:recaps/$n/$(basename "$L") || exit 1; done'
check "recaps PR created" 'grep -q -- "--head recaps/$(date +%F)-55555555" "$T/gh.log"'
check "recaps worktree cleaned up" '[ ! -e "$W/rr/.wt-recaps-55555555" ]'
check "untouched nothing-to-ship repos stay out of the recap" '! grep -q "/rr: skipped" "$L"'
finish
