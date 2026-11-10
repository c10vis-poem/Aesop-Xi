#!/usr/bin/env bash
# ship-session.sh scope: (1) a worktree the session never touched is NOT shipped (operator order 2026-11-05),
# while one reached with `git -C` IS listed and shipped,
# (2) a repo with no origin is reported "NO REMOTE, NOT SHIPPED" (not silently skipped),
# (3) no recap copy per repo: the session log is save-session-log's (Rule 7), one place only.
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
# A second worktree the session did reach, through git -C from another cwd.
( cd "$W/rn" && git worktree add -q -b reached "$REPOS_DIR/.wt-rn-reached" && cd "$REPOS_DIR/.wt-rn-reached" && echo r > r.txt && git add r.txt && git commit -q -m "feat: reached" ) >/dev/null 2>&1
ledger "$(bash_ev "git -C $REPOS_DIR/.wt-rn-reached commit -m reached" "$T")"
L=$(ls "$RECAPS_DIR"/*-55555555.md)
touch "$STATE_DIR/pushok-$SID"
check "ledger lists rn and rw but not rx or its worktree" 'grep -q "/rn$" "$L" && grep -q "/rw$" "$L" && ! grep -q "rx" "$L"'

dry=$(bash "$HOOKS/ship-session.sh" --dry-run "$SID" 2>&1); echo "$dry"
check "dry-run: unlisted worktree branch NOT planned" '! grep -q "pending-fold" <<<"$dry"'
check "dry-run: git -C worktree planned" 'grep -q "would push reached" <<<"$dry"'
check "dry-run: no-remote repo reported" 'grep -q "/rw: NO REMOTE, NOT SHIPPED" <<<"$dry"'
check "dry-run: no recap copy planned" '! grep -q "would copy" <<<"$dry"'

bash "$HOOKS/ship-session.sh" --worker "$SID" > "$SHIP_LOG" 2>&1; cat "$SHIP_LOG"; echo ----; cat "$L"; echo ----; cat "$T/gh.log"
check "untouched repo rx: not pushed, no PR" '! git -C "$T/remotes/rx.git" rev-parse -q --verify refs/heads/pending-fold >/dev/null && ! grep -q -- "--head pending-fold" "$T/gh.log"'
check "untouched repo rx: not in the recap" '! grep -q "/rx" "$L"'
check "git -C worktree branch pushed with a PR" 'git -C "$T/remotes/rn.git" rev-parse -q --verify refs/heads/reached >/dev/null && grep -q -- "--head reached" "$T/gh.log"'
check "no-remote repo: loud line in recap" 'grep -q "/rw: NO REMOTE, NOT SHIPPED" "$L"'
check "no-remote repo: not described as a non-fork skip" '! grep -q "/rw: skipped: origin not" "$L"'
check "no recaps/<repo> branch made by ship-session" '! git -C "$T/remotes/rr.git" rev-parse -q --verify refs/heads/recaps/$(date +%F)-55555555 >/dev/null'
check "recaps worktree cleaned up" '[ ! -e "$W/rr/.wt-recaps-55555555" ]'
check "untouched nothing-to-ship repos stay out of the recap" '! grep -q "/rr: skipped" "$L"'
finish
