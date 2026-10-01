#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse hook (Bash|Edit|Write|Read): sync a c10vis-poem repo once per session, detached. Always exit 0.

sync_repo() {  # detached worker: sync_repo <sid> <dir> <name>
  local sid=${1:0:8} d=$2 n=$3 log="$HOME/.claude/logs/sync-on-use.log" out up def br
  mkdir -p "${log%/*}"
  say() { echo "$(date '+%F %T') $sid $n $*" >>"$log"; }
  if [ "$(gh repo view "c10vis-poem/$n" --json isFork,parent --jq .isFork 2>/dev/null)" = true ]; then
    if out=$(gh repo sync "c10vis-poem/$n" 2>&1); then say "synced"
    else
      case $out in
        *diverging*)
          up=$(gh api "repos/c10vis-poem/$n" --jq '"\(.parent.owner.login):\(.parent.default_branch) \(.default_branch)"')
          set -- $up
          gh pr list --repo "c10vis-poem/$n" --head "${1#*:}" --state open --json number --jq length | grep -q '^[1-9]' \
            || gh pr create --repo "c10vis-poem/$n" --base "$2" --head "$1" --title "sync: merge upstream ${1}" --body "Fork diverged; upstream brought in by PR (never force-synced)." >/dev/null 2>&1
          say "diverged: upstream PR ensured" ;;
        *) say "sync FAILED: ${out//$'\n'/ }" ;;
      esac
    fi
  else say "not a fork, no gh sync"; fi
  br=$(git -C "$d" symbolic-ref --short -q HEAD)
  def=$(git -C "$d" symbolic-ref --short -q refs/remotes/origin/HEAD); def=${def#origin/}
  if [ -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]; then
    git -C "$d" fetch -q 2>/dev/null; say "not pulled: dirty"
  elif [ -z "$br" ] || [ "$br" != "${def:-main}" ]; then
    git -C "$d" fetch -q 2>/dev/null; say "not pulled: branch ${br:-detached}"
  elif git -C "$d" pull --ff-only -q 2>/dev/null; then say "pulled @ $(git -C "$d" rev-parse --short HEAD)"
  else say "pull FAILED"; fi
}

if [ "$1" = --sync ]; then sync_repo "$2" "$3" "$4"; exit 0; fi

# fast path: no forks except jq; repo name from path alone
IFS="|" read -r sid cwd tool fp < <(jq -r '[.session_id, .cwd, .tool_name, (.tool_input.file_path // "")] | join("|")' 2>/dev/null)
case $tool in Edit|Write|Read) p=${fp%/*} ;; Bash) p=$cwd ;; *) exit 0 ;; esac
root="$HOME/repos/"
case $p/ in "$root"?*) ;; *) exit 0 ;; esac
n=${p#"$root"}; n=${n%%/*}
[ -n "$sid" ] && [ -n "$n" ] || exit 0
state="$HOME/.claude/state"; m="$state/synced-$sid-$n"
[ -e "$m" ] && exit 0

# slow path (once per repo per session): verify it is a c10vis-poem repo
mkdir -p "$state"; : >"$m"
d="$root$n"
[ "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" = "$d" ] || exit 0
case $(git -C "$d" remote get-url origin 2>/dev/null) in *github.com[:/]c10vis-poem/"$n"|*github.com[:/]c10vis-poem/"$n".git) ;; *) exit 0 ;; esac
nohup bash "$0" --sync "$sid" "$d" "$n" >/dev/null 2>&1 </dev/null &
exit 0
