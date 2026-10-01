#!/data/data/com.termux/files/usr/bin/bash
# PostToolUse (Edit|Write|Bash): append this session's repos / files / git actions to
# <vault>/_recaps/<date>-<sid8>.md. Read by ship-session.sh at SessionEnd. Never blocks.
# Env overrides (tests): VAULT, STATE_DIR.
VAULT=${VAULT:-/data/data/com.termux/files/home/storage/shared/Documents/NovAExorpus}
STATE_DIR=${STATE_DIR:-$HOME/.claude/state}

# Insert "- $2" at the end of section "## $1" unless already present.
add() {
  grep -Fxq -- "- $2" "$ledger" && return
  awk -v sec="## $1" -v line="- $2" '
    function flush() { if (insec && !done) { print line; done = 1 } }
    /^## / { flush(); insec = ($0 == sec) }
    { if (insec && $0 == "") { pending++; next } while (pending) { print ""; pending-- } print }
    END { flush(); while (pending) { print ""; pending-- } }
  ' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
}

main() {
  local in sid tool cwd path cmd top
  in=$(cat)
  IFS=$'\t' read -r sid tool cwd path < <(jq -r '[.session_id // "", .tool_name // "", .cwd // "", .tool_input.file_path // ""] | @tsv' <<<"$in")
  [ -n "$sid" ] || return
  mkdir -p "$STATE_DIR" "$VAULT/_recaps" || return
  [ -e "$STATE_DIR/session-$sid.start" ] || touch "$STATE_DIR/session-$sid.start"

  exec 9>>"$STATE_DIR/session-$sid.lock"; flock -w 5 9
  ledger=$(ls "$VAULT/_recaps/"*-"${sid:0:8}".md 2>/dev/null | head -1)
  if [ -z "$ledger" ]; then
    ledger="$VAULT/_recaps/$(date +%F)-${sid:0:8}.md"
    [ -e "$ledger" ] || printf '# Session %s\n\nsession_id: %s\n\n## Repos touched\n\n## Files written\n\n## Git actions\n' \
      "${sid:0:8}" "$sid" > "$ledger"
  fi

  case $tool in
    Edit|Write)
      [ -n "$path" ] || return
      top=$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null)
      [ -n "$top" ] && add "Repos touched" "$top"
      add "Files written" "$path" ;;
    Bash)
      top=$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)
      [ -n "$top" ] && add "Repos touched" "$top"
      cmd=$(jq -r '.tool_input.command // ""' <<<"$in"); cmd=${cmd//$'\n'/ }
      grep -Eq '(^|[^[:alnum:]_-])(git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push)|gh[[:space:]]+pr[[:space:]]+(create|merge))([^[:alnum:]_-]|$)' <<<"$cmd" \
        && add "Git actions" "\`${cmd:0:200}\`" ;;
  esac
}

main 2>/dev/null
exit 0
