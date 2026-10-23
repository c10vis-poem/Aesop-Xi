#!/data/data/com.termux/files/usr/bin/bash
# Absence-claim gate (Stop, decision 56; obs 0007/0016/0024/0034). A final answer that says something is
# "not found / doesn't exist / undefined / no such X" needs a search in the same turn (since the last real
# user message): Bash grep/find/rg/ls/gh search/gh api/gh repo/git log, Grep, Glob, WebSearch, or an MCP
# search / hf_fs call. Lines that already name their probes ("searched", "probes:", "not found by",
# "Where I looked") are fine. Blocks once (stop_hook_active allows). Fails open on bad input, logged.
log="$HOME/.claude/state/absence-gate.log"
fail(){ mkdir -p "${log%/*}"; echo "$(date '+%F %T') fail-open: $1" >> "$log"; exit 0; }
in=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$in" 2>/dev/null) || fail "bad stdin JSON"
[ "$active" = true ] && exit 0
msg=$(jq -r '.last_assistant_message // ""' <<<"$in")
claim=$(command grep -iE "not found|(doesn|does not|didn)['’]?t? exist|no such|undefined in|(couldn|can)['’]t find|could not find|cannot find|(isn|is not|wasn)['’]?t? installed|never existed|there is no" <<<"$msg" \
  | command grep -viE "searched|probes:|not found by|where I looked" | head -1)
[ -n "$claim" ] || exit 0; claim=${claim%.}
tp=$(jq -r '.transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}
[ -f "$tp" ] || fail "no transcript: $tp"
# Newest-first tail; keep entries up to the last real user prompt (string content, or array without tool_result)
n=$(tac "$tp" | head -n 4000 | jq -s '
  (map(.type=="user" and (.isMeta|not) and (.message.content | if type=="string" then true
     else (type=="array" and all(.[]; .type!="tool_result")) end)) | index(true)) as $i
  | .[:($i // length)] | [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
  | select(.name=="Grep" or .name=="Glob" or .name=="WebSearch"
      or (.name|test("^mcp__.*(search|hf_fs)"; "i"))
      or (.name=="Bash" and ((.input.command // "") | test("(^|[^[:alnum:]_-])(grep|rg|find|ls|fd|locate)([[:space:]]|$)|gh (search|api|repo (list|view))|git log"))))
  ] | length' 2>/dev/null) || fail "transcript parse error: $tp"
[ "${n:-0}" -gt 0 ] && exit 0
echo "Absence claim without a search this turn: ${claim:0:160}. Search local repos, the vault/memory and GitHub first, then say 'not found by <probes>'." >&2
exit 2
