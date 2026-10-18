#!/data/data/com.termux/files/usr/bin/bash
# Tests H9 (carryover.sh + its stop-gate check + "#defer N why:" in enforce-prompt) in a fake HOME.
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T; st=$T/.claude/state; V=$T/storage/shared/Documents/NovAExorpus
mkdir -p "$st" "$V"; echo "- Finish PR triage" > "$V/PENDING.md"; echo old > "$V/RESUME.md"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1, want $2)"; fi; }
snap(){ printf '# RESUME\n\n## START HERE\n1. %s\n2. Grill session with the operator\n\n## Other\n' "${2:-Finish PR triage}" > "$st/resume-$1.snap.md"
        touch "$st/resume-$1.ok" "$st/wrapup-$1" "$st/plan-$1.txt"; }
mark(){ printf '%s\t%s\t00:00\n' "$2" "$3" >> "$st/confirm-$1.tsv"; }
G(){ jq -n --arg s "$1" '{session_id:$s,cwd:"/",transcript_path:"/none"}' | bash "$S/stop-gate.sh" | jq -r '.reason // ""'; }
P(){ jq -n --arg s "$1" --arg p "$2" '{session_id:$s,prompt:$p,cwd:"/"}' | bash "$S/enforce-prompt.sh" >/dev/null; }
h9(){ grep -c "item $2 was already carried over" <<<"$1"; }

snap Z; ok "$(bash "$S/carryover.sh" list "$st/resume-Z.snap.md" Z | grep -c .)" 0 "nothing carried before any session"; rm "$st/wrapup-Z"

# Session A: item 1 deferred for the first time, item 2 done
snap A; mark A 1 deferred; mark A 2 confirmed-done
out=$(G A); ok "$(h9 "$out" 1)" 0 "first deferral is allowed"
ok "$(cut -f1,2 "$st/carryover/A.tsv")" "$(printf 'finishprtriage\tdeferred')" "ledger holds only the unfinished item"

# Session B: item 1 again (title now in bold), deferred with no reason -> blocked; item 2 was done in A
snap B "**Finish PR triage**"; mark B 1 deferred; mark B 2 deferred
out=$(G B); ok "$(h9 "$out" 1)" 1 "second deferral without a reason is blocked"
ok "$(grep -c 'carried over 1 time' <<<"$out")" 1 "message gives the carry-over count"
ok "$(h9 "$out" 2)" 0 "item finished last session is not a carry-over"
ok "$(grep -c "needs the operator's /ok" <<<"$out")" 1 "message counts as operator-only (stop gate can yield)"

# Operator gives a reason -> allowed
P B "/defer 1 why: waiting on Qualcomm's HMX fix"
ok "$(cut -f1,2 "$st/defer-why-B.tsv")" "$(printf "1\twaiting on Qualcomm's HMX fix")" "enforce-prompt records the reason"
ok "$(grep "^1	" "$st/confirm-B.tsv" | tail -1 | cut -f2)" deferred "the /defer still marks it deferred"
out=$(G B); ok "$(h9 "$out" 1)" 0 "deferral with a reason passes"
P B "#defer 2" ; ok "$(grep -c "^2	" "$st/defer-why-B.tsv")" 0 "plain #defer records no reason"

# Session C: finished this time -> no block, and it drops out of the ledger
snap C; mark C 1 confirmed-done; mark C 2 confirmed-done
out=$(G C); ok "$(h9 "$out" 1)" 0 "finished item passes"
ok "$(grep -c finishprtriage "$st/carryover/C.tsv")" 0 "finished item not recorded"

# Session D: bare #ok turns a blocked item into deferred -> still needs a reason (now 2 prior sessions)
snap D; printf '1\tblocked\tx\n' > "$st/resume-items-D.tsv"; P D "#ok"
out=$(G D); ok "$(grep -c 'item 1 was already carried over 2 time' <<<"$out")" 1 "bare #ok on a blocked carry-over is blocked too"

# CLI
ok "$(bash "$S/carryover.sh" list "$st/resume-D.snap.md" D | cut -f1,2)" "$(printf '1\t2\n2\t1')" "list prints carried items with counts (item 2: deferred in B)"

# Rewritten every Stop run: a later mark replaces the earlier status
snap E; mark E 1 deferred; G E >/dev/null; mark E 1 confirmed-done; G E >/dev/null
ok "$(grep -c finishprtriage "$st/carryover/E.tsv")" 0 "ledger follows the operator's latest mark"

echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
