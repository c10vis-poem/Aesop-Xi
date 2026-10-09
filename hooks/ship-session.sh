#!/data/data/com.termux/files/usr/bin/bash
# SessionEnd: ship everything this session made, in one pass (policy: mid-session commits stay on
# LOCAL topic branches; no push/PR/merge until here). Per repo in the session-ledger.sh recap's
# "## Repos touched" (not the vault, not ECC-aesop, origin must match ORIGIN_RE):
#   1. leftovers = ledger "Files written" in that repo + dirty files newer than the start marker
#      -> committed onto a session branch (never `git add -A`).
#   2. every local branch (any worktree) except the default with commits not on any remote branch
#      and committed after the start marker -> push (pre-push gitleaks) -> PR (reuse open one)
#      -> gh pr merge --auto --squash --delete-branch.
#   3. poll PR state up to POLL_MAX s; local+remote branch deleted ONLY once state is MERGED.
#   4. append "## Shipped" (+ RESUME: rewritten|NOT REWRITTEN) and "## Title" to the recap;
#      write $STATE_DIR/last-session-resume.flag (ok | missing <sid8> <date>).
# Usage: SessionEnd hook (JSON on stdin; detaches) | ship-session.sh --dry-run <session_id>
# Env overrides (tests): VAULT, STATE_DIR, PROJECTS_DIR, ORIGIN_RE, SHIP_LOG, POLL_MAX, POLL_SECS.
VAULT=${VAULT:-/data/data/com.termux/files/home/storage/shared/Documents/NovAExorpus}
STATE_DIR=${STATE_DIR:-$HOME/.claude/state}
PROJECTS_DIR=${PROJECTS_DIR:-$HOME/.claude/projects}
ORIGIN_RE=${ORIGIN_RE:-github\.com[:/]c10vis-poem/}
SHIP_LOG=${SHIP_LOG:-$HOME/.claude/logs/ship-session.log}
POLL_MAX=${POLL_MAX:-600}
POLL_SECS=${POLL_SECS:-30}
SKIP=" "   # none: ECC is parked, not off-limits (2026-10-01)

case $1 in
  --dry-run) dry=1; sid=$2 ;;
  --worker|--now) sid=$2 ;;
  *) # hook entry: detach so session exit isn't delayed
    sid=$(jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$sid" ] || exit 0
    mkdir -p "${SHIP_LOG%/*}"
    setsid nohup "$0" --worker "$sid" >>"$SHIP_LOG" 2>&1 </dev/null &
    exit 0 ;;
esac
[ -n "$sid" ] || { echo "usage: $0 --dry-run <session_id>" >&2; exit 2; }

ledger=$(ls "$VAULT/_recaps/"*-"${sid:0:8}".md 2>/dev/null | head -1)
[ -n "$ledger" ] || { echo "no ledger for $sid"; exit 0; }
date=$(basename "$ledger"); date=${date:0:10}
marker="$STATE_DIR/session-$sid.start"
since=; [ -e "$marker" ] && since=@$(stat -c %Y "$marker")
section() { awk -v s="## $1" '/^## /{on=($0==s);next} on && /^- /{print substr($0,3)}' "$ledger"; }
vault_top=$(git -C "$VAULT" rev-parse --show-toplevel 2>/dev/null)
echo "=== $(date '+%F %T') session=$sid dry=${dry:-0}"

# Nothing ships until the operator has approved the change review ("#ok push"; review-changes.sh).
if [ -s "$STATE_DIR/changes-$sid.log" ] && [ ! -f "$STATE_DIR/pushok-$sid" ]; then
  echo "held: change review not approved"
  [ -z "$dry" ] && printf '\n## Shipped\n\n- NOT SHIPPED: the operator has not approved the change review (#ok push). Run hooks/review-changes.sh %s, then ship with: ship-session.sh --now %s\n' "$sid" "$sid" >> "$ledger"
  exit 0
fi

# "Rewritten" = RESUME.md's top 40 lines carry today's date (WRAP-UP requires a dated rewrite);
# mtime alone is unreliable (GitSync conflict handling touches the file).
# Content check (mtime is unreliable on shared storage): differs from the hash resume-gate stored at session start.
base=$(cat "$STATE_DIR/resume-$sid.ok" 2>/dev/null)
if [ -n "$base" ] && [ "$(sha256sum "$VAULT/RESUME.md" | cut -d' ' -f1)" != "$base" ] && head -40 "$VAULT/RESUME.md" 2>/dev/null | grep -q "$(date +%F)"; then resume=rewritten; flag=ok
else resume="NOT REWRITTEN"; flag="missing ${sid:0:8} $date"; fi
[ -z "$dry" ] && { mkdir -p "$STATE_DIR"; echo "$flag" > "$STATE_DIR/last-session-resume.flag"; }

lines=()                                   # repo-level results
B_top=() B_br=() B_pr=() B_am=() B_mg=()   # one entry per shipped branch

commit_leftovers() { # in $top; sets $result (empty if nothing to commit)
  local cur br made files=() f out orig written
  written=$(section 'Files written'); result=
  while IFS= read -r -d '' f; do
    [ -e "$f" ] || continue   # deletions are not shipped
    if grep -Fxq -- "$top/$f" <<<"$written" || { [ -e "$marker" ] && [ "$f" -nt "$marker" ]; }; then files+=("$f"); fi
  done < <({ git ls-files -z -m -o --exclude-standard; git diff -z --cached --name-only; } | sort -zu)
  [ ${#files[@]} -gt 0 ] || return
  cur=$(git branch --show-current)
  br=$cur; [ -z "$cur" ] || [ "$cur" = "$def" ] && br="session/$date-${sid:0:8}"
  [ -n "$dry" ] && { result="DRY-RUN: would commit ${#files[@]} file(s) on $br: ${files[*]}"; return; }
  orig=${cur:-$(git rev-parse HEAD)}
  [ "$br" != "$cur" ] && { git switch -q -c "$br" || { result="BLOCKED: cannot create $br"; return; }; made=1; }
  git add -- "${files[@]}"
  if ! out=$(git commit -q -m "chore: session $date changes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "${files[@]}" 2>&1); then
    git reset -q -- "${files[@]}"
    git switch -q "$orig" 2>/dev/null || git checkout -q "$orig"
    [ -n "$made" ] && git branch -q -d "$br"
    echo "$out"
    grep -q gitleaks <<<"$out" && result="BLOCKED: secret found" || result="BLOCKED: commit failed"; return
  fi
  result="committed leftovers on $br ($(git rev-parse --short HEAD))"
  git switch -q "$orig" 2>/dev/null || git checkout -q "$orig"
}

ship_branch() { # $1 = local branch, in $top
  local br=$1 out pr am=refused
  if [ -n "$dry" ]; then lines+=("- $top: DRY-RUN: would push $br, PR to $def, auto-merge, delete after MERGED"); return; fi
  if ! out=$(git push -q -u origin "$br" 2>&1); then
    echo "$out"
    grep -q gitleaks <<<"$out" && lines+=("- $top: branch $br: BLOCKED: secret found at push") \
                               || lines+=("- $top: branch $br: BLOCKED: push rejected"); return
  fi
  pr=$(gh pr list --repo "$slug" --head "$br" --state open --json url -q '.[0].url' 2>/dev/null)
  [ -n "$pr" ] || pr=$(gh pr create --repo "$slug" --base "$def" --head "$br" --title "$(git log -1 --format=%s "$br")" \
        --body "Session $sid work on \`$br\`, shipped by ship-session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" 2>/dev/null | tail -1)
  if grep -Fxq -- "$br" "$STATE_DIR/keep-$sid.txt" 2>/dev/null; then   # operator said #keep-branch
    git push -q origin "$br:refs/heads/saved/$br" 2>/dev/null && lines+=("- $top: kept copy saved/$br (operator #keep-branch)")
  fi
  # No auto-merge without CI and required checks: on such a branch "auto" means "merge now, unchecked".
  why=$(bash "$(dirname "$0")/ci-ready.sh" "$slug" "$def"); rc=$?
  if [ -n "$pr" ] && [ $rc -eq 3 ]; then   # private + free plan: wait for green CI, then merge
    if timeout "$POLL_MAX" gh pr checks "$pr" --watch --fail-fast >/dev/null 2>&1 \
       && gh pr merge "$pr" --squash --delete-branch >/dev/null 2>&1; then am="merged after green CI (private repo)"
    else am="refused (CI not green; private repo, merge by hand)"; fi
  elif [ -n "$pr" ] && [ $rc -ne 0 ]; then
    am="refused ($why)"
  else
    [ -n "$pr" ] && gh pr merge "$pr" --auto --squash --delete-branch >/dev/null 2>&1 && am=on
  fi
  B_top+=("$top") B_br+=("$br") B_pr+=("${pr:-none}") B_am+=("$am") B_mg+=("$([ -n "$pr" ] && echo pending || echo no-PR)")
}

ship_repo() { # $1 = repo toplevel
  local url br n0=${#lines[@]} nb0=${#B_br[@]}
  top=$1
  [ "$top" = "$vault_top" ] && { lines+=("- $top: skipped: vault (GitSync)"); return; }
  # A worktree shares refs with its main repo: ship each real repo once.
  local common; common=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return
  [ "${common##*/}" = .git ] && top=${common%/.git}
  case " ${SEEN_REPOS:-} " in *" $top "*) return;; esac
  SEEN_REPOS="${SEEN_REPOS:-} $top"
  case $SKIP in *" ${top##*/} "*) lines+=("- $top: skipped: off-limits"); return;; esac
  url=$(git -C "$top" remote get-url origin 2>/dev/null)
  [[ $url =~ $ORIGIN_RE ]] || { lines+=("- $top: skipped: origin not a c10vis-poem fork"); return; }
  url=${url%.git}; slug=${url##*[:/]}; url=${url%/*}; slug=${url##*[:/]}/$slug
  cd "$top" || { lines+=("- $top: skipped: missing"); return; }
  def=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); def=${def#origin/}; def=${def:-main}

  commit_leftovers; [ -n "$result" ] && lines+=("- $top: $result")
  [ -n "$since" ] || { lines+=("- $top: no start marker; unpushed branches not shipped"); return; }
  while IFS= read -r br; do
    [ -n "$(git log -1 --format=%H "refs/heads/$br" --not --remotes --since="$since")" ] || continue
    [ "$br" = "$def" ] && { lines+=("- $top: unpushed commits on $def NOT shipped (never push to default)"); continue; }
    ship_branch "$br"
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)
  [ ${#lines[@]} -eq "$n0" ] && [ ${#B_br[@]} -eq "$nb0" ] && lines+=("- $top: skipped: nothing to ship")
}


# Vault: GitSync pushes to the unprotected vault-sync branch; vault-sync -> main goes through a
# normal PR (CI + secret scan) with a MERGE commit, then vault-sync is brought back to main
# (fast-forward, or recreated if the merge auto-deleted it).
VAULT_REPO=${VAULT_REPO:-c10vis-poem/NovAExorpus}; vault_pr=""
vault_step() {
  local ahead am
  ahead=$(gh api "repos/$VAULT_REPO/compare/main...vault-sync" --jq .ahead_by 2>/dev/null) || ahead=0
  if [ "${ahead:-0}" -gt 0 ]; then
    if [ -n "$dry" ]; then lines+=("- vault: vault-sync is $ahead commit(s) ahead of main; would open PR + auto-merge (merge commit)"); return; fi
    vault_pr=$(gh pr list -R "$VAULT_REPO" --head vault-sync --state open --json url -q '.[0].url' 2>/dev/null)
    [ -n "$vault_pr" ] || vault_pr=$(gh pr create -R "$VAULT_REPO" --base main --head vault-sync --title "vault sync $(date +%F)" \
      --body "$(printf 'GitSync vault changes from the phone. Merged by the end-of-session ship step.\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)')" 2>/dev/null)
    am=refused; [ -n "$vault_pr" ] && gh pr merge "$vault_pr" -R "$VAULT_REPO" --auto --merge >/dev/null 2>&1 && am=on
    lines+=("- vault: PR ${vault_pr:-none} (vault-sync -> main, $ahead commits), auto-merge $am")
  else lines+=("- vault: vault-sync has nothing new for main"); fi
}
vault_realign() {
  local m st
  m=$(gh api "repos/$VAULT_REPO/commits/main" --jq .sha 2>/dev/null) || return
  if ! gh api "repos/$VAULT_REPO/git/refs/heads/vault-sync" >/dev/null 2>&1; then
    gh api -X POST "repos/$VAULT_REPO/git/refs" -f ref=refs/heads/vault-sync -f sha="$m" >/dev/null 2>&1 \
      && lines+=("- vault: vault-sync recreated at main ${m:0:7}") || lines+=("- vault: vault-sync recreate FAILED")
    return
  fi
  st=$(gh api "repos/$VAULT_REPO/compare/vault-sync...main" --jq .status 2>/dev/null)
  [ "$st" = ahead ] && { gh api -X PATCH "repos/$VAULT_REPO/git/refs/heads/vault-sync" -f sha="$m" -F force=false >/dev/null 2>&1 \
      && lines+=("- vault: vault-sync fast-forwarded to main ${m:0:7}") || lines+=("- vault: vault-sync fast-forward FAILED (diverged)"); }
}

while IFS= read -r top; do ship_repo "$top" </dev/null; done < <(section 'Repos touched')
# upload the vault first (vault-ship replaces GitSync's upload); then the vault-sync -> main PR
if [ -z "$dry" ]; then lines+=("- vault: $(bash "$(dirname "$0")/vault-ship.sh" 2>&1 | tail -1)"); fi
vault_step

if [ -n "$dry" ]; then printf '%s\n' "${lines[@]}"; echo "RESUME: $resume"; exit 0; fi

# Poll until every PR is MERGED or POLL_MAX elapses; delete branches only after MERGED.
end=$((SECONDS + POLL_MAX))
while :; do
  left=0
  for i in "${!B_br[@]}"; do
    [ "${B_mg[i]}" = pending ] || continue
    if [ "$(gh pr view "${B_pr[i]}" --json state -q .state 2>/dev/null)" = MERGED ]; then
      B_mg[i]=yes
      git -C "${B_top[i]}" branch -q -D "${B_br[i]}" 2>/dev/null   # fails if checked out somewhere
      git -C "${B_top[i]}" ls-remote -q --exit-code --heads origin "${B_br[i]}" >/dev/null \
        && git -C "${B_top[i]}" push -q origin --delete "${B_br[i]}"
    else left=1; fi
  done
  if [ -n "$vault_pr" ]; then [ "$(gh pr view "$vault_pr" --json state -q .state 2>/dev/null)" = MERGED ] && vault_pr="" || left=1; fi
  [ $left = 0 ] || [ $SECONDS -ge $end ] && break
  sleep "$POLL_SECS"
done
for i in "${!B_br[@]}"; do
  del=no
  [ "${B_mg[i]}" = yes ] && ! git -C "${B_top[i]}" rev-parse -q --verify "refs/heads/${B_br[i]}" >/dev/null \
    && ! git -C "${B_top[i]}" ls-remote -q --exit-code --heads origin "${B_br[i]}" >/dev/null && del=yes
  mg=${B_mg[i]}; [ "$mg" = pending ] && mg="pending (awaiting merge)"
  lines+=("- ${B_top[i]}: branch ${B_br[i]}, PR ${B_pr[i]}, auto-merge ${B_am[i]}, merged $mg, branch deleted $del")
done

vault_realign

printf '%s\n' "${lines[@]}"
title=$(cat "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | grep '"ai-title"' | jq -r 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
printf '\n## Shipped\n\n%s\n\nRESUME: %s\n\n## Title\n\n%s\n' "$(printf '%s\n' "${lines[@]:-- nothing}")" "$resume" "${title:-(no ai-title found)}" >> "$ledger"
echo "=== done"
