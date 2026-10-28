#!/data/data/com.termux/files/usr/bin/bash
# H1 Stop gate. The turn cannot end while a required step of the session is missing. Two checklists:
#
# OPENING (every turn until the operator has checked in):
#   O1 RESUME.md read (resume-gate snapshot)   O2 AGENTS.md of the repo read (when it exists)
#   O3 PENDING.md read (repo, else vault)      O4 START HERE plan posted (resume-item plan)
#   O5 task-observer loaded + session-start scan (when the vault's skill-observations exists)
#   O6 operator checked in (/ok, /defer, /reject, /write) -- operator-only: blocks once, then yields
# WRAP-UP (/wrapup; WRAP-UP.md steps, each named):
#   W1 every START HERE item confirmed done (/ok N after resume-item N done) or deferred (/defer N) BY THE OPERATOR;
#      a deferred item is in PENDING.md (repo or vault); a carried-over item needs /defer N why: <reason> (H9)
#   W2 task-observer: friction events logged/dismissed; weekly review not overdue; parked observations whose
#      branch merged are reported
#   W3 per-repo docs: MEMORY.md exists and changed, AGENTS.md exists, no tracked CLAUDE.md (base repos)
#   W4 PENDING.md (vault) changed this session
#   W5 RESUME.md rewritten: content differs from the session-start hash AND its first 40 lines carry today's date
#   W6 nothing uncommitted: session work in c10vis-poem repos committed; the vault has no uncommitted changes
#      (vault-ship), and every touched repo with commits to ship has CI + required checks (ci-ready)
#   W7 change review shown and approved by the operator (/ok push)
#   W8 staged skill updates installed or #staged-defer (Termux)
# Always: pending ENFORCEMENTS requirements; after a compaction, task-observer loaded again + new scan.
# Operator-only items block once, then yield (stop_hook_active) so the operator can answer.
# Bypass hardening: #skip-enforce / #staged-defer count only in prompts the operator typed, never inside a
# subagent hand-back (<agent-message>, <task-notification>). Items/statuses come from the session-start snapshot.
# Cloud: the same checks run; a check that needs the phone (vault, task-observer, gh) and cannot be
# satisfied here is reported as a NOTE instead of blocking (lib/env.sh advise), never silently dropped.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat); sid=$(jq -r '.session_id // empty' <<<"$in") || exit 0; [ -n "$sid" ] || exit 0
tp=$(jq -r '.transcript_path // empty' <<<"$in"); tp=${tp/#\~/$HOME}; cwd=$(jq -r '.cwd // ""' <<<"$in")
st=$ST; log="$st/enforce-$sid.log"; items="$st/resume-items-$sid.tsv"; vault=$VAULT
notes=()

# Operator override (user-typed only): the latest operator prompt contains #skip-enforce. Subagent hand-backs
# (which arrive as user messages) never count.
last_operator_prompt() {
  [ -f "$tp" ] || return
  jq -r 'select(.type=="user" and (.isMeta|not) and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null \
    | grep -vE '<agent-message|<task-notification>|^Another Claude session sent a message' | tail -1
}
operator_typed() { [ -f "$tp" ] || return 1; jq -r 'select(.type=="user" and (.isMeta|not) and (.message.content|type)=="string") | .message.content' "$tp" 2>/dev/null | grep -vE '<agent-message|<task-notification>|^Another Claude session sent a message' | grep -q -- "$1"; }
if last_operator_prompt | grep -q '#skip-enforce'; then echo "$(date +%T) STOP-SKIP #skip-enforce" >> "$log"; exit 0; fi

top=$(git -C "${cwd:-$HOME}" rev-parse --show-toplevel 2>/dev/null)
r="$top/RESUME.md"; [ -n "$top" ] && [ -f "$r" ] || r="${vault:-/nonexistent}/RESUME.md"
miss=()
wrap=; [ -f "$st/wrapup-$sid" ] && wrap=1
snap="$st/resume-$sid.snap.md"; conf="$st/confirm-$sid.tsv"; open="$st/opening-$sid.tsv"
start_items() { awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");print}' "$1"; }
item_title() { awk -v n="$2" '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&$0 ~ "^"n"\\. "{sub(/^[0-9]+\. /,""); gsub(/\*/,""); print substr($0,1,40); exit}' "$1"; }
was_read() { grep -q "^read:$1	" "$open" 2>/dev/null; }

# ---------- OPENING ----------
if [ -f "$r" ]; then
  if [ ! -f "$st/resume-$sid.ok" ]; then
    miss+=("Opening O1: Read $r")
  elif [ -f "$snap" ]; then
    [ -f "$st/checkin-$sid" ] || [ -s "$conf" ] || [ -n "$wrap" ] || {
      [ -n "$top" ] && [ -f "$top/AGENTS.md" ] && ! was_read AGENTS.md && miss+=("Opening O2: Read $top/AGENTS.md (the repo's rules) before posting the plan")
      pf="$top/PENDING.md"; [ -n "$top" ] && [ -f "$pf" ] || pf="${vault:-/nonexistent}/PENDING.md"
      [ -f "$pf" ] && ! was_read PENDING.md && miss+=("Opening O3: Read $pf and review its open items with the operator")
      [ -f "$st/plan-$sid.txt" ] || miss+=("Opening O4: post the START HERE plan to the operator (each item, what you'll do, tools/skills to load), run: resume-item plan, then end the turn for their /ok N, /defer N, /reject N or /write N <text>")
      [ -f "$st/plan-$sid.txt" ] && miss+=("Opening O6: waiting for the operator's check-in (/ok, /ok 1-3, /defer N, /reject N, /write N <instruction>, /write <new item>); it needs the operator's /ok")
    }
    if [ -n "$wrap" ]; then   # W1: every item closed BY THE OPERATOR
      . "$HOOKS_DIR/carryover.sh"
      co_record "$sid" "$snap" "$conf"
      while IFS=$'\t' read -r n title; do
        [ "$(grep "^$n	" "$conf" 2>/dev/null | tail -1 | cut -f2)" = deferred ] || continue
        c=$(co_prior "$(co_key "$title")" "$sid"); [ "$c" -gt 0 ] || continue
        grep -q "^$n	." "$st/defer-why-$sid.tsv" 2>/dev/null && continue
        miss+=("Wrap-up W1: item $n was already carried over $c time(s) (\"${title:0:40}…\") and can't be deferred again without a reason — finish it (resume-item $n done \"<evidence>\"; it needs the operator's /ok $n), or the operator types: /defer $n why: <reason>")
      done < <(co_items "$snap")
      for n in $(start_items "$snap"); do
        last=$(grep "^$n	" "$conf" 2>/dev/null | tail -1 | cut -f2)
        case $last in
          confirmed-done|rejected) ;;
          deferred) t=$(item_title "$snap" "$n")
                    { grep -qF -- "$t" "${top:-/nonexistent}/PENDING.md" 2>/dev/null || grep -qF -- "$t" "${vault:-/nonexistent}/PENDING.md" 2>/dev/null; } \
                      || miss+=("Wrap-up W1: item $n was deferred by the operator — add it to PENDING.md (repo or vault) (\"$t…\")") ;;
          *) miss+=("Wrap-up W1: item $n not closed — needs the operator's /ok (after you mark it: resume-item $n done \"<evidence>\") or /defer $n") ;;
        esac
      done
    fi
  else
    for n in $(start_items "$r"); do   # older sessions (no snapshot): each item needs a status
      grep -q "^$n	" "$items" 2>/dev/null || miss+=("RESUME item $n has no status: run resume-item $n done|blocked \"<evidence / what you need from the operator>\"")
    done
  fi
fi

# ---------- OBSERVER (O5, W2, compaction) ----------
so="${vault:-/nonexistent}/skill-observations"
if [ -d "$so" ]; then
  if [ -f "$tp" ] && ! jq -e 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill" and (.input.skill|test("task-observer")))' "$tp" >/dev/null 2>&1; then
    miss+=("Opening O5: load the task-observer skill and run its Session Start Protocol")
  elif [ -f "$st/resume-$sid.ok" ] && [ ! "$so/checkpoints.log" -nt "$st/resume-$sid.ok" ]; then
    miss+=("Opening O5: run the task-observer session-start scan (it appends to skill-observations/checkpoints.log)")
  fi
  if [ -f "$st/compact-$sid" ]; then
    { read -r ct; read -r cn; } < "$st/compact-$sid"
    [ -f "$tp" ] && ! jq -e --arg t "$ct" 'select(.type=="assistant" and (.timestamp // "") > $t) | .message.content[]? | select(.type=="tool_use" and .name=="Skill" and (.input.skill|test("task-observer")))' "$tp" >/dev/null 2>&1 \
      && miss+=("Context was compacted: load the task-observer skill again and run its Session Start Protocol")
    [ "$(grep -c 'session-start scan:' "$so/checkpoints.log" 2>/dev/null)" -gt "${cn:-0}" ] 2>/dev/null \
      || miss+=("Context was compacted: run the task-observer session-start scan again (scripts/session-start-scan.sh appends to skill-observations/checkpoints.log)")
  fi
else
  n=$(advise observer "no vault skill-observations/ reachable from this session (VAULT='${vault:-none}'): the task-observer checks (O5, W2) cannot be verified here; log observations in the repo's PENDING.md instead and say so at wrap-up"); [ -n "$n" ] && notes+=("$n")
fi

# Friction events (observe-event.sh queue + gate BLOCK lines imported from the enforce log)
bash "$HOOKS_DIR/observe-event.sh" sync "$sid"
newest=$(find "$so/observation-log" -maxdepth 1 -name '[0-9]*.md' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
openev=$(awk -F'\t' -v nw="${newest%.*}" '$1=="dismiss"{d[$2]=1;next} {o[++n]=$1; e[$1]=$2; s[$1]=$3": "$4}
  END{for(i=1;i<=n;i++){x=o[i]; if(!(x in d) && e[x]+0>=nw+0) printf "%s\t%s\t%s\n", x, strftime("%H:%M",e[x]), s[x]}}' "$st/observe-queue-$sid.tsv" 2>/dev/null)
nfr=0; [ -n "$openev" ] && nfr=$(wc -l <<<"$openev")
pfr=$(cat "$st/observe-blocked-$sid" 2>/dev/null || echo 0); echo "$nfr" > "$st/observe-blocked-$sid"
[ "$nfr" -gt 0 ] && while IFS=$'\t' read -r id t s; do
  miss+=("Friction event $id ($t, $s): log a task-observer observation about it, or: observe-dismiss $id \"<reason>\"")
done < <(head -5 <<<"$openev")
[ "$nfr" -gt 5 ] && miss+=("Friction event list: $((nfr-5)) more (observe-dismiss list)")

if [ -n "$wrap" ] && [ -d "$so" ]; then   # W2
  lr=$(head -1 "$so/last-review-date.txt" 2>/dev/null | tr -d '[:space:]')
  nopen=$(grep -lE '^status:[[:space:]]*"?open' "$so"/observation-log/[0-9]*.md 2>/dev/null | wc -l)
  age=$(( ($(date +%s) - $(date -d "${lr:-never}" +%s 2>/dev/null || echo 0)) / 86400 ))
  [ "$nopen" -gt 0 ] && [ "$age" -gt 7 ] && miss+=("Wrap-up W2: the task-observer weekly review is due (last review: ${lr:-never}) and $nopen observation(s) are open — run the review (task-observer skill) before closing")
  grep -lE '^status:[[:space:]]*"?parked' "$so"/observation-log/[0-9]*.md 2>/dev/null | while read -r f; do
    sed -nE 's/^parked_until:.*fork branch ([^ "]+) merged into ([^ "]+).*/\1 \2/p' "$f" | while read -r b rp; do
      [ "$(ghq pr list -R "c10vis-poem/$rp" --state merged --head "$b" --json number --jq length)" -gt 0 ] 2>/dev/null \
        && echo "${f##*/} waits for branch $b merged into $rp — it is merged"
    done
  done > "$st/parked-merged-$sid.txt"
  while read -r m; do miss+=("Wrap-up W2: parked observation $m: report it to the operator and unpark it (status, parked_until)"); done < "$st/parked-merged-$sid.txt"
fi

# ---------- WRAP-UP W5: RESUME rewritten and dated today ----------
if [ -n "$wrap" ] && [ -f "$st/resume-$sid.ok" ] && [ -f "$r" ]; then
  base=$(head -1 "$st/resume-$sid.ok")
  if [ "$(sha256sum "$r" | cut -d" " -f1)" = "$base" ]; then
    miss+=("Wrap-up W5: rewrite $r from scratch (WRAP-UP.md step 5) — it hasn't changed this session")
  elif [ "$(resume_date "$r")" != "$(date +%F)" ]; then
    miss+=("Wrap-up W5: $r was changed but its first 40 lines don't carry today's date ($(date +%F)); the rewrite must be dated")
  fi
  if [ "$(realpath "$r")" != "$(realpath "${vault:-/nonexistent}/RESUME.md" 2>/dev/null)" ] && [ -f "${vault:-/nonexistent}/RESUME.md" ]; then
    vr="$vault/RESUME.md"
    { [ -f "$st/vault-resume-$sid.sha" ] && [ "$(sha256sum "$vr" | cut -d" " -f1)" != "$(cat "$st/vault-resume-$sid.sha")" ]; } \
      || [ "$(resume_date "$vr")" = "$(date +%F)" ] \
      || miss+=("Wrap-up W5: the vault RESUME.md ($vr) is not rewritten/dated today — WRAP-UP step 5 covers the vault plus every repo worked in")
  fi
fi

# ---------- WRAP-UP W6: committed, vault shipped, CI-ready ----------
rec=$(ls -t "${vault:-/nonexistent}"/_recaps/*-"${sid:0:8}".md 2>/dev/null | head -1)
if [ -n "$wrap" ]; then
  [ -n "$rec" ] || notes+=("$(advise recap "no session recap found (vault _recaps/*-${sid:0:8}.md): session-ledger.sh needs a reachable vault; W6/W3 use git status of the current repo instead")")
  { [ -n "$rec" ] && awk '/^## Files written/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec"; [ -n "$top" ] && git -C "$top" status --porcelain 2>/dev/null | awk '{print $2}' | sed "s#^#$top/#"; } | while read -r fw; do
    [ -e "$fw" ] || continue
    t=$(git -C "${fw%/*}" rev-parse --show-toplevel 2>/dev/null) || continue
    [ -n "$(git -C "$t" status --porcelain -- "$fw" 2>/dev/null)" ] && echo "$t"
  done | sort -u > "$st/uncommitted-$sid.txt"
  if [ -s "$st/uncommitted-$sid.txt" ]; then
    while read -r t; do
      if [ -n "$vault" ] && [ "$(realpath "$t")" = "$(realpath "$vault")" ]; then
        miss+=("Wrap-up W6: the vault has uncommitted changes — ship it with vault-ship (WRAP-UP step 6; ship-session never ships the vault)")
      else miss+=("Wrap-up W6: uncommitted session work in $t — commit on a topic branch (WRAP-UP step 1)"); fi
    done < "$st/uncommitted-$sid.txt"
  fi
fi

# ---------- WRAP-UP W3/W4: per-repo docs ----------
if [ -n "$wrap" ]; then
  base_repos=" NovAExorpus Aesop-Xi NovusAExenti NovAExopia Hyperion-XI AEthX-AEsc CloviX-AEyre wiki-admin "
  start=$(stat -c %Y "$st/resume-$sid.ok" 2>/dev/null || echo 0)
  changed() {  # $1 repo top, $2 file: differs on disk from origin's default branch, or committed after session start
    local d t; d=$(git -C "$1" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    git -C "$1" rev-parse -q --verify "$d" >/dev/null 2>&1 || return 0
    git -C "$1" show "$d:$2" 2>/dev/null | cmp -s - "$1/$2" || return 0
    for t in $(git -C "$1" log -1 --format=%ct "$d" -- "$2" 2>/dev/null) $(git -C "$1" log -1 --format=%ct HEAD -- "$2" 2>/dev/null); do
      [ "$t" -ge "$start" ] && return 0
    done
    return 1
  }
  tops=$( { [ -n "$rec" ] && awk '/^## Files written/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec" | while read -r fw; do
      [ -e "$fw" ] && git -C "${fw%/*}" rev-parse --show-toplevel 2>/dev/null; done; [ -n "$top" ] && echo "$top"; } | sort -u)
  for t in $tops; do
    name=$(basename "$(git -C "$t" config --get remote.origin.url 2>/dev/null | sed 's/\.git$//')" 2>/dev/null); [ -n "$name" ] || name=$(basename "$t")
    case $base_repos in *" $name "*) ;; *) continue ;; esac
    [ -f "$t/MEMORY.md" ] || { miss+=("Wrap-up W3: $name has no MEMORY.md — create it (WRAP-UP step 4b)"); continue; }
    upd=; for w in $(git -C "$t" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p'); do
      [ -f "$w/MEMORY.md" ] && changed "$w" MEMORY.md && { upd=1; break; }; done
    [ -n "$upd" ] || miss+=("Wrap-up W3: update $name/MEMORY.md with what this session learned (WRAP-UP step 4b)")
    [ -f "$t/AGENTS.md" ] || miss+=("Wrap-up W3: $name has no AGENTS.md (the only repo instruction file)")
    [ -n "$(git -C "$t" ls-files CLAUDE.md .claude/CLAUDE.md 2>/dev/null)" ] && miss+=("Wrap-up W3: $name still tracks a CLAUDE.md — move its content into AGENTS.md and delete it")
  done
  if [ -n "$vault" ] && [ -f "$vault/PENDING.md" ]; then
    changed "$vault" PENDING.md || miss+=("Wrap-up W4: move every unaddressed item into the vault PENDING.md (WRAP-UP step 4) — it hasn't changed this session")
  elif [ -n "$top" ] && [ -f "$top/PENDING.md" ]; then
    changed "$top" PENDING.md || miss+=("Wrap-up W4: move every unaddressed item into $top/PENDING.md (WRAP-UP step 4) — it hasn't changed this session")
  fi
fi

# ---------- WRAP-UP W6b: CI + required checks for every repo with something to ship ----------
if [ -n "$wrap" ]; then
  { [ -n "$rec" ] && awk '/^## Repos touched/{f=1;next} /^## /{f=0} f&&/^- /{sub(/^- /,"");print}' "$rec"; [ -n "$top" ] && echo "$top"; } | sort -u | while read -r t; do
    c=$(git -C "$t" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    [ "${c##*/}" = .git ] && t=${c%/.git}
    u=$(git -C "$t" remote get-url origin 2>/dev/null); u=${u%.git}
    [[ $u =~ github.com[:/](c10vis-poem/[^/]+)$ ]] || continue
    s=${BASH_REMATCH[1]}; case $s in */NovAExorpus) continue ;; esac
    d=$(git -C "$t" symbolic-ref -q --short refs/remotes/origin/HEAD); d=${d#origin/}
    ship=$(git -C "$t" for-each-ref --format='%(refname:short)' refs/heads | while read -r b; do
      [ "$b" = "${d:-main}" ] && continue
      [ -n "$(git -C "$t" log -1 --format=%H "refs/heads/$b" --not --remotes --since="@$(stat -c %Y "$st/resume-$sid.ok" 2>/dev/null || echo 0)" 2>/dev/null)" ] && echo "$b"; done)
    [ -n "$ship" ] || continue
    command -v gh >/dev/null 2>&1 || { echo "@nogh $s"; continue; }
    why=$(timeout 30 bash "$HOOKS_DIR/ci-ready.sh" "$s" "${d:-main}"); rc=$?
    [ $rc -eq 0 ] && continue
    [ $rc -eq 3 ] && why="$s: "
    for b in $ship; do
      [ -n "$(git -C "$t" ls-tree -r --name-only "$b" -- .github/workflows 2>/dev/null)" ] && why=${why//no CI workflow;/} && why=${why//no CI workflow/} && break
    done
    case $why in *": ") ;; *) echo "$why" ;; esac
  done | sort -u > "$st/ci-missing-$sid.txt"
  while read -r m; do
    case $m in "@nogh "*) notes+=("$(advise ci "gh is not available here: CI/required-checks for ${m#@nogh } not verified (W6)")") ;;
      *) miss+=("Wrap-up W6: $m — add a CI workflow (gitleaks + tests) and branch protection with required checks before shipping") ;; esac
  done < "$st/ci-missing-$sid.txt"
fi

# ---------- WRAP-UP W7: change review approved ----------
if [ -n "$wrap" ] && [ -s "$st/changes-$sid.log" ] && [ ! -f "$st/pushok-$sid" ]; then
  miss+=("Wrap-up W7: show the operator the change review (bash $HOOKS_DIR/review-changes.sh $sid; paste its tables and the outside-the-vault list) — it needs the operator's /ok push before anything ships")
fi

# ---------- W8: staged skill updates (Termux) ----------
stg=$(bash "$HOOKS_DIR/staged-updates.sh" names 2>/dev/null)
if [ -n "$stg" ] && ! operator_typed '#staged-defer'; then
  miss+=("Staged skill updates pending ($(paste -sd ';' <<<"$stg")): tell the operator; install, then mark each heading [installed <date>] in $vault/skill-updates/PENDING.md, or the operator types #staged-defer")
fi

# ---------- ENFORCEMENTS requirements still pending for this prompt ----------
[ -s "$st/required-$sid.tsv" ] && miss+=("Pending ENFORCEMENTS: $(cut -f2 "$st/required-$sid.tsv" | paste -sd ';')")

if [ ${#miss[@]} -eq 0 ]; then
  [ ${#notes[@]} -gt 0 ] && printf '%s\n' "${notes[@]}"
  exit 0
fi
# Items only the operator can close (/ok, /defer, /write, /ok push, #staged-defer) block once, then let the turn end
# so the operator can type them. Friction events likewise yield once a re-block resolved none of them.
if [ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ]; then
  ops=0; for m in "${miss[@]}"; do case $m in *"needs the operator's /ok"*|"Staged skill updates"*|*"Opening O6"*) ops=$((ops+1)) ;; "Friction event"*) [ "$nfr" -ge "$pfr" ] && ops=$((ops+1)) ;; esac; done
  [ "$ops" -eq ${#miss[@]} ] && { echo "$(date +%T) STOP-YIELD awaiting operator /ok|/defer|/write or unresolved friction events" >> "$log"; exit 0; }
fi
reason="BLOCKED (stop-gate): not done yet —"; for m in "${miss[@]}"; do reason+=$'\n'"- $m"; done
for n in "${notes[@]}"; do reason+=$'\n'"- $n"; done
echo "$(date +%T) STOP-BLOCK ${#miss[@]} item(s)" >> "$log"
jq -n --arg r "$reason" '{decision:"block", reason:$r}'
