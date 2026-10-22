#!/data/data/com.termux/files/usr/bin/bash
# SubagentStop gate. A subagent whose spawn prompt names its progress file (~/.claude/session-work/<date>/agent-<topic>.md)
# cannot finish while that file is missing or a "- [ ]" line in ## Plan is not listed under ## Blocked.
# Exit 2 + stderr goes back to the subagent only. Touches no main-session state, queues no observer events.
in=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ] && exit 0   # one block, then allow
tp=$(jq -r '.agent_transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}
[ -f "$tp" ] || exit 0
pf=$(jq -r 'select(.type=="user") | .message.content | if type=="string" then . else (map(.text? // empty) | join("\n")) end' "$tp" 2>/dev/null \
  | grep -m1 -oE 'session-work/[0-9-]+/agent-[A-Za-z0-9._-]+\.md')
[ -n "$pf" ] || exit 0
pf="$HOME/.claude/$pf"
if [ ! -f "$pf" ]; then echo "BLOCKED (subagent-stop-gate): progress file $pf is missing. Create it (## Plan, ## Last action, ## Findings, ## Blocked) before finishing." >&2; exit 2; fi
open=$(awk '/^## /{s=$0} s ~ /^## Plan/ && /^[[:space:]]*- \[ \]/{sub(/^[[:space:]]*- \[ \] */,""); print}' "$pf" \
  | while IFS= read -r l; do awk -v l="$l" '/^## /{s=$0} s ~ /^## Blocked/ && index($0,l){f=1} END{exit !f}' "$pf" || echo "- $l"; done)
[ -z "$open" ] && exit 0
echo "BLOCKED (subagent-stop-gate): unchecked steps in $pf ## Plan. Finish them, or list them under ## Blocked with the reason:
$open" >&2; exit 2
