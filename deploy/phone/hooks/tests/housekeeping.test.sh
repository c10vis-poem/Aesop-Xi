#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export PENDING_FILE=$T/P.md
mk(){ printf '# P\n## Routines\nlast-housekeeping: %s\n- roll recaps\n- audit repos\n## Other\n- x\n' "$1" > "$PENDING_FILE"; }
c(){ bash "$S/housekeeping-check.sh" | head -1 | cut -c1-40; }
mk never;                              echo "never      -> $(c)"
mk "$(date -d '9 days ago' +%F)";      echo "9 days ago -> $(c)"
mk "$(date +%F)";                      echo "today      -> [$(c)] (expect empty)"
echo "routine lines shown: $(mk never; bash "$S/housekeeping-check.sh" | grep -c '^- ') (expect 2)"
rm -rf "$T"
