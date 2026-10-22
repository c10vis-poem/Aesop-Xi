#!/data/data/com.termux/files/usr/bin/bash
# SessionStart: show what changed in CLAUDE.md and MEMORY.md since the last session.
snap="$HOME/.claude/state/snapshots"; mkdir -p "$snap"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/projects/-data-data-com-termux-files-home/memory/MEMORY.md"; do
  s="$snap/$(basename "$f")"
  if [ -f "$s" ] && ! cmp -s "$s" "$f"; then
    echo "## Changed since last session: $f"
    diff "$s" "$f" | grep -E '^[<>]' | sed 's/^</- removed:/; s/^>/+ added:/' | head -40
  fi
  cp "$f" "$s"
done
exit 0
