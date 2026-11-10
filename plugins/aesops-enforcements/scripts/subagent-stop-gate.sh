#!/usr/bin/env bash
# Rule 10, SubagentStop: the write-to-task stop gate for every subagent that can write. A subagent cannot stop while:
#   1. it has no progress file (named in its spawn prompt, or written by it), or
#   2. a "- [ ]" step in ## Plan is not explained under ## Blocked (a skipped step), or
#   3. steps are done but ## Findings is empty, or
#   4. the progress file is older than its last tool call (it stopped writing to task), or
#   5. a tool or skill failed to load (unknown tool, schema not loaded, skill not found) and ## Blocked does not say so, or
#   6. it wrote outside the scope its spawn prompt declared (obs 0040), or
#   7. a file its spawn prompt assigned (Files: list, Paths file:, Folder:) was never opened, or opened only in part
#      (operator 2026-11-10: sub-agents read 5 of 60 and claim all 60), or
#   8. a skill or tool in its agent definition was never used,
#   unless ## Blocked names it and says why. Every stop writes an audit line (subagent_audit.py) to the
#   session's task log; one let go with gaps after MAX blocks is also queued as a friction event.
# Blocks up to MAX times per subagent (obs 0051: no endless loop), then lets it stop with a logged notice.
# Exit 2 + stderr goes back to the subagent only. Fails open on bad input.
in=$(cat)
. "$(dirname "$(realpath "$0")")/lib/subagent.sh"
sa_exempt && exit 0
[ -f "$sa_tp" ] || exit 0
MAX=${AESOP_SUBAGENT_MAX_BLOCKS:-4}
st=${STATE_DIR:-$HOME/.claude/state}; cdir="$st/subagent-stop"; mkdir -p "$cdir" 2>/dev/null
key=${sa_aid:-$(basename "$sa_tp" .jsonl)}; cf="$cdir/${key//[^A-Za-z0-9_-]/_}"
n=$(cat "$cf" 2>/dev/null || echo 0)
msid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null)
aud=
audit() {   # $1 verdict: one line per stop in the session's audit (read into the task log by save-session-log)
  [ -n "$msid" ] || return 0
  [ -n "$aud" ] || aud=$(python3 "$(dirname "$(realpath "$0")")/subagent_audit.py" "$sa_tp" "$sa_at" "${sa_pf:-}" 2>/dev/null)
  local a f p u tu su; a=$(jq -r '.assigned|length' <<<"$aud" 2>/dev/null); f=$(jq -r '.full|length' <<<"$aud" 2>/dev/null)
  p=$(jq -r '.partial|length' <<<"$aud" 2>/dev/null); u=$(jq -r '.unread|length' <<<"$aud" 2>/dev/null)
  tu=$(jq -r '"\((.tools_equipped|length)-(.tools_unused|length))/\(.tools_equipped|length)"' <<<"$aud" 2>/dev/null)
  su=$(jq -r '"\((.skills_equipped|length)-(.skills_unused|length))/\(.skills_equipped|length)"' <<<"$aud" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\tassigned %s, read whole %s, partial %s, unread %s; tools %s; skills %s\t%s\n' "$(date '+%F %T')" "${sa_at:-?}" "$key" "$1" \
    "${a:-0}" "${f:-0}" "${p:-0}" "${u:-0}" "${tu:-0/0}" "${su:-0/0}" "${sa_pf:-no progress file}" >> "$st/subagent-audit-$msid.tsv" 2>/dev/null
}
block() {
  if [ "$n" -ge "$MAX" ]; then
    printf '%s subagent-stop-gate: %s stopped after %s blocks, task file incomplete: %s\n' "$(date '+%F %T')" "$key" "$n" "${1:0:200}" >> "$st/hooks.log" 2>/dev/null
    audit "let go with gaps"
    [ -n "$msid" ] && bash "$(dirname "$(realpath "$0")")/observe-event.sh" add "$msid" subagent-gap "${sa_at:-?} $key stopped with gaps: ${1:0:100}" >/dev/null 2>&1
    rm -f "$cf"; exit 0
  fi
  echo $((n + 1)) > "$cf"
  echo "BLOCKED (subagent-stop-gate, rule 10, block $((n + 1))/$MAX): $1 OVERRIDE: the operator's direct instruction. REVOKE: the operator runs gate off stop-gate." >&2
  exit 2
}
spawn=$(jq -r 'select(.type=="user") | .message.content | if type=="string" then . else (map(.text? // empty) | join("\n")) end' "$sa_tp" 2>/dev/null | head -c 20000)
pf=$sa_pf
[ -n "$pf" ] && [ -f "$pf" ] || block "You have no progress file. $SA_HOW Create it now, fill it from what you did, then finish."
sec() { awk -v h="$1" '/^## /{f=($0 ~ "^## " h)} f && !/^## / && NF' "$pf"; }
blk=$(sec Blocked | grep -viE '^[[:space:]]*(-[[:space:]]*)?(none|nothing|n/a|-)\.?[[:space:]]*$')
open=$(sec Plan | grep -E '^[[:space:]]*-?[[:space:]]*\[ \]' | sed -E 's/^[[:space:]]*-?[[:space:]]*\[ \][[:space:]]*//')
miss=
while IFS= read -r l; do
  [ -n "$l" ] || continue
  k=$(cut -c1-30 <<<"$l")
  grep -qiF -- "$k" <<<"$blk" || miss+="$l; "
done <<<"$open"
if [ -n "$miss" ] && [ "$(grep -c . <<<"$blk")" -lt "$(grep -c . <<<"$open")" ]; then
  block "Skipped step(s) in $pf ## Plan: ${miss:0:400} Do them, or write one line per step under ## Blocked naming it and why it can't be done (error text, what you tried). Results go under ## Findings."
fi
done_n=$(sec Plan | grep -cE '^[[:space:]]*-?[[:space:]]*\[[xX]\]')
[ "${done_n:-0}" -gt 0 ] && [ -z "$(sec Findings)" ] && block "$pf has $done_n finished step(s) but ## Findings is empty. Write your results there (numbers, proof lines, file paths), then stop."
last=$(jq -r 'select(.type=="assistant") | select([.message.content[]? | select(.type=="tool_use")] | length > 0) | .timestamp' "$sa_tp" 2>/dev/null | tail -1)
if [ -n "$last" ]; then
  lt=$(date -d "$last" +%s 2>/dev/null); pm=$(stat -c %Y "$pf")
  [ -n "$lt" ] && [ $((lt - pm)) -gt 90 ] && block "$pf was last written before your last action: you stopped writing to task. Update ## Last action (timestamp, what you did) and ## Findings with your final results, then stop."
fi
fails=$(jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result" and (.is_error==true)) | (.content | if type=="string" then . else (map(.text? // empty) | join(" ")) end)' "$sa_tp" 2>/dev/null \
  | grep -oiE "(no such tool available[^.]*|InputValidationError[^.]*|tool [^ ]+ (is )?not (found|available|loaded)[^.]*|unknown skill[^.]*|skill [^ ]+ (was )?not found[^.]*|not a valid skill[^.]*|schema[^.]*not loaded[^.]*)" | sort -u | head -5)
if [ -n "$fails" ]; then
  unexplained=
  while IFS= read -r f; do grep -qiF -- "$(cut -c1-24 <<<"$f")" <<<"$blk" || unexplained+="$f; "; done <<<"$fails"
  [ -n "$unexplained" ] && block "A tool or skill failed to load: ${unexplained:0:400} Load it properly (ToolSearch select:<name> for a deferred tool; the Skill tool with the exact name) and redo that step, or write under ## Blocked the error text and why it can't be loaded."
fi
scope=$(grep -oiE '(change only|write only to|scope clause:|## scope)[^.]*' <<<"$spawn" | grep -oE '(~|/)[^[:space:],;)("]+' | sed "s#^~#$HOME#" | sort -u)
if [ -n "$scope" ]; then
  bad=
  while IFS= read -r f; do
    [ -n "$f" ] && [ "$f" != "$pf" ] || continue
    okp=; while IFS= read -r s; do case $f in "$s"|"${s%/}"/*) okp=1; break ;; esac; done <<<"$scope"
    [ -n "$okp" ] || grep -qF -- "$f" <<<"$blk" || bad+="$f "
  done < <(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and (.name=="Edit" or .name=="Write" or .name=="NotebookEdit")) | .input.file_path // .input.notebook_path // empty' "$sa_tp" 2>/dev/null | sed "s#^~#$HOME#" | sort -u)
  [ -n "$bad" ] && block "Files written outside your declared scope ($(paste -sd ' ' <<<"$scope")): $bad Revert them or list each under ## Blocked with why it was needed (obs 0040)."
fi
# 7-8. reads, skills, tools (subagent_audit.py)
aud=$(python3 "$(dirname "$(realpath "$0")")/subagent_audit.py" "$sa_tp" "$sa_at" "$pf" 2>/dev/null)
unex() { local x out=; while IFS= read -r x; do [ -n "$x" ] || continue; grep -qiF -- "${x##*/}" <<<"$blk" || out+="${x##*/} "; done; echo "$out"; }
nu=$(jq -r '.unread[]?' <<<"$aud" | unex); np=$(jq -r '.partial[]?' <<<"$aud" | unex)
na=$(jq -r '.assigned|length' <<<"$aud" 2>/dev/null)
if [ -n "$nu$np" ]; then
  block "You were assigned ${na:-?} files and have not read them all. Never opened: ${nu:-none}. Opened only in part: ${np:-none}. Read each one whole (Read in ranges until every line is covered), record it under ## Findings, or name it under ## Blocked with the error. Do not report a file as read that you did not open."
fi
tu=$(jq -r '.tools_unused[]?' <<<"$aud" | unex); su=$(jq -r '.skills_unused[]?' <<<"$aud" | unex)
[ -n "$tu$su" ] && block "You were launched with skills and tools you never used. Skills: ${su:-none}. Tools: ${tu:-none}. Use each where the job calls for it (a preloaded skill: say under ## Skills used how you applied it), or name it under ## Blocked with why it did not apply."
audit pass
rm -f "$cf"; exit 0
