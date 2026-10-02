#!/data/data/com.termux/files/usr/bin/bash
# H1 Stop gate: the turn can't end until RESUME was read AND every item in its
# "NEXT SESSION — START HERE" list has a status (done / blocked), task-observer
# ran its session-start protocol, and no ENFORCEMENTS requirement is pending.
# Record item status with: resume-item <n> done|blocked "<evidence or what's needed>"
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
st="$HOME/.claude/state"; log="$st/enforce-$sid.log"; items="$st/resume-items-$sid.tsv"
vault="$HOME/storage/shared/Documents/NovAExorpus"

# Operator override (manual, user-typed only): latest real user prompt contains #skip-enforce
if [ -f "$tp" ] && jq -r 'select(.type=="user" and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null | tail -1 | grep -q '#skip-enforce'; then
  echo "$(date +%T) STOP-SKIP #skip-enforce" >> "$log"; exit 0
fi

top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="$vault/RESUME.md"
miss=()

if [ -f "$r" ]; then
  if [ ! -f "$st/resume-$sid.ok" ]; then
    miss+=("Read $r")
  else
    # numbered items under the START HERE heading, up to the next heading
    for n in $(awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");print}' "$r"); do
      grep -q "^$n	" "$items" 2>/dev/null || miss+=("RESUME item $n has no status: run resume-item $n done|blocked \"<evidence / what you need from the operator>\"")
    done
  fi
fi

# task-observer: skill loaded this session + session-start scan written after RESUME was read
if [ -f "$tp" ] && ! jq -e 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill" and (.input.skill|test("task-observer")))' "$tp" >/dev/null 2>&1; then
  miss+=("Load the task-observer skill and run its Session Start Protocol")
elif [ -f "$st/resume-$sid.ok" ] && [ ! "$vault/skill-observations/checkpoints.log" -nt "$st/resume-$sid.ok" ]; then
  miss+=("Run the task-observer session-start scan (it appends to skill-observations/checkpoints.log)")
fi

# ENFORCEMENTS requirements still pending for this prompt
[ -s "$st/required-$sid.tsv" ] && miss+=("Pending ENFORCEMENTS: $(cut -f2 "$st/required-$sid.tsv" | paste -sd ';')")

[ ${#miss[@]} -eq 0 ] && exit 0
reason="BLOCKED (stop-gate): not done yet —"; for m in "${miss[@]}"; do reason+=$'\n'"- $m"; done
echo "$(date +%T) STOP-BLOCK ${#miss[@]} item(s)" >> "$log"
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
