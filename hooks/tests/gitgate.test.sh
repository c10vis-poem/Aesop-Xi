#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T; mkdir -p "$T/.claude/state"
cp "$S/ENFORCEMENTS.md" "$T/.claude/ENFORCEMENTS.md"; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
G(){ jq -n --arg c "$1" '{session_id:"S1",tool_name:"Bash",tool_input:{command:$c}}' | bash "$S/git-gate.sh" >/dev/null 2>&1; echo $?; }
P(){ jq -n --arg p "$1" '{session_id:"S1",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null 2>&1; }
P "fix the readme"
ok "$(G 'git push -u origin feat/x')" 2 "push blocked mid-session"
ok "$(G 'cd repo && git -C x push origin br')" 2 "git -C push blocked"
ok "$(G 'gh pr create --base main')" 2 "pr create blocked"
ok "$(G 'gh pr merge 5 --auto')" 2 "pr merge blocked"
ok "$(G 'git commit -m push-later')" 0 "commit allowed"
ok "$(G 'git status; gh pr list')" 0 "status/list allowed"
ok "$(G 'echo git push is blocked')" 2 "mention in text also blocked (fail-safe, accepted)"
P "ok push now please"; ok "$(G 'git push origin br')" 0 "push now unlocks this prompt"
P "next thing"; ok "$(G 'git push origin br')" 2 "push now cleared next prompt"
P "lets wrap up the session"; ok "$(G 'gh pr create')" 0 "wrap up unlocks"
P "another prompt"; ok "$(G 'git push')" 0 "wrap-up mode persists for session"
P2(){ jq -n --arg p "$1" '{session_id:"S1",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh"; }
ok "$(P2 'close session now' | grep -c WRAP-UP)" 1 "wrap-up prompt requires reading WRAP-UP.md"
F="$T/.claude/state/last-session-resume.flag"; echo "missing ab12cd34 2026-10-01" > "$F"
ok "$(PENDING_FILE=/nonexistent bash "$S/housekeeping-check.sh" | grep -c 'without rewriting RESUME')" 1 "RESUME-missing warning at start"
echo ok > "$F"; ok "$(PENDING_FILE=/nonexistent bash "$S/housekeeping-check.sh" | grep -c RESUME)" 0 "no warning when ok"
echo "== $pass passed, $fail failed"; rm -rf "$T"
