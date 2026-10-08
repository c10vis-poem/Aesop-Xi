#!/data/data/com.termux/files/usr/bin/bash
# H2, PreToolUse (Bash|Edit|Write|Read): a c10vis-poem repo under ~/repos is not touched until it is
# synced. The first tool call that touches it (file path, cwd, or a ~/repos/<name> path inside a Bash
# command; worktrees resolve to their real repo) waits for: `gh repo sync` of the fork from upstream,
# then a fast-forward of the local default branch. Success is remembered for the session; failure
# BLOCKS the call (exit 2) with the reason, and the next call retries.
# Diverged forks: an upstream-merge PR is ensured and work may proceed (a fork that cannot
# fast-forward only gets upstream through that PR). Dirty clones or clones on a feature branch are
# fetched, not pulled; branch-current-gate.sh then requires work to start from current main.
log="$HOME/.claude/logs/sync-on-use.log"; state="$HOME/.claude/state"; root="$HOME/repos/"
mkdir -p "${log%/*}" "$state"

sync_repo() {  # sync_repo <sid8> <dir> <name>; prints a failure reason and returns 1 on failure
  local sid=$1 d=$2 n=$3 out up def br
  say() { echo "$(date '+%F %T') $sid $n $*" >>"$log"; }
  if [ "$(timeout 20 gh repo view "c10vis-poem/$n" --json isFork --jq .isFork 2>/dev/null)" = true ]; then
    if out=$(timeout 30 gh repo sync "c10vis-poem/$n" 2>&1); then say "synced"
    else
      case $out in
        *diverging*)
          up=$(gh api "repos/c10vis-poem/$n" --jq '"\(.parent.owner.login):\(.parent.default_branch) \(.default_branch)"')
          set -- $up
          gh pr list --repo "c10vis-poem/$n" --head "${1#*:}" --state open --json number --jq length | grep -q '^[1-9]' \
            || gh pr create --repo "c10vis-poem/$n" --base "$2" --head "$1" --title "sync: merge upstream ${1}" --body "Fork diverged; upstream brought in by PR (never force-synced)." >/dev/null 2>&1
          say "diverged: upstream PR ensured" ;;
        *) say "sync FAILED: ${out//$'\n'/ }"; echo "gh repo sync failed: ${out//$'\n'/ }"; return 1 ;;
      esac
    fi
  else say "not a fork, no gh sync"; fi
  br=$(git -C "$d" symbolic-ref --short -q HEAD)
  def=$(git -C "$d" symbolic-ref --short -q refs/remotes/origin/HEAD); def=${def#origin/}
  if ! timeout 30 git -C "$d" fetch -q origin 2>/dev/null; then say "fetch FAILED"; echo "git fetch failed"; return 1; fi
  if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then say "not pulled: dirty"
  elif [ -z "$br" ] || [ "$br" != "${def:-main}" ]; then say "not pulled: branch ${br:-detached}"
  elif git -C "$d" merge --ff-only -q "origin/${def:-main}" 2>/dev/null; then say "pulled @ $(git -C "$d" rev-parse --short HEAD)"
  else say "pull FAILED"; echo "local ${def:-main} cannot fast-forward to origin"; return 1; fi
}

IFS="|" read -r sid cwd tool fp cmd < <(jq -r '[.session_id, .cwd, .tool_name, (.tool_input.file_path // ""), ((.tool_input.command // "") | gsub("[|\n]"; " "))] | join("|")' 2>/dev/null)
[ -n "$sid" ] || exit 0
case $tool in
  Edit|Write|Read) paths=${fp%/*} ;;
  Bash) paths=$(printf '%s\n' "$cwd"; grep -oE "(~|\\\$HOME|$HOME)/repos/[^[:space:]/\"';|&)]+" <<<"$cmd" | sed "s#^~#$HOME#; s#^\\\$HOME#$HOME#") ;;
  *) exit 0 ;;
esac

fail=()
while IFS= read -r p; do
  case $p/ in "$root"?*) ;; *) continue ;; esac
  n=${p#"$root"}; n=${n%%/*}; d="$root$n"
  [ -d "$d" ] || continue
  c=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  [ "${c##*/}" = .git ] && d=${c%/.git}; n=${d##*/}          # worktree -> its real repo
  m="$state/synced-$sid-$n"; [ -e "$m" ] && continue
  case $(git -C "$d" remote get-url origin 2>/dev/null) in
    *github.com[:/]c10vis-poem/"$n"|*github.com[:/]c10vis-poem/"$n".git) ;;
    *) : >"$m"; continue ;;                                   # not one of the operator's repos
  esac
  if why=$(sync_repo "${sid:0:8}" "$d" "$n"); then : >"$m"; else fail+=("$n: $why"); fi
done < <(printf '%s\n' "$paths" | sort -u)

[ ${#fail[@]} -eq 0 ] && exit 0
echo "BLOCKED (sync-on-use): not synced yet, so not touched: $(IFS=';'; echo "${fail[*]}"). Fix the cause (network, auth, local divergence) and retry; the next call syncs again." >&2
exit 2
