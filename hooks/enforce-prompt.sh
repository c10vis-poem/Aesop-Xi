#!/data/data/com.termux/files/usr/bin/bash
# H6, UserPromptSubmit: work out what this prompt requires and write it to state.
# stdout is added to Claude's context (one pointer line). Always exits 0.
. "$(dirname "$(realpath "$0")")/lib/env.sh"
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in")
prompt=$(jq -r '.prompt // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
st=$ST
req="$st/required-$sid.tsv"; done_="$st/satisfied-$sid.tsv"; loaded="$st/loaded-$sid.txt"; log="$st/enforce-$sid.log"
touch "$done_" "$loaded"; : > "$req"
# Subagent hand-backs arrive as prompts but are not the operator: require nothing, record no marks, keep "push now".
is_operator_prompt "$prompt" || exit 0
lp=$(tr '[:upper:]' '[:lower:]' <<<"$prompt")
# Wrap-up mode ONLY from the /wrapup command at the start of the prompt (mentions of "wrap up" don't count).
wrapcmd=; grep -qE '^/wrap-?up([[:space:]]|$)' <<<"$lp" && { touch "$st/wrapup-$sid"; wrapcmd=1; }
# "push now" lasts for the rest of the session (a later prompt doesn't revoke it); "hold push" / "don't push" does.
grep -q 'push now' <<<"$lp" && touch "$st/pushnow-$sid"
grep -qE "hold (the )?push|don'?t push|stop push" <<<"$lp" && rm -f "$st/pushnow-$sid"
# Operator check-off (sessions with a RESUME snapshot):
#   #ok | #ok 1,3 | #ok 1-4 | #ok all | #defer 2 | #reject 2 | #write 2 <text> | #write <text>
# Slash forms (/ok, /defer, /reject, /write; /edit and /rewrite = /write) anywhere after a space, a stray dash
# before numbers ("/ok -0"). Any mark = checked in. "#ok N" confirms N as done if a done was proposed, else
# accepts the plan item. "#write N <text>" replaces item N's instruction with the operator's text (recorded in
# written-<sid>.tsv and in the snapshot) and accepts it; "#write <text>" adds a new START HERE item.
lp=$(sed -E 's#(^|[[:space:]])/(ok|defer|reject|write|edit|rewrite)([[:space:]]|$)#\1\#\2\3#g; s/#(edit|rewrite)([[:space:]]|$)/#write\2/g; s#(\#(ok|defer|reject|write))[[:space:]]+-([0-9])#\1 \3#g' <<<"$lp")
# Operator approves the wrap-up change review: "#ok push" / "/ok push" (read by stop-gate and ship-session)
grep -qE '#ok[[:space:]]+push' <<<"$lp" && touch "$st/pushok-$sid"
snap="$st/resume-$sid.snap.md"; conf="$st/confirm-$sid.tsv"; written="$st/written-$sid.tsv"
items_of() { awk '/^#+ .*START HERE/{f=1;next} f&&/^#/{exit} f&&/^[0-9]+\. /{sub(/\..*/,"");printf "%s ",$0}' "$snap"; }
expand() {  # "1,3-5, 7" -> "1 3 4 5 7"; "all" -> every item
  local out= t a b
  for t in $(tr ',' ' ' <<<"$1"); do
    case $t in all) out="$out $(items_of)" ;;
      *-*) a=${t%-*}; b=${t#*-}; [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ ]] && [ "$a" -le "$b" ] && out="$out $(seq -s ' ' "$a" "$b")" ;;
      *) [[ $t =~ ^[0-9]+$ ]] && out="$out $t" ;;
    esac
  done; echo $out
}
if [ -f "$snap" ]; then
  touch "$conf"
  # Bare "#ok" / "/ok" = accept every START HERE item as proposed (done -> confirmed, blocked -> deferred, else accepted).
  if grep -qE '^#ok[[:space:]]*$' <<<"$lp"; then
    touch "$st/checkin-$sid"
    for n in $(items_of); do
      s=$(grep "^$n	" "$st/resume-items-$sid.tsv" 2>/dev/null | tail -1 | cut -f2)
      case $s in done) v=confirmed-done ;; blocked) v=deferred ;; *) v=accepted ;; esac
      printf '%s\t%s\t%s\n' "$n" "$v" "$(date +%T)" >> "$conf"
    done
  fi
  items=" $(items_of)"
  before=$(wc -l < "$conf" 2>/dev/null || echo 0)
  # #write N <text> and #write <text>: taken from the original prompt so the operator's text keeps its case.
  # split the prompt at every /write|#write (and /edit, /rewrite) mark; each piece ends at the next mark or newline
  sed -E 's#(^|[[:space:]])[/\#](write|edit|rewrite)([[:space:]]|$)#\n@@WRITE@@ #Ig; s#(^|[[:space:]])[/\#](ok|defer|reject)([[:space:]]|$)#\n@@MARK@@ #Ig' <<<"$prompt" | grep '^@@WRITE@@ ' | while IFS= read -r w; do
    body=${w#@@WRITE@@ }; n=
    [[ $body =~ ^-?([0-9]+)[[:space:]]*:?[[:space:]]+(.+)$ ]] && { n=${BASH_REMATCH[1]}; body=${BASH_REMATCH[2]}; }
    body=$(sed -E 's/[[:space:]]+$//; s/^[[:space:]]+//' <<<"$body"); [ -n "$body" ] || continue
    touch "$st/checkin-$sid"
    if [ -n "$n" ]; then
      [[ $items == *" $n "* ]] || { echo "CHECK-IN ignored: $n is not a START HERE item"; continue; }
      # replace the item's text in the snapshot (the file every reader uses) and record the operator's words
      awk -v n="$n" -v t="$body" '/^#+ .*START HERE/{f=1} f&&/^#/&&!/START HERE/{f=0} f&&$0 ~ "^"n"\\. "{print n". "t" (rewritten by the operator)"; next} {print}' "$snap" > "$snap.tmp" && mv "$snap.tmp" "$snap"
      printf '%s\t%s\t%s\n' "$n" "$body" "$(date +%T)" >> "$written"
      printf '%s\t%s\t%s\n' "$n" "written" "$(date +%T)" >> "$conf"
    else
      n=$(( $(items_of | tr ' ' '\n' | sort -n | tail -1) + 1 ))
      awk -v line="$n. $body (added by the operator)" '/^#+ .*START HERE/{f=1;print;next} f&&/^#/{print line; f=0} {print} END{if(f)print line}' "$snap" > "$snap.tmp" && mv "$snap.tmp" "$snap"
      printf '%s\t%s\t%s\n' "$n" "$body" "$(date +%T)" >> "$written"
      printf '%s\t%s\t%s\n' "$n" "added" "$(date +%T)" >> "$conf"
    fi
  done
  items=" $(items_of)"
  # "16. /ok 17. next point": a number followed by "." is the operator's next list label, not an item
  sed -E 's#(\#(ok|defer|reject))[[:space:]]+[0-9]+\.([[:space:]]|$)#\1\3#g' <<<"$lp" |
  grep -oE '#(ok|defer|reject)([[:space:]]+(all|[0-9][0-9,-]*([[:space:]]*,[[:space:]]*[0-9][0-9-]*)*))?' | while read -r m rest; do
    touch "$st/checkin-$sid"
    for n in $(expand "$rest"); do
      [[ $items == *" $n "* ]] || { echo "CHECK-IN ignored: $n is not a START HERE item"; continue; }
      case $m in
        '#ok') grep -q "^$n	done	" "$st/resume-items-$sid.tsv" 2>/dev/null && v=confirmed-done || v=accepted ;;
        '#defer') v=deferred ;;
        '#reject') v=rejected; grep -v "^$n	" "$st/resume-items-$sid.tsv" > "$st/ri.tmp" 2>/dev/null; mv "$st/ri.tmp" "$st/resume-items-$sid.tsv" 2>/dev/null ;;
      esac
      printf '%s\t%s\t%s\n' "$n" "$v" "$(date +%T)" >> "$conf"
    done
  done
  if grep -qE '#(ok|defer|reject|write)' <<<"$lp"; then
    new=$(tail -n +$((before + 1)) "$conf" 2>/dev/null | cut -f1,2 | tr '\t\n' '= ')
    if [ -n "$new" ]; then echo "CHECK-IN recorded: $new"
    elif [ -f "$st/checkin-$sid" ]; then echo "CHECK-IN recorded: checked in, no item numbers in this prompt"
    else echo "CHECK-IN NOT recorded: no usable #ok/#defer/#reject/#write mark found"; fi
    grep -q . "$written" 2>/dev/null && [ "$(tail -n +$((before + 1)) "$conf" | grep -cE '	(written|added)	')" -gt 0 ] \
      && echo "OPERATOR WROTE: $(tail -n +$((before + 1)) "$conf" | grep -E '	(written|added)	' | cut -f1 | while read -r n; do printf '%s=%s; ' "$n" "$(grep "^$n	" "$written" | tail -1 | cut -f2 | cut -c1-120)"; done) -- follow the operator's text, not the old item"
  fi
  # Operator's reason for deferring an item again (H9, read by stop-gate): "#defer 3 why: <reason>"
  sed -nE 's#^[[:space:]]*/defer[[:space:]]#\#defer #; s#.*\#defer[[:space:]]+([0-9]+)[[:space:]]+(why|because):?[[:space:]]+(.+)#\1\t\3#Ip' <<<"$prompt" |
    while IFS=$'\t' read -r n why; do printf '%s\t%s\t%s\n' "$n" "$why" "$(date +%T)" >> "$st/defer-why-$sid.tsv"; done
fi
grep -qE '(^|[[:space:]])[/#](o|okk|ko|deffer|rejct|wrte|wirte)([[:space:]]|$)' <<<"$lp" && echo "CHECK-IN NOT recorded: unrecognised mark (use /ok, /defer, /reject, /write)"
[ -f "$snap" ] || ! grep -qE '#(ok|defer|reject|write)' <<<"$lp" || grep -qE '#ok[[:space:]]+push' <<<"$lp" || echo "CHECK-IN NOT recorded: this session has no RESUME snapshot"
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
  [ -n "$first" ] && { [ "$r" = "skill: $first" ] || [ "$r" = "skill: ${first##*:}" ]; } && continue   # /skill typed in this prompt
  printf '%s\t%s\t%s\n' "$id" "$r" "$scope" >> "$req"
done

[ -n "$wrapcmd" ] && printf 'wrapup\tread: %s\tturn\n' "$( [ -f "$HOME/.claude/WRAP-UP.md" ] && echo "~/.claude/WRAP-UP.md" || echo "$H/WRAP-UP.md")" >> "$req"

if [ -s "$req" ]; then
  echo "ENFORCEMENTS: before other tools, do: $(cut -f2 "$req" | paste -sd ';' | sed 's/;/; /g') (see ~/.claude/ENFORCEMENTS.md)"
  cut -f1 "$req" | sed "s/^/$(date +%T) REQUIRED /" >> "$log"
fi
exit 0
