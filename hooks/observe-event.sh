#!/data/data/com.termux/files/usr/bin/bash
# Observer events (SessionStart, PostToolUseFailure, PermissionDenied, UserPromptSubmit). Always exits 0.
# SessionStart source=compact: re-arms enforcement (clears satisfied-<sid>.tsv) and records the compaction
#   (time + scan-line count of checkpoints.log) so stop-gate wants task-observer loaded and a new scan.
# Friction events go to state/observe-queue-<sid>.tsv: <id> <epoch> <kind> <detail> (tab-separated).
#   tool-fail (PostToolUseFailure; Bash only on timeout), denied (PermissionDenied), correction (operator prompt matching
#   observe-corrections.txt), block (gate BLOCK lines of the enforce log, imported by `sync <sid>`).
# stop-gate holds the turn until each has an observation written after it or `observe-dismiss <id> "<why>"`.
st="$HOME/.claude/state"; mkdir -p "$st"
ck="$HOME/storage/shared/Documents/NovAExorpus/skill-observations/checkpoints.log"
add() {  # kind detail [epoch] -> appends an event, prints its id
  local id=e$RANDOM; while grep -q "^$id	" "$q" 2>/dev/null; do id=e$RANDOM; done
  printf '%s\t%s\t%s\t%s\n' "$id" "${3:-$(date +%s)}" "$1" "$(tr '\t\n' '  ' <<<"$2" | cut -c1-120)" >> "$q"; echo "$id"
}

if [ "${1:-}" = sync ]; then   # import the enforce log's new gate BLOCK lines (stop-gate runs this)
  sid=$2; q="$st/observe-queue-$sid.tsv"; log="$st/enforce-$sid.log"; off="$st/observe-off-$sid"
  [ -f "$log" ] || exit 0
  n0=$(cat "$off" 2>/dev/null || echo 0); n1=$(wc -l < "$log" | tr -d ' '); now=$(date +%s)
  awk -v a="$n0" -v b="$n1" 'NR>a && NR<=b && /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9] BLOCK /' "$log" | while read -r t _ rest; do
    e=$(date -d "$t" +%s); [ "$e" -gt "$now" ] && e=$((e-86400))   # log has time of day only
    add block "$rest" "$e" >/dev/null
  done
  echo "$n1" > "$off"; exit 0
fi

in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
q="$st/observe-queue-$sid.tsv"
case $(jq -r '.hook_event_name // ""' <<<"$in") in
  SessionStart)
    [ "$(jq -r '.source // ""' <<<"$in")" = compact ] || exit 0
    rm -f "$st/satisfied-$sid.tsv"
    n=$(grep -c 'session-start scan:' "$ck" 2>/dev/null); printf '%s\n%s\n' "$(date -u +%FT%T)" "${n:-0}" > "$st/compact-$sid"
    echo "Context was compacted: keyword requirements are re-armed. Load the task-observer skill again and run its session-start scan (scripts/session-start-scan.sh) before ending the turn." ;;
  PostToolUseFailure)   # a Bash non-zero exit is routine (grep no match); only its timeouts count; interrupts never
    jq -e '.is_interrupt == true or (.tool_name == "Bash" and .is_timeout != true)' <<<"$in" >/dev/null && exit 0
    add tool-fail "$(jq -r '"\(.tool_name): \(.error // "" | split("\n")[0])"' <<<"$in")" >/dev/null ;;
  PermissionDenied)
    add denied "$(jq -r '"\(.tool_name): \(.reason // "")"' <<<"$in")" >/dev/null ;;
  UserPromptSubmit)
    p=$(jq -r '.prompt // ""' <<<"$in")
    grep -qE '<agent-message|<task-notification>|^Another Claude session sent a message' <<<"$p" && exit 0   # subagent hand-backs are not the operator
    grep -qiE -f <(grep -vE '^[[:space:]]*(#|$)' "$(dirname "$(realpath "$0")")/observe-corrections.txt" 2>/dev/null) <<<"$p" || exit 0
    id=$(add correction "$p")
    echo "OBSERVE: this prompt reads as an operator correction, queued as $id. Log it as a task-observer observation, or: observe-dismiss $id \"<reason>\"" ;;
esac
exit 0
