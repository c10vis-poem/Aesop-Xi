#!/data/data/com.termux/files/usr/bin/bash
# checkin-gate.sh judges the command, not the text (obs 0042); interpreter runs count (obs 0044).
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; export HOME=$T
st=$T/.claude/state; mkdir -p "$st"; printf '## START HERE\n1. a\n' > "$st/resume-S.snap.md"; touch "$st/resume-S.ok"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
G(){ jq -n --arg t "$1" --argjson i "$2" '{session_id:"S",tool_name:$t,tool_input:$i}' | bash "$S/checkin-gate.sh" 2>"$T/err"; echo $?; }
B(){ G Bash "$(jq -n --arg c "$1" '{command:$c}')"; }
ok "$(G StructuredOutput '{}')" 0 "StructuredOutput (hook auditor) allowed"
ok "$(G TaskCreate '{"subject":"x"}')" 0 "task tools allowed"
ok "$(G Edit '{"file_path":"/x"}')" 2 "Edit blocked"
ok "$(G Agent '{"subagent_type":"Explore","prompt":"look"}')" 0 "Explore subagent allowed"
ok "$(G Agent '{"subagent_type":"general-purpose","prompt":"build it"}')" 2 "writing subagent blocked"
ok "$(B "grep -rn 'rm -rf' ~/.claude/projects/*.jsonl | head")" 0 "rm inside quotes is text"
ok "$(B "jq -r 'select(.type==\"user\") | .message.content' t.jsonl | grep -c delete")" 0 "jq over transcripts allowed"
ok "$(B "cat <<'EOF'
rm -rf /tmp/x
mv a b
EOF")" 0 "heredoc body is text"
ok "$(B "ls -la; git status; git log --oneline -3")" 0 "read-only git allowed"
ok "$(B "rm -rf build")" 2 "rm blocked"
ok "$(B "python3 -I tools/check.py --help")" 2 "interpreter run blocked (obs 0044)"
ok "$(B "bash scripts/run.sh")" 2 "script run blocked"
ok "$(B "python3 --version")" 0 "interpreter with only flags allowed"
ok "$(B "echo done > out.txt")" 2 "redirect blocked"
ok "$(B "resume-item plan")" 0 "resume-item plan allowed"
ok "$(grep -c '/write' "$T/err")" 0 "last allowed call wrote no message"
B "rm x" >/dev/null; ok "$(grep -c '/write' "$T/err")" 1 "block message offers /write"
touch "$st/checkin-S"; ok "$(B "rm -rf build")" 0 "after check-in: allowed"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
