#!/data/data/com.termux/files/usr/bin/bash
# run-hook.sh in a cloud session: phone-only gates stand down, cloud-safe hooks still run.
HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
repo="$T/r"; git init -q "$repo"; echo x > "$repo/RESUME.md"
ev=$(jq -nc --arg c "$repo" --arg t "$T/t.jsonl" '{session_id:"s1",transcript_path:$t,cwd:$c,tool_name:"Bash",tool_input:{command:"git push -u origin x"}}')
run() { env -u PREFIX HOME="$T" "$@" bash "$HOOKS/run-hook.sh" "$H" <<<"$ev" 2>/dev/null; }

for H in resume-gate.sh git-gate.sh; do
  run CLAUDE_CODE_REMOTE=true >/dev/null; check "cloud: $H stands down" '[ $? -eq 0 ]'
  run CLAUDE_CODE_REMOTE= >/dev/null; check "local: $H still blocks" '[ $? -eq 2 ]'
  run CLAUDE_CODE_REMOTE=true AESOP_CLOUD_GATES=1 >/dev/null; check "cloud + AESOP_CLOUD_GATES=1: $H blocks" '[ $? -eq 2 ]'
  run CLAUDE_CODE_REMOTE=true PREFIX=/data/data/com.termux/files/usr >/dev/null; check "termux with CLAUDE_CODE_REMOTE: $H blocks" '[ $? -eq 2 ]'
done
H=stop-gate.sh
check "cloud: stop-gate stays quiet" '[ -z "$(run CLAUDE_CODE_REMOTE=true)" ]'
check "local: stop-gate still blocks" 'run CLAUDE_CODE_REMOTE= | grep -q "\"decision\": \"block\""'
H=secret-guard.sh; ev=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit --no-verify"}}')
run CLAUDE_CODE_REMOTE=true; check "cloud: secret-guard still runs" '[ $? -eq 2 ]'

echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
