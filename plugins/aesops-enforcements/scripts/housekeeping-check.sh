#!/usr/bin/env bash
# H1b, SessionStart: remind when weekly housekeeping is due.
# Due if PENDING.md "last-housekeeping:" is missing/never, 7+ days old,
# or it's Fri-Sun and the last run was before this Friday. Never blocks.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
P=${PENDING_FILE:-${VAULT:-/nonexistent}/PENDING.md}
F="$HOME/.claude/state/last-session-resume.flag"
# A "missing" flag is stale once a RESUME.md (the vault's, or the launch repo's) carries a date after the flagged session's.
if [ -f "$F" ] && grep -q '^missing' "$F"; then
  fd=$(awk '{print $3}' "$F"); newest=
  for r in "${VAULT:-/nonexistent}/RESUME.md" "${CLAUDE_PROJECT_DIR:-$PWD}/RESUME.md"; do
    [ -f "$r" ] || continue; d=$(resume_date "$r"); [ -n "$d" ] && [ "$d" \> "${newest:-0}" ] && newest=$d
  done
  if [ -n "$newest" ] && [ -n "$fd" ] && [ "$newest" \> "$fd" ]; then echo "ok (cleared: RESUME.md dated $newest)" > "$F"
  elif [ "${1:-}" != due ]; then echo "WARNING: last session ended without rewriting RESUME.md ($(cut -d' ' -f2- "$F")). Fix that first."; fi
fi
[ -f "$P" ] || { degrade housekeeping "housekeeping-check: no PENDING.md at $P"; exit 0; }
last=$(sed -n 's/^last-housekeeping: *\([0-9-]*\).*/\1/p' "$P" | head -1)
today=$(date +%s); dow=$(date +%u)   # 1=Mon .. 7=Sun
due=""
if [ -z "$last" ]; then due="never run"
else
  l=$(date -d "$last" +%s 2>/dev/null) || l=0
  days=$(( (today - l) / 86400 ))
  [ "$days" -ge 7 ] && due="$days days ago"
  if [ -z "$due" ] && [ "$dow" -ge 5 ]; then
    fri=$(date -d "$(( dow - 5 )) days ago" +%F); [ "$last" \< "$fri" ] && due="end of week"
  fi
fi
[ "${1:-}" = due ] && { [ -n "$due" ] && echo "$due"; exit 0; }
[ -z "$due" ] && exit 0
# Build the report in the background once a day, so /housekeeping starts from it. Read-only.
m="$ST/housekeeping/last-auto"; mkdir -p "${m%/*}" 2>/dev/null
if [ "$(cat "$m" 2>/dev/null)" != "$(date +%F)" ]; then
  date +%F > "$m" 2>/dev/null
  setsid nohup bash "$HOOKS_DIR/../bin/housekeeping" report >/dev/null 2>&1 </dev/null &
fi
echo "HOUSEKEEPING DUE ($due). The report is being built; /housekeeping runs it. Tell the builder before anything else. Routines: see '## Routines' in $P"
sed -n '/^## Routines/,/^## /{/^- /p}' "$P" | head -12
exit 0
