#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Write, Edit, NotebookEdit, Bash): record every write, move, copy, delete and script run
# the agent makes, anywhere, so the operator reviews them all at wrap-up before anything is pushed
# (review-changes.sh shows the list; ship-session.sh ships only after the operator's "#ok push").
# Nothing is blocked. One line per action in state/changes-<sid>.log:
#   time  kind  where  detail
#   kind:  NEW (new file) | EDIT | CHANGE (mv/cp/rm/mkdir/redirect/...) | SCRIPT (interpreter run)
#   where: vault | keep | DOCUMENTS (elsewhere in shared Documents/) | repo:<name> | home | other
# Bash is a heuristic: a write verb, redirect or interpreter in the command. Reads are not logged.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
ST="$HOME/.claude/state"; LOG="$ST/changes-$sid.log"
DOCS='(/storage/emulated/0|/sdcard|~/storage/shared|/data/data/com\.termux/files/home/storage/shared|\$HOME/storage/shared)/Documents/'
where() { # $1 = path or command text
  local t; t=$(sed -E "s#$DOCS#@@DOCS@@#g; s#Merovingian.s_keep#Merovingian_s_keep#g" <<<"$1")
  case $t in
    *@@DOCS@@NovAExorpus/../*|*@@DOCS@@NovAExorpus-*) echo DOCUMENTS; return ;;
  esac
  grep -qE '@@DOCS@@' <<<"$t" && {
    grep -qvE '@@DOCS@@(NovAExorpus|Merovingian.s_keep)(/|[[:space:]"'"'"']|$)' <(grep -oE '@@DOCS@@[^[:space:]"'"'"']*' <<<"$t") && { echo DOCUMENTS; return; }
    grep -q '@@DOCS@@Merovingian' <<<"$t" && { echo keep; return; }
    echo vault; return; }
  local p; p=$(grep -oE '(/|~/)[^[:space:]"'"'"';|&>]+' <<<"$1" | head -1); p=${p/#\~/$HOME}
  [ -n "$p" ] || p=$cwd
  local d=$p; while [ -n "$d" ] && [ ! -d "$d" ]; do d=${d%/*}; done
  local top; top=$(git -C "${d:-/}" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$top" ]; then echo "repo:${top##*/}"
  else case $p in "$HOME"/*) echo home ;; *) echo other ;; esac; fi
}
log() { mkdir -p "$ST"; printf '%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "$(where "$2")" "$(tr '\n' ' ' <<<"${2:0:400}")" >> "$LOG"; }

if [ "$tool" = Bash ]; then
  c=$(jq -r '.tool_input.command // ""' <<<"$in")
  s=$(sed -E 's/[0-9]*>&[0-9]//g; s#[0-9]*>>?[[:space:]]*/dev/null##g' <<<"$c")
  V='(^|[|;&[:space:]])'
  if grep -qE "${V}(mv|cp|rm|rmdir|mkdir|touch|ln|rsync|install|truncate|dd|unzip|tar|curl|wget|tee|pkg|apt|npm|pip)([[:space:]]|$)|git[[:space:]]+(mv|rm)|>" <<<"$s"; then log CHANGE "$c"
  elif grep -qE "${V}(python3?|node|perl|ruby)([[:space:]]|$)|${V}(bash|sh|zsh)[[:space:]]+[^-]" <<<"$s"; then log SCRIPT "$c"
  elif grep -qE "sed[^|;&]*[[:space:]]-[a-zA-Z]*i|${V}(chmod|chown)([[:space:]]|$)" <<<"$s"; then log EDIT "$c"
  fi
  exit 0
fi
f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")
[ -n "$f" ] || exit 0
if [ "$tool" = Write ] && [ ! -e "$f" ]; then log NEW "$f"; else log EDIT "$f"; fi
exit 0
