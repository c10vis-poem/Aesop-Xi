#!/usr/bin/env sh
# Frankenstein kill switch. Usage: killswitch.sh <package> [hook-name]
# Exit 0 = hooks are OFF for this package/hook (caller must stop and exit 0).
# Exit 1 = hooks are ON (caller continues).
pkg="$1"; hook="$2"; off="$HOME/.claude/state/off"
[ -e "$HOME/.nvaex-hooks-off" ] && exit 0
[ -n "$pkg" ] && [ -e "$off/$pkg" ] && exit 0
[ -n "$pkg" ] && [ -n "$hook" ] && [ -e "$off/$pkg.$hook" ] && exit 0
exit 1
