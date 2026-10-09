#!/usr/bin/env bash
# Project-level launcher for the H1–H7 hooks (registered in Aesop-Xi/.claude/settings.json).
# If this device already has the global copy (~/.claude/hooks/<name>, wired in user settings),
# that one runs and this exits 0, so nothing fires twice. Otherwise run the repo copy.
name="$1"; shift
[ -x "$HOME/.claude/hooks/$name" ] && exit 0
exec bash "$(dirname "$0")/$name" "$@"
