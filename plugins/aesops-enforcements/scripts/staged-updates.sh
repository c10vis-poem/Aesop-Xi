#!/usr/bin/env bash
# SessionStart (Termux only): staged skill updates waiting in the vault skill-updates/PENDING.md, plus a
# one-line inventory of the Termux skills and plugins this session should attach. No network. Never blocks.
# `staged-updates.sh names` prints the pending entries one per line (used by stop-gate.sh).
# Manifest entry = a "## <name> -> <path> ..." heading; it stops counting once the heading carries "[installed".
. "$(dirname "$(realpath "$0")")/lib/env.sh"
[ -n "$TERMUX_VERSION" ] || [[ ${PREFIX:-} == *com.termux* ]] || { [ "$1" = names ] || degrade staged "staged-updates: not Termux, no staged skill updates to check"; exit 0; }
m="${VAULT:-/nonexistent}/skill-updates/PENDING.md"
[ -f "$m" ] || { [ "$1" = names ] || degrade staged "staged-updates: no manifest at $m"; }
names=$( [ -f "$m" ] && sed -n '/^## /{/\[installed/!{s/^## *//; s/ *->.*//; p}}' "$m")
[ "$1" = names ] && { [ -n "$names" ] && echo "$names"; exit 0; }
if [ -n "$names" ]; then
  echo "STAGED SKILL UPDATES PENDING ($(wc -l <<<"$names")): $(paste -sd ';' <<<"$names" | sed 's/;/; /g')"
  echo "  Manifest: $m. Tell the operator; install, then mark the heading [installed <date>], or the operator types #staged-defer (Stop gate asks until one happens)."
fi
sk=$(grep -liE '^description:.*(termux|android)' "$HOME"/.claude/skills/*/SKILL.md 2>/dev/null | sed 's|/SKILL.md$||; s|.*/||' | paste -sd ',')
pl=$(jq -r '.plugins | keys[] | sub("@.*"; "")' "$HOME/.claude/plugins/installed_plugins.json" 2>/dev/null | sort -u | paste -sd ',')
echo "TERMUX ASSETS: skills ${sk:-none}; plugins ${pl:-none}"
exit 0
