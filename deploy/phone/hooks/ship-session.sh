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

if [ -n "$since" ] && [ "$VAULT/RESUME.md" -nt "$marker" ]; then resume=rewritten; flag=ok
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
  [ -n "$pr" ] && gh pr merge "$pr" --auto --squash --delete-branch >/dev/null 2>&1 && am=on
  B_top+=("$top") B_br+=("$br") B_pr+=("${pr:-none}") B_am+=("$am") B_mg+=("$([ -n "$pr" ] && echo pending || echo no-PR)")
}

ship_repo() { # $1 = repo toplevel
  local url br n0=${#lines[@]} nb0=${#B_br[@]}
  top=$1
  [ "$top" = "$vault_top" ] && { lines+=("- $top: skipped: vault (GitSync)"); return; }
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

while IFS= read -r top; do ship_repo "$top" </dev/null; done < <(section 'Repos touched')

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

printf '%s\n' "${lines[@]}"
title=$(cat "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | grep '"ai-title"' | jq -r 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
printf '\n## Shipped\n\n%s\n\nRESUME: %s\n\n## Title\n\n%s\n' "$(printf '%s\n' "${lines[@]:-- nothing}")" "$resume" "${title:-(no ai-title found)}" >> "$ledger"
echo "=== done"
