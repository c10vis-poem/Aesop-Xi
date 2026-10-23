#!/data/data/com.termux/files/usr/bin/bash
# Tests staged-updates.sh (SessionStart) and the stop-gate staged-update item in a fake HOME.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T TERMUX_VERSION=test; v=$T/storage/shared/Documents/NovAExorpus; m=$v/skill-updates/PENDING.md
mkdir -p "$T/.claude/state" "$v/skill-updates" "$T/.claude/skills/tx" "$T/.claude/skills/other" "$T/.claude/plugins"
printf -- '---\nname: tx\ndescription: Use for any Android or Termux task.\n---\n' > "$T/.claude/skills/tx/SKILL.md"
printf -- '---\nname: other\ndescription: Unrelated.\n---\n' > "$T/.claude/skills/other/SKILL.md"
echo '{"plugins":{"honey@greenpt":[],"mem0@mem0-plugins":[]}}' > "$T/.claude/plugins/installed_plugins.json"
printf '# Staged updates manifest\n## skill-a -> skill-updates/x/skill-a/ (install = copy)\n- obs 1\n## Hook specs -> proposals/h.md\n' > "$m"
tp=$T/t.jsonl; jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:"task-observer"}}]}}' > "$tp"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
SG(){ jq -n --arg tp "$tp" --arg c "$T" --argjson a "${1:-false}" '{session_id:"S1",transcript_path:$tp,cwd:$c,stop_hook_active:$a}' | bash "$S/stop-gate.sh" | jq -r .reason; }

out=$(bash "$S/staged-updates.sh")
ok "$(grep -c '^STAGED SKILL UPDATES PENDING (2): skill-a; Hook specs$' <<<"$out")" 1 "session start lists count + names"
ok "$(grep -c '^TERMUX ASSETS: skills tx; plugins honey,mem0$' <<<"$out")" 1 "inventory: Termux skills + plugin names"
ok "$(bash "$S/staged-updates.sh" names | paste -sd '|')" "skill-a|Hook specs" "names mode"
ok "$(SG | grep -c '^- Staged skill updates pending (skill-a;Hook specs)')" 1 "stop blocked while updates pending"
ok "$(SG true | wc -c | tr -d ' ')" 0 "operator-only item yields on stop_hook_active"
sed -i 's/^## skill-a .*/& [installed 2026-10-23]/' "$m"
ok "$(SG | grep -c 'pending (Hook specs)')" 1 "installed heading no longer counts"
jq -nc '{type:"user",message:{content:"later #staged-defer"}}' >> "$tp"
ok "$(SG | wc -c | tr -d ' ')" 0 "#staged-defer from the operator clears it"
sed -i 's/^## Hook specs.*/& [installed 2026-10-23]/' "$m"
ok "$(bash "$S/staged-updates.sh" | grep -c STAGED)" 0 "all installed -> no pending line"
rm "$m"; ok "$(bash "$S/staged-updates.sh" | grep -c '^TERMUX ASSETS')" 1 "no manifest -> inventory only"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
