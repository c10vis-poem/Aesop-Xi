#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (all tools): nothing runs until this session has Read RESUME.md.
# RESUME = the one at the current repo's root, else the vault's.
in=$(cat); sid=$(jq -r .session_id <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
ok="$HOME/.claude/state/resume-$sid.ok"; [ -f "$ok" ] && exit 0
top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="$HOME/storage/shared/Documents/NovAExorpus/RESUME.md"
[ -f "$r" ] || exit 0
r=$(realpath "$r")
if [ "$(jq -r .tool_name <<<"$in")" = Read ]; then
  f=$(jq -r '.tool_input.file_path // ""' <<<"$in")
  [ "$(realpath "$f" 2>/dev/null)" = "$r" ] && { mkdir -p "${ok%/*}"; sha256sum "$r" | cut -d" " -f1 > "$ok"; cp "$r" "${ok%.ok}.snap.md"; exit 0; }  # hash + snapshot of RESUME as read at session start (mtime is unreliable on shared storage)
fi
echo "BLOCKED (resume-gate): Read $r first, then follow it." >&2; exit 2
