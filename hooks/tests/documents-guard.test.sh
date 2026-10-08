#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T; mkdir -p "$T/.claude/state"
cp "$S/ENFORCEMENTS.md" "$T/.claude/ENFORCEMENTS.md"; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
D=/storage/emulated/0/Documents
# decision: block (exit 2) | ask (permission prompt) | allow
R(){ local o; o=$(bash "$S/documents-guard.sh" 2>/dev/null); case $? in 2) echo block;; *) grep -q '"ask"' <<<"$o" && echo ask || echo allow;; esac; }
W(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Write",tool_input:{file_path:$f}}' | R; }
E(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Edit",tool_input:{file_path:$f}}' | R; }
B(){ jq -n --arg c "$1" '{session_id:"S1",tool_name:"Bash",tool_input:{command:$c}}' | R; }
P(){ jq -n --arg p "$1" '{session_id:"S1",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null 2>&1; }
V="$T/Documents/NovAExorpus"; mkdir -p "$V"; echo x > "$V/existing.md"
P "fix the readme"
# outside the vault and the keep: blocked
ok "$(W "$D/Zip/x.md")" block "outside vault blocked"
ok "$(W "$D/NovAExorpus/../Zip/x.md")" block "traversal out of vault blocked"
ok "$(W "$D/NovAExorpus-nested-mirror/x")" block "lookalike dir blocked"
ok "$(W "/sdcard/Documents/new/x")" block "sdcard alias blocked"
ok "$(B "echo hi > $D/Zip/a.txt")" block "bash redirect outside blocked"
ok "$(B "mv a '$D/Zip/b'")" block "bash mv outside blocked"
ok "$(B "rm -rf $D/WebView")" block "bash rm outside blocked"
# inside: creating, moving, copying, deleting, scripts ask the operator
ok "$(W "$D/NovAExorpus/clean_md/new-file.md")" ask "new vault file asks"
ok "$(B "mv a '$D/NovAExorpus/tools/b'")" ask "bash mv into vault asks"
ok "$(B "mkdir -p '$D/Merovingian's_keep/x'")" ask "bash mkdir in keep asks"
ok "$(B "cp x $D/NovAExorpus/01-inbox/y")" ask "bash cp asks"
ok "$(B "rm $D/NovAExorpus/a.md")" ask "bash rm in vault asks"
ok "$(B "python3 move.py $D/NovAExorpus")" ask "script on vault asks"
# inside: editing existing files and reading are allowed
ok "$(E "$D/NovAExorpus/PENDING.md")" allow "edit allowed"
ok "$(B "sed -i 's/a/b/' $D/NovAExorpus/PENDING.md")" allow "sed -i edit allowed"
ok "$(B "ls $D/Zip 2>&1")" allow "bash read allowed"
ok "$(B "cat $D/Zip/a > /dev/null")" allow "bash read to /dev/null allowed"
ok "$(W "$HOME/repos/x")" allow "non-Documents ignored"
# every asked/edited action is logged
ok "$(grep -c . "$T/.claude/state/docs-changes-S1.log")" 8 "actions logged"
# override pre-approves this prompt only
P "do it #skip-enforce"; ok "$(W "$D/Zip/x.md")" allow "override token unlocks this prompt"
ok "$(B "mv a '$D/NovAExorpus/b'")" allow "override pre-approves vault move"
P "next"; ok "$(W "$D/Zip/x.md")" block "override cleared next prompt"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" = 0 ]
