#!/usr/bin/env bash
# Rule 10, PreToolUse for subagents only: write to task as you work (operator's spec, Documents/Read this
# Subagent Persuasion/04 and 05). The progress file is the task log; it must state the current target before
# the agent acts:
#   - before the file exists: at most 2 read-only calls (Read, Grep, Glob, ToolSearch) to load the brief;
#   - every state-changing call (Bash, Write, Edit, NotebookEdit, Agent, Skill, WebFetch, MCP tools) needs a
#     progress-file write since the previous state-changing call;
#   - at most 3 read-only calls in a row without a progress-file write;
#   - the file must have a "## Last action" section (the current target and next step).
# Writing the progress file itself always passes. Main session: no effect. Fails open on bad input.
in=$(cat)
. "$(dirname "$(realpath "$0")")/lib/subagent.sh"
[ -n "$sa_aid" ] || exit 0
sa_exempt && exit 0
[ -f "$sa_tp" ] || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in"); target=$(jq -r '.tool_input.file_path // .tool_input.command // ""' <<<"$in")
case $tool in TodoWrite) exit 0 ;; esac
[[ $target == *session-work/*agent-*.md* ]] && exit 0
ro() { case $1 in Read|Grep|Glob|ToolSearch|LS) return 0 ;; esac; return 1; }
OV="OVERRIDE: the operator's direct instruction. REVOKE: the operator runs gate off task-gate."
blk() { echo "BLOCKED (subagent-task-gate, rule 10): $1 $OV" >&2; exit 2; }
# The agent's tool calls so far, in order: name<TAB>file-or-command
calls=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | [.name, (.input.file_path // .input.command // "")] | @tsv' "$sa_tp" 2>/dev/null)
if [ -z "$sa_pf" ] || [ ! -f "$sa_pf" ]; then
  n=$(grep -c . <<<"$calls")
  ro "$tool" && [ "${n:-0}" -lt 2 ] && exit 0
  blk "write to task first. $SA_HOW Write the plan before the work, then continue."
fi
grep -q '^## Last action' "$sa_pf" || blk "$sa_pf has no ## Last action section. Add it (timestamp, CURRENT_TARGET, NEXT_STEP), then continue."
# Walk the history backwards to the last write of the progress file.
since_ro=0; since_rw=0
while IFS=$'\t' read -r name arg; do
  [ -n "$name" ] || continue
  [[ $arg == *session-work/*agent-*.md* ]] && break
  if ro "$name"; then since_ro=$((since_ro + 1)); else since_rw=$((since_rw + 1)); fi
done < <(tac <<<"$calls")
if ! ro "$tool" && [ "$since_rw" -ge 1 ]; then
  blk "update $sa_pf before this $tool call: tick what you finished, set ## Last action to the current target and next step. One progress-file write per state-changing step."
fi
if ro "$tool" && [ "$since_ro" -ge 3 ]; then
  blk "$since_ro read-only calls since your last progress-file write. Record what you found under ## Findings and the next step under ## Last action, then continue."
fi
exit 0
