#!/data/data/com.termux/files/usr/bin/bash
# run-hook.sh in a cloud session (CLAUDE_CODE_REMOTE=true): every gate still runs and still blocks; nothing
# stands down. A hook that crashes or hangs is allowed (fail-open) and logged, so a hook can never end a
# cloud session. A device with the global copy (~/.claude/hooks/<name>) lets that copy run instead.
HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
repo="$T/r"; git init -q "$repo"; echo "# RESUME 2026-10-24" > "$repo/RESUME.md"
ev=$(jq -nc --arg c "$repo" --arg t "$T/t.jsonl" '{session_id:"s1",transcript_path:$t,cwd:$c,tool_name:"Bash",tool_input:{command:"git push -u origin x"}}')
RH=$HOOKS/run-hook.sh
run() { env -u PREFIX HOME="$T" "$@" bash "$RH" "$H" <<<"$ev" 2>/dev/null; }

for H in resume-gate.sh git-gate.sh; do
  run CLAUDE_CODE_REMOTE=true >/dev/null; check "cloud: $H still blocks" '[ $? -eq 2 ]'
  run CLAUDE_CODE_REMOTE= >/dev/null; check "local: $H blocks" '[ $? -eq 2 ]'
done
H=stop-gate.sh
check "cloud: stop-gate still gates (RESUME not read)" 'run CLAUDE_CODE_REMOTE=true | grep -q "\"decision\": \"block\""'
check "cloud: stop-gate names the opening step" 'run CLAUDE_CODE_REMOTE=true | grep -q "Opening O1"'
H=secret-guard.sh; ev=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit --no-verify"}}')
run CLAUDE_CODE_REMOTE=true; check "cloud: secret-guard still runs" '[ $? -eq 2 ]'

# fail-open: a crashing hook and a hanging hook are both allowed and logged
mkdir -p "$T/hooks"; cp "$HOOKS/run-hook.sh" "$T/hooks/"; RH=$T/hooks/run-hook.sh
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/hooks/crash.sh"; printf '#!/usr/bin/env bash\nsleep 30\n' > "$T/hooks/hang.sh"
H=crash.sh; run CLAUDE_CODE_REMOTE=true AESOP_HOOK_TIMEOUT=2; check "crashing hook is allowed (fail-open)" '[ $? -eq 0 ]'
H=hang.sh; t0=$SECONDS; run CLAUDE_CODE_REMOTE=true AESOP_HOOK_TIMEOUT=2; rc=$?; check "hanging hook times out and is allowed" "[ $rc -eq 0 ] && [ $((SECONDS - t0)) -lt 10 ]"
check "both logged" 'grep -q "crash.sh ERROR" "$T/.claude/state/hooks.log" && grep -q "hang.sh TIMEOUT" "$T/.claude/state/hooks.log"'
# a deliberate block (exit 2) still passes through
printf '#!/usr/bin/env bash\necho BLOCKED >&2; exit 2\n' > "$T/hooks/block.sh"
H=block.sh; run CLAUDE_CODE_REMOTE=true; check "exit 2 passes through" '[ $? -eq 2 ]'
# global copy present -> project copy stands aside (nothing fires twice)
mkdir -p "$T/.claude/hooks"; printf '#!/usr/bin/env bash\nexit 2\n' > "$T/.claude/hooks/block.sh"; chmod +x "$T/.claude/hooks/block.sh"
run CLAUDE_CODE_REMOTE=true; check "global copy present: launcher exits 0" '[ $? -eq 0 ]'

# lib/env.sh: vault resolves to a cloud checkout by remote URL; cloud flag set
mkdir -p "$T/novaexorpus"; git init -q "$T/novaexorpus"; git -C "$T/novaexorpus" remote add origin https://github.com/c10vis-poem/NovAExorpus.git
v=$(env -u PREFIX HOME="$T" CLAUDE_CODE_REMOTE=true bash -c ". '$HOOKS/lib/env.sh'; echo \"\$AESOP_CLOUD \$VAULT\"")
check "env: cloud flag + vault found by remote" '[ "$v" = "1 $T/novaexorpus" ]'
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
