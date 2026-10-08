#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T; mkdir -p "$T/.claude/state"
cp "$S/ENFORCEMENTS.md" "$T/.claude/ENFORCEMENTS.md"; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
D=/storage/emulated/0/Documents
W(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Write",tool_input:{file_path:$f}}' | bash "$S/documents-guard.sh" >/dev/null 2>&1; echo $?; }
B(){ jq -n --arg c "$1" '{session_id:"S1",tool_name:"Bash",tool_input:{command:$c}}' | bash "$S/documents-guard.sh" >/dev/null 2>&1; echo $?; }
P(){ jq -n --arg p "$1" '{session_id:"S1",prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null 2>&1; }
P "fix the readme"
ok "$(W "$D/NovAExorpus/clean_md/x.md")" 2 "vault non-pinned blocked"
ok "$(W "$D/Zip/x.md")" 2 "outside vault blocked"
ok "$(W "$D/NovAExorpus/01-inbox/a/b.md")" 0 "inbox allowed"
ok "$(W "$D/NovAExorpus/PENDING.md")" 0 "pinned root file allowed"
ok "$(W "$D/NovAExorpus/PENDING.md.bak")" 2 "near-name not pinned"
ok "$(W "$D/NovAExorpus/skill-observations/observation-log/1.md")" 0 "pinned dir allowed"
ok "$(W "$D/Merovingian's_keep/vault-moved/x")" 0 "keep allowed"
ok "$(W "$D/NovAExorpus/01-inbox/../tools/x")" 2 "traversal blocked"
ok "$(W "$D/NovAExorpus-nested-mirror/x")" 2 "lookalike dir blocked"
ok "$(W "/sdcard/Documents/new/x")" 2 "sdcard alias blocked"
ok "$(W "$HOME/repos/x")" 0 "non-Documents ignored"
ok "$(B "echo hi > $D/Zip/a.txt")" 2 "bash redirect blocked"
ok "$(B "mv a '$D/NovAExorpus/tools/b'")" 2 "bash mv blocked"
ok "$(B "mkdir -p '$D/Merovingian's_keep/x'")" 0 "bash mkdir in keep allowed"
ok "$(B "ls $D/Zip 2>&1")" 0 "bash read allowed"
ok "$(B "cat $D/Zip/a > /dev/null")" 0 "bash read to /dev/null allowed"
ok "$(B "cp x $D/NovAExorpus/01-inbox/y")" 0 "bash cp to inbox allowed"
ok "$(B "rm -rf $D/WebView")" 2 "bash rm blocked"
P "do it #skip-enforce"; ok "$(W "$D/Zip/x.md")" 0 "override token unlocks this prompt"
P "next"; ok "$(W "$D/Zip/x.md")" 2 "override cleared next prompt"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" = 0 ]
