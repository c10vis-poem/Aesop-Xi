#!/data/data/com.termux/files/usr/bin/bash
# PreToolUse (Write, Edit, NotebookEdit, Bash): block agent writes under shared-storage Documents/
# except Merovingian's_keep/, NovAExorpus/01-inbox/ and the vault's pinned root files.
# Operator override: #skip-enforce in the prompt (enforce-prompt.sh sets state/docsok-<sid>, cleared each prompt).
# Bash is a heuristic: a write verb or redirect plus an absolute Documents path. A bare `cd` + relative write is not seen.
in=$(cat); sid=$(jq -r '.session_id // "x"' <<<"$in") || exit 0
tool=$(jq -r '.tool_name // ""' <<<"$in")
[ -f "$HOME/.claude/state/docsok-$sid" ] && exit 0
PRE='(/storage/emulated/0|/sdcard|~/storage/shared|/data/data/com\.termux/files/home/storage/shared|\$HOME/storage/shared)/Documents/'
PIN="AGENTS\.md|README\.md|MAP\.md|RESUME\.md|PENDING\.md|unresolved\.md|MASTER-CLAUDE\.md|MASTER-RESUME\.md"
PDIR="skill-observations|skill-updates|_recaps|docs|\.claude|\.github|\.obsidian"
OK="^(Merovingian's_keep/|NovAExorpus/01-inbox/|NovAExorpus/(($PIN)([^A-Za-z0-9_.-]|$)|($PDIR)/))"
bad=
scan() { # $1 = text; sets bad to the first disallowed tail
  local t
  while IFS= read -r t; do
    case "$t" in *"/../"*|*"/.."|"../"*) bad=$t; return;; esac
    grep -qE "$OK" <<<"$t" || { bad=$t; return; }
  done < <(sed -E "s#$PRE#\n@@#g" <<<"$1" | sed -n 's/^@@//p')
}
if [ "$tool" = Bash ]; then
  c=$(jq -r '.tool_input.command // ""' <<<"$in")
  grep -qE "$PRE" <<<"$c" || exit 0
  s=$(sed -E 's/[0-9]*>&[0-9]//g; s#[0-9]*>[[:space:]]*/dev/null##g' <<<"$c")
  grep -qE '>|(^|[|;&[:space:]])(tee|mv|cp|rm|rmdir|mkdir|touch|ln|rsync|install|truncate|dd|chmod|chown|unzip|tar|curl|wget)([[:space:]]|$)|sed[^|;&]*[[:space:]]-[a-zA-Z]*i|git[[:space:]]+(mv|rm)' <<<"$s" || exit 0
  scan "$c"
else
  f=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' <<<"$in")
  scan "$(sed -E 's#^/#/#' <<<"$f")"
fi
[ -z "$bad" ] && exit 0
echo "BLOCKED (documents-guard): agent writes in Documents/ are limited to Merovingian's_keep/, NovAExorpus/01-inbox/ and the vault's pinned root files. Got: Documents/${bad:0:80}. Operator can add #skip-enforce to a prompt." >&2
exit 2
