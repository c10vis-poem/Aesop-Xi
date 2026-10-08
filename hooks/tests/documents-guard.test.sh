#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T; mkdir -p "$T/.claude/state"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
D=/storage/emulated/0/Documents; L="$T/.claude/state/docs-changes-S1.log"
# run the hook; print exit code and the last log line's kind+where (or "-" if nothing logged)
R(){ local n0 n1 rc; n0=$(cat "$L" 2>/dev/null | wc -l); bash "$S/documents-guard.sh" >/dev/null 2>&1; rc=$?
     n1=$(cat "$L" 2>/dev/null | wc -l); [ "$n1" -gt "$n0" ] && echo "$rc $(tail -1 "$L" | cut -f2,3 | tr '\t' ' ')" || echo "$rc -"; }
W(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Write",tool_input:{file_path:$f}}' | R; }
E(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Edit",tool_input:{file_path:$f}}' | R; }
B(){ jq -n --arg c "$1" '{session_id:"S1",tool_name:"Bash",tool_input:{command:$c}}' | R; }
# nothing is ever blocked (exit 0); every change is logged with kind and where
ok "$(W "$D/NovAExorpus/clean_md/new-file.md")" "0 NEW vault" "new vault file logged"
ok "$(E "$D/NovAExorpus/PENDING.md")" "0 EDIT vault" "edit logged"
ok "$(B "mv a '$D/NovAExorpus/tools/b'")" "0 CHANGE vault" "mv into vault logged"
ok "$(B "mkdir -p '$D/Merovingian's_keep/x'")" "0 CHANGE keep" "mkdir in keep logged"
ok "$(B "rm -rf $D/WebView")" "0 CHANGE OUTSIDE" "rm outside flagged"
ok "$(B "echo hi > $D/Zip/a.txt")" "0 CHANGE OUTSIDE" "redirect outside flagged"
ok "$(W "$D/NovAExorpus/../Zip/x.md")" "0 NEW OUTSIDE" "traversal flagged outside"
ok "$(W "$D/NovAExorpus-nested-mirror/x")" "0 NEW OUTSIDE" "lookalike dir flagged outside"
ok "$(B "cp $D/NovAExorpus/a $D/Zip/b")" "0 CHANGE OUTSIDE" "mixed paths flagged outside"
ok "$(B "python3 move.py $D/NovAExorpus")" "0 SCRIPT vault" "script logged"
ok "$(B "sed -i 's/a/b/' $D/NovAExorpus/PENDING.md")" "0 EDIT vault" "sed -i logged as edit"
# reads and non-Documents paths are not logged
ok "$(B "ls $D/Zip 2>&1")" "0 -" "read not logged"
ok "$(B "cat $D/Zip/a > /dev/null")" "0 -" "read to /dev/null not logged"
ok "$(W "$HOME/repos/x")" "0 -" "non-Documents ignored"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" = 0 ]
