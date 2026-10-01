#!/data/data/com.termux/files/usr/bin/bash
# H1b, SessionStart: remind when weekly housekeeping is due.
# Due if PENDING.md "last-housekeeping:" is missing/never, 7+ days old,
# or it's Fri-Sun and the last run was before this Friday. Never blocks.
P=${PENDING_FILE:-$HOME/storage/shared/Documents/NovAExorpus/PENDING.md}
[ -f "$P" ] || exit 0
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
[ -z "$due" ] && exit 0
echo "HOUSEKEEPING DUE ($due). Tell the builder before anything else. Routines: see '## Routines' in $P"
sed -n '/^## Routines/,/^## /{/^- /p}' "$P" | head -12
exit 0
