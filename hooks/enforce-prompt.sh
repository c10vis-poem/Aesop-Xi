#!/data/data/com.termux/files/usr/bin/bash
# H6, UserPromptSubmit: work out what this prompt requires and write it to state.
# stdout is added to Claude's context (one pointer line). Always exits 0.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in")
prompt=$(jq -r '.prompt // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
st="$HOME/.claude/state"; mkdir -p "$st"
req="$st/required-$sid.tsv"; done_="$st/satisfied-$sid.tsv"; loaded="$st/loaded-$sid.txt"; log="$st/enforce-$sid.log"
touch "$done_" "$loaded"; : > "$req"
rm -f "$st/pushnow-$sid"
lp=$(tr '[:upper:]' '[:lower:]' <<<"$prompt")
# Wrap-up mode ONLY from the /wrapup command at the start of the prompt (mentions of "wrap up" don't count).
wrapcmd=; grep -qE '^/wrap-?up([[:space:]]|$)' <<<"$lp" && { touch "$st/wrapup-$sid"; wrapcmd=1; }
grep -q 'push now' <<<"$lp" && touch "$st/pushnow-$sid"
# Operator check-off (sessions with a RESUME snapshot): #ok | #ok 1,3 | #defer 2 | #reject 2.
# Any mark = checked in. "#ok N" confirms N as done if a done was proposed, else accepts the plan item.
# Slash forms (/ok, /ok 1,3, /defer 2, /reject 2) at the start of the prompt = the # forms.
lp=$(sed -E 's#^/(ok|defer|reject)([[:space:]]|$)#\#\1\2#' <<<"$lp")
# Operator approves the wrap-up change review: "#ok push" / "/ok push" (read by stop-gate and ship-session)
grep -qE '#ok[[:space:]]+push' <<<"$lp" && touch "$st/pushok-$sid"
if [ -f "$st/resume-$sid.snap.md" ]; then
  # Bare "#ok" / "/ok" = accept every START HERE item as proposed (done → confirmed, blocked → deferred, else accepted).
  if grep -qE '^#ok[[:space:]]*$' <<<"$lp"; then
    touch "$st/checkin-$sid"
    for n in $(awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");print}' "$st/resume-$sid.snap.md"); do
      s=$(grep "^$n	" "$st/resume-items-$sid.tsv" 2>/dev/null | tail -1 | cut -f2)
      case $s in done) v=confirmed-done ;; blocked) v=deferred ;; *) v=accepted ;; esac
      printf '%s\t%s\t%s\n' "$n" "$v" "$(date +%T)" >> "$st/confirm-$sid.tsv"
    done
  fi
  grep -oE '#(ok|defer|reject)([[:space:]]+[0-9][0-9, ]*)?' <<<"$lp" | while read -r m rest; do
    touch "$st/checkin-$sid"
    for n in $(tr ',' ' ' <<<"$rest"); do
      case $m in
        '#ok') grep -q "^$n	done	" "$st/resume-items-$sid.tsv" 2>/dev/null && v=confirmed-done || v=accepted ;;
        '#defer') v=deferred ;;
        '#reject') v=rejected; grep -v "^$n	" "$st/resume-items-$sid.tsv" > "$st/ri.tmp" 2>/dev/null; mv "$st/ri.tmp" "$st/resume-items-$sid.tsv" 2>/dev/null ;;
      esac
      printf '%s\t%s\t%s\n' "$n" "$v" "$(date +%T)" >> "$st/confirm-$sid.tsv"
    done
  done
fi
# Operator keeps a branch from deletion: "#keep-branch <name>" (session-wide list read by ship-session)
grep -oE '#keep-branch[[:space:]]+[^[:space:]]+' <<<"$prompt" | awk '{print $2}' >> "$st/keep-$sid.txt"
H=$(dirname "$(realpath "$0")")

# A /skill typed by the operator counts as loading that skill.
first=$(sed -n '1s|^/\([A-Za-z0-9:_-]*\).*|\1|p' <<<"$prompt")
[ -n "$first" ] && { echo "$first" >> "$loaded"; printf 'skill: %s\n' "$first" >> "$done_"; }

if grep -q '#skip-enforce' <<<"$prompt"; then
  echo "$(date +%T) SKIP operator used #skip-enforce" >> "$log"; exit 0
fi

out=$(jq -n --arg p "$prompt" --arg c "$cwd" --rawfile l "$loaded" \
  '{prompt:$p, cwd:$c, loaded_skills:($l|split("\n")|map(select(length>0)))}' | bash "$H/classify.sh" 2>/dev/null)
jq -r '.required[]? | [.id, .require, .scope] | @tsv' <<<"$out" 2>/dev/null | while IFS=$'\t' read -r id r scope; do
  [ "$scope" = session ] && grep -qxF "$r" "$done_" && continue
  printf '%s\t%s\t%s\n' "$id" "$r" "$scope" >> "$req"
done

[ -n "$wrapcmd" ] && printf 'wrapup\tread: ~/.claude/WRAP-UP.md\tturn\n' >> "$req"

if [ -s "$req" ]; then
  echo "ENFORCEMENTS: before other tools, do: $(cut -f2 "$req" | paste -sd ';' | sed 's/;/; /g') (see ~/.claude/ENFORCEMENTS.md)"
  cut -f1 "$req" | sed "s/^/$(date +%T) REQUIRED /" >> "$log"
fi
exit 0
