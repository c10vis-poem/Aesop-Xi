#!/usr/bin/env bash
# housekeeping-check.sh: due when never run or 7+ days old, quiet when run today, routines listed.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export HOME=$T PENDING_FILE=$T/P.md
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got '$1' want '$2')"; fi; }
mk(){ printf '# P\n## Routines\nlast-housekeeping: %s\n- roll recaps\n- audit repos\n## Other\n- x\n' "$1" > "$PENDING_FILE"; }
c(){ bash "$S/housekeeping-check.sh" | head -1 | cut -d. -f1; }
mk never;                         ok "$(c)" "HOUSEKEEPING DUE (never run)" "never run is due"
mk "$(date -d '9 days ago' +%F)"; ok "$(c)" "HOUSEKEEPING DUE (9 days ago)" "9 days old is due"
mk "$(date +%F)";                 ok "$(c)" "" "run today is quiet"
mk never; ok "$(bash "$S/housekeeping-check.sh" | grep -c '^- ')" 2 "routine lines shown"
rm "$PENDING_FILE"; ok "$(c)" "" "no PENDING.md: quiet"
# stale "RESUME not rewritten" flag (crane test 2026-11-10): cleared once a RESUME.md is dated after the flagged session
mkdir -p "$T/.claude/state" "$T/v"; F=$T/.claude/state/last-session-resume.flag; mk "$(date +%F)"
echo "missing 89c1bc9d 2026-10-28" > "$F"; printf '# RESUME
Last updated: 2026-10-01
' > "$T/v/RESUME.md"
ok "$(VAULT=$T/v bash "$S/housekeeping-check.sh" | grep -c 'without rewriting RESUME')" 1 "older RESUME: warning stays"
printf '# RESUME
Last updated: 2026-11-10
' > "$T/v/RESUME.md"
ok "$(VAULT=$T/v bash "$S/housekeeping-check.sh" | grep -c 'without rewriting RESUME')" 0 "RESUME dated after the flag: no warning"
ok "$(cut -d' ' -f1 "$F")" ok "and the flag is cleared"
ok "$(grep -c 'DEGRADE housekeeping-check' "$T/.claude/state/hooks.log")" 1 "no PENDING.md: logged"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
