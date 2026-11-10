#!/usr/bin/env bash
# Runs every ported hook test, then the end-to-end checks in gates.test.sh. Exit 0 only if all pass.
# Set SELFTEST_SHOW=1 for every PASS line.
here=$(cd "$(dirname "$0")" && pwd); total=0; bad=0; failed=
for t in "$here"/hooks/*.sh "$here"/gates.test.sh; do
  case ${t##*/} in lib.sh) continue ;; esac
  out=$(timeout 280 bash "$t" 2>&1); rc=$?
  p=$(grep -c '^PASS' <<<"$out"); f=$(grep -c '^FAIL' <<<"$out")
  [ -n "${SELFTEST_SHOW:-}" ] && grep -E '^(PASS|FAIL)' <<<"$out"
  grep -E '^FAIL' <<<"$out"
  [ "$p" -gt 0 ] || rc=1   # a test that asserts nothing proves nothing
  grep -q '^SKIP' <<<"$out" && { echo "SKIPPED ${t##*/}: $(grep '^SKIP' <<<"$out")"; rc=1; }
  printf '%-34s %3s passed %3s failed rc=%s\n' "${t##*/}" "$p" "$f" "$rc"
  total=$((total+p)); bad=$((bad+f)); [ "$rc" -eq 0 ] && [ "$f" -eq 0 ] || failed="$failed ${t##*/}"
done
echo "TOTAL $total passed, $bad failed"
[ -z "$failed" ] && { echo "SELFTEST OK"; exit 0; }
echo "SELFTEST FAILED:$failed"; exit 1
