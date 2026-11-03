#!/data/data/com.termux/files/usr/bin/bash
# run-hook.sh safety net (operator, 2026-11-03): master switch, operator override, loop breaker,
# block footer, exit-0 global stubs don't stand the project copy aside.
HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
mkdir -p "$T/hooks"; cp "$HOOKS/run-hook.sh" "$HOOKS/override-phrases.txt" "$T/hooks/"; RH=$T/hooks/run-hook.sh
printf '#!/usr/bin/env bash\necho BLOCKED >&2; exit 2\n' > "$T/hooks/block.sh"
printf '#!/usr/bin/env bash\necho "{\\"decision\\": \\"block\\", \\"reason\\": \\"not yet\\"}"\n' > "$T/hooks/stopblock.sh"
printf '#!/usr/bin/env bash\ncat >/dev/null; exit 0\n' > "$T/hooks/noop.sh"
ST=$T/.claude/state
run() { env -u PREFIX HOME="$T" bash "$RH" "$1" <<<"$2" 2>"$T/err"; }
tool='{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Read"}'
prompt() { jq -nc --arg p "$1" '{session_id:"s1",hook_event_name:"UserPromptSubmit",prompt:$p}'; }

run noop.sh "$(prompt 'fix the thing')"
run block.sh "$tool"; check "block passes through" '[ $? -eq 2 ]'
check "block carries the footer" 'grep -q "Hook safety net" "$T/err"'
run block.sh "$tool"; check "second block passes" '[ $? -eq 2 ]'
run block.sh "$tool"; check "third block in a turn: loop breaker yields" '[ $? -eq 0 ]'
check "loop breaker logged" 'grep -q "block.sh LOOP-BREAKER" "$ST/hooks.log"'

run noop.sh "$(prompt 'next thing')"
run block.sh "$tool"; check "new turn: counter reset, blocks again" '[ $? -eq 2 ]'

run noop.sh "$(prompt 'no, you can read it, I told you')"
run block.sh "$tool"; check "operator override lets the block through" '[ $? -eq 0 ]'
out=$(run stopblock.sh '{"session_id":"s1","hook_event_name":"Stop"}')
check "override drops a Stop JSON block" '[ -z "$out" ]'
check "override logged" 'grep -q "LET THROUGH" "$ST/hooks.log"'

run noop.sh "$(prompt 'ok carry on')"
out=$(run stopblock.sh '{"session_id":"s1","hook_event_name":"Stop"}')
check "override ends with the turn" 'grep -q "\"decision\": \"block\"" <<<"$out"'
check "Stop JSON reason gets the footer" 'grep -q "Hook safety net" <<<"$out"'

run noop.sh "$(jq -nc '{session_id:"s1",hook_event_name:"UserPromptSubmit",prompt:"<task-notification>override</task-notification>"}')"
run block.sh "$tool"; check "override inside a subagent/notification does not count" '[ $? -eq 2 ]'

run noop.sh "$(prompt 'turn the hooks off')"
check "master switch file set" '[ -e "$ST/hooks-off" ]'
run block.sh "$tool"; check "hooks off: nothing blocks" '[ $? -eq 0 ]'
out=$(run noop.sh '{"session_id":"s2","hook_event_name":"SessionStart"}')
check "hooks off survives into a new session and says so" 'grep -q "hooks-on" <<<"$out"'
run noop.sh "$(jq -nc '{session_id:"s2",hook_event_name:"UserPromptSubmit",prompt:"#hooks-on"}')"
run block.sh '{"session_id":"s2","hook_event_name":"PreToolUse"}'; check "#hooks-on: blocks again" '[ $? -eq 2 ]'
AESOP_HOOKS_OFF=1 run block.sh "$tool"; check "env AESOP_HOOKS_OFF=1 turns hooks off" '[ $? -eq 0 ]'

mkdir -p "$T/.claude/hooks"; printf '#!/usr/bin/env bash\n# disabled 2026-10-28\nexit 0\n' > "$T/.claude/hooks/block.sh"; chmod +x "$T/.claude/hooks/block.sh"
run noop.sh "$(prompt 'go on')"
run block.sh "$tool"; check "exit-0 global stub: project copy still runs" '[ $? -eq 2 ]'
printf '#!/usr/bin/env bash\necho real; exit 2\n' > "$T/.claude/hooks/block.sh"
run block.sh "$tool"; check "real global copy: project copy stands aside" '[ $? -eq 0 ]'
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
