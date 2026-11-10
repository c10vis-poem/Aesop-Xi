#!/usr/bin/env bash
# Rule 7 (operator numbering), the session log, written at SessionEnd (the wrap-up's last step). Two parts, one place:
#   NvAEx-Recaps session-logs/<date>-<sid8>/scratchpad/   the agent's notes: what was done all session
#   NvAEx-Recaps session-logs/<date>-<sid8>/task-log.md   repos, files, git actions, changes, skills used, tools used
# Committed on branch session-log/<date>-<sid8> off the Recaps default branch (the git hooks scan it for
# secrets); ship-session ships that branch under the GitHub rule. No other copy is kept. Never blocks.
# Env overrides (tests): RECAPS_REPO, RECAPS_DIR, STATE_DIR, SCRATCH_ROOT.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$in" 2>/dev/null); [ -n "$sid" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}
RR=${RECAPS_REPO:-${REPOS_DIR:-$HOME/repos}/NvAEx-Recaps}
[ -d "$RR/.git" ] || { hook_log "save-session-log: $RR is not a git repo, session log NOT saved ($sid)"; exit 0; }
date=$(date +%F); s8=${sid:0:8}; rel="session-logs/$date-$s8"
src=$(ls -d "${SCRATCH_ROOT:-${TMPDIR:-/tmp}}"/claude-*/*/"$sid"/scratchpad 2>/dev/null | head -1)
ledger=$(ls "$RECAPS_DIR/"*-"$s8".md 2>/dev/null | head -1)

git -C "$RR" fetch -q origin 2>/dev/null
def=$(git -C "$RR" symbolic-ref -q --short refs/remotes/origin/HEAD); def=${def:-origin/main}
br="session-log/$date-$s8"; wt="$RR/.wt-session-log-$s8"
git -C "$RR" worktree add -q -b "$br" "$wt" "$def" 2>/dev/null \
  || git -C "$RR" worktree add -q "$wt" "$br" 2>/dev/null \
  || { hook_log "save-session-log: cannot make worktree $wt ($sid)"; exit 0; }
d="$wt/$rel"; mkdir -p "$d"

# Part 1: the scratchpad
if [ -n "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ]; then
  mkdir -p "$d/scratchpad"
  rsync -a --exclude '.git/' --exclude 'node_modules/' "$src"/ "$d/scratchpad"/ 2>/dev/null || cp -r "$src"/. "$d/scratchpad"/
fi

# Part 2: the task log
{
  echo "# Task log: session $sid ($date)"
  [ -n "$ledger" ] && { echo; sed '1{/^# /d}' "$ledger"; }
  [ -s "$ST/changes-$sid.log" ] && { echo; echo "## Changes"; echo; sed 's/^/- /' "$ST/changes-$sid.log"; }
  if [ -s "$ST/subagent-audit-$sid.tsv" ]; then
    echo; echo "## Sub-agent audits"; echo
    awk -F'\t' '{print "- " $1 " " $2 " (" $3 "): " $4 "; " $5 "; task file: " $6}' "$ST/subagent-audit-$sid.tsv"
  fi
  if [ -f "$tp" ]; then
    echo; echo "## Skills used"; echo
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill // empty' "$tp" 2>/dev/null \
      | sort | uniq -c | sort -rn | awk '{c=$1; $1=""; sub(/^ /,""); print "- " $0 " (" c ")"}'
    echo; echo "## Tools used"; echo
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' "$tp" 2>/dev/null \
      | sort | uniq -c | sort -rn | awk '{print "- " $2 " (" $1 ")"}'
  fi
} > "$d/task-log.md"
# the sub-agents' own task files belong to the task log
if [ -s "$ST/subagent-audit-$sid.tsv" ]; then
  cut -f6 "$ST/subagent-audit-$sid.tsv" | sort -u | while IFS= read -r f; do
    [ -f "$f" ] && { mkdir -p "$d/subagents"; cp "$f" "$d/subagents/"; }
  done
fi

git -C "$wt" add "$rel"
if git -C "$wt" commit -q -m "session log: $date $s8" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" >/dev/null 2>&1; then
  hook_log "save-session-log: $rel committed on $br ($sid)"
else hook_log "save-session-log: commit BLOCKED on $br (secret found or nothing to commit) ($sid)"; fi
git -C "$RR" worktree remove --force "$wt" 2>/dev/null
exit 0
