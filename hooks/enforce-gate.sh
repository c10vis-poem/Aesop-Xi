#!/data/data/com.termux/files/usr/bin/bash
# H6, PreToolUse "*": refuse tool calls until this prompt's requirements are met.
# A call that satisfies a requirement is allowed and ticks it off. Fails open on errors.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
st="$HOME/.claude/state"; req="$st/required-$sid.tsv"; done_="$st/satisfied-$sid.tsv"; log="$st/enforce-$sid.log"
[ -s "$req" ] || exit 0
[ -f "$st/resume-$sid.ok" ] || exit 0          # resume-gate goes first; no deadlock
tool=$(jq -r '.tool_name // ""' <<<"$in")
skill=$(jq -r '.tool_input.skill // ""' <<<"$in")
file=$(jq -r '.tool_input.file_path // ""' <<<"$in")
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
x(){ eval echo "$1" 2>/dev/null; }             # expand ~ in registry paths

hit=""
while IFS=$'\t' read -r id r scope; do
  kind=${r%%:*}; val=$(sed 's/^[a-z]*: *//' <<<"$r")
  case $kind in
    skill) [ "$tool" = Skill ] && { [ "$skill" = "$val" ] || [ "${skill##*:}" = "$val" ]; } && hit="$hit$id"$'\n' ;;
    read)  [ "$tool" = Read ] && [ -n "$file" ] && [ "$(realpath -m "$file")" = "$(realpath -m "$(x "$val")")" ] && hit="$hit$id"$'\n' ;;
    run)   [ "$tool" = Bash ] && case $cmd in "$val"*) true ;; *) false ;; esac && hit="$hit$id"$'\n' ;;
  esac
done < "$req"

if [ -n "$hit" ]; then
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    grep -P "^\Q$id\E\t" "$req" | cut -f2 >> "$done_"
    grep -vP "^\Q$id\E\t" "$req" > "$req.tmp"; mv "$req.tmp" "$req"
    echo "$(date +%T) PASS $id" >> "$log"
  done <<<"$hit"
  exit 0
fi

echo "$(date +%T) BLOCK $tool ($(cut -f1 "$req" | paste -sd,))" >> "$log"
echo "BLOCKED (enforcements): first do: $(cut -f2 "$req" | paste -sd ';' | sed 's/;/; /g'). Rules: ~/.claude/ENFORCEMENTS.md. Operator can add #skip-enforce to a prompt." >&2
exit 2
