#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
B(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$S/settings-guard.sh" 2>"$T/err"; echo $?; }
W(){ jq -cn --arg t "$1" --arg f "$2" '{tool_name:$t,tool_input:{file_path:$f}}' | bash "$S/settings-guard.sh" 2>/dev/null; echo $?; }
ok "$(W Edit "$T/.claude/settings.json")" 2 "Edit settings.json -> block"
ok "$(W Write '~/.claude/settings.local.json')" 2 "Write settings.local.json (~) -> block"
ok "$(W Write "$T/.claude.json")" 2 "Write ~/.claude.json -> block"
ok "$(B 'jq ".model=\"x\"" ~/.claude/settings.json > ~/.claude/settings.json')" 2 "jq > settings.json -> block"
ok "$(command grep -c 'operator-owned' "$T/err")" 1 "message names operator-owned"
ok "$(B 'echo {} >> "$HOME/.claude/settings.local.json"')" 2 "append redirect -> block"
ok "$(B 'jq . x.json | tee ~/.claude/settings.json')" 2 "tee -> block"
ok "$(B 'jq . ~/.claude/settings.json > /tmp/n && mv /tmp/n ~/.claude/settings.json')" 2 "mv onto -> block"
ok "$(B 'cp /tmp/n ~/.claude/settings.json')" 2 "cp onto -> block"
ok "$(B 'sed -i s/a/b/ ~/.claude.json')" 2 "sed -i ~/.claude.json -> block"
ok "$(B "cd ~/.claude && sed -i 's/a/b/' settings.json")" 2 "cd ~/.claude then sed -i -> block"
ok "$(B "echo x > $T/.claude/settings.json")" 2 "absolute home path -> block"
ok "$(B 'jq .hooks ~/.claude/settings.json')" 0 "jq read -> pass"
ok "$(B 'jq -r .model ~/.claude/settings.json 2>/dev/null | head -1')" 0 "jq read piped -> pass"
ok "$(B 'cp ~/.claude/settings.json ~/backup.json')" 0 "cp from settings (backup) -> pass"
ok "$(W Edit "$T/repos/x/.claude/settings.json")" 0 "project .claude/settings.json Edit -> pass"
ok "$(B 'jq . a.json > ~/repos/x/.claude/settings.json')" 0 "project settings redirect -> pass"
ok "$(B 'echo hi > /tmp/settings-notes.txt')" 0 "unrelated file -> pass"
ok "$(echo 'not json{' | bash "$S/settings-guard.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
