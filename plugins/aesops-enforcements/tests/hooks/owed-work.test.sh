#!/usr/bin/env bash
# Owed work carries across prompts; tool: rows; always rows; the housekeeping stop and report.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); B=$S/../bin; T=$(mktemp -d); export HOME=$T STATE_DIR=$T/.claude/state; st=$STATE_DIR; mkdir -p "$st"
export ENFORCEMENTS_FILE=$T/enf.md VAULT=$T/v HOUSEKEEPING_REPOS=none; mkdir -p "$VAULT"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got '$1' want '$2')"; fi; }
cat > "$ENFORCEMENTS_FILE" <<'E'
| id | when | require | scope | note | mode |
|----|------|---------|-------|------|------|
| s1 | kw: alpha | skill: foo | session | n | always |
| t1 | kw: beta | skill: bar | turn | n | always |
| w1 | kw: gamma | tool: claw|tinyfish | turn | n | always |
E
P(){ jq -nc --arg p "$1" --arg c "$T" '{session_id:"S",prompt:$p,cwd:$c}' | bash "$S/enforce-prompt.sh" >/dev/null; }
G(){ jq -nc --arg t "$1" '{session_id:"S",tool_name:$t,tool_input:{}}' | bash "$S/enforce-gate.sh" >/dev/null 2>&1; echo $?; }
: > "$st/resume-S.ok"
P "do alpha and beta"
ok "$(cut -f1 "$st/required-S.tsv" | sort | paste -sd,)" "s1,t1" "both rows owed"
P "something else"
ok "$(cut -f1 "$st/required-S.tsv" | paste -sd,)" "s1" "session row carries to the next prompt; turn row does not"
P "alpha again"
ok "$(grep -c '^s1' "$st/required-S.tsv")" 1 "not listed twice"
P '<task-notification>done</task-notification>'
ok "$(cut -f1 "$st/required-S.tsv" | paste -sd,)" "s1" "a subagent hand-back does not wipe what is owed"
: > "$st/required-S.tsv"; P "gamma"
ok "$(G Bash)" 2 "tool row blocks another tool"
ok "$(G ToolSearch)" 0 "ToolSearch passes so the tool can load"
ok "$(G mcp__claw__claw.search)" 0 "a matching tool meets the row"
ok "$([ -s "$st/required-S.tsv" ] && echo owed || echo met)" met "row ticked off"
printf '| id | when | require | scope | note | mode |\n|---|---|---|---|---|---|\n| a1 | always | skill: zed | session | n | always |\n' > "$ENFORCEMENTS_FILE"
P "anything"
ok "$(cut -f1 "$st/required-S.tsv")" a1 "always row applies with no keyword"

printf '## Routines\nlast-housekeeping: 2020-01-01\n- Builder reminders: x\n\n## Open\n' > "$VAULT/PENDING.md"
ok "$(bash "$S/housekeeping-check.sh" due | grep -c 'days ago')" 1 "due mode says how old"
: > "$st/required-S.tsv"; : > "$st/wrapup-S"
tp=$T/t.jsonl; : > "$tp"
Stop(){ jq -nc --arg t "$tp" --arg c "$T" '{session_id:"S",transcript_path:$t,cwd:$c}' | bash "$S/stop-gate.sh" 2>/dev/null; }
ok "$(Stop | jq -r .reason | grep -c 'W9: housekeeping is due')" 1 "wrap-up held while housekeeping is due"
jq -nc '{type:"user",message:{content:"#housekeeping-defer"}}' > "$tp"
ok "$(Stop | jq -r '.reason // ""' | grep -c 'W9')" 0 "operator defer lifts it"
: > "$tp"
r=$(bash "$B/housekeeping" report); ok "$([ -f "$r" ] && echo yes)" yes "report written"
for h in '## 1' '## 2' '## 3' '## 4' '## 5'; do ok "$(grep -c "^$h" "$r")" 1 "report has $h"; done
ok "$(bash "$B/housekeeping" done)" "last-housekeeping: $(date +%F)" "done prints the date"
ok "$(bash "$S/housekeeping-check.sh" due | wc -c | tr -d ' ')" 0 "no longer due after done"
ok "$(Stop | jq -r '.reason // ""' | grep -c 'W9')" 0 "wrap-up no longer held"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
