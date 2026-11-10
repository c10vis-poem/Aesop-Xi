#!/usr/bin/env bash
# PostToolUse (Edit|Write|Bash): append this session's repos / files / git actions to
# $RECAPS_DIR/<date>-<sid8>.md (repos named by `git -C X` or `cd X` in a git action count as touched). Read by ship-session.sh at SessionEnd. Never blocks.
# Env overrides (tests): RECAPS_DIR, STATE_DIR.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
STATE_DIR=$ST

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
  mkdir -p "$STATE_DIR" "$RECAPS_DIR" || return
  [ -e "$STATE_DIR/session-$sid.start" ] || touch "$STATE_DIR/session-$sid.start"

  exec 9>>"$STATE_DIR/session-$sid.lock"; flock -w 5 9
  ledger=$(ls "$RECAPS_DIR/"*-"${sid:0:8}".md 2>/dev/null | head -1)
  if [ -z "$ledger" ]; then
    ledger="$RECAPS_DIR/$(date +%F)-${sid:0:8}.md"
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
      if grep -Eq '(^|[^[:alnum:]_-])(git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push)|gh[[:space:]]+pr[[:space:]]+(create|merge))([^[:alnum:]_-]|$)' <<<"$cmd"; then
        add "Git actions" "\`${cmd:0:200}\`"
        # ship-session ships only what is listed here, so a repo reached by -C or cd must be listed too
        while IFS= read -r d; do
          d=${d//[\"\']/}; d=${d/#\~/$HOME}; d=${d//\$HOME/$HOME}; [[ $d = /* ]] || d=$cwd/$d
          top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) && add "Repos touched" "$top"
        done < <(grep -oE '(^|[;&|[:space:](])(cd|git[[:space:]]+-C)[[:space:]]+[^;&|[:space:]]+' <<<"$cmd" | awk '{print $NF}')
        # Rule 10: what was pushed, for the Stop gate. The branch is the push's last word, else the current branch.
        p=$(grep -oE 'git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[^;&|]*' <<<"$cmd" | tail -1)
        if [ -n "$p" ] && [ -n "$top" ]; then
          b=$(awk '{print $NF}' <<<"$p"); b=${b##*:}
          case $b in push|origin|HEAD|-*) b=$(git -C "$top" branch --show-current 2>/dev/null) ;; esac
          [ -n "$b" ] && { grep -qxF "$top	$b" "$STATE_DIR/pushed-$sid.tsv" 2>/dev/null || printf '%s\t%s\n' "$top" "$b" >> "$STATE_DIR/pushed-$sid.tsv"; }
        fi
      fi ;;
  esac
}

main 2>/dev/null
exit 0
