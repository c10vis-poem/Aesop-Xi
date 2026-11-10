#!/usr/bin/env bash
# Rule 1, the operator's words: no actions, no reading, no tool use without explicit permission or direction.
# Replaces resume-gate. UserPromptSubmit decides, PreToolUse enforces.
#   A prompt starting with # (or the word "hashtag", for dictation) is a direction: opens the job.
#   An affirmation (okay, yes, go, override...) opens the job. Any other prompt closes it.
#   One opening covers the whole job, every tool and step, until the next non-opening prompt.
# Closed: only the opening reads (AGENTS, MEMORY, RESUME, HANDOFF, PENDING, MAP, CLAUDE, and paths those
# documents name), the task-observer session start, and asking the operator.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
ev=$(jq -r '.hook_event_name // ""' <<<"$in"); job="$ST/job-$sid"; open="$ST/opening-$sid.tsv"

if [ "$ev" = UserPromptSubmit ]; then
  p=$(jq -r '.prompt // ""' <<<"$in" | sed -E '/^[[:space:]]*$/d' | head -1 | sed -E 's/^[[:space:]]+//' | tr '[:upper:]' '[:lower:]')
  pall=$(jq -r '.prompt // ""' <<<"$in" | tr '[:upper:]' '[:lower:]')   # every line: a direction can sit anywhere in the message
  # the session-started marker other gates key off (was written by resume-gate)
  cwd=$(jq -r '.cwd // ""' <<<"$in"); top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
  r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="${VAULT:-/nonexistent}/RESUME.md"
  [ -f "$ST/resume-$sid.ok" ] || { if [ -f "$r" ]; then sha256sum "$r" | cut -d" " -f1 > "$ST/resume-$sid.ok"; else : > "$ST/resume-$sid.ok"; fi; }
  # Direction: a # word anywhere ("#go ahead" at the end of a message counts), or "hashtag" (dictation).
  # Affirmation: the Rule 2 check-in answers (okay, amend, override, defer) or a plain yes/go, at the start of any line.
  # Rule 4, "unless the operator directs it": a direction (#) that names settings, hooks, gates or the
  # switches lets guard (settings-guard, state-guard) through for this prompt only; the next prompt re-decides.
  rm -f "$ST/direct4-$sid"
  if grep -qE '(^|[[:space:]])#[[:space:]]?[[:alnum:]]|(^|[[:space:]])hashtag([[:space:]]|$)' <<<"$pall" \
     && grep -qE '(settings|hooks?|gates?|switch(es)?|disableallhooks|kill switch)' <<<"$pall"; then
    echo "$(date '+%F %T')" > "$ST/direct4-$sid"; hook_log "Rule 4: operator direction names settings/hooks/rules ($sid)"
  fi
  if grep -qE '(^|[[:space:]])#[[:space:]]?[[:alnum:]]|(^|[[:space:]])hashtag([[:space:]]|$)' <<<"$pall"; then echo direction > "$job"
  elif grep -qE "^[[:space:]]*[0-9.)-]*[[:space:]]*(ok|okay|yes|yep|yup|yeah|go|go ahead|do it|override|amend|defer|approved)([[:space:][:punct:]]|$)" <<<"$pall"; then echo affirmation > "$job"
  # Rule 1: one opening covers the whole job. A comment or question mid-job does not close it
  # (operator 2026-11-09); only a stop word does.
  elif grep -qE "^[[:space:]]*(stop|hold|hold on|wait|halt)([[:space:][:punct:]]|$)" <<<"$pall"; then rm -f "$job"
  fi
  exit 0
fi

tool=$(jq -r '.tool_name // ""' <<<"$in")
f=$(jq -r '.tool_input.file_path // ""' <<<"$in"); f=${f/#\~/$HOME}
rf=; [ -n "$f" ] && rf=$(realpath "$f" 2>/dev/null)
isdoc() { case ${1##*/} in AGENTS.md|MEMORY.md|RESUME.md|HANDOFF.md|handoff.md|PENDING.md|MAP.md|CLAUDE.md) return 0 ;; esac; return 1; }
# the opening ledger the stop gate reports from: recorded whether or not the job is open
[ "$tool" = Read ] && [ -n "$rf" ] && isdoc "$rf" && printf 'read:%s\t%s\t%s\n' "${rf##*/}" "$rf" "$(date +%T)" >> "$open"
[ -f "$job" ] && exit 0

root_of() {  # path -> "<repo name><TAB><path inside it>" for repos and the vault (both spellings of shared storage)
  local p=$1 R V1 V2
  R=$(realpath -m "${REPOS_DIR:-$HOME/repos}"); V1=$(realpath -m "${VAULT:-/nonexistent}"); V2=$HOME/storage/shared/Documents/NovAExorpus
  case $p in
    "$V1"/*|"$V2"/*|/storage/emulated/0/Documents/NovAExorpus/*) p=${p#"$V1"/}; p=${p#"$V2"/}; p=${p#/storage/emulated/0/Documents/NovAExorpus/}; printf 'NovAExorpus\t%s\n' "$p" ;;
    "$R"/*) p=${p#"$R"/}; printf '%s\t%s\n' "${p%%/*}" "${p#*/}" ;;
  esac
}
named() {   # is this path named in a document already read this session (or in the session's agent definition)?
  local short=${1/#$HOME/\~} doc repo rel docs
  IFS=$'\t' read -r repo rel < <(root_of "$1")
  # read this session, plus what loads into every session without a Read: the global and launch-folder instructions
  docs=$(cut -f2 "$open" 2>/dev/null; [ -n "${AGENT_DEF:-}" ] && echo "$AGENT_DEF"
         printf '%s\n' "$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$_cwd/AGENTS.md" "$_cwd/CLAUDE.md")
  while IFS= read -r doc; do
    [ -f "$doc" ] || continue
    grep -qF -- "$1" "$doc" && return 0; grep -qF -- "$short" "$doc" && return 0
    case $1 in "${doc%/*}"/*) grep -qF -- "${1#"${doc%/*}"/}" "$doc" && return 0 ;; esac
    if [ -n "$rel" ] && [ "$rel" != "$1" ]; then
      # "<repo> `path/inside`": the repo named anywhere in the document and the inside path in it
      grep -qF -- "$rel" "$doc" && { grep -qiF -- "$repo" "$doc" || [ "$(root_of "$(realpath -m "$doc")" | cut -f1)" = "$repo" ]; } && return 0
    fi
  done <<<"$docs"
  return 1
}
# the session's agent (settings "agent" in the launch folder): its definition counts as an opening document
_cwd=$(jq -r '.cwd // ""' <<<"$in" 2>/dev/null)
_ag=$(jq -r '.agent // empty' "$_cwd/.claude/settings.json" 2>/dev/null)
[ -n "$_ag" ] && AGENT_DEF=$(ls "$HOME"/repos/*/plugins/*/agents/"${_ag##*:}".md "$HOME"/storage/shared/Documents/NovAExorpus/plugins/*/agents/"${_ag##*:}".md 2>/dev/null | head -1)
reqd() {   # the opening protocol includes what ENFORCEMENTS requires this prompt: those reads and skills always pass
  [ -s "$ST/required-$sid.tsv" ] || return 1
  grep -qF -- "$1" "$ST/required-$sid.tsv" || grep -qF -- "${1/#$HOME/\~}" "$ST/required-$sid.tsv"
}
case $tool in
  AskUserQuestion|ToolSearch|TodoWrite) exit 0 ;;
  Read) [ -n "$rf" ] && reqd "$rf" && exit 0 ;;
esac
case $tool in
  Skill) reqd "skill: $(jq -r '.tool_input.skill // ""' <<<"$in")" && exit 0 ;;
esac
case $tool in
  Read) [ -n "$rf" ] && { isdoc "$rf" && exit 0; [ -f "$open" ] && named "$rf" && exit 0; } ;;
  Skill) [ "$(jq -r '.tool_input.skill // ""' <<<"$in")" = task-observer ] && exit 0 ;;
  Bash) grep -qE '^bash [^;&|]*session-start-scan\.sh [^;&|]*$' <<<"$(jq -r '.tool_input.command // ""' <<<"$in")" && exit 0 ;;
esac
echo "$(date +%T) HOLD direction-gate: $tool" >> "$ST/enforce-$sid.log"   # not a BLOCK line: a Rule 1 hold is not friction
echo "BLOCKED (direction-gate): Rule 1, no action without the operator's direction ($tool). Say what you would do and ask. The operator opens the job with okay or yes, or a message starting with #." >&2
exit 2
