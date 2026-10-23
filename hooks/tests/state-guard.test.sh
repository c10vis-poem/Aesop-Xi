#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
B(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$S/state-guard.sh" 2>/dev/null; echo $?; }
W(){ jq -cn --arg t "$1" --arg f "$2" '{tool_name:$t,tool_input:{file_path:$f}}' | bash "$S/state-guard.sh" 2>/dev/null; echo $?; }
ok "$(B 'rm ~/.claude/state/wrapup-x ~/.claude/state/resume-S1.ok')" 2 "rm resume-*.ok -> block"
ok "$(B 'mv $HOME/.claude/state/pushnow-S1 /tmp/')" 2 "mv pushnow -> block"
ok "$(B 'truncate -s0 ~/.claude/state/observe-queue-S1.tsv')" 2 "truncate observe-queue -> block"
ok "$(B 'echo x > ~/.claude/state/confirm-S1.tsv')" 2 "redirect into confirm -> block"
ok "$(B 'echo 3 >> "$HOME/.claude/state/required-S1.tsv"')" 2 "append into required -> block"
ok "$(B 'cd ~/.claude/state && rm satisfied-S1.tsv')" 2 "cd then rm -> block"
ok "$(B 'sed -i /x/d ~/.claude/state/plan-S1.txt')" 2 "sed -i plan -> block"
ok "$(B 'find ~/.claude/state -name "checkin-*" -delete')" 2 "find -delete checkin -> block"
ok "$(W Write "$T/.claude/state/resume-S1.ok")" 2 "Write resume -> block"
ok "$(W Edit '~/.claude/state/confirm-S1.tsv')" 2 "Edit ~ path -> block"
ok "$(B 'cat ~/.claude/state/resume-S1.ok; ls ~/.claude/state/ 2>/dev/null')" 0 "reads -> pass"
ok "$(B 'cat ~/.claude/state/confirm-S1.tsv > /tmp/copy 2>&1')" 0 "read redirected elsewhere -> pass"
ok "$(B 'rm ~/.claude/state/absence-gate.log')" 0 "non-enforcement state file -> pass"
ok "$(B 'resume-item 2 done "tests green"; observe-dismiss 3 "noise"')" 0 "official tools -> pass"
ok "$(W Write "$T/repos/x/resume-notes.md")" 0 "Write outside state -> pass"
ok "$(echo 'not json{' | bash "$S/state-guard.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
