#!/data/data/com.termux/files/usr/bin/bash
# Wrap-up change review: summarise everything change-log.sh recorded this session, write it into the
# session recap ("## Change review"), and print it for the operator. The operator approves with
# "#ok push"; until then ship-session.sh ships nothing.
# Usage: review-changes.sh <session_id>   Env overrides (tests): VAULT, STATE_DIR.
VAULT=${VAULT:-/data/data/com.termux/files/home/storage/shared/Documents/NovAExorpus}
STATE_DIR=${STATE_DIR:-$HOME/.claude/state}
sid=${1:?usage: review-changes.sh <session_id>}
LOG="$STATE_DIR/changes-$sid.log"
[ -s "$LOG" ] || { echo "No changes recorded this session."; exit 0; }

out=$(
  echo "## Change review"
  echo
  echo "$(wc -l < "$LOG") actions recorded. Full log: $LOG"
  echo
  echo "| where | NEW | EDIT | CHANGE | SCRIPT |"
  echo "|---|---|---|---|---|"
  awk -F'\t' '{n[$3]++; c[$3,$2]++} END {for (w in n) printf "| %s | %d | %d | %d | %d |\n", w, c[w,"NEW"]+0, c[w,"EDIT"]+0, c[w,"CHANGE"]+0, c[w,"SCRIPT"]+0}' "$LOG" | sort
  echo
  if grep -q $'\tDOCUMENTS\t' "$LOG"; then
    echo "### Outside the vault and the keep (check these first)"
    grep $'\tDOCUMENTS\t' "$LOG" | cut -f1,2,4 | sed 's/^/- /; s/\t/ | /g'
    echo
  fi
  echo "### Moves, copies, deletes and scripts"
  grep -E $'\t(CHANGE|SCRIPT)\t' "$LOG" | grep -v $'\tDOCUMENTS\t' | cut -f2,3,4 | cut -c1-240 | sed 's/^/- /; s/\t/ | /g'
  echo
  echo "### Files created or edited"
  grep -E $'\t(NEW|EDIT)\t' "$LOG" | grep -v $'\tDOCUMENTS\t' | cut -f2,3,4 | sort -u | cut -c1-240 | sed 's/^/- /; s/\t/ | /g'
)
printf '%s\n' "$out"
ledger=$(ls "$VAULT/_recaps/"*-"${sid:0:8}".md 2>/dev/null | head -1)
if [ -n "$ledger" ]; then
  awk '/^## Change review$/{skip=1; next} /^## /{skip=0} !skip' "$ledger" > "$ledger.tmp" && mv "$ledger.tmp" "$ledger"
  printf '\n%s\n' "$out" >> "$ledger"
  echo; echo "(written to $ledger)"
fi
echo; echo 'Approve with "#ok push". Nothing is pushed until then.'
