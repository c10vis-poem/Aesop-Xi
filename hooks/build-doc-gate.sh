#!/data/data/com.termux/files/usr/bin/bash
# obs 0005. PostToolUse Read: a Read of a checkout's install/build doc (README, INSTALL, BUILD,
# CONTRIBUTING, docs/*install*|*build*) is recorded in ~/.claude/state/docread-<sid>.txt.
# PreToolUse Bash: pip install / npm install / npm ci / pnpm install / make / cargo build /
# cmake --build / gradle / ./gradlew inside a ~/repos/<repo> checkout (cwd, or `cd` in the command)
# is blocked until that repo's doc was Read this session. Worktrees count as their repo.
# The fork sync itself is H2 sync-on-use.sh's job.
in=$(cat)
IFS=$'\x1f' read -r ev sid tool cwd fp < <(jq -r '[.hook_event_name, .session_id, .tool_name, (.cwd // ""), (.tool_input.file_path // "")] | join("\u001f")' <<<"$in" 2>/dev/null)
[ -n "$sid" ] || exit 0
st="$HOME/.claude/state"; f="$st/docread-$sid.txt"
key(){ case $1 in "$HOME"/repos/*) ;; *) return 1 ;; esac   # repo identity: shared git dir
  [ -d "$1" ] || return 1
  d=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && echo "${d%/.git}"; }
if [ "$ev" = PostToolUse ]; then
  [ "$tool" = Read ] || exit 0
  fp=${fp/#\~/$HOME}
  [[ ${fp##*/} =~ ^(README|INSTALL|BUILD|CONTRIBUTING)(\.md)?$ || ${fp,,} =~ /docs/.*(install|build)[^/]*$ ]] || exit 0
  k=$(key "${fp%/*}") || exit 0
  mkdir -p "$st"; echo "$k" >> "$f"; exit 0
fi
c=$(jq -r '.tool_input.command // ""' <<<"$in")
B='(^|[;&|[:space:](])(pip3? install|npm (install|ci)|pnpm install|make|cargo build|cmake --build|gradle|\./gradlew)([[:space:]]|$)'
command grep -qE "$B" <<<"$c" || exit 0
d=$(command grep -oE '(^|[;&|[:space:](])cd[[:space:]]+[^;&|[:space:]]+' <<<"$c" | head -1 | sed -E 's/.*cd[[:space:]]+//; s/["'\'']//g')
d=${d/#\~/$HOME}; d=${d//\$HOME/$HOME}; [ -n "$d" ] || d=$cwd; [[ $d = /* ]] || d=$cwd/$d
k=$(key "$d") || exit 0
command grep -qxF "$k" "$f" 2>/dev/null && exit 0
echo "BLOCKED (build-doc-gate): read ${k##*/}'s install/build doc first (README.md, INSTALL.md, BUILD.md, CONTRIBUTING.md or docs/*install*|*build*) with the Read tool, then rerun (obs 0005)." >&2
exit 2
