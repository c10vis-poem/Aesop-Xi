#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Write, Edit, NotebookEdit, Bash): record every change under shared-storage Documents/
# so the operator reviews them all at wrap-up, before anything is pushed. Nothing is blocked.
#   state/docs-changes-<sid>.log, one line per action: time, kind, where, detail
#   kind: NEW (new file), CHANGE (mv/cp/rm/mkdir/redirect/...), SCRIPT (interpreter run), EDIT
#   where: vault | keep | OUTSIDE (anywhere else in Documents/, flagged for review)
# Bash is a heuristic: a verb plus an absolute Documents path. A bare `cd` + relative write is not seen.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in")
ST="$HOME/.claude/state"; LOG="$ST/docs-changes-$sid.log"
PRE='(/storage/emulated/0|/sdcard|~/storage/shared|/data/data/com\.termux/files/home/storage/shared|\$HOME/storage/shared)/Documents/'
where() { # $1 = text; prints vault | keep | OUTSIDE (OUTSIDE wins if any path is outside)
  local t w=
  while IFS= read -r t; do
    case "$t" in *"/../"*|*"/.."|"../"*) echo OUTSIDE; return;; esac
    case "$t" in NovAExorpus|NovAExorpus/*) w=${w:-vault};; "Merovingian's_keep"|"Merovingian's_keep"/*) w=keep;; *) echo OUTSIDE; return;; esac
  done < <(sed -E "s#$PRE#\n@@#g" <<<"$1" | sed -n 's/^@@//p')
  echo "${w:-vault}"
}
log() { mkdir -p "$ST"; printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$(where "$2")" "${2:0:300}" >> "$LOG"; }

if [ "$tool" = Bash ]; then
  c=$(jq -r '.tool_input.command // ""' <<<"$in")
  grep -qE "$PRE" <<<"$c" || exit 0
  s=$(sed -E 's/[0-9]*>&[0-9]//g; s#[0-9]*>[[:space:]]*/dev/null##g' <<<"$c")
  V='(^|[|;&[:space:]])'
  if grep -qE "${V}(mv|cp|rm|rmdir|mkdir|touch|ln|rsync|install|truncate|dd|unzip|tar|curl|wget|tee)([[:space:]]|$)|git[[:space:]]+(mv|rm)|>" <<<"$s"; then log CHANGE "$c"
  elif grep -qE "${V}(python3?|node|bash|sh|zsh|perl|ruby)([[:space:]]|$)" <<<"$s"; then log SCRIPT "$c"
  elif grep -qE "sed[^|;&]*[[:space:]]-[a-zA-Z]*i|${V}(chmod|chown)([[:space:]]|$)" <<<"$s"; then log EDIT "$c"
  fi
  exit 0
fi
f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")
grep -qE "$PRE" <<<"$f" || exit 0
if [ "$tool" = Write ] && [ ! -e "$f" ]; then log NEW "$f"; else log EDIT "$f"; fi
exit 0
