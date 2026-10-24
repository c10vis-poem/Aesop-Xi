#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (all tools): nothing runs until this session has Read RESUME.md
# (the one at the current repo's root, else the vault's). Then, on every later call:
#   - opening-sequence ledger: Reads of AGENTS.md, PENDING.md, MEMORY.md, WRAP-UP.md, RESUME.md are
#     recorded in state/opening-<sid>.tsv (the Stop gate reports which opening steps are still missing);
#   - drift check (obs 0044): if RESUME.md no longer matches the hash taken when it was read, and this
#     session did not write it (change log) and is not in wrap-up, the call is blocked until it is Read
#     again (the re-read refreshes the hash and snapshot; the old snapshot is kept as .snap.prev.md).
#   - date check: the newest YYYY-MM-DD in RESUME's first 40 lines is recorded (state/resume-date-<sid>);
#     missing, future, or older than AESOP_RESUME_MAX_AGE_DAYS (14) is reported as context, once.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
cwd=$(jq -r '.cwd // ""' <<<"$in"); tool=$(jq -r '.tool_name // ""' <<<"$in")
f=$(jq -r '.tool_input.file_path // ""' <<<"$in"); f=${f/#\~/$HOME}
top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="${VAULT:-/nonexistent}/RESUME.md"
[ -f "$r" ] || exit 0
r=$(realpath "$r"); ok="$ST/resume-$sid.ok"; snap="${ok%.ok}.snap.md"; open="$ST/opening-$sid.tsv"
rf=; [ "$tool" = Read ] && [ -n "$f" ] && rf=$(realpath "$f" 2>/dev/null)

record_open() {   # opening ledger: which of the session-start documents were Read, and when
  local b=${rf##*/}
  case $b in AGENTS.md|PENDING.md|MEMORY.md|WRAP-UP.md|RESUME.md|CLAUDE.md) printf 'read:%s\t%s\t%s\n' "$b" "$rf" "$(date +%T)" >> "$open" ;; esac
}
snapshot() {      # hash + snapshot of RESUME as read (mtime is unreliable on shared storage)
  [ -f "$snap" ] && cp "$snap" "${ok%.ok}.snap.prev.md"
  sha256sum "$r" | cut -d" " -f1 > "$ok"; cp "$r" "$snap"
  resume_date "$r" > "$ST/resume-date-$sid"
}
date_notice() {   # context line about RESUME's own date, once per session
  local d=$1 max=${AESOP_RESUME_MAX_AGE_DAYS:-14} age
  if [ -z "$d" ]; then echo "RESUME.md ($r) carries no date in its first 40 lines; treat its START HERE list as unverified and say so to the operator."; return; fi
  age=$(( ( $(date +%s) - $(date -d "$d" +%s 2>/dev/null || date +%s) ) / 86400 ))
  [ "$age" -lt 0 ] && { echo "RESUME.md is dated $d, in the future; the file may be a conflict copy. Tell the operator before acting on it."; return; }
  [ "$age" -gt "$max" ] && echo "RESUME.md is dated $d ($age days ago, limit $max). Its START HERE list may be stale: confirm each item with the operator before working on it."
}

if [ -f "$ok" ]; then
  [ -n "$rf" ] && record_open
  base=$(head -1 "$ok"); cur=$(sha256sum "$r" | cut -d" " -f1)
  if [ "$cur" != "$base" ] && [ ! -f "$ST/wrapup-$sid" ] \
     && ! grep -qF -- "$r" "$ST/changes-$sid.log" 2>/dev/null && ! grep -qF -- "$r" "$ST/resume-written-$sid" 2>/dev/null; then
    if [ "$rf" = "$r" ]; then snapshot; echo "$(date +%T) RESUME re-read after external change" >> "$ST/enforce-$sid.log"; exit 0; fi
    echo "$(date +%T) BLOCK resume-gate: RESUME changed on disk" >> "$ST/enforce-$sid.log"
    echo "BLOCKED (resume-gate): $r changed since this session read it (another session or device rewrote it). Read it again, then follow the new START HERE list; items you already proposed stay recorded." >&2; exit 2
  fi
  exit 0
fi
if [ "$rf" = "$r" ]; then
  snapshot; record_open
  n=$(date_notice "$(cat "$ST/resume-date-$sid")")
  [ -n "$n" ] && jq -n --arg c "$n" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",additionalContext:$c}}'
  exit 0
fi
echo "$(date +%T) BLOCK resume-gate: $tool before RESUME" >> "$ST/enforce-$sid.log"
echo "BLOCKED (resume-gate): Read $r first, then follow it." >&2; exit 2
