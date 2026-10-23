#!/data/data/com.termux/files/usr/bin/bash
# H7: a keyword in a passing mention must not fire a mode=command row; a command must; mode=always still fires on mention.
S=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export ENFORCEMENTS_FILE=$S/ENFORCEMENTS.md
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
ids(){ jq -n --arg p "$1" '{prompt:$p,cwd:"/"}' | bash "$S/classify.sh" | jq -r '[.required[].id]|sort|join(",")'; }

qa=$'1. yes, the NPU numbers look fine.\n2. did Obsidian sync? I used graphify last week.\n3. Kokoro was the old voice, right?\n4. what about the benchmark history?'
ok "$(ids "$qa")" "" "passing mentions in numbered Q&A -> nothing required"
ok "$(ids "run the NPU benchmark")" "bench,npu" "imperative 'run the NPU benchmark' -> npu + bench"
ok "$(ids "Please install graphify on the VM and then check the logs.")" "graphify" "verb within 6 words -> graphify"
ok "$(ids "npu status")" "npu" "short prompt -> fires"
ok "$(ids "why is the npu slow today in this setup?")" "" "question mentioning npu -> no"
ok "$(ids "I ran into the hook problem. Also the NPU is fine.")" "hooks" "always row (hooks) fires on mention; command row (npu) does not"
ok "$(ids "1. fine. 2. the rename went well. 3. NPU was ok.")" "naming" "always row (naming) fires in long Q&A"
ok "$(ids "fix it now please. the npu part is separate from that")" "" "sentence break ends the verb window"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
