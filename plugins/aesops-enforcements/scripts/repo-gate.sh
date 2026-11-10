#!/usr/bin/env bash
# Rule 10, PreToolUse: a fork is synced before it is touched, and no work on a branch behind main.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
case $tool in
  Read) run_parts sync-on-use ;;
  *) run_parts sync-on-use branch-current-gate ;;
esac
