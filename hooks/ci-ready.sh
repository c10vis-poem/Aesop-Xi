#!/data/data/com.termux/files/usr/bin/bash
# ci-ready.sh <owner/repo> <branch>: exit 0 when the repo can ship through the full pipeline:
# at least one GitHub Actions workflow AND <branch> requires status checks (branch protection or a
# ruleset). Otherwise print what is missing and exit 1. Used by stop-gate.sh (wrap-up) and
# ship-session.sh (no auto-merge without required checks: it would merge with no CI at all).
# Exit 3: a private repo on the free plan (GitHub offers no branch protection or auto-merge there);
# CI is enough, and ship-session waits for green checks and merges itself.
slug=${1:?usage: ci-ready.sh <owner/repo> <branch>}; br=${2:-main}
miss=()
wf=$(gh api "repos/$slug/actions/workflows" --jq '.total_count' 2>/dev/null) || wf=0
[ "${wf:-0}" -gt 0 ] || miss+=("no CI workflow")
req=$(gh api "repos/$slug/branches/$br/protection/required_status_checks" --jq '(.contexts // []) + [.checks[]?.context] | length' 2>/dev/null) || req=0
[ "${req:-0}" -gt 0 ] || req=$(gh api "repos/$slug/rules/branches/$br" --jq '[.[] | select(.type=="required_status_checks")] | length' 2>/dev/null) || req=0
if [ "${req:-0}" -eq 0 ] && [ "$(gh api "repos/$slug" --jq .private 2>/dev/null)" = true ] \
   && gh api "repos/$slug/branches/$br/protection" 2>&1 | grep -q 'Upgrade to GitHub Pro'; then
  [ ${#miss[@]} -eq 0 ] && { echo "$slug: private repo on the free plan: CI only, ship-session merges after green checks"; exit 3; }
  echo "$slug: ${miss[0]}"; exit 1          # only the workflow can be missing here
fi
[ "${req:-0}" -gt 0 ] || miss+=("no required status checks on $br")
[ ${#miss[@]} -eq 0 ] && exit 0
echo "$slug: $(IFS=';'; echo "${miss[*]}")"; exit 1
