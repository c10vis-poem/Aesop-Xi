#!/data/data/com.termux/files/usr/bin/bash
# ci-ready.sh <owner/repo> <branch>: exit 0 when the repo can ship through the full pipeline:
# at least one GitHub Actions workflow AND <branch> requires status checks (branch protection or a
# ruleset). Otherwise print what is missing and exit 1. Used by stop-gate.sh (wrap-up) and
# ship-session.sh (no auto-merge without required checks: it would merge with no CI at all).
slug=${1:?usage: ci-ready.sh <owner/repo> <branch>}; br=${2:-main}
miss=()
wf=$(gh api "repos/$slug/actions/workflows" --jq '.total_count' 2>/dev/null) || wf=0
[ "${wf:-0}" -gt 0 ] || miss+=("no CI workflow")
req=$(gh api "repos/$slug/branches/$br/protection/required_status_checks" --jq '(.contexts // []) + [.checks[]?.context] | length' 2>/dev/null) || req=0
[ "${req:-0}" -gt 0 ] || req=$(gh api "repos/$slug/rules/branches/$br" --jq '[.[] | select(.type=="required_status_checks")] | length' 2>/dev/null) || req=0
[ "${req:-0}" -gt 0 ] || miss+=("no required status checks on $br")
[ ${#miss[@]} -eq 0 ] && exit 0
echo "$slug: $(IFS=';'; echo "${miss[*]}")"; exit 1
