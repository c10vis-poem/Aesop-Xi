#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Bash|Edit|Write): the agent may not change the operator's Claude Code configuration:
# ~/.claude/settings.json, ~/.claude/settings.local.json, ~/.claude.json. Blocks Edit/Write on them and
# Bash that writes them (redirect, tee, sed -i, mv, cp onto, truncate, rm, ln). Reads stay allowed.
# No agent override; the operator's own `!` commands are not agent tool calls and never reach here.
in=$(cat); tool=$(jq -r '.tool_name // ""' <<<"$in" 2>/dev/null) || exit 0
say(){ echo "BLOCKED (settings-guard): Claude Code settings are operator-owned (advisor, model, plugins, hooks). Give the operator the command as a ! line instead." >&2; exit 2; }
if [ "$tool" != Bash ]; then
  f=$(jq -r '.tool_input.file_path // ""' <<<"$in"); f=${f/#\~/$HOME}
  case $f in "$HOME/.claude/settings.json"|"$HOME/.claude/settings.local.json"|"$HOME/.claude.json") say ;; esac
  exit 0
fi
c=$(jq -r '.tool_input.command // ""' <<<"$in")
H="(~|\\\$HOME|\\\$\\{HOME\\}|${HOME//./\\.})"
F="$H/\\.claude(/settings(\\.local)?\\.json|\\.json)"
# After `cd ~/.claude`, bare settings(.local).json names count too
command grep -qE "(^|[;&|[:space:]])cd[[:space:]]+[\"']?$H/\\.claude/?[\"']?([;&|[:space:]]|$)" <<<"$c" && F="($F|(^|[[:space:]\"'])settings(\\.local)?\\.json)"
command grep -qE "$F" <<<"$c" || exit 0
while IFS= read -r s; do
  command grep -qE "$F" <<<"$s" || continue
  command grep -qE ">[[:space:]]*[\"']?$F|(^|[[:space:](])(tee|mv|truncate|rm|ln|unlink|dd)[[:space:]]|(sed|perl)[[:space:]]+-[a-zA-Z]*i" <<<"$s" && say
  command grep -qE "(^|[[:space:](])cp[[:space:]].*[[:space:]][\"']?$F[\"']?[[:space:]]*$" <<<"$s" && say
done < <(sed -E 's/[0-9]*>+[[:space:]]*(\/dev\/null|&[0-9])//g' <<<"$c" | tr ';&|' '\n\n\n')
exit 0
