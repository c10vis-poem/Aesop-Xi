#!/data/data/com.termux/files/usr/bin/bash
# SubagentStop gate. A subagent whose spawn prompt names its progress file (~/.claude/session-work/<date>/agent-<topic>.md)
# cannot finish while that file is missing or a "- [ ]" line in ## Plan is not listed under ## Blocked.
# Scope check (obs 0040): when the spawn prompt declares a scope ("Change only <paths>", "SCOPE CLAUSE:", "## Scope",
# "Write only to <paths>"), every file the subagent Edited/Wrote must sit under one of the declared paths (the progress
# file always allowed); a write outside it blocks once with the list, so the subagent reports it under ## Blocked.
# Exit 2 + stderr goes back to the subagent only. Touches no main-session state, queues no observer events.
in=$(cat)
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ] && exit 0   # one block, then allow
tp=$(jq -r '.agent_transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}
[ -f "$tp" ] || exit 0
spawn=$(jq -r 'select(.type=="user") | .message.content | if type=="string" then . else (map(.text? // empty) | join("\n")) end' "$tp" 2>/dev/null | head -c 20000)
pf=$(grep -m1 -oE 'session-work/[0-9-]+/agent-[A-Za-z0-9._-]+\.md' <<<"$spawn")
out=
if [ -n "$pf" ]; then
  pf="$HOME/.claude/$pf"
  if [ ! -f "$pf" ]; then echo "BLOCKED (subagent-stop-gate): progress file $pf is missing. Create it (## Plan, ## Last action, ## Findings, ## Blocked) before finishing." >&2; exit 2; fi
  open=$(awk '/^## /{s=$0} s ~ /^## Plan/ && /^[[:space:]]*- \[ \]/{sub(/^[[:space:]]*- \[ \] */,""); print}' "$pf" \
    | while IFS= read -r l; do awk -v l="$l" '/^## /{s=$0} s ~ /^## Blocked/ && index($0,l){f=1} END{exit !f}' "$pf" || echo "- $l"; done)
  [ -n "$open" ] && out+="unchecked steps in $pf ## Plan. Finish them, or list them under ## Blocked with the reason:"$'\n'"$open"$'\n'
fi
# scope: paths named after "Change only", "Write only to", "SCOPE CLAUSE:", "## Scope" up to the end of that sentence/line
scope=$(grep -oiE '(change only|write only to|scope clause:|## scope)[^.]*' <<<"$spawn" | grep -oE '(~|/)[^[:space:],;)("]+' | sed "s#^~#$HOME#" | sort -u)
if [ -n "$scope" ]; then
  touched=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="NotebookEdit")) | .input.file_path // .input.notebook_path // empty' "$tp" 2>/dev/null | sed "s#^~#$HOME#" | sort -u)
  bad=
  while IFS= read -r f; do
    [ -n "$f" ] || continue; [ "$f" = "$pf" ] && continue
    okp=; while IFS= read -r s; do case $f in "$s"|"$s"/*|"${s%/}"/*) okp=1; break ;; esac; done <<<"$scope"
    [ -n "$okp" ] || bad+="- $f"$'\n'
  done <<<"$touched"
  [ -n "$bad" ] && out+="files written outside the declared scope ($(paste -sd ' ' <<<"$scope")). Revert them or list each under ## Blocked with why it was needed; counts and paths given to you are hard limits (obs 0040):"$'\n'"$bad"
fi
[ -z "$out" ] && exit 0
echo "BLOCKED (subagent-stop-gate): $out" >&2; exit 2
