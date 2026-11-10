#!/usr/bin/env bash
# Rule 9, the one session log. Before a call: the action (change-log). After: repos, files and git actions
# (session-ledger), and unfinished items carried from earlier sessions when RESUME is Read (carryover).
# SessionEnd: the session log, scratchpad and task log, goes to NvAEx-Recaps session-logs/<date>-<sid8>/
# (save-session-log; no other copy), and this session's unfinished items are recorded. Never blocks.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
case $event:$tool in
  PreToolUse:*) run_parts change-log ;;
  PostToolUse:Read) run_parts carryover ;;
  PostToolUse:*) run_parts session-ledger ;;
  SessionEnd:*) run_parts save-session-log carryover ;;
esac
