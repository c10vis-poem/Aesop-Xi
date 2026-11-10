#!/usr/bin/env bash
# Rule 10: the log records pushes; the Stop gate holds until PR, auto-merge and delete are done.
S=$(cd "$(dirname "$0")/../../scripts" && pwd); T=$(mktemp -d); export HOME=$T STATE_DIR=$T/.claude/state RECAPS_DIR=$T/r; st=$STATE_DIR; mkdir -p "$st" "$T/bin"
export VAULT=$T/novault GH_TIMEOUT=5 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.invalid
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got '$1' want '$2')"; fi; }
cat > "$T/bin/gh" <<G
#!/data/data/com.termux/files/usr/bin/bash
cat "$T/pr" 2>/dev/null
G
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH"
r=$T/repo; git init -q -b main "$r"; git -C "$r" commit -q --allow-empty -m 1; git -C "$r" switch -q -c topic
git -C "$r" remote add origin https://github.com/c10vis-poem/x
L(){ jq -nc --arg c "$1" --arg d "$r" '{session_id:"S",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' | bash "$S/session-ledger.sh"; }
Stop(){ jq -nc --arg c "$r" '{session_id:"S",cwd:$c,transcript_path:""}' | bash "$S/stop-gate.sh" 2>/dev/null | jq -r '.reason // ""' | grep -c "$1"; }
L 'git status'; ok "$([ -e "$st/pushed-S.tsv" ] && echo y || echo n)" n "a command with no push records nothing"
L 'git push -u origin topic'; ok "$(cut -f2 "$st/pushed-S.tsv")" topic "named branch recorded"
L 'git push'; ok "$(wc -l < "$st/pushed-S.tsv" | tr -d ' ')" 1 "bare push: current branch, not listed twice"
: > "$T/pr"; ok "$(Stop 'with no PR')" 1 "no PR: held"
printf '7\tOPEN\tfalse\n' > "$T/pr"; ok "$(Stop 'has no auto-merge')" 1 "PR without auto-merge: held"
printf '7\tOPEN\ttrue\n' > "$T/pr"; ok "$(Stop 'Rule 10')" 0 "auto-merge on: not held"
printf '7\tMERGED\tfalse\n' > "$T/pr"; ok "$(Stop 'not deleted')" 0 "merged, branch still here: not held (GitHub deletes it)"
touch "$st/nomerge-S"; printf '7\tOPEN\tfalse\n' > "$T/pr"; ok "$(Stop 'Rule 10')" 0 "#no-merge lifts it"; rm "$st/nomerge-S"
echo topic > "$st/keep-S.txt"; printf '7\tMERGED\tfalse\n' > "$T/pr"; ok "$(Stop 'not deleted')" 0 "#keep-branch keeps it"
ok "$(wc -c < "$st/pushed-S.tsv" | tr -d ' ')" 0 "kept branch is done with"
rm "$st/keep-S.txt"; printf '%s\ttopic\n' "$r" > "$st/pushed-S.tsv"; git -C "$r" switch -q main; git -C "$r" branch -q -D topic
ok "$(Stop 'not deleted')" 0 "merged and gone: done (no remote branch reachable here)"
printf '%s\tmain\n' "$r" > "$st/pushed-S.tsv"; : > "$T/pr"; ok "$(Stop 'Rule 10')" 0 "default branch is not checked"
jq -nc --arg p 'leave it #no-merge' '{session_id:"S2",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null; ok "$([ -e "$st/nomerge-S2" ] && echo y)" y "#no-merge in a prompt is recorded"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" -eq 0 ]
