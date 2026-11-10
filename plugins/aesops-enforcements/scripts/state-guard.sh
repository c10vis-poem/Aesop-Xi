#!/usr/bin/env bash
# PreToolUse (Bash|Write|Edit), obs 0017: the agent may not delete, move, truncate or write the
# ~/.claude/state enforcement files (resume-, confirm-, plan-, required-, satisfied-, observe-queue-,
# checkin-, pushnow-, written-, opening-, advised-, pushok-, defer-why-, wrapup-; run-gate's override-, blocks-,
# prompt-, noship-, shown-, hooks-off; the off/ switches and ~/.nvaex-hooks-off). Reads stay allowed. `gate off|on`
# by the agent is refused: a rule the agent can switch off is no rule (operator: `! gate off <hook>`).
# They change only through the operator's own `!` commands, the official tools (resume-item,
# observe-dismiss) and the hook scripts, none of which reach here. An interpreter (python/node/perl/ruby)
# or a shell -c string that names the state dir counts as a write (it can open() anything).
in=$(cat); tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || exit 0
P='((resume|confirm|plan|required|satisfied|observe-queue|checkin|pushnow|pushok|written|opening|advised|defer-why|wrapup|override|blocks|prompt|noship|nomerge|shown|direct4|job|source|source-mode|source-asked)-|hooks-off|off([/[:space:]"'"'"']|$))'
say(){ echo "BLOCKED (state-guard): $1 is enforcement state. Only the operator, resume-item, observe-dismiss or the hooks change it (obs 0017)." >&2; exit 2; }
if [ "$tool" != Bash ]; then
  f=$(jq -r '.tool_input.file_path // ""' <<<"$in"); f=${f/#\~/$HOME}
  [[ $f =~ ^$HOME/\.claude/state/$P ]] && say "$f"
  [ "$f" = "$HOME/.nvaex-hooks-off" ] && say "$f"
  exit 0
fi
c=$(jq -r '.tool_input.command // ""' <<<"$in")
u=$(sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" <<<"$c")   # quoted text is not a command
command grep -qE '(^|[;&|[:space:]/])gate[[:space:]]+(off|on)([[:space:]]|$)' <<<"$u" && say "the gate switch"
command grep -qE '\.nvaex-hooks-off' <<<"$c" && command grep -qE "(^|[;&|[:space:](])(rm|mv|cp|truncate|tee|touch|ln|unlink|dd|install)[[:space:]]|>[[:space:]]*[\"']?[^[:space:]]*\.nvaex-hooks-off" <<<"$c" && say "the kill switch ~/.nvaex-hooks-off"
command grep -q '\.claude/state' <<<"$c" || exit 0
command grep -qE "(^|[;&|[:space:](])(python3?|node|perl|ruby|uv run|npx)[[:space:]]|(^|[;&|[:space:](])(bash|sh|zsh)[[:space:]]+-c[[:space:]]" <<<"$c" && say "an interpreter run that names ~/.claude/state"
# Drop harmless redirects (2>/dev/null, 2>&1, >&2), then split into simple commands
while IFS= read -r s; do
  command grep -qE "(^|[/[:space:]\"'])$P" <<<"$s" || continue
  command grep -qE "(^|[[:space:](])(rm|mv|cp|truncate|tee|touch|ln|unlink|shred|dd|install|rsync)[[:space:]]|sed[[:space:]]+-[a-zA-Z]*i|-delete|>[[:space:]]*[\"']?([^[:space:]\"']*/)?$P" <<<"$s" && say "${s:0:120}"
done < <(sed -E 's/[0-9]*>+[[:space:]]*(\/dev\/null|&[0-9])//g' <<<"$c" | tr ';&|' '\n\n\n')
exit 0
