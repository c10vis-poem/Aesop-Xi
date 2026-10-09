#!/data/data/com.termux/files/usr/bin/bash
# Tests H6/H7 in a fake HOME so no live state is touched.
S=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); export HOME=$T; mkdir -p "$T/.claude/state" "$T/repos/Aesop-Xi"
git -C "$T/repos/Aesop-Xi" init -q
cp "$S/ENFORCEMENTS.md" "$T/.claude/ENFORCEMENTS.md"
echo "| aesop | repo: Aesop-Xi | read: ~/repos/Aesop-Xi/AGENTS.md | session | test |" >> "$T/.claude/ENFORCEMENTS.md"
touch "$T/repos/Aesop-Xi/AGENTS.md" "$T/.claude/state/resume-S1.ok"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
P(){ jq -n --arg p "$1" --arg c "${2:-$T}" '{session_id:"S1",prompt:$p,cwd:$c}' | bash "$S/enforce-prompt.sh"; }
G(){ jq -n --arg t "$1" --argjson i "$2" '{session_id:"S1",tool_name:$t,tool_input:$i}' | bash "$S/enforce-gate.sh" >/dev/null 2>&1; echo $?; }

out=$(P "check the termux pkg list"); ok "$(grep -c android-termux-operator <<<"$out")" 1 "termux prompt -> pointer line"
ok "$(G Bash '{"command":"ls"}')" 2 "bash blocked before skill"
ok "$(G Skill '{"skill":"android-termux-operator"}')" 0 "required skill allowed"
ok "$(G Bash '{"command":"ls"}')" 0 "bash allowed after skill"
P "more termux work" >/dev/null; ok "$(G Bash '{"command":"ls"}')" 0 "session scope: not required again"
P "PR done, see /data/data/com.termux/files/usr/tmp/x.output" >/dev/null; ok "$(wc -l < "$T/.claude/state/required-S1.tsv" | tr -d ' ')" 0 "keyword inside a path -> ignored"
P "write a poem" >/dev/null; ok "$(G Bash '{"command":"ls"}')" 0 "unrelated prompt -> no block"
P "/task-observer" >/dev/null; P "log an observation" >/dev/null; ok "$(G Bash '{"command":"ls"}')" 0 "preloaded /skill satisfies"
P "rename to Hyperion" >/dev/null; ok "$(G Bash '{"command":"ls"}')" 2 "naming -> blocked"
ok "$(G Read '{"file_path":"'"$T"'/.claude/projects/-data-data-com-termux-files-home/memory/project_naming_canon.md"}')" 0 "required read allowed"
P "fix the readme" "$T/repos/Aesop-Xi" >/dev/null; ok "$(G Edit '{"file_path":"x"}')" 2 "repo row -> blocked"
ok "$(G Read '{"file_path":"'"$T"'/repos/Aesop-Xi/AGENTS.md"}')" 0 "repo guide read allowed"
P "rename again #skip-enforce" >/dev/null; ok "$(G Bash '{"command":"ls"}')" 0 "#skip-enforce bypasses"
rm "$T/.claude/state/resume-S1.ok"; P "adb devices" >/dev/null
jq -n '{session_id:"S1",tool_name:"Bash",tool_input:{command:"ls"}}' | bash "$S/enforce-gate.sh" >/dev/null 2>&1
ok "$?" 0 "resume not read yet -> gate yields (no deadlock)"
echo '{"session_id":"S1"' | bash "$S/enforce-gate.sh" >/dev/null 2>&1; ok "$?" 0 "garbage input -> fail open"
CLASSIFY_URL=http://127.0.0.1:9/none ok "$(jq -n '{prompt:"termux",cwd:"/"}' | CLASSIFY_URL=http://127.0.0.1:9/x bash "$S/classify.sh" | jq -r .backend)" keywords "remote down -> keyword fallback"
echo "log:"; cat "$T/.claude/state/enforce-S1.log"
echo "== $pass passed, $fail failed"; rm -rf "$T"
