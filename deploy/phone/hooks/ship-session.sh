#!/data/data/com.termux/files/usr/bin/bash
# SessionEnd: ship ONLY what this session touched, per the session-ledger.sh recap.
# Per repo in "## Repos touched" (not the vault, not ECC-aesop, origin must match ORIGIN_RE):
#   files = ledger "Files written" in that repo + dirty files newer than the session-start marker.
#   branch (if on default) -> commit those paths only (global gitleaks hook runs) -> push -> PR
#   -> auto-merge THAT PR -> switch back. Then append "## Shipped" and "## Title" to the recap.
# Usage: SessionEnd hook (JSON on stdin; detaches) | ship-session.sh --dry-run <session_id>
# Env overrides (tests): VAULT, STATE_DIR, PROJECTS_DIR, ORIGIN_RE, SHIP_LOG.
VAULT=${VAULT:-/data/data/com.termux/files/home/storage/shared/Documents/NovAExorpus}
STATE_DIR=${STATE_DIR:-$HOME/.claude/state}
PROJECTS_DIR=${PROJECTS_DIR:-$HOME/.claude/projects}
ORIGIN_RE=${ORIGIN_RE:-github\.com[:/]c10vis-poem/}
SHIP_LOG=${SHIP_LOG:-$HOME/.claude/logs/ship-session.log}
SKIP=" ECC-aesop "

case $1 in
  --dry-run) dry=1; sid=$2 ;;
  --worker) sid=$2 ;;
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
section() { awk -v s="## $1" '/^## /{on=($0==s);next} on && /^- /{print substr($0,3)}' "$ledger"; }
vault_top=$(git -C "$VAULT" rev-parse --show-toplevel 2>/dev/null)
echo "=== $(date '+%F %T') session=$sid dry=${dry:-0}"

shipped=()
ship_repo() { # $1 = repo toplevel; sets $result
  local top=$1 url slug def cur br made files=() f msg out sha pr
  [ "$top" = "$vault_top" ] && { result="skipped: vault (GitSync)"; return; }
  case $SKIP in *" ${top##*/} "*) result="skipped: off-limits"; return;; esac
  url=$(git -C "$top" remote get-url origin 2>/dev/null)
  [[ $url =~ $ORIGIN_RE ]] || { result="skipped: origin not a c10vis-poem fork"; return; }
  url=${url%.git}; slug=${url##*[:/]}; url=${url%/*}; slug=${url##*[:/]}/$slug
  cd "$top" || { result="skipped: missing"; return; }

  local written; written=$(section 'Files written')
  while IFS= read -r -d '' f; do
    [ -e "$f" ] || continue   # deletions are not shipped
    if grep -Fxq -- "$top/$f" <<<"$written" || { [ -e "$marker" ] && [ "$f" -nt "$marker" ]; }; then files+=("$f"); fi
  done < <({ git ls-files -z -m -o --exclude-standard; git diff -z --cached --name-only; } | sort -zu)
  [ ${#files[@]} -gt 0 ] || { result="skipped: nothing to ship"; return; }

  def=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); def=${def#origin/}; def=${def:-main}
  cur=$(git branch --show-current)
  br=$cur; [ -z "$cur" ] || [ "$cur" = "$def" ] && br="session/$date-${sid:0:8}"
  if [ -n "$dry" ]; then
    result="DRY-RUN: would commit ${#files[@]} file(s) on $br, push, PR to $def, auto-merge: ${files[*]}"; return
  fi

  local orig=${cur:-$(git rev-parse HEAD)}
  [ "$br" != "$cur" ] && { git switch -q -c "$br" || { result="BLOCKED: cannot create $br"; return; }; made=1; }
  git add -- "${files[@]}"
  if ! out=$(git commit -q -m "chore: session $date changes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "${files[@]}" 2>&1); then
    git reset -q -- "${files[@]}"
    git switch -q "$orig" 2>/dev/null || git checkout -q "$orig"
    [ -n "$made" ] && git branch -q -d "$br"
    echo "$out"
    grep -q gitleaks <<<"$out" && result="BLOCKED: secret found" || result="BLOCKED: commit failed"; return
  fi
  sha=$(git rev-parse --short HEAD)
  if ! git push -q -u origin "$br"; then
    git switch -q "$orig" 2>/dev/null || git checkout -q "$orig"
    result="BLOCKED: push rejected ($br $sha)"; return
  fi
  pr=$(gh pr create --repo "$slug" --base "$def" --head "$br" --title "chore: session $date changes" \
        --body "Session $sid changes, shipped by ship-session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)" 2>/dev/null | tail -1)
  [ -n "$pr" ] || pr=$(gh pr view "$br" --repo "$slug" --json url -q .url 2>/dev/null)
  local am=refused; [ -n "$pr" ] && gh pr merge "$pr" --auto --squash >/dev/null 2>&1 && am=on
  git switch -q "$orig" 2>/dev/null || git checkout -q "$orig"
  result="branch $br, commit $sha, PR ${pr:-none}, auto-merge $am"
}

while IFS= read -r top; do
  ship_repo "$top" </dev/null
  echo "$top: $result"
  shipped+=("- $top: $result")
done < <(section 'Repos touched')

[ -n "$dry" ] && exit 0
title=$(cat "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | grep '"ai-title"' | jq -r 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
printf '\n## Shipped\n\n%s\n\n## Title\n\n%s\n' "$(printf '%s\n' "${shipped[@]:-- nothing}")" "${title:-(no ai-title found)}" >> "$ledger"
echo "=== done"
