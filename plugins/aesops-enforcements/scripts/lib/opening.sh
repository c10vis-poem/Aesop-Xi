# Sourced by stop-gate.sh and direction-gate.sh. One source for the opening steps (observation 0090):
# what the stop-gate demands as an opening step, the direction-gate lets through. Both read only this file,
# so the two cannot disagree. Needs $VAULT (lib/env.sh).

# The scan command, exactly as the stop-gate tells the agent to run it.
opening_scan_cmd() {
  local s; s=$(ls "$HOME"/.claude/skills/task-observer/scripts/session-start-scan.sh 2>/dev/null | head -1)
  printf 'bash %s "%s"' "${s:-~/.claude/skills/task-observer/scripts/session-start-scan.sh}" "${VAULT:-<vault>}"
}

# The opening, in order, as the stop-gate states it. $1 = load (task-observer not loaded yet) or scan.
opening_text() {
  local last="run the task-observer session-start scan: $(opening_scan_cmd)"
  [ "$1" = load ] && last="load the task-observer skill and run its Session Start Protocol; its scan is: $(opening_scan_cmd)"
  printf "Opening, in this order (no okay needed): read the launch folder's AGENTS.md, MEMORY.md, RESUME.md, the handoff it points to and PENDING.md, and the files they point to; then last, %s (it appends to skill-observations/checkpoints.log; a resumed session gets a new id and runs it again)" "$last"
}

# Paths that belong to the task-observer opening: its workspace, its skill, the scan output, and the vault root
# itself (the scan's argument).
opening_path() {
  local v
  for v in "${VAULT:-}" "$HOME/storage/shared/Documents/NovAExorpus" /storage/emulated/0/Documents/NovAExorpus; do
    [ -n "$v" ] || continue; v=${v%/}
    case $1 in "$v"|"$v/"|"$v"/skill-observations|"$v"/skill-observations/*) return 0 ;; esac
  done
  case $1 in */skill-observations|*/skill-observations/*|"$HOME"/.claude/skills/task-observer/*|"$HOME"/.claude/projects/*/tool-results/*) return 0 ;; esac
  return 1
}

# Is this Bash command an opening step? The scan or observation helper alone, or a command whose every path is
# an opening path (ls, cat, head of the workspace). Redirects to /dev/null and stderr are not paths.
opening_bash() {
  local c=$1 w ok= bad=
  # the scan's output is read whole (task-observer protocol: "never through tail, head or grep"): no pipe, no chain
  case $c in *session-start-scan*) grep -qE '[|;&]' <<<"$c" && return 1 ;; esac
  # quoted or bare, exactly as the protocol writes it (field test 8f020c32: the quoted form was refused)
  grep -qE '^bash [^;&|]*(session-start-scan|new-observation)\.sh"? [^;&|]*$' <<<"$c" && return 0
  for w in $(grep -oE '(~|/)[^[:space:]"'"'"';|&<>()]+' <<<"$c"); do w=${w/#\~/$HOME}
    case $w in /dev/null|/dev/std*) continue ;; esac
    if opening_path "$w"; then ok=1; else bad=1; fi
  done
  [ -n "$ok" ] && [ -z "$bad" ]
}

# The opening reads the stop-gate checks: the launch folder's AGENTS, MEMORY, RESUME, HANDOFF and PENDING (those that
# exist) and the handoff RESUME.md points to ("Handoff: NvAEx-Recaps `handoff/<date>/handoff.md`"). Prints each one not
# yet read whole with Read this session. $1 = repo top, $2 = the opening ledger (direction-gate writes it).
opening_reads_missing() {
  local top=$1 led=$2 f h
  [ -n "$top" ] || return 0
  for f in AGENTS.md MEMORY.md RESUME.md HANDOFF.md PENDING.md; do
    [ -f "$top/$f" ] || continue
    grep -qF -- "	$(realpath "$top/$f")	" "$led" 2>/dev/null || echo "$top/$f"
  done
  h=$(grep -oE 'NvAEx-Recaps[^`]*`handoff/[^`]+`' "$top/RESUME.md" 2>/dev/null | head -1 | sed -E 's/.*`(handoff\/[^`]+)`/\1/')
  if [ -n "$h" ]; then h=${REPOS_DIR:-$HOME/repos}/NvAEx-Recaps/$h
    [ -f "$h" ] && { grep -qF -- "	$(realpath "$h")	" "$led" 2>/dev/null || echo "$h"; }
  fi
}
