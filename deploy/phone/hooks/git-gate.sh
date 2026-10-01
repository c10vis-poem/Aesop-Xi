#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Bash): no push / PR / merge mid-session. Commit on local branches;
# everything ships at wrap-up (ship-session). Unlocked by wrap-up mode
# (state/wrapup-<sid>, set when the operator says wrap up / close session) or
# by "push now" in the current prompt (state/pushnow-<sid>, cleared each prompt).
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
grep -qE '(^|[;&|[:space:]])(git[[:space:]]+([^;&|]*[[:space:]])?push|gh[[:space:]]+pr[[:space:]]+(create|merge|ready))([[:space:]]|$)' <<<"$cmd" || exit 0
st="$HOME/.claude/state"
[ -f "$st/wrapup-$sid" ] || [ -f "$st/pushnow-$sid" ] && exit 0
echo "$(date +%T) BLOCK git-gate: $(head -c 80 <<<"$cmd")" >> "$st/enforce-$sid.log"
echo "BLOCKED (git-gate): no push/PR/merge mid-session. Commit on a local branch; everything ships at wrap-up. Operator can say \"push now\" or \"wrap up\"." >&2
exit 2
