#!/usr/bin/env bash
# Rule 9, read and verify before saying it (Stop). Two checks on the final answer, besides absence-gate's
# "not found needs a search":
#   1. A claim cited by file and line (`name.ext:12`) needs that file read this session: a Read of it, or a
#      Bash command naming it (cat, sed, grep, head, ...).
#   2. "Done / fixed / passing / works / verified" after edits this turn needs a real run after the last edit:
#      a Bash call that comes after the last Edit/Write/NotebookEdit of the turn.
# Blocks once (stop_hook_active allows). Fails open on bad input, logged.
log="$HOME/.claude/state/claim-gate.log"
fail(){ mkdir -p "${log%/*}"; echo "$(date '+%F %T') fail-open: $1" >> "$log"; exit 0; }
in=$(cat)
active=$(jq -r '.stop_hook_active // false' <<<"$in" 2>/dev/null) || fail "bad stdin JSON"
[ "$active" = true ] && exit 0
msg=$(jq -r '.last_assistant_message // ""' <<<"$in")
[ -n "$msg" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}
[ -f "$tp" ] || fail "no transcript: $tp"

# 1. file:line citations need the file read this session
cites=$(command grep -oE '[A-Za-z0-9_./~-]+\.(md|sh|json|jsonl|py|js|ts|tsv|txt|yml|yaml|toml):[0-9]+' <<<"$msg" | sed -E 's/:[0-9]+$//' | sort -u)
if [ -n "$cites" ]; then
  seen=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
    | (.input.file_path // .input.command // .input.path // "")' "$tp" 2>/dev/null) || fail "transcript parse error: $tp"
  miss=()
  while IFS= read -r c; do
    command grep -qF -- "${c##*/}" <<<"$seen" || miss+=("$c")
  done <<<"$cites"
  if [ ${#miss[@]} -gt 0 ]; then
    echo "BLOCKED (claim-gate): Rule 9, the answer cites ${miss[*]:0:3} by line, but that file was not read this session. Read it, then answer." >&2
    exit 2
  fi
fi

# 3. "false / won't work / not supported / not possible" needs, this turn, official documentation fetched
#    (WebFetch, WebSearch, an MCP docs/fetch/search tool, the web-fetch agent, or a Read of a README / docs /
#    INSTALL / CHANGELOG file) or a real trial (a Bash run that is not just a read). Training data is not a source.
# quoted text and "doesn't mean ... won't work" are not claims (false positive, 2026-11-10)
plain=$(sed -E "s/\"[^\"]*\"//g; s/“[^”]*”//g; s/(doesn.?t|does not|didn.?t) mean[^.]*//Ig" <<<"$msg")
neg=$(command grep -iE "(won['’]?t|will not|wouldn['’]?t|doesn['’]?t|does not|can['’]?t|cannot) (work|be done|support|run|install|exist)|(isn['’]?t |is not |not |un)supported|not possible|impossible|(is|that['’]?s|it['’]?s) (false|not true)|isn['’]?t true|no longer (exists|works|available)|never existed|was removed in" <<<"$plain" | head -1)
if [ -n "$neg" ]; then
  probes=$(tac "$tp" | head -n 4000 | jq -s '
    (map(.type=="user" and (.isMeta|not) and (.message.content | if type=="string" then true
       else (type=="array" and all(.[]; .type!="tool_result")) end)) | index(true)) as $i
    | .[:($i // length)] | [ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
    | select(.name=="WebFetch" or .name=="WebSearch"
        or (.name|test("^mcp__.*(fetch|docs|search|read|guide)"; "i"))
        or (.name=="Agent" and ((.input.subagent_type // "") | test("web-fetch|claude-code-guide")))
        or (.name=="Read" and ((.input.file_path // "") | test("(?i)(readme|install|changelog|/docs?/|guide)")))
        or (.name=="Bash" and ((.input.command // "") | test("^[[:space:]]*(cat|sed|head|tail|grep|rg|ls|find|less|wc|command grep)[[:space:]]") | not)))
    ] | length' 2>/dev/null) || fail "transcript parse error: $tp"
  if [ "${probes:-0}" -eq 0 ]; then
    echo "BLOCKED (claim-gate): Rule 9, \"${neg:0:140}\" says something is false or won't work, with no official documentation fetched and no trial run this turn. Check the vendor docs or try it, cite which, then answer." >&2
    exit 2
  fi
fi

# 2. done-claims after edits this turn need a run after the last edit
command grep -qiE '(^|[^[:alnum:]])(done|fixed|passing|passes|passed|works|working|verified|green)([^[:alnum:]]|$)' <<<"$msg" || exit 0
order=$(tac "$tp" | head -n 4000 | jq -rs '
  (map(.type=="user" and (.isMeta|not) and (.message.content | if type=="string" then true
     else (type=="array" and all(.[]; .type!="tool_result")) end)) | index(true)) as $i
  | .[:($i // length)] | reverse | .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' 2>/dev/null) || fail "transcript parse error: $tp"
last_edit=$(command grep -nE '^(Edit|Write|NotebookEdit)$' <<<"$order" | tail -1 | cut -d: -f1)
[ -n "$last_edit" ] || exit 0
tail -n +"$((last_edit+1))" <<<"$order" | command grep -qx Bash && exit 0
echo "BLOCKED (claim-gate): Rule 9, the answer says done/fixed/passing after edits, but nothing ran after the last edit. Run the test or the command that proves it, then answer." >&2
exit 2
