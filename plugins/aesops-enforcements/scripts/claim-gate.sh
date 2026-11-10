#!/usr/bin/env bash
# Rule 9, read and verify before saying it (Stop). Two checks on the final answer, besides absence-gate's
# "not found needs a search":
#   1. A claim cited by file and line (`name.ext:12`) needs that file read this session: a Read of it, or a
#      Bash command naming it (cat, sed, grep, head, ...).
#   2. "Done / fixed / passing / works / verified" after edits this turn needs a real run after the last edit:
#      a Bash call that comes after the last Edit/Write/NotebookEdit of the turn.
#   4. A file list under a status matches the tool output it came from; 5. "read N files" needs N Reads.
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

# 4. A list of files with a status (unsupported, empty, error, failed, quarantined, flagged, released) must match
#    the source it came from (operator 2026-11-10: "You should have to be forced to prove it"). Each file named under
#    a status, on the status line or in the bullets that follow it, must appear this turn in a tool result on a line
#    that carries the same status. A name seen only in some other output (another script's list) is not proof.
# 5. "read / ingested / analyzed / understood N files" needs N distinct files opened by Read this session.
turn_results=$(tac "$tp" | head -n 4000 | jq -rs '
  (map(.type=="user" and (.isMeta|not) and (.message.content | if type=="string" then true
     else (type=="array" and all(.[]; .type!="tool_result")) end)) | index(true)) as $i
  | .[:($i // length)] | .[] | select(.type=="user") | .message.content[]? | select(.type=="tool_result")
  | .content | if type=="string" then . else ([.[]? | .text? // empty] | join("\n")) end' 2>/dev/null) || fail "transcript parse error: $tp"
syn(){ case $1 in unsupported) echo 'unsupported|no converter' ;; empty) echo 'empty' ;; error*) echo 'error' ;;
  fail*) echo 'fail' ;; quarantin*) echo 'quarantin' ;; flag*) echo 'flag|review|quarantin' ;; released) echo 'released' ;; esac; }
listed=$(awk '
  # a status line: only the sentence the status word sits in (from the word to the next ". ") lists files
  { st=""; if (match(tolower($0), /(unsupported|empty|errors?|errored|failed|fails|quarantined|quarantine|flagged|released)/)) {
      st=substr(tolower($0), RSTART, RLENGTH); line=substr($0, RSTART); if (match(line, /\. [A-Z]/)) line=substr(line, 1, RSTART) } }
  st!="" { cur=st }
  st=="" && /^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ && cur!="" { line=$0 }
  st=="" && !/^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]/ { cur=""; next }
  cur!="" { n=split(line, parts, "`"); for (i=2; i<=n; i+=2) if (parts[i] ~ /[.\/]/ && parts[i] !~ /[[:space:]]-/) print cur "\t" parts[i] }' <<<"$msg" | sort -u)
if [ -n "$listed" ]; then
  bad=()
  while IFS=$'\t' read -r st name; do
    b=${name##*/}; [ -n "$b" ] || continue
    re=$(syn "$st"); [ -n "$re" ] || continue
    command grep -F -- "$b" <<<"$turn_results" | command grep -qiE "$re" || bad+=("$name ($st)")
  done <<<"$listed"
  if [ ${#bad[@]} -gt 0 ]; then
    echo "BLOCKED (claim-gate): Rule 9, the answer lists ${bad[*]:0:3} under a status no tool output this turn gives them. Read the report the list comes from, copy the names from it, then answer." >&2
    exit 2
  fi
fi
claimN=$(command grep -oiE "(read|ingested|analy[sz]ed|understood|went through)( all| every one of)?( the)? [0-9]+ (files|documents|docs)|[0-9]+ (files|documents|docs) (read|ingested|analy[sz]ed|understood)" <<<"$msg" | command grep -oE '[0-9]+' | sort -n | tail -1)
if [ -n "$claimN" ]; then
  nread=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path // empty' "$tp" 2>/dev/null | sort -u | wc -l)
  if [ "$nread" -lt "$claimN" ]; then
    echo "BLOCKED (claim-gate): Rule 9, the answer says $claimN files were read or ingested, but this session opened $nread with Read. Read them, or say how many were read and by whom (a worker's record), then answer." >&2
    exit 2
  fi
fi

# 6. "I read / opened / checked / reviewed `name`" needs that name in a tool call this session.
# 7. A test result quoted as numbers ("787 of 787", "12/12 pass") needs those numbers in a tool result this turn.
seen_all=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
  | (.input.file_path // .input.command // .input.path // .input.pattern // "")' "$tp" 2>/dev/null) || fail "transcript parse error: $tp"
rd=$(command grep -oiE "\bI(['’]ve| have)? (read|opened|checked|reviewed|went through)( the| all of| every line of)? \`.*" <<<"$msg" | sed -E "s/\\. [A-Z].*//" | command grep -oE '`[^`]+`' | tr -d '`' | sort -u)
if [ -n "$rd" ]; then
  bad=(); while IFS= read -r n; do b=${n##*/}; command grep -qF -- "$b" <<<"$seen_all" || bad+=("$n"); done <<<"$rd"
  if [ ${#bad[@]} -gt 0 ]; then
    echo "BLOCKED (claim-gate): Rule 13, no lying: the answer says ${bad[*]:0:3} was read or checked, and no tool call this session touched it. Read it, or take the claim out, then answer." >&2
    exit 2
  fi
fi
nums=$(command grep -oiE "\b[0-9]+ (of|/) ?[0-9]+( tests?| checks?)?( pass(ed|es)?| fail(ed|s)?)|\b[0-9]+/[0-9]+ (pass|fail)|(pass(es|ed)?|fail(s|ed)?) [0-9]+ (of|/) ?[0-9]+" <<<"$msg" | command grep -oE '[0-9]+' | sort -u)
if [ -n "$nums" ]; then
  bad=(); while IFS= read -r n; do command grep -qE "(^|[^0-9])$n([^0-9]|$)" <<<"$turn_results" || bad+=("$n"); done <<<"$nums"
  if [ ${#bad[@]} -gt 0 ]; then
    echo "BLOCKED (claim-gate): Rule 13, no lying: the answer quotes test numbers (${bad[*]:0:4}) that no tool output this turn shows. Run the test this turn and copy its numbers, then answer." >&2
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
