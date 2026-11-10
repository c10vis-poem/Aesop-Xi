#!/usr/bin/env bash
# Rule 10, PreToolUse Bash: no push, PR or merge mid-session, and no auto-merge without CI.
. "$(dirname "$(realpath "$0")")/lib/parts.sh"
run_parts git-gate ci-ready
