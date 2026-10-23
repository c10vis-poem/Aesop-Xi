#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
R="$T/repos/FAKE"; git init -q -b main "$R"; git -C "$R" -c user.email=a@b -c user.name=a commit -q --allow-empty -m i
git -C "$R" worktree add -q -b wt "$T/repos/wt-fake" 2>/dev/null; git init -q -b main "$T/repos/OTHER"; mkdir -p "$T/elsewhere" "$T/repos/OTHER/docs"
B(){ jq -cn --arg c "$1" --arg d "${2:-$R}" '{hook_event_name:"PreToolUse",session_id:"S1",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' | bash "$S/build-doc-gate.sh" 2>"$T/err"; echo $?; }
RD(){ jq -cn --arg f "$1" '{hook_event_name:"PostToolUse",session_id:"S1",tool_name:"Read",cwd:"/",tool_input:{file_path:$f}}' | bash "$S/build-doc-gate.sh"; }
ok "$(B 'npm install')" 2 "npm install in checkout, no doc read -> block"
ok "$(command grep -c 'FAKE' "$T/err")" 1 "reason names the repo"
ok "$(B 'cd ~/repos/FAKE && make' "$T/elsewhere")" 2 "cd into checkout then make -> block"
ok "$(B 'pip install -e .' "$T/repos/wt-fake")" 2 "worktree counts as its repo -> block"
ok "$(B 'cargo build --release')" 2 "cargo build -> block"
ok "$(B './gradlew assembleDebug')" 2 "./gradlew -> block"
RD "$R/src/main.py"; ok "$(B 'npm ci')" 2 "non-doc read doesn't count"
RD "$R/README.md"
ok "$(B 'npm ci')" 0 "after README read -> pass"
ok "$(B 'make' "$T/repos/wt-fake")" 0 "doc read in main checkout covers its worktree"
ok "$(B 'make' "$T/repos/OTHER")" 2 "other repo still blocked"
RD "$T/repos/OTHER/docs/Building-on-Termux.md"; ok "$(B 'make' "$T/repos/OTHER")" 0 "docs/*build* read -> pass"
ok "$(B 'npm install' "$T/elsewhere")" 0 "outside ~/repos -> pass"
ok "$(B 'cmake -S . -B out' "$T/repos/wt-fake")" 0 "cmake configure (not a build) -> pass"
ok "$(B 'git status')" 0 "non-build command -> pass"
ok "$(echo 'not json{' | bash "$S/build-doc-gate.sh" 2>/dev/null; echo $?)" 0 "malformed input -> pass"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
