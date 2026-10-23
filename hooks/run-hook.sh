#!/usr/bin/env bash
# Project-level launcher for the H1–H7 hooks (registered in Aesop-Xi/.claude/settings.json).
# If this device already has the global copy (~/.claude/hooks/<name>, wired in user settings),
# that one runs and this exits 0, so nothing fires twice. Otherwise run the repo copy.
name="$1"; shift
[ -x "$HOME/.claude/hooks/$name" ] && exit 0
# Cloud sessions (CLAUDE_CODE_REMOTE=true, never Termux) have no vault, ~/.claude/state, resume-item
# or task-observer, so the RESUME/check-in/Stop/ENFORCEMENTS/git gates can never be satisfied there
# and the Stop gate re-blocks forever. Only hooks that work without the phone run in the cloud.
# AESOP_CLOUD_GATES=1 runs everything anyway.
if [ "$CLAUDE_CODE_REMOTE" = true ] && [ "$AESOP_CLOUD_GATES" != 1 ]; then
  case $PREFIX in *com.termux*) ;; *)
    case $name in secret-guard.sh|branch-current-gate.sh|context-diff.sh) ;; *) exit 0 ;; esac ;;
  esac
fi
exec bash "$(dirname "$0")/$name" "$@"
