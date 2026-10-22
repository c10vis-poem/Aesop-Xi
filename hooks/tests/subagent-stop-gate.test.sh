#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T; D="$T/.claude/session-work/2026-10-21"; mkdir -p "$D" "$T/.claude/state"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
tr_(){ jq -cn --arg c "$1" '{type:"user",message:{role:"user",content:$c}}' > "$T/tr.jsonl"; }
G(){ jq -n --arg t "${1:-$T/tr.jsonl}" --argjson a "${2:-false}" '{session_id:"S1",agent_transcript_path:$t,stop_hook_active:$a}' | bash "$S/subagent-stop-gate.sh" 2>"$T/err"; echo $?; }
PF="$D/agent-x.md"
ok "$(G /nonexistent)" 0 "no transcript -> allow"
tr_ "do a thing, no progress file"; ok "$(G)" 0 "no progress path -> allow"
tr_ "Keep a progress file: ~/.claude/session-work/2026-10-21/agent-x.md first"
ok "$(G)" 2 "missing file -> block"
printf '## Plan\n- [x] a\n- [ ] b\n## Last action\nx\n## Blocked\n' > "$PF"
ok "$(G)" 2 "unchecked box -> block"; ok "$(grep -c '^- b$' "$T/err")" 1 "reason names the step"
printf '## Plan\n- [x] a\n- [ ] b\n## Blocked\n- b: waiting on operator\n' > "$PF"
ok "$(G)" 0 "unchecked but in Blocked -> allow"
printf '## Plan\n- [x] a\n- [x] b\n## Blocked\n' > "$PF"; ok "$(G)" 0 "all checked -> allow"
printf '## Plan\n- [ ] b\n## Blocked\n' > "$PF"; ok "$(G "" true)" 0 "stop_hook_active -> allow"
ok "$(ls "$T/.claude/state" | wc -l)" 0 "no main-session state written"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
