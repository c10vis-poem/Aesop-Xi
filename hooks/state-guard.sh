#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Bash|Write|Edit), obs 0017: the agent may not delete, move, truncate or write the
# ~/.claude/state enforcement files (resume-, confirm-, plan-, required-, satisfied-, observe-queue-,
# checkin-, pushnow-). Reads stay allowed. They change only through the operator's own `!` commands,
# the official tools (~/bin/resume-item, observe-dismiss) and the hook scripts, none of which reach here.
in=$(cat); tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || exit 0
P='(resume|confirm|plan|required|satisfied|observe-queue|checkin|pushnow)-'
say(){ echo "BLOCKED (state-guard): $1 is enforcement state. Only the operator, resume-item, observe-dismiss or the hooks change it (obs 0017)." >&2; exit 2; }
if [ "$tool" != Bash ]; then
  f=$(jq -r '.tool_input.file_path // ""' <<<"$in"); f=${f/#\~/$HOME}
  [[ $f =~ ^$HOME/\.claude/state/$P ]] && say "$f"
  exit 0
fi
c=$(jq -r '.tool_input.command // ""' <<<"$in")
command grep -q '\.claude/state' <<<"$c" || exit 0
# Drop harmless redirects (2>/dev/null, 2>&1, >&2), then split into simple commands
while IFS= read -r s; do
  command grep -qE "(^|[/[:space:]\"'])$P" <<<"$s" || continue
  command grep -qE "(^|[[:space:](])(rm|mv|cp|truncate|tee|touch|ln|unlink|shred|dd)[[:space:]]|sed[[:space:]]+-[a-zA-Z]*i|-delete|>[[:space:]]*[\"']?([^[:space:]\"']*/)?$P" <<<"$s" && say "${s:0:120}"
done < <(sed -E 's/[0-9]*>+[[:space:]]*(\/dev\/null|&[0-9])//g' <<<"$c" | tr ';&|' '\n\n\n')
exit 0
