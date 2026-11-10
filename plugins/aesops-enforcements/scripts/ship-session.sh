#!/usr/bin/env bash
# SessionEnd: the operator's GitHub rule (Rule 8), in one pass. Forks touched are synced first (repo-gate);
# every push and merge waits until here. Nothing ships until the operator's wrap-up order (/wrapup, recorded
# by enforce-prompt); only repos in the session-ledger.sh recap's "## Repos touched" are looked at: never
# a repo merely because it has worktrees or unpushed branches. #no-ship skips the SessionEnd run.
# The session log (scratchpad and task log) is the wrap-up's job, not this one: save-session-log.sh.
# Per touched repo (origin must match ORIGIN_RE):
#   1. leftovers = ledger "Files written" in that repo + dirty files newer than the start marker
#      -> committed onto a session branch (never `git add -A`).
#   2. every local branch (any worktree) except the default with commits not on any remote branch
#      and committed after the start marker -> gitleaks scan (no gitleaks, no gh: not shipped) -> push
#      -> PR (reuse open one) -> ci-ready preflight -> the repo's "delete head branches on merge" setting on
#      -> gh pr merge --auto --squash, set while CI runs. No watching CI, no deleting by hand: GitHub merges
#      on green and deletes the branch. (Private free-plan repos cannot auto-merge: wait for green, merge.)
#   (also) the vault ships (vault-ship, then the vault-sync PR) only when the session touched it.
#   (also) a repo with no origin is reported "NO REMOTE, NOT SHIPPED", never silently skipped.
#   4. append "## Shipped" (+ RESUME: rewritten|NOT REWRITTEN) and "## Title" to the recap;
#      write $STATE_DIR/last-session-resume.flag (ok | missing <sid8> <date>).
# Usage: SessionEnd hook (JSON on stdin; detaches) | ship-session.sh --dry-run <session_id>
# Env overrides (tests): VAULT, STATE_DIR, RECAPS_DIR, PROJECTS_DIR, ORIGIN_RE, SHIP_LOG, POLL_MAX, POLL_SECS.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
STATE_DIR=$ST
PROJECTS_DIR=${PROJECTS_DIR:-$HOME/.claude/projects}
ORIGIN_RE=${ORIGIN_RE:-github\.com[:/]c10vis-poem/}
SHIP_LOG=${SHIP_LOG:-$HOME/.claude/logs/ship-session.log}
POLL_MAX=${POLL_MAX:-600}
POLL_SECS=${POLL_SECS:-30}
REPOS_DIR=${REPOS_DIR:-$HOME/repos}
RECAPS_REPO=${RECAPS_REPO:-$REPOS_DIR/NvAEx-Recaps}
SKIP=" "   # none: ECC is parked, not off-limits (2026-10-01)

case $1 in
  --dry-run) dry=1; sid=$2 ;;
  --worker|--now) sid=$2 ;;
  *) # hook entry: detach so session exit isn't delayed
    sid=$(jq -r '.session_id // empty' 2>/dev/null)
    [ -n "$sid" ] || exit 0
    mkdir -p "${SHIP_LOG%/*}"
    setsid nohup bash "$0" --worker "$sid" >>"$SHIP_LOG" 2>&1 </dev/null &
    exit 0 ;;
esac
[ -n "$sid" ] || { echo "usage: $0 --dry-run <session_id>" >&2; exit 2; }

ledger=$(ls "$RECAPS_DIR/"*-"${sid:0:8}".md 2>/dev/null | head -1)
[ -n "$ledger" ] || { echo "no ledger for $sid"; exit 0; }
date=$(basename "$ledger"); date=${date:0:10}
marker="$STATE_DIR/session-$sid.start"
since=; [ -e "$marker" ] && since=@$(stat -c %Y "$marker")
section() { awk -v s="## $1" '/^## /{on=($0==s);next} on && /^- /{print substr($0,3)}' "$ledger"; }
vault_top=; [ -n "$VAULT" ] && vault_top=$(git -C "$VAULT" rev-parse --show-toplevel 2>/dev/null)
vault_touched=; [ -n "$vault_top" ] && section 'Repos touched' | grep -qxF -- "$vault_top" && vault_touched=1
echo "=== $(date '+%F %T') session=$sid dry=${dry:-0}"
[ "$1" = --worker ] && [ -e "$STATE_DIR/noship-$sid" ] && { echo "held: operator typed #no-ship"; printf '\n## Shipped\n\n- NOT SHIPPED: the operator typed #no-ship. Ship by hand with: ship-session --now %s\n' "$sid" >> "$ledger"; exit 0; }

# Nothing ships until the operator's wrap-up order (/wrapup; enforce-prompt records it).
if [ ! -f "$STATE_DIR/pushok-$sid" ]; then
  echo "held: no wrap-up order"
  [ -z "$dry" ] && printf '\n## Shipped\n\n- NOT SHIPPED: the operator did not give the wrap-up order (/wrapup). Ship with: ship-session --now %s\n' "$sid" >> "$ledger"
  exit 0
fi

# "Rewritten" = RESUME.md's top 40 lines carry today's date (WRAP-UP requires a dated rewrite);
# mtime alone is unreliable (GitSync conflict handling touches the file).
# Content check (mtime is unreliable on shared storage): differs from the hash direction-gate stored at session start.
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
  if [ -n "$dry" ]; then lines+=("- $top: DRY-RUN: would push $br, PR to $def, auto-merge and auto-delete"); return; fi
  # The pipeline's secret scan runs here too: a device without the global git hooks must not push unscanned.
  command -v gitleaks >/dev/null 2>&1 || { degrade ship-scan "ship-session: no gitleaks here, $top not shipped"; lines+=("- $top: branch $br: NOT SHIPPED: no gitleaks on this device (pipeline needs the secret scan)"); return; }
  command -v gh >/dev/null 2>&1 || { degrade ship-gh "ship-session: no gh here, $top not shipped"; lines+=("- $top: branch $br: NOT SHIPPED: no gh on this device (no PR, so no push)"); return; }
  if ! out=$(gitleaks git --log-opts="$br --not --remotes" --redact --no-banner 2>&1); then
    echo "$out"; lines+=("- $top: branch $br: BLOCKED: secret found at push"); return
  fi
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
  why=$(bash "$HOOKS_DIR/ci-ready.sh" "$slug" "$def"); rc=$?
  if [ -e "$STATE_DIR/nomerge-$sid" ]; then
    am="held (operator typed #no-merge)"
  elif [ -n "$pr" ] && [ $rc -eq 3 ]; then   # private + free plan: wait for green CI, then merge
    # obs 0069: right after a push, "no checks reported" means "not registered yet", never "no CI".
    # Wait (up to 120 s) until at least one check exists for the PR before watching it.
    for _w in $(seq 24); do
      [ -n "$(gh pr checks "$pr" --json name -q '.[].name' 2>/dev/null)" ] && break; sleep 5
    done
    if timeout "$POLL_MAX" gh pr checks "$pr" --watch --fail-fast >/dev/null 2>&1 \
       && gh pr merge "$pr" --squash --delete-branch >/dev/null 2>&1; then am="merged after green CI (private repo)"
    else am="refused (CI not green; private repo, merge by hand)"; fi
  elif [ -n "$pr" ] && [ $rc -ne 0 ]; then
    am="refused ($why)"
  else
    # GitHub deletes the branch on merge (repo setting); auto-merge set now, while CI runs. No watching.
    gh repo edit "$slug" --delete-branch-on-merge >/dev/null 2>&1 && ad=on || ad="not set (gh repo edit failed)"
    [ -n "$pr" ] && gh pr merge "$pr" --auto --squash >/dev/null 2>&1 && am="on, auto-delete $ad"
  fi
  B_top+=("$top") B_br+=("$br") B_pr+=("${pr:-none}") B_am+=("$am")
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
  [ -n "$url" ] || { lines+=("- $top: NO REMOTE, NOT SHIPPED ($(git -C "$top" status --porcelain 2>/dev/null | wc -l) dirty file(s); create its c10vis-poem GitHub repo and add origin)"); return; }
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

main_top() { # $1 = any path inside a repo or worktree -> the main repo's toplevel
  local c; c=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "${c##*/}" = .git ] && echo "${c%/.git}" || echo "$1"
}
# Quiet variant for the recaps repo (ship-session touched it, the session did not).
ship_extra() {
  local n=${#lines[@]} nb=${#B_br[@]} i keep=()
  ship_repo "$1" </dev/null
  [ ${#B_br[@]} -gt "$nb" ] && return
  for ((i = n; i < ${#lines[@]}; i++)); do
    case ${lines[i]} in *": skipped:"*|*": no start marker"*) ;; *) keep+=("${lines[i]}");; esac
  done
  lines=("${lines[@]:0:n}" "${keep[@]}")
}
while IFS= read -r top; do ship_repo "$top" </dev/null; done < <(section 'Repos touched')
[ -n "$dry" ] || [ ! -d "$RECAPS_REPO/.git" ] || ship_extra "$RECAPS_REPO"
# upload the vault first (vault-ship replaces GitSync's upload); then the vault-sync -> main PR
if [ -n "$vault_touched" ]; then
  [ -n "$dry" ] || lines+=("- vault: $(bash "$HOOKS_DIR/vault-ship.sh" 2>&1 | tail -1)")
  vault_step
fi

if [ -n "$dry" ]; then printf '%s\n' "${lines[@]}"; echo "RESUME: $resume"; exit 0; fi

for i in "${!B_br[@]}"; do
  lines+=("- ${B_top[i]}: branch ${B_br[i]}, PR ${B_pr[i]}, auto-merge ${B_am[i]}")
done

[ -n "$vault_touched" ] && vault_realign

printf '%s\n' "${lines[@]}"
title=$(cat "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | grep '"ai-title"' | jq -r 'select(.type=="ai-title") | .aiTitle // empty' 2>/dev/null | tail -1)
printf '\n## Shipped\n\n%s\n\nRESUME: %s\n\n## Title\n\n%s\n' "$(printf '%s\n' "${lines[@]:-- nothing}")" "$resume" "${title:-(no ai-title found)}" >> "$ledger"
echo "=== done"
