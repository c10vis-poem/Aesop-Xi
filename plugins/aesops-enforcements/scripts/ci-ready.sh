#!/usr/bin/env bash
# ci-ready.sh <owner/repo> <branch>: exit 0 when the repo can ship through the full pipeline:
# at least one GitHub Actions workflow AND <branch> requires status checks (branch protection or a
# ruleset). Otherwise print what is missing and exit 1. Used by stop-gate.sh (wrap-up) and
# ship-session.sh (no auto-merge without required checks: it would merge with no CI at all).
# Exit 3: a private repo on the free plan (GitHub offers no branch protection or auto-merge there);
# CI is enough, and ship-session waits for green checks and merges itself.
if [ $# -eq 0 ]; then   # hook entry (PreToolUse Bash): obs 0026 preflight on the agent's own `gh pr merge --auto`
  . "$(dirname "$(realpath "$0")")/lib/env.sh"
  in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
  c=$(jq -r '.tool_input.command // ""' <<<"$in" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")
  grep -qE '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge[[:space:]][^;&|]*--auto|(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+--auto' <<<"$c" || exit 0
  command -v gh >/dev/null 2>&1 || { degrade ci-ready "ci-ready: no gh here, auto-merge preflight skipped"; exit 0; }
  [ -d "$cwd" ] && cd "$cwd"
  slug=$(grep -oE '(-R|--repo)[[:space:]=]+[^[:space:];&|]+' <<<"$c" | head -1 | awk '{print $NF}' | sed 's/^--repo=//')
  [ -n "$slug" ] || slug=$(ghq repo view --json nameWithOwner -q .nameWithOwner)
  [ -n "$slug" ] && ghq api "repos/$slug" --jq .full_name >/dev/null || { degrade ci-ready "ci-ready: cannot reach GitHub for ${slug:-this repo}, auto-merge preflight skipped"; exit 0; }
  n=$(sed -nE 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([0-9]+|https:[^[:space:]]+).*/\1/p' <<<"$c" | head -1)
  br=$(ghq pr view $n -R "$slug" --json baseRefName -q .baseRefName); br=${br:-main}
  why=$(bash "$0" "$slug" "$br"); rc=$?
  [ $rc -eq 1 ] || exit 0
  echo "$(date +%T) BLOCK ci-ready: $why" >> "$ST/enforce-$sid.log"
  echo "BLOCKED (ci-ready): $why. Auto-merge on a branch with no required checks means merge now (obs 0026). Wait for green CI and merge by hand, or ask the operator to set protection." >&2
  exit 2
fi
slug=$1; br=${2:-main}
miss=()
wf=$(gh api "repos/$slug/actions/workflows" --jq '.total_count' 2>/dev/null) || wf=0
[ "${wf:-0}" -gt 0 ] || miss+=("no CI workflow")
runs=$(gh api "repos/$slug/actions/runs?per_page=1" --jq .total_count 2>/dev/null) || runs=0
[ "${wf:-0}" -eq 0 ] || [ "${runs:-0}" -gt 0 ] || miss+=("no workflow has run on this fork yet")
req=$(gh api "repos/$slug/branches/$br/protection/required_status_checks" --jq '(.contexts // []) + [.checks[]?.context] | length' 2>/dev/null) || req=0
[ "${req:-0}" -gt 0 ] || req=$(gh api "repos/$slug/rules/branches/$br" --jq '[.[] | select(.type=="required_status_checks")] | length' 2>/dev/null) || req=0
if [ "${req:-0}" -eq 0 ] && [ "$(gh api "repos/$slug" --jq .private 2>/dev/null)" = true ] \
   && gh api "repos/$slug/branches/$br/protection" 2>&1 | grep -q 'Upgrade to GitHub Pro'; then
  [ ${#miss[@]} -eq 0 ] && { echo "$slug: private repo on the free plan: CI only, ship-session merges after green checks"; exit 3; }
  echo "$slug: ${miss[0]}"; exit 1          # only the workflow can be missing here
fi
[ "${req:-0}" -gt 0 ] || miss+=("no required status checks on $br")
# every required check name must be produced by a workflow job (id or name), else the PR blocks forever
if [ "${req:-0}" -gt 0 ] && [ "${wf:-0}" -gt 0 ]; then
  names=$({ gh api "repos/$slug/branches/$br/protection/required_status_checks" --jq '(.contexts // []) + [.checks[]?.context] | .[]' 2>/dev/null
            gh api "repos/$slug/rules/branches/$br" --jq '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null; } | sort -u)
  jobs=$(for p in $(gh api "repos/$slug/actions/workflows" --jq '.workflows[].path' 2>/dev/null); do
    gh api "repos/$slug/contents/$p?ref=$br" -H 'Accept: application/vnd.github.raw' 2>/dev/null | awk '
      /^jobs:/ {j=1; next}  j && /^[^ #]/ {j=0}
      j && /^  [A-Za-z0-9_-]+:/ {id=$1; sub(/:$/,"",id); print id}
      j && /^    name:/ {n=$0; sub(/^    name:[ ]*/,"",n); gsub(/^["\047]|["\047][ ]*$/,"",n); print n}'
  done)
  while IFS= read -r n; do
    [ -n "$n" ] || continue; short=${n##* / }; hit=0
    while IFS= read -r j; do
      [ -n "$j" ] || continue
      case "$j" in *'${{'*) pre=${j%%'${{'*}; case "$n" in "$pre"*) hit=1;; esac;; *) [ "$j" = "$n" ] || [ "$j" = "$short" ] && hit=1;; esac
    done <<<"$jobs"
    [ $hit -eq 1 ] || miss+=("required check '$n' matches no workflow job (job id or name:)")
  done <<<"$names"
fi
[ ${#miss[@]} -eq 0 ] && exit 0
echo "$slug: $(IFS=';'; echo "${miss[*]}")"; exit 1
