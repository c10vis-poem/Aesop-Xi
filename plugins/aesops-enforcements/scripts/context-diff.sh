#!/usr/bin/env bash
# SessionStart: show what changed in CLAUDE.md and MEMORY.md since the last session.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
snap="$ST/snapshots"; mkdir -p "$snap"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/projects/$(sed 's#[/.]#-#g' <<<"$HOME")/memory/MEMORY.md"; do
  [ -f "$f" ] || { degrade "ctx-${f##*/}" "context-diff: $f not on this device"; continue; }
  s="$snap/$(basename "$f")"
  if [ -f "$s" ] && ! cmp -s "$s" "$f"; then
    echo "## Changed since last session: $f"
    diff "$s" "$f" | grep -E '^[<>]' | sed 's/^</- removed:/; s/^>/+ added:/' | head -40
  fi
  cp "$f" "$s"
done
exit 0
