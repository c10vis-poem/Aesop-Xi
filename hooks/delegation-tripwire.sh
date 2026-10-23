#!/data/data/com.termux/files/usr/bin/bash
# obs 0028 delegation trip-wire. UserPromptSubmit resets the turn. PostToolUse Bash records which
# ~/repos/<repo> or vault folders each call touched (path in the command, or cwd). Once a turn has
# more than 6 such calls over more than 3 distinct repos/folders, the next PreToolUse Bash gets a
# non-blocking reminder (once per turn) to hand audit-shaped work to a subagent. Subagent calls skipped.
in=$(cat)
IFS=$'\x1f' read -r ev sid aid cwd < <(jq -r '[.hook_event_name, .session_id, (.agent_id // ""), (.cwd // "")] | join("\u001f")' <<<"$in" 2>/dev/null)
[ -n "$sid" ] && [ -z "$aid" ] || exit 0
st="$HOME/.claude/state"; f="$st/tripwire-$sid.txt"
case $ev in
  UserPromptSubmit) rm -f "$f" "$f.warned" ;;
  PostToolUse)
    V="storage/shared/Documents/NovAExorpus"
    t=$(jq -r '.tool_input.command // ""' <<<"$in" | sed "s|~/|$HOME/|g; s|\\\$HOME/|$HOME/|g; s|/storage/emulated/0/Documents/NovAExorpus|$HOME/$V|g" \
      | { cat; echo " $cwd"; } | command grep -oE "$HOME/(repos|$V)/[^/[:space:]\"';&|)]+" | sort -u | tr '\n' ' ')
    [ -n "$t" ] && { mkdir -p "$st"; echo "$t" >> "$f"; } ;;
  PreToolUse)
    [ -f "$f" ] && [ ! -f "$f.warned" ] || exit 0
    [ "$(wc -l < "$f")" -gt 6 ] && [ "$(tr ' ' '\n' < "$f" | sed '/^$/d' | sort -u | wc -l)" -gt 3 ] || exit 0
    touch "$f.warned"
    jq -cn '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:"Delegation trip-wire (obs 0028): this turn ran more than 6 Bash calls across more than 3 repos/vault folders. Audit-shaped work goes to subagents: spawn them (general-purpose/builder, with a progress file) instead of continuing inline."}}' ;;
esac
exit 0
