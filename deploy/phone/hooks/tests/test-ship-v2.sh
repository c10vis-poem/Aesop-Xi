#!/data/data/com.termux/files/usr/bin/bash
# ship-session.v2.sh end-to-end: local bare remotes, stub gh (PR OPEN for 2 views, then MERGED;
# head $GH_STUCK stays OPEN forever), fake vault. Global gitleaks git hooks run for real.
source "$(dirname "$0")/lib.sh"
V2=$HOOKS/ship-session.v2.sh
SID=33333333-aaaa-bbbb-cccc-000000000000
S="session/$(date +%F)-33333333"
export GHT=$T GH_STUCK=topic/two POLL_MAX=6 POLL_SECS=1
mkdir -p "$T/ghpr"
cat > "$T/bin/gh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
echo "$*" >> "$GHT/gh.log"
case "$1 $2" in
  "pr create")
    while [ $# -gt 0 ]; do [ "$1" = --head ] && head=$2; shift; done
    n=$(( $(ls "$GHT/ghpr" | grep -c '\.head$') + 1 ))
    echo "$head" > "$GHT/ghpr/$n.head"; pwd > "$GHT/ghpr/$n.dir"
    echo "https://github.com/stub/repo/pull/$n" ;;
  "pr view")
    n=${3##*/}; head=$(cat "$GHT/ghpr/$n.head"); c=$(( $(cat "$GHT/ghpr/$n.c" 2>/dev/null || echo 0) + 1 ))
    echo $c > "$GHT/ghpr/$n.c"
    { [ "$head" = "$GH_STUCK" ] || [ $c -le 2 ]; } && s=OPEN || s=MERGED
    git -C "$(cat "$GHT/ghpr/$n.dir")" rev-parse -q --verify "refs/heads/$head" >/dev/null && ex=yes || ex=no
    echo "VIEW $head $s local=$ex" >> "$GHT/gh.log"
    echo $s ;;
esac
exit 0
EOF
for r in ra rs rn; do mkrepo $r; done
W=$T/work; R=$T/remotes
refs() { for r in ra rs rn; do git -C "$W/$r" for-each-ref; git -C "$R/$r.git" for-each-ref; git -C "$W/$r" status --porcelain; done; }

# Before the session: an old unpushed branch (commit dated 2h ago) + old dirt.
( cd "$W/ra" && git switch -q -c old/stale && echo s > stale.txt && git add stale.txt \
  && GIT_COMMITTER_DATE="$(date -d '-2 hour' -R)" GIT_AUTHOR_DATE="$(date -d '-2 hour' -R)" git commit -q -m stale \
  && git switch -q main ) >/dev/null 2>&1
echo pre >> "$W/ra/b.txt"; touch -d '-1 hour' "$W/ra/b.txt"

# Session start marker (back-dated so session writes are clearly newer).
ledger "$(bash_ev 'git status' "$W/rn")"
touch -d '-1 minute' "$STATE_DIR/session-$SID.start"
# Two local topic branches: topic/one in main worktree, topic/two in a second worktree.
( cd "$W/ra" && git switch -q -c topic/one && echo 1 > one.txt && git add one.txt && git commit -q -m "feat: one" && git switch -q main
  git worktree add -q -b topic/two "$T/work/ra-wt" && cd "$T/work/ra-wt" && echo 2 > two.txt && git add two.txt && git commit -q -m "feat: two" ) >/dev/null 2>&1
ledger "$(bash_ev 'git commit -m one' "$W/ra")"
echo session >> "$W/ra/a.txt"; ledger "$(write_ev "$W/ra/a.txt")"            # leftover, uncommitted
# rs: secret committed past the pre-commit hook; pre-push gitleaks must refuse it.
( cd "$W/rs" && git switch -q -c topic/secret \
  && printf 'token = "ghp_%s"\n' "$(head -c 400 /dev/urandom | tr -dc A-Za-z0-9 | head -c 36)" > conf.txt \
  && git add conf.txt && git commit -q --no-verify -m "chore: conf" && git switch -q main ) >/dev/null 2>&1
ledger "$(bash_ev 'git commit -m conf' "$W/rs")"
echo note > "$VAULT/note.md"; ledger "$(write_ev "$VAULT/note.md")"
L=$(ls "$VAULT"/_recaps/*-33333333.md)

# Dry run: reports, changes nothing.
before=$(refs; cat "$L"); dry=$(bash "$V2" --dry-run "$SID" 2>&1); echo "$dry"
check "dry-run: plans leftover commit + both topic branches" 'grep -q "would commit 1 file(s) on $S" <<<"$dry" && grep -q "would push topic/one" <<<"$dry" && grep -q "would push topic/two" <<<"$dry"'
check "dry-run: old branch not planned" '! grep -q old/stale <<<"$dry"'
check "dry-run: changes nothing (refs, remotes, status, recap, flag)" '[ "$before" = "$(refs; cat "$L")" ] && [ ! -e "$STATE_DIR/last-session-resume.flag" ]'

# Real run (no RESUME.md in vault).
bash "$V2" --worker "$SID" > "$SHIP_LOG" 2>&1
cat "$SHIP_LOG"; echo ----; cat "$L"; echo ----; cat "$T/gh.log"
sha=$(sed -n "s|.*/ra: committed leftovers on $S (\([0-9a-f]*\))|\1|p" "$L")
check "leftover: only a.txt committed on $S, pushed, PR'd" '[ -n "$sha" ] && [ "$(git -C "$R/ra.git" show --name-only --format= "$sha")" = a.txt ] && grep -q -- "--head $S" "$T/gh.log"'
check "leftover: pre-existing b.txt still dirty" 'git -C "$W/ra" status --porcelain | grep -q "^ M b.txt"'
check "topic/one + topic/two pushed" 'grep -q "pr create.*--head topic/one" "$T/gh.log" && git -C "$R/ra.git" rev-parse -q --verify refs/heads/topic/two >/dev/null'
check "3 PRs created (session, one, two), body ends with Claude Code line" '[ "$(grep -c "^pr create" "$T/gh.log")" = 3 ] && grep -q "Generated with \[Claude Code\](https://claude.com/claude-code)" "$T/gh.log"'
check "auto-merge --squash --delete-branch per PR" '[ "$(grep -c -- "^pr merge https://github.com/stub/repo/pull/[0-9] --auto --squash --delete-branch$" "$T/gh.log")" = 3 ]'
check "old unpushed branch NOT pushed" '! git -C "$R/ra.git" rev-parse -q --verify refs/heads/old/stale >/dev/null && ! grep -q old/stale "$T/gh.log" && git -C "$W/ra" rev-parse -q --verify refs/heads/old/stale >/dev/null'
check "no branch deleted while OPEN (local existed at every OPEN view)" 'grep -q "OPEN local=yes" "$T/gh.log" && ! grep -q "OPEN local=no" "$T/gh.log"'
check "topic/one deleted after MERGED (local+remote)" 'grep -q "VIEW topic/one MERGED" "$T/gh.log" && ! git -C "$W/ra" rev-parse -q --verify refs/heads/topic/one >/dev/null && ! git -C "$R/ra.git" rev-parse -q --verify refs/heads/topic/one >/dev/null'
check "topic/two still OPEN -> kept local+remote, awaiting merge" 'git -C "$W/ra" rev-parse -q --verify refs/heads/topic/two >/dev/null && git -C "$R/ra.git" rev-parse -q --verify refs/heads/topic/two >/dev/null && grep -q "branch topic/two, PR .*, auto-merge on, merged pending (awaiting merge), branch deleted no" "$L"'
check "recap row for topic/one" 'grep -qE "/ra: branch topic/one, PR https://github.com/stub/repo/pull/[0-9], auto-merge on, merged yes, branch deleted yes" "$L"'
check "secret branch BLOCKED at push, not on remote, no PR" 'grep -q "/rs: branch topic/secret: BLOCKED: secret found at push" "$L" && ! git -C "$R/rs.git" rev-parse -q --verify refs/heads/topic/secret >/dev/null && ! grep -q topic/secret "$T/gh.log"'
check "rn nothing to ship; vault skipped" 'grep -q "/rn: skipped: nothing to ship" "$L" && grep -q "/vault: skipped: vault (GitSync)" "$L"'
check "RESUME missing -> recap + flag" 'grep -qx "RESUME: NOT REWRITTEN" "$L" && [ "$(cat "$STATE_DIR/last-session-resume.flag")" = "missing 33333333 $(date +%F)" ]'
check "recap sections" '[ "$(grep "^## " "$L" | tr "\n" "|")" = "## Repos touched|## Files written|## Git actions|## Shipped|## Title|" ]'

# Second session rewrites the vault RESUME.md -> flag ok.
SID=44444444-aaaa-bbbb-cccc-000000000000
ledger "$(bash_ev 'ls' "$VAULT")"; touch -d '-1 minute' "$STATE_DIR/session-$SID.start"
echo resume > "$VAULT/RESUME.md"; ledger "$(write_ev "$VAULT/RESUME.md")"
bash "$V2" --worker "$SID" >> "$SHIP_LOG" 2>&1
check "RESUME rewritten -> recap + flag ok" 'grep -qx "RESUME: rewritten" "$VAULT"/_recaps/*-44444444.md && [ "$(cat "$STATE_DIR/last-session-resume.flag")" = ok ]'
finish
