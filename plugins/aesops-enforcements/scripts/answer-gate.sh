#!/usr/bin/env bash
# Rules 5 and 8 (operator numbering: 5 and 9; claim-gate is the rest of 9). PreToolUse AskUserQuestion: a menu needs a write-in option.
# Stop: the final answer cannot claim something is missing without a search, or end on a yes/no question.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
case $event in
  PreToolUse) run_parts menu-gate ;;
  *) run_parts absence-gate claim-gate question-gate ;;
esac
