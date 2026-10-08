#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Write, Edit, NotebookEdit, Bash): nothing under shared-storage Documents/ is created,
# moved, copied or deleted without the operator approving it.
#   - outside the vault (NovAExorpus/) and Merovingian's_keep/: blocked
#   - inside them: creating, moving, copying, deleting, or running a script on a Documents path asks
#     the operator (Claude Code permission prompt); editing an existing file is allowed
#   - every allowed or asked action is appended to state/docs-changes-<sid>.log
# Operator override: #skip-enforce in the prompt (enforce-prompt.sh sets state/docsok-<sid>, cleared
# each prompt) pre-approves this prompt's Documents changes, e.g. an approved batch job.
# Bash is a heuristic: a verb plus an absolute Documents path. A bare `cd` + relative write is not seen.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in")
ST="$HOME/.claude/state"; LOG="$ST/docs-changes-$sid.log"
PRE='(/storage/emulated/0|/sdcard|~/storage/shared|/data/data/com\.termux/files/home/storage/shared|\$HOME/storage/shared)/Documents/'
OK="^(Merovingian's_keep|NovAExorpus)(/|$)"
bad=
scan() { # $1 = text; sets bad to the first disallowed tail
  local t
  while IFS= read -r t; do
    case "$t" in *"/../"*|*"/.."|"../"*) bad=$t; return;; esac
    grep -qE "$OK" <<<"$t" || { bad=$t; return; }
  done < <(sed -E "s#$PRE#\n@@#g" <<<"$1" | sed -n 's/^@@//p')
}
log() { mkdir -p "$ST"; printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$1" "${2:0:300}" >> "$LOG"; }
ask() { # $1 = what, $2 = detail
  log "ASK $1" "$2"
  jq -n --arg r "documents-guard: $1 in Documents/ needs your approval: ${2:0:200}" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

if [ "$tool" = Bash ]; then
  c=$(jq -r '.tool_input.command // ""' <<<"$in")
  grep -qE "$PRE" <<<"$c" || exit 0
  s=$(sed -E 's/[0-9]*>&[0-9]//g; s#[0-9]*>[[:space:]]*/dev/null##g' <<<"$c")
  V='(^|[|;&[:space:]])'
  change="${V}(mv|cp|rm|rmdir|mkdir|touch|ln|rsync|install|truncate|dd|unzip|tar|curl|wget|tee)([[:space:]]|$)|git[[:space:]]+(mv|rm)|>"
  script="${V}(python3?|node|bash|sh|zsh|perl|ruby)([[:space:]]|$)"
  edit="sed[^|;&]*[[:space:]]-[a-zA-Z]*i|${V}(chmod|chown)([[:space:]]|$)"
  grep -qE "$change|$script|$edit" <<<"$s" || exit 0
  scan "$c"
  [ -n "$bad" ] && [ ! -f "$ST/docsok-$sid" ] && {
    echo "BLOCKED (documents-guard): agent writes in Documents/ are limited to the vault (NovAExorpus/) and Merovingian's_keep/. Got: Documents/${bad:0:80}. Operator can add #skip-enforce to a prompt." >&2
    exit 2; }
  [ -f "$ST/docsok-$sid" ] && { log "PRE-APPROVED bash" "$c"; exit 0; }
  grep -qE "$change" <<<"$s" && ask "create/move/delete" "$c"
  grep -qE "$script" <<<"$s" && ask "script run" "$c"
  log "EDIT bash" "$c"; exit 0
fi

f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")
grep -qE "$PRE" <<<"$f" || exit 0
scan "$f"
[ -n "$bad" ] && [ ! -f "$ST/docsok-$sid" ] && {
  echo "BLOCKED (documents-guard): agent writes in Documents/ are limited to the vault (NovAExorpus/) and Merovingian's_keep/. Got: Documents/${bad:0:80}. Operator can add #skip-enforce to a prompt." >&2
  exit 2; }
[ -f "$ST/docsok-$sid" ] && { log "PRE-APPROVED $tool" "$f"; exit 0; }
[ "$tool" = Write ] && [ ! -e "$f" ] && ask "new file" "$f"
log "EDIT $tool" "$f"; exit 0
