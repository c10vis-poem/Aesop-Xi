#!/usr/bin/env bash
# run-gate.sh in a cloud session (CLAUDE_CODE_REMOTE=true): every gate still runs and still blocks; nothing
# stands down. A hook that crashes or hangs is allowed (fail-open) and logged, so a hook can never end a
# cloud session.
HOOKS=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if eval "$2"; then echo "PASS $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
repo="$T/r"; git init -q "$repo"; echo "# RESUME 2026-10-24" > "$repo/RESUME.md"
ev=$(jq -nc --arg c "$repo" --arg t "$T/t.jsonl" '{session_id:"s1",transcript_path:$t,cwd:$c,tool_name:"Bash",tool_input:{command:"git push -u origin x"}}')
RH=$HOOKS/run-gate.sh
run() { env -u PREFIX HOME="$T" "$@" bash "$RH" "$H" <<<"$ev" 2>"$T/err"; }

for H in direction-gate git-gate; do
  rm -rf "$T/.claude/state"
  run CLAUDE_CODE_REMOTE=true >/dev/null; check "cloud: $H still blocks" '[ $? -eq 2 ]'
  rm -rf "$T/.claude/state"
  run CLAUDE_CODE_REMOTE= >/dev/null; check "local: $H blocks" '[ $? -eq 2 ]'
done
rm -rf "$T/.claude/state"
H=stop-gate
run CLAUDE_CODE_REMOTE=true >/dev/null; check "cloud: stop-gate still gates (RESUME not read)" '[ $? -eq 2 ]'
check "cloud: stop-gate names the opening step" 'grep -q "Opening O1" "$T/err"'
H=secret-guard; ev=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git commit --no-verify"}}')
run CLAUDE_CODE_REMOTE=true; check "cloud: secret-guard still runs" '[ $? -eq 2 ]'

# fail-open: a crashing hook and a hanging hook are both allowed and logged
mkdir -p "$T/p/scripts"; cp "$HOOKS/run-gate.sh" "$HOOKS/killswitch.sh" "$HOOKS/gates.tsv" "$T/p/scripts/"; RH=$T/p/scripts/run-gate.sh
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/p/scripts/crash.sh"; printf '#!/usr/bin/env bash\nsleep 30\n' > "$T/p/scripts/hang.sh"
printf '#!/usr/bin/env bash\necho "syntax"; if\n' > "$T/p/scripts/broken.sh"
H=crash; run CLAUDE_CODE_REMOTE=true AESOP_HOOK_TIMEOUT=2; check "crashing hook is allowed (fail-open)" '[ $? -eq 0 ]'
H=hang; t0=$SECONDS; run CLAUDE_CODE_REMOTE=true AESOP_HOOK_TIMEOUT=2; rc=$?; check "hanging hook times out and is allowed" "[ $rc -eq 0 ] && [ $((SECONDS - t0)) -lt 10 ]"
H=broken; run CLAUDE_CODE_REMOTE=true; check "syntax error (bash exit 2) is a crash, not a block" '[ $? -eq 0 ]'
check "all logged" 'grep -q "crash ERROR" "$T/.claude/state/hooks.log" && grep -q "hang TIMEOUT" "$T/.claude/state/hooks.log" && grep -q "broken CRASH" "$T/.claude/state/hooks.log"'
# a deliberate block (exit 2 + BLOCKED) still passes through
printf '#!/usr/bin/env bash\necho "BLOCKED (x): no" >&2; exit 2\n' > "$T/p/scripts/block.sh"
H=block; run CLAUDE_CODE_REMOTE=true; check "exit 2 passes through" '[ $? -eq 2 ]'

# lib/env.sh: vault resolves to a cloud checkout by remote URL; cloud flag set
mkdir -p "$T/novaexorpus"; git init -q "$T/novaexorpus"; git -C "$T/novaexorpus" remote add origin https://github.com/c10vis-poem/NovAExorpus.git
v=$(env -u PREFIX -u VAULT HOME="$T" CLAUDE_CODE_REMOTE=true bash -c ". '$HOOKS/lib/env.sh'; echo \"\$AESOP_CLOUD \$VAULT\"")
check "env: cloud flag + vault found by remote" '[ "$v" = "1 $T/novaexorpus" ]'
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
