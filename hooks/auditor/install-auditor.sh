#!/data/data/com.termux/files/usr/bin/bash
# Optional/experimental: add (or --uninstall) the per-task Stop auditor in ~/.claude/settings.json.
# Backs up first, merges with jq, fails closed (settings untouched on any error). Idempotent.
set -euo pipefail
S="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
SNIP="$(dirname "$(realpath "$0")")/settings-snippet.json"
MARK='AUDITOR.'
[ -f "$S" ] || { echo "no $S" >&2; exit 1; }
jq -e . "$S" >/dev/null || { echo "invalid JSON: $S" >&2; exit 1; }
jq -e '.hooks[0].type=="agent" and (.hooks[0].prompt|startswith("AUDITOR."))' "$SNIP" >/dev/null || { echo "bad snippet" >&2; exit 1; }
if [ "${1:-}" = --uninstall ]; then
  f='.hooks.Stop |= (if . == null then . else map(select(any(.hooks[]?; (.prompt? // "") | startswith($m)) | not)) end)'
else
  f='if any(.hooks.Stop[]?; any(.hooks[]?; (.prompt? // "") | startswith($m))) then . else .hooks.Stop = ((.hooks.Stop // []) + [$s[0]]) end'
fi
out=$(jq --arg m "$MARK" --slurpfile s "$SNIP" "$f" "$S") || { echo "jq failed; $S untouched" >&2; exit 1; }
if [ "$out" != "$(jq . "$S")" ]; then
  cp -p "$S" "$S.bak-$(date +%F)"
  printf '%s\n' "$out" > "$S.tmp" && mv "$S.tmp" "$S"
fi
jq '.hooks.Stop' "$S"
