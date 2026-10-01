#!/data/data/com.termux/files/usr/bin/bash
# H6, UserPromptSubmit: work out what this prompt requires and write it to state.
# stdout is added to Claude's context (one pointer line). Always exits 0.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in")
prompt=$(jq -r '.prompt // ""' <<<"$in"); cwd=$(jq -r '.cwd // ""' <<<"$in")
st="$HOME/.claude/state"; mkdir -p "$st"
req="$st/required-$sid.tsv"; done_="$st/satisfied-$sid.tsv"; loaded="$st/loaded-$sid.txt"; log="$st/enforce-$sid.log"
touch "$done_" "$loaded"; : > "$req"
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

if [ -s "$req" ]; then
  echo "ENFORCEMENTS: before other tools, do: $(cut -f2 "$req" | paste -sd ';' | sed 's/;/; /g') (see ~/.claude/ENFORCEMENTS.md)"
  cut -f1 "$req" | sed "s/^/$(date +%T) REQUIRED /" >> "$log"
fi
exit 0
