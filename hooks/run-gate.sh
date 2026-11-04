#!/usr/bin/env bash
# Single launcher for every rule in RULES.md. Adds, around the existing hook scripts:
#   1. kill switch:  ~/.claude/state/off/<name> present -> exit 0 (operator: `gate off <name>`)
#   2. override verb: the operator's latest typed prompt contains the hook's #skip-<tag> -> exit 0
#      (subagent hand-backs never count)
#   3. no bare yes/no: every exit-2 block is suffixed with the override verb and the revoke command
#   4. watchdog: timeout/crash -> logged to ~/.claude/state/hooks.log, call allowed (fail-open)
name="${1%.sh}"; shift
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
st="$HOME/.claude/state"; mkdir -p "$st/off" 2>/dev/null
[ -e "$st/off/$name" ] && exit 0
[ -f "$here/$name.sh" ] || exit 0
in=$(cat)
case $name in
  resume-gate) tag=resume;; checkin-gate) tag=checkin;; secret-guard) tag=secret;; branch-current-gate) tag=branch;;
  enforce-gate) tag=enforce;; stop-gate) tag=stop;; absence-gate) tag=absence;; ship-session) tag=ship;; *) tag="";;
esac
tp=$(jq -r '.transcript_path // empty' <<<"$in" 2>/dev/null); tp=${tp/#\~/$HOME}
if [ -n "$tag" ] && [ -f "$tp" ]; then
  last=$(jq -r 'select(.type=="user" and (.isMeta|not) and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null \
        | grep -vE '<agent-message|<task-notification>|^Another Claude session sent a message' | tail -1)
  grep -q -- "#skip-$tag" <<<"$last" && { echo "$(date '+%F %T') $name SKIPPED by operator #skip-$tag" >> "$st/hooks.log"; exit 0; }
fi
tmo=${AESOP_HOOK_TIMEOUT:-8}; case $name in ship-session|archive-scratchpad) tmo=${AESOP_HOOK_TIMEOUT:-60};; esac
err=$(mktemp)
if command -v timeout >/dev/null; then timeout -k 2 "$tmo" bash "$here/$name.sh" "$@" <<<"$in" 2>"$err"; rc=$?
else bash "$here/$name.sh" "$@" <<<"$in" 2>"$err"; rc=$?; fi
case $rc in
  0) cat "$err" >&2; rm -f "$err"; exit 0;;
  2) cat "$err" >&2; [ -n "$tag" ] && echo "OVERRIDE this call: put #skip-$tag in your prompt. REVOKE this rule: gate off $name  (gate on $name to restore)." >&2; rm -f "$err"; exit 2;;
  124|137) echo "$(date '+%F %T') $name TIMEOUT ${tmo}s (allowed)" >> "$st/hooks.log"; rm -f "$err"; exit 0;;
  *) echo "$(date '+%F %T') $name ERROR exit $rc (allowed): $(head -c 300 "$err")" >> "$st/hooks.log"; rm -f "$err"; exit 0;;
esac
