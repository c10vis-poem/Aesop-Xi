#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Bash|Edit|Write): no edits or commits in a c10vis-poem repo whose branch doesn't contain
# the latest origin/<default>. Work must start from current main. Vault exempt (GitSync owns it).
# Fetches each repo once per session. Fails open on errors.
in=$(cat)
IFS=$'\t' read -r sid tool fp cwd < <(jq -r '[.session_id, .tool_name, (.tool_input.file_path // ""), (.cwd // "")] | @tsv' <<<"$in" 2>/dev/null)
case $tool in
  Edit|Write) p=${fp%/*} ;;
  Bash) jq -r '.tool_input.command // ""' <<<"$in" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)' || exit 0
        # the directory in effect at the commit: last `cd X` before `git commit` (or -C path)
        c=$(jq -r '.tool_input.command' <<<"$in" | sed -E 's/git[[:space:]]+([^;&|]*[[:space:]])?commit.*//' | grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|[:space:]]+' | tail -1 | sed -E 's/.*cd[[:space:]]+//')
        p=$(eval echo "${c:-$cwd}" 2>/dev/null) ;;
  *) exit 0 ;;
esac
top=$(git -C "$p" rev-parse --show-toplevel 2>/dev/null) || exit 0
case $top in */NovAExorpus*|*/storage/emulated/*) exit 0 ;; esac
case $(git -C "$top" remote get-url origin 2>/dev/null) in *github.com[:/]c10vis-poem/*) ;; *) exit 0 ;; esac
def=$(git -C "$top" symbolic-ref --short -q refs/remotes/origin/HEAD); def=${def:-origin/main}
st="$HOME/.claude/state"; m="$st/fetched-$sid-$(echo "$top" | md5sum | cut -c1-8)"
[ -e "$m" ] || { timeout 25 git -C "$top" fetch -q origin 2>/dev/null; mkdir -p "$st"; : > "$m"; }
git -C "$top" rev-parse -q --verify "$def" >/dev/null || exit 0
git -C "$top" merge-base --is-ancestor "$def" HEAD && exit 0
br=$(git -C "$top" symbolic-ref --short -q HEAD || echo detached)
echo "$(date +%T) BLOCK branch-current: $top ($br) lacks $def" >> "$st/enforce-$sid.log"
echo "BLOCKED (branch-current): $top is on '$br', which doesn't contain the latest $def. Start from current main: git -C $top worktree add -b <topic> ../.wt-<topic> $def  (or merge $def into '$br' first)." >&2
exit 2
