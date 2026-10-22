#!/data/data/com.termux/files/usr/bin/bash
S=$(cd "$(dirname "$0")/.." && pwd); T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir "$T/bin" "$T/fx"
pass=0; fail=0
ok(){ if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "PASS $3"; else fail=$((fail+1)); echo "FAIL $3 (got $1 want $2)"; fi; }
# stub gh: api <path> [--jq F] [-H ...]; serves $T/fx/<path with / and ? as _>; applies --jq with jq
cat > "$T/bin/gh" <<'STUB'
#!/data/data/com.termux/files/usr/bin/bash
p=$2; shift 2; q=
while [ $# -gt 0 ]; do case $1 in --jq) q=$2; shift;; esac; shift; done
f="$FX/$(tr '/?' '__' <<<"$p")"; [ -f "$f" ] || exit 1
if [ -n "$q" ]; then jq -r "$q" "$f"; else cat "$f"; fi
STUB
chmod +x "$T/bin/gh"; export PATH="$T/bin:$PATH" FX="$T/fx"
fx(){ printf '%s' "$2" > "$FX/$1"; }
fx repos_o_r_actions_workflows '{"total_count":1,"workflows":[{"path":".github/workflows/ci.yml"}]}'
fx repos_o_r_rules_branches_main '[]'
fx repos_o_r '{"private":false}'
printf 'name: CI\non: pull_request\njobs:\n  test:\n    runs-on: x\n  build:\n    name: Build app\n    runs-on: x\n' > "$FX/repos_o_r_contents_.github_workflows_ci.yml_ref=main"
R(){ fx repos_o_r_branches_main_protection_required_status_checks "{\"contexts\":[$1],\"checks\":[]}"; bash "$S/ci-ready.sh" o/r main 2>&1; echo "rc=$?"; }
out=$(R '"test"'); ok "$out" "rc=0" "required name = job id passes"
out=$(R '"Build app"'); ok "$out" "rc=0" "required name = job name: passes"
out=$(R '"check"'); ok "$(grep -c "required check 'check' matches no workflow job" <<<"$out")$(grep -c 'rc=1' <<<"$out")" 11 "mismatched name fails with message"
out=$(R '"test","check"'); ok "$(grep -c "'check' matches no" <<<"$out")$(grep -c "'test' matches" <<<"$out")" 10 "only the bad name is reported"
echo "== $pass passed, $fail failed"; [ "$fail" -eq 0 ]
