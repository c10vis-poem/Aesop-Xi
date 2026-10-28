#!/usr/bin/env bash
# Project-level launcher for every hook (registered in Aesop-Xi/.claude/settings.json).
# - If this device already has the global copy (~/.claude/hooks/<name>, wired in user settings),
#   that one runs and this exits 0, so nothing fires twice.
# - Every hook runs on every device, cloud sessions included. Nothing stands down (operator,
#   2026-10-24: "DON'T EVEN THINK ABOUT DISABLING THEM"). What differs in the cloud is handled inside
#   the hooks through hooks/lib/env.sh: paths resolve to the cloud checkouts, and a requirement that
#   only the phone can satisfy is reported instead of blocking forever.
# - A hook may not crash or hang a session: it runs under a watchdog (AESOP_HOOK_TIMEOUT, default 8 s;
#   SessionEnd ship uses its own detach). A timeout or an internal error (any exit other than 0 or 2)
#   is logged to ~/.claude/state/hooks.log and the call is allowed (fail-open). Exit 2 (a deliberate
#   block) and stdout (Stop JSON, context lines) pass through unchanged.
name="$1"; shift
[ -x "$HOME/.claude/hooks/$name" ] && exit 0
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ -f "$here/$name" ] || exit 0
st="$HOME/.claude/state"; mkdir -p "$st" 2>/dev/null
tmo=${AESOP_HOOK_TIMEOUT:-8}
case $name in ship-session.sh|archive-scratchpad.sh|sync-on-use.sh) tmo=${AESOP_HOOK_TIMEOUT:-60} ;; esac
if command -v timeout >/dev/null 2>&1; then
  timeout -k 2 "$tmo" bash "$here/$name" "$@"; rc=$?
else
  bash "$here/$name" "$@"; rc=$?
fi
case $rc in
  0|2) exit $rc ;;
  124|137) echo "$(date '+%F %T') $name TIMEOUT after ${tmo}s (allowed)" >> "$st/hooks.log" 2>/dev/null; exit 0 ;;
  *)      echo "$(date '+%F %T') $name ERROR exit $rc (allowed)" >> "$st/hooks.log" 2>/dev/null; exit 0 ;;
esac
