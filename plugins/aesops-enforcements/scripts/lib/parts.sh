# Sourced by the merged hooks. run_parts A B C: runs each check in order on the event in $in.
# The first block (exit 2) ends the hook with that block. A crash or a missing check is logged and allowed.
_here=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)
in=$(cat)
event=$(jq -r '.hook_event_name // ""' <<<"$in" 2>/dev/null)
tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null)
_log() { mkdir -p "${STATE_DIR:-$HOME/.claude/state}" 2>/dev/null; printf '%s %s\n' "$(date '+%F %T')" "$*" >> "${STATE_DIR:-$HOME/.claude/state}/hooks.log" 2>/dev/null; }
run_parts() {
  local p rc
  for p in "$@"; do
    [ -f "$_here/$p.sh" ] || { _log "MISSING check $p: $_here/$p.sh is not there (call allowed)"; continue; }
    bash "$_here/$p.sh" <<<"$in"; rc=$?
    [ "$rc" = 2 ] && exit 2
    [ "$rc" = 0 ] || _log "$p ERROR exit $rc (allowed)"
  done
  exit 0
}
