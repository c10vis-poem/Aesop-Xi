#!/usr/bin/env bash
# Rule 6: what the task requires comes first. PreToolUse: subagent type, build docs, ENFORCEMENTS rows
# (enforce-gate last, so it ticks a requirement only for a call that will run). PostToolUse Read records a build doc.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
case $event:$tool in
  PostToolUse:*) run_parts build-doc-gate ;;
  PreToolUse:Agent) run_parts subagent-task-gate agent-type-gate enforce-gate ;;
  PreToolUse:Bash) run_parts subagent-task-gate build-doc-gate enforce-gate ;;
  *) run_parts subagent-task-gate enforce-gate ;;
esac
