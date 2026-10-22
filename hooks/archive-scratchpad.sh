#!/data/data/com.termux/files/usr/bin/bash
# SessionEnd/PreCompact: copy this session's scratchpad to durable storage.
# Scratchpads live under $TMPDIR and are deleted after the session (obs 0008).
sid=$(jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
src=$(ls -d "${TMPDIR:-/data/data/com.termux/files/usr/tmp}"/claude-*/*/"$sid"/scratchpad 2>/dev/null | head -1)
[ -n "$src" ] && [ -n "$(ls -A "$src" 2>/dev/null)" ] || exit 0
dst="$HOME/.claude/scratchpad-archive/$(date +%F)_$sid"
mkdir -p "$dst"
# skip bulk clones/deps; keep notes, drafts, scripts
rsync -a --exclude '.git/' --exclude 'node_modules/' --exclude '/src/' "$src"/ "$dst"/ 2>/dev/null \
  || cp -r "$src"/. "$dst"/
