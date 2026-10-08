#!/data/data/com.termux/files/usr/bin/bash
# change-log.sh records every change (nothing blocked); review-changes.sh summarises it into the recap;
# "#ok push" (enforce-prompt.sh) unlocks stop-gate's wrap-up item and ship-session's hold.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); export HOME=$T STATE_DIR=$T/.claude/state VAULT=$T/vault
mkdir -p "$STATE_DIR" "$VAULT/_recaps"; pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
D=/storage/emulated/0/Documents; L="$STATE_DIR/changes-S1.log"
R(){ local n0 n1 rc; n0=$(cat "$L" 2>/dev/null | wc -l); bash "$S/change-log.sh" >/dev/null 2>&1; rc=$?
     n1=$(cat "$L" 2>/dev/null | wc -l); [ "$n1" -gt "$n0" ] && echo "$rc $(tail -1 "$L" | cut -f2,3 | tr '\t' ' ')" || echo "$rc -"; }
W(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Write",tool_input:{file_path:$f}}' | R; }
E(){ jq -n --arg f "$1" '{session_id:"S1",tool_name:"Edit",tool_input:{file_path:$f}}' | R; }
B(){ jq -n --arg c "$1" --arg d "$T" '{session_id:"S1",tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' | R; }

ok "$(W "$D/NovAExorpus/clean_md/new-file.md")" "0 NEW vault" "new vault file"
ok "$(E "$D/NovAExorpus/PENDING.md")" "0 EDIT vault" "vault edit"
ok "$(B "mv a '$D/NovAExorpus/tools/b'")" "0 CHANGE vault" "mv into vault"
ok "$(B "mkdir -p '$D/Merovingian's_keep/x'")" "0 CHANGE keep" "mkdir in keep"
ok "$(B "rm -rf $D/WebView")" "0 CHANGE DOCUMENTS" "rm elsewhere in Documents flagged"
ok "$(W "$D/NovAExorpus/../Zip/x.md")" "0 NEW DOCUMENTS" "traversal flagged"
ok "$(W "$D/NovAExorpus-nested-mirror/x")" "0 NEW DOCUMENTS" "lookalike dir flagged"
ok "$(B "cp $D/NovAExorpus/a $D/Zip/b")" "0 CHANGE DOCUMENTS" "mixed paths flagged"
ok "$(B "python3 move.py $D/NovAExorpus")" "0 SCRIPT vault" "script on vault"
ok "$(B "sed -i 's/a/b/' $D/NovAExorpus/PENDING.md")" "0 EDIT vault" "sed -i is an edit"
git -C "$T" init -q repo; ok "$(W "$T/repo/src/x.py")" "0 NEW repo:repo" "new file in a git repo"
ok "$(W "$T/notes.txt")" "0 NEW home" "new file in home"
ok "$(B "ls $D/Zip 2>&1")" "0 -" "read not logged"
ok "$(B "cat $D/Zip/a > /dev/null")" "0 -" "read to /dev/null not logged"

# review: summary written into the recap, outside-the-vault lines listed first
printf '# Session S1\n\n## Files written\n' > "$VAULT/_recaps/2026-10-08-S1.md"
out=$(bash "$S/review-changes.sh" S1)
ok "$(grep -c 'Outside the vault and the keep' <<<"$out")" 1 "review lists outside-the-vault section"
ok "$(grep -c '^## Change review' "$VAULT/_recaps/2026-10-08-S1.md")" 1 "review written into recap"
bash "$S/review-changes.sh" S1 >/dev/null
ok "$(grep -c '^## Change review' "$VAULT/_recaps/2026-10-08-S1.md")" 1 "re-running replaces, not duplicates"

# ship-session holds until "#ok push"
ok "$(bash "$S/ship-session.sh" --dry-run S1 2>/dev/null | grep -c 'held: change review not approved')" 1 "ship held before approval"
jq -n '{session_id:"S1",prompt:"/ok push",cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null 2>&1
ok "$([ -f "$STATE_DIR/pushok-S1" ] && echo yes)" yes "/ok push records approval"
ok "$(bash "$S/ship-session.sh" --dry-run S1 2>/dev/null | grep -c 'held: change review')" 0 "ship proceeds after approval"
echo "== $pass passed, $fail failed"; rm -rf "$T"; [ "$fail" = 0 ]
