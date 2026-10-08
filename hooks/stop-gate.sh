#!/data/data/com.termux/files/usr/bin/bash
# H1 Stop gate. Each turn: RESUME read; the START HERE plan posted (resume-item plan) until the operator
# checks in; task-observer ran; no ENFORCEMENTS requirement pending. In /wrapup: every START HERE item
# confirmed done (#ok N) or deferred (#defer N, then in PENDING.md) BY THE OPERATOR; RESUME rewritten;
# session work committed. Items/statuses come from the session-start RESUME snapshot.
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
st="$HOME/.claude/state"; log="$st/enforce-$sid.log"; items="$st/resume-items-$sid.tsv"
vault="$HOME/storage/shared/Documents/NovAExorpus"

# Operator override (manual, user-typed only): latest real user prompt contains #skip-enforce
if [ -f "$tp" ] && jq -r 'select(.type=="user" and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null | tail -1 | grep -q '#skip-enforce'; then
  echo "$(date +%T) STOP-SKIP #skip-enforce" >> "$log"; exit 0
fi

top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="$vault/RESUME.md"
miss=()

if [ -f "$r" ]; then
  if [ ! -f "$st/resume-$sid.ok" ]; then
    miss+=("Read $r")
  elif [ -f "$st/resume-$sid.snap.md" ]; then
    # Operator check-off flow: post the plan once, then wait for the operator's marks
    [ -f "$st/plan-$sid.txt" ] || [ -f "$st/checkin-$sid" ] || \
      miss+=("Post the START HERE plan to the operator (each item, what you'll do, tools/skills to load), run: resume-item plan, then end the turn for their /ok N / /defer N")
    if [ -f "$st/wrapup-$sid" ]; then   # closing: every item confirmed done or deferred BY THE OPERATOR
      for n in $(awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");print}' "$st/resume-$sid.snap.md"); do
        last=$(grep "^$n	" "$st/confirm-$sid.tsv" 2>/dev/null | tail -1 | cut -f2)
        case $last in
          confirmed-done) ;;
          deferred) t=$(awk -v n="$n" '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&$0 ~ "^"n"\\. "{sub(/^[0-9]+\. /,""); gsub(/\*/,""); print substr($0,1,40); exit}' "$st/resume-$sid.snap.md")
                    grep -qF -- "$t" "$vault/PENDING.md" 2>/dev/null || miss+=("Wrap-up: item $n was deferred by the operator — add it to PENDING.md (\"$t…\")") ;;
          *) miss+=("Wrap-up: item $n not closed — needs the operator's /ok (after you mark it: resume-item $n done \"<evidence>\") or /defer $n") ;;
        esac
      done
    fi
  else
    # Older sessions (no snapshot): previous rule — each item needs a status
    for n in $(awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");print}' "$r"); do
      grep -q "^$n	" "$items" 2>/dev/null || miss+=("RESUME item $n has no status: run resume-item $n done|blocked \"<evidence / what you need from the operator>\"")
    done
  fi
fi

# task-observer: skill loaded this session + session-start scan written after RESUME was read
if [ -f "$tp" ] && ! jq -e 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill" and (.input.skill|test("task-observer")))' "$tp" >/dev/null 2>&1; then
  miss+=("Load the task-observer skill and run its Session Start Protocol")
elif [ -f "$st/resume-$sid.ok" ] && [ ! "$vault/skill-observations/checkpoints.log" -nt "$st/resume-$sid.ok" ]; then
  miss+=("Run the task-observer session-start scan (it appends to skill-observations/checkpoints.log)")
fi

# Wrap-up mode: RESUME.md must be rewritten this session (content differs from session start)
# Compare content, not mtime (shared storage doesn't update mtime on rewrite). Baseline = hash
# recorded by resume-gate at session start, else the last synced version on origin/main.
base=$(cat "$st/resume-$sid.ok" 2>/dev/null)
[ -n "$base" ] || base=$(git -C "$vault" show origin/main:RESUME.md 2>/dev/null | sha256sum | cut -d" " -f1)
if [ -f "$st/wrapup-$sid" ] && [ -f "$st/resume-$sid.ok" ] && [ "$(sha256sum "$vault/RESUME.md" | cut -d" " -f1)" = "$base" ]; then
  miss+=("Wrap-up: rewrite $vault/RESUME.md from scratch (WRAP-UP.md step 5) — it hasn't changed this session")
fi

# Wrap-up mode: files this session wrote inside c10vis-poem repos must be committed (vault exempt: GitSync)
if [ -f "$st/wrapup-$sid" ]; then
  rec=$(ls -t "$vault"/_recaps/*-"${sid:0:8}".md 2>/dev/null | head -1)
  [ -n "$rec" ] && awk '/^## Files written/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec" | while read -r fw; do
    [ -e "$fw" ] || continue
    t=$(git -C "${fw%/*}" rev-parse --show-toplevel 2>/dev/null) || continue
    case $t in */NovAExorpus*|*/storage/emulated/*) continue ;; esac
    [ -n "$(git -C "$t" status --porcelain -- "$fw" 2>/dev/null)" ] && echo "$t"
  done | sort -u > "$st/uncommitted-$sid.txt"
  [ -s "$st/uncommitted-$sid.txt" ] && miss+=("Wrap-up: uncommitted session work in: $(paste -sd ' ' "$st/uncommitted-$sid.txt") — commit on a topic branch (WRAP-UP step 1)")
fi

# Wrap-up mode: per-repo docs (WRAP-UP step 4/4b) for every repo this session wrote in, vault included.
# MEMORY.md must exist and differ from origin's default branch; AGENTS.md must exist and CLAUDE.md must
# not (operator 2026-10-05: AGENTS.md is the only repo instruction file; upstream forks are exempt);
# the vault PENDING.md must differ from origin/main.
if [ -f "$st/wrapup-$sid" ]; then
  base_repos=" NovAExorpus aesop-xi novus-aexenti NovAExopia Hyperion-XI novus-aesc novus-aeyre wiki-admin "
  start=$(stat -c %Y "$st/resume-$sid.ok" 2>/dev/null || echo 0)   # session start (RESUME read)
  changed() {  # $1 repo top, $2 file: changed this session = differs on disk from origin's default branch
    # (content compare: the vault's index is stale under GitSync), or already shipped: its last commit
    # there (or on HEAD) is newer than the session start.
    local d t; d=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    git -C "$1" rev-parse -q --verify "$d" >/dev/null 2>&1 || return 0   # no remote yet: existence is enough
    git -C "$1" show "$d:$2" 2>/dev/null | cmp -s - "$1/$2" || return 0
    for t in $(git -C "$1" log -1 --format=%ct "$d" -- "$2" 2>/dev/null) $(git -C "$1" log -1 --format=%ct HEAD -- "$2" 2>/dev/null); do
      [ "$t" -ge "$start" ] && return 0
    done
    return 1
  }
  rec=$(ls -t "$vault"/_recaps/*-"${sid:0:8}".md 2>/dev/null | head -1)
  tops=$( { [ -n "$rec" ] && awk '/^## Files written/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec"; } | while read -r fw; do
    case $fw in */storage/*/Documents/NovAExorpus/*|*/storage/shared/Documents/NovAExorpus/*) echo "$vault"; continue ;; esac
    [ -e "$fw" ] && git -C "${fw%/*}" rev-parse --show-toplevel 2>/dev/null
  done | sort -u)
  for t in $tops; do
    name=$(basename "$(git -C "$t" config --get remote.origin.url 2>/dev/null | sed 's/\.git$//')" 2>/dev/null); [ -n "$name" ] || name=$(basename "$t")
    case $base_repos in *" $name "*) ;; *) continue ;; esac
    [ -f "$t/MEMORY.md" ] || { miss+=("Wrap-up: $name has no MEMORY.md — create it (WRAP-UP step 4b)"); continue; }
    changed "$t" MEMORY.md || miss+=("Wrap-up: update $name/MEMORY.md with what this session learned (WRAP-UP step 4b)")
    [ -f "$t/AGENTS.md" ] || miss+=("Wrap-up: $name has no AGENTS.md (the only repo instruction file)")
    [ -n "$(git -C "$t" ls-files CLAUDE.md .claude/CLAUDE.md 2>/dev/null)" ] && miss+=("Wrap-up: $name still tracks a CLAUDE.md — move its content into AGENTS.md and delete it")
  done
  changed "$vault" PENDING.md || miss+=("Wrap-up: move every unaddressed item into the vault PENDING.md (WRAP-UP step 4) — it hasn't changed this session")
fi

# Wrap-up mode: every c10vis-poem repo this session touched must have CI + required checks, or
# ship-session refuses auto-merge (nothing would gate the merge).
if [ -f "$st/wrapup-$sid" ]; then
  rec=$(ls -t "$vault"/_recaps/*-"${sid:0:8}".md 2>/dev/null | head -1)
  [ -n "$rec" ] && awk '/^## Repos touched/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec" | while read -r t; do
    c=$(git -C "$t" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    [ "${c##*/}" = .git ] && t=${c%/.git}
    u=$(git -C "$t" remote get-url origin 2>/dev/null); u=${u%.git}
    [[ $u =~ github.com[:/](c10vis-poem/[^/]+)$ ]] || continue
    s=${BASH_REMATCH[1]}; case $s in */NovAExorpus) continue ;; esac
    d=$(git -C "$t" symbolic-ref -q --short refs/remotes/origin/HEAD); d=${d#origin/}
    bash "$(dirname "$0")/ci-ready.sh" "$s" "${d:-main}"
  done | sort -u > "$st/ci-missing-$sid.txt"
  while read -r m; do miss+=("Wrap-up: $m — add a CI workflow (gitleaks + tests) and branch protection with required checks (github-project skill) before shipping"); done < "$st/ci-missing-$sid.txt"
fi

# Wrap-up mode: the operator reviews every recorded change (change-log.sh) and approves the push
if [ -f "$st/wrapup-$sid" ] && [ -s "$st/changes-$sid.log" ] && [ ! -f "$st/pushok-$sid" ]; then
  miss+=("Wrap-up: show the operator the change review (bash ~/.claude/hooks/review-changes.sh $sid; paste its tables and the outside-the-vault list) — it needs the operator's /ok push before anything ships")
fi

# ENFORCEMENTS requirements still pending for this prompt
[ -s "$st/required-$sid.tsv" ] && miss+=("Pending ENFORCEMENTS: $(cut -f2 "$st/required-$sid.tsv" | paste -sd ';')")

[ ${#miss[@]} -eq 0 ] && exit 0
# Items only the operator can close (/ok, /defer) block once, then let the turn end so the operator can
# type them: re-blocking on stop_hook_active would loop forever with no way for them to answer.
if [ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ]; then
  ops=0; for m in "${miss[@]}"; do case $m in *"needs the operator's /ok"*) ops=$((ops+1)) ;; esac; done   # incl. "/ok push"
  [ "$ops" -eq ${#miss[@]} ] && { echo "$(date +%T) STOP-YIELD awaiting operator /ok|/defer" >> "$log"; exit 0; }
fi
reason="BLOCKED (stop-gate): not done yet —"; for m in "${miss[@]}"; do reason+=$'\n'"- $m"; done
echo "$(date +%T) STOP-BLOCK ${#miss[@]} item(s)" >> "$log"
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
