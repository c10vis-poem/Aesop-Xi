#!/data/data/com.termux/files/usr/bin/bash
# branch-current-gate: blocks commits on a stale branch, allows the commit that merges main in.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
W=$T/w; mkdir -p "$W" "$T/.claude/state"
g(){ git -C "$W" -c user.name=t -c user.email=t@t -c core.hooksPath=/dev/null "$@" >/dev/null 2>&1; }
g init -q -b main; g commit --allow-empty -m base
g remote add origin https://github.com/c10vis-poem/x.git
g switch -q -c topic; echo a > "$W/a"; g add a; g commit -m topic
g switch -q main; echo b > "$W/a"; g add a; g commit -m main
git -C "$W" update-ref refs/remotes/origin/main main
git -C "$W" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
g switch -q topic
top=$(git -C "$W" rev-parse --show-toplevel)
: > "$T/.claude/state/fetched-S-$(echo "$top" | md5sum | cut -c1-8)"   # no network fetch
G(){ jq -n --arg c "$1" --arg d "$W" '{session_id:"S",tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$S/branch-current-gate.sh" 2>/dev/null; echo $?; }
ok "$(G 'git commit -m x')" 2 "stale branch commit blocked"
g merge origin/main
ok "$(G 'git commit -m merge')" 0 "commit finishing a merge of main allowed"
g merge --abort
ok "$(G 'git commit -m y')" 2 "aborted merge -> blocked again"
g merge -s ours --no-edit origin/main
ok "$(G 'git commit -m z')" 0 "branch containing main allowed"
echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
